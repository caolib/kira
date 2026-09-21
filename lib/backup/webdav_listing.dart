import 'dart:io';

import 'package:xml/xml.dart';

import 'webdav_config.dart';

const webDavPropfindBody = '''<?xml version="1.0" encoding="utf-8"?>
<d:propfind xmlns:d="DAV:"><d:prop><d:resourcetype/><d:getcontentlength/>
<d:getlastmodified/></d:prop></d:propfind>''';

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

List<WebDavBackupEntry> parseWebDavListing(String xml, WebDavConfig config) {
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
    var successful = false;
    var collection = false;
    int? size;
    DateTime? modified;
    for (final properties in _successfulProperties(response)) {
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
