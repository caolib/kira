import 'dart:io';

import 'package:xml/xml.dart';

import 'webdav_config.dart';

const webDavPropfindBody = '''<?xml version="1.0" encoding="utf-8"?>
<d:propfind xmlns:d="DAV:"><d:prop><d:resourcetype/><d:getcontentlength/>
<d:getlastmodified/></d:prop></d:propfind>''';

const webDavDeleteCheckBody = '''<?xml version="1.0" encoding="utf-8"?>
<d:propfind xmlns:d="DAV:"><d:prop><d:resourcetype/><d:getetag/></d:prop></d:propfind>''';

XmlElement _multistatus(String xml) {
  if (RegExp(r'<!\s*(DOCTYPE|ENTITY)', caseSensitive: false).hasMatch(xml)) {
    throw const WebDavException(WebDavErrorCode.invalidResponse);
  }
  try {
    final root = XmlDocument.parse(xml).rootElement;
    if (root.name.local != 'multistatus' || root.namespaceUri != 'DAV:') {
      throw const WebDavException(WebDavErrorCode.invalidResponse);
    }
    return root;
  } on XmlException {
    throw const WebDavException(WebDavErrorCode.invalidResponse);
  }
}

String? _text(XmlElement parent, String name) =>
    parent.findElements(name, namespace: 'DAV:').firstOrNull?.innerText;

Iterable<XmlElement> _successfulProperties(XmlElement response) sync* {
  for (final propstat in response.findElements('propstat', namespace: 'DAV:')) {
    final status = _text(propstat, 'status') ?? '';
    if (!RegExp(r'^HTTP/\S+\s+2\d\d(?:\s|$)').hasMatch(status.trim())) continue;
    yield* propstat.findElements('prop', namespace: 'DAV:');
  }
}

Uri? _safeHref(String? href, Uri base, WebDavConfig config) {
  if (href == null || href.trim().isEmpty) return null;
  final reference = Uri.tryParse(href.trim());
  if (reference == null ||
      reference.hasQuery ||
      reference.hasFragment ||
      reference.userInfo.isNotEmpty ||
      !WebDavConfig.safeSegments(reference.pathSegments)) {
    return null;
  }
  final uri = base.resolveUri(reference);
  if (!config.sameOrigin(uri) || !WebDavConfig.safeSegments(uri.pathSegments)) {
    return null;
  }
  return uri;
}

bool webDavCollectionExists(String xml, Uri target, WebDavConfig config) {
  for (final response in _multistatus(
    xml,
  ).findElements('response', namespace: 'DAV:')) {
    final uri = _safeHref(_text(response, 'href'), target, config);
    if (uri == null ||
        uri.pathSegments.where((s) => s.isNotEmpty).join('/') !=
            target.pathSegments.where((s) => s.isNotEmpty).join('/')) {
      continue;
    }
    for (final properties in _successfulProperties(response)) {
      if (properties
          .findElements('resourcetype', namespace: 'DAV:')
          .any(
            (type) =>
                type.findElements('collection', namespace: 'DAV:').isNotEmpty,
          )) {
        return true;
      }
    }
  }
  return false;
}

bool _ordinaryFile(Iterable<XmlElement> types) =>
    types.isNotEmpty &&
    types.every((t) => t.childElements.isEmpty && t.innerText.trim().isEmpty);

void _checkStatus(String? line, String method) {
  if (line == null) return;
  final match = RegExp(r'^HTTP/\S+\s+(\d{3})(?:\s|$)').firstMatch(line.trim());
  final status = int.tryParse(match?[1] ?? '');
  if (status == null) {
    throw const WebDavException(WebDavErrorCode.invalidResponse);
  }
  if (status < 200 || status >= 300) {
    throw WebDavException.fromStatus(method, status);
  }
}

