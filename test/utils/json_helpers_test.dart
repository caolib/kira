import 'package:flutter_test/flutter_test.dart';
import 'package:kira/utils/json_helpers.dart';

void main() {
  // ── jsonList ──────────────────────────────────────────────────────────

  group('jsonList', () {
    test('returns empty list when json is null', () {
      expect(jsonList(null, 'key'), []);
    });

    test('returns empty list when key is missing', () {
      expect(jsonList({}, 'key'), []);
    });

    test('returns empty list when value is not a list', () {
      expect(jsonList({'key': 'not a list'}, 'key'), []);
      expect(jsonList({'key': 42}, 'key'), []);
      expect(
        jsonList({
          'key': {'nested': true},
        }, 'key'),
        [],
      );
    });

    test('returns list when value is a valid list', () {
      expect(
        jsonList({
          'key': [1, 2, 3],
        }, 'key'),
        [1, 2, 3],
      );
    });

    test('returns empty list when value is an empty list', () {
      expect(jsonList({'key': <dynamic>[]}, 'key'), <dynamic>[]);
    });
  });

  // ── jsonInt ───────────────────────────────────────────────────────────

  group('jsonInt', () {
    test('returns fallback when json is null', () {
      expect(jsonInt(null, 'key'), 0);
    });

    test('returns fallback when key is missing', () {
      expect(jsonInt({}, 'key'), 0);
    });

    test('returns int value directly', () {
      expect(jsonInt({'key': 42}, 'key'), 42);
    });

    test('parses string number to int', () {
      expect(jsonInt({'key': '99'}, 'key'), 99);
    });

    test('returns fallback for invalid string', () {
      expect(jsonInt({'key': 'abc'}, 'key'), 0);
    });

    test('returns custom fallback', () {
      expect(jsonInt(null, 'key', fallback: -1), -1);
      expect(jsonInt({}, 'key', fallback: -1), -1);
      expect(jsonInt({'key': 'bad'}, 'key', fallback: 7), 7);
    });

    test('returns fallback for double value', () {
      // double is not int; 3.14.toString() = "3.14" which int.tryParse can't parse
      expect(jsonInt({'key': 3.14}, 'key'), 0);
    });
  });

  // ── jsonString ───────────────────────────────────────────────────────

  group('jsonString', () {
    test('returns fallback when json is null', () {
      expect(jsonString(null, 'key'), '');
    });

    test('returns fallback when key is missing', () {
      expect(jsonString({}, 'key'), '');
    });

    test('returns string value', () {
      expect(jsonString({'key': 'hello'}, 'key'), 'hello');
    });

    test('returns fallback when value is null', () {
      expect(jsonString({'key': null}, 'key'), '');
    });

    test('returns toString() for non-string value', () {
      expect(jsonString({'key': 42}, 'key'), '42');
      expect(jsonString({'key': true}, 'key'), 'true');
    });

    test('returns custom fallback', () {
      expect(jsonString(null, 'key', fallback: 'default'), 'default');
    });
  });

  // ── jsonDouble ────────────────────────────────────────────────────────

  group('jsonDouble', () {
    test('returns fallback when json is null', () {
      expect(jsonDouble(null, 'key'), 0.0);
    });

    test('returns double value directly', () {
      expect(jsonDouble({'key': 3.14}, 'key'), 3.14);
    });

    test('converts int value to double', () {
      expect(jsonDouble({'key': 5}, 'key'), 5.0);
    });

    test('parses string number to double', () {
      expect(jsonDouble({'key': '2.5'}, 'key'), 2.5);
    });

    test('returns fallback for invalid string', () {
      expect(jsonDouble({'key': 'abc'}, 'key'), 0.0);
    });

    test('returns custom fallback', () {
      expect(jsonDouble(null, 'key', fallback: -1.0), -1.0);
    });
  });

  // ── jsonBool ──────────────────────────────────────────────────────────

  group('jsonBool', () {
    test('returns fallback when json is null', () {
      expect(jsonBool(null, 'key'), false);
    });

    test('returns true for bool true', () {
      expect(jsonBool({'key': true}, 'key'), true);
    });

    test('returns false for bool false', () {
      expect(jsonBool({'key': false}, 'key'), false);
    });

    test('returns fallback for non-bool value', () {
      expect(jsonBool({'key': 1}, 'key'), false);
      expect(jsonBool({'key': 'true'}, 'key'), false);
      expect(jsonBool({'key': null}, 'key'), false);
    });

    test('returns custom fallback', () {
      expect(jsonBool(null, 'key', fallback: true), true);
    });
  });

  // ── jsonMap ───────────────────────────────────────────────────────────

  group('jsonMap', () {
    test('returns null when json is null', () {
      expect(jsonMap(null, 'key'), isNull);
    });

    test('returns null when key is missing', () {
      expect(jsonMap({}, 'key'), isNull);
    });

    test('returns null when value is not a map', () {
      expect(jsonMap({'key': 'string'}, 'key'), isNull);
      expect(jsonMap({'key': 42}, 'key'), isNull);
      expect(
        jsonMap({
          'key': [1, 2],
        }, 'key'),
        isNull,
      );
    });

    test('returns map for valid map value', () {
      final result = jsonMap({
        'key': {'a': 1},
      }, 'key');
      expect(result, isNotNull);
      expect(result!['a'], 1);
    });

    test('coerces non-string keys to string', () {
      final result = jsonMap({
        'key': {1: 'one', 2: 'two'},
      }, 'key');
      // Map<String, dynamic>.from() coerces int keys to their string form
      expect(result, isNotNull);
      expect(result!['1'], 'one');
      expect(result['2'], 'two');
    });
  });

  // ── NullIfEmptyString ────────────────────────────────────────────────

  group('NullIfEmptyString', () {
    test('returns null for empty string', () {
      expect(''.nullIfEmpty(), isNull);
    });

    test('returns the string for non-empty string', () {
      expect('hello'.nullIfEmpty(), 'hello');
      expect(' '.nullIfEmpty(), ' ');
    });
  });
}