/// Depth: 0 must positively identify the exact resource as an ordinary file.
/// A missing/failed resourcetype propstat is not evidence that it isn't a collection.
String? checkWebDavDeleteTarget(String xml, Uri target, WebDavConfig config) {
  final response = _multistatus(
    xml,
  ).findElements('response', namespace: 'DAV:').singleOrNull;
  if (response == null ||
      _safeHref(_text(response, 'href'), target, config) != target) {
    throw const WebDavException(WebDavErrorCode.invalidResponse);
  }
  _checkStatus(_text(response, 'status'), 'PROPFIND');
  for (final propstat in response.findElements('propstat', namespace: 'DAV:')) {
    if (propstat
        .findAllElements('resourcetype', namespace: 'DAV:')
        .isNotEmpty) {
      _checkStatus(_text(propstat, 'status'), 'PROPFIND');
    }
  }
  final properties = _successfulProperties(response);
  if (!_ordinaryFile(
    properties.expand((p) => p.findElements('resourcetype', namespace: 'DAV:')),
  )) {
    throw const WebDavException(WebDavErrorCode.unsafePath);
  }
  final etag = properties
      .map((p) => _text(p, 'getetag')?.trim())
      .nonNulls
      .firstOrNull;
  return etag != null && RegExp(r'^"[\x21\x23-\x7e\x80-\xff]*"$').hasMatch(etag)
      ? etag
      : null;
}

/// A DELETE multistatus describes a partial outcome, not confirmed success.
Never throwWebDavDeleteMultistatus(String xml) {
  for (final status in _multistatus(
    xml,
  ).findAllElements('status', namespace: 'DAV:')) {
    _checkStatus(status.innerText, 'DELETE');
  }
  throw const WebDavException(WebDavErrorCode.invalidResponse, status: 207);
}

List<WebDavBackupEntry> parseWebDavListing(
  String xml,
  WebDavConfig config, {
  bool confirmedFilesOnly = false,
}) {
  final entries = <String, WebDavBackupEntry>{};
  final rootParts = config.rootSegments;
  for (final response in _multistatus(
    xml,
  ).findElements('response', namespace: 'DAV:')) {
    final uri = _safeHref(_text(response, 'href'), config.root, config);
    if (uri == null) continue;
    final parts = uri.pathSegments;
    if (parts.length != rootParts.length + 1 ||
        !Iterable<int>.generate(
          rootParts.length,
        ).every((i) => rootParts[i] == parts[i])) {
      continue;
    }
    final name = parts.last;
    if (!WebDavBackupEntry.isBackupName(name)) continue;
    final propertiesWithSuccess = _successfulProperties(response);
    if (confirmedFilesOnly &&
        !_ordinaryFile(
          propertiesWithSuccess.expand(
            (p) => p.findElements('resourcetype', namespace: 'DAV:'),
          ),
        )) {
      continue;
    }
    var successful = false;
    var collection = false;
    int? size;
    DateTime? modified;
    for (final properties in propertiesWithSuccess) {
      successful = true;
      collection |= properties
          .findElements('resourcetype', namespace: 'DAV:')
          .any(
            (type) =>
                type.findElements('collection', namespace: 'DAV:').isNotEmpty,
          );
      size ??= int.tryParse(_text(properties, 'getcontentlength') ?? '');
      final date = _text(properties, 'getlastmodified');
      if (date != null) {
        try {
          modified = HttpDate.parse(date);
        } on FormatException {
          // Optional remote metadata must not prevent listing valid backups.
          modified = DateTime.tryParse(date);
        }
      }
    }
    if (!successful || collection || (size != null && size < 0)) continue;
    entries[name] = WebDavBackupEntry(
      name: name,
      size: size,
      modified: modified,
    );
  }
  final result = entries.values.toList()
    ..sort((a, b) {
      final byDate = (b.modified ?? DateTime.fromMillisecondsSinceEpoch(0))
          .compareTo(a.modified ?? DateTime.fromMillisecondsSinceEpoch(0));
      return byDate == 0 ? b.name.compareTo(a.name) : byDate;
    });
  return result;
}
