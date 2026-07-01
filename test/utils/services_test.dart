import 'package:flutter_test/flutter_test.dart';
import 'package:kira/utils/services.dart';

/// Test-only service type that can have distinct instances.
class _TestService {
  final int id;
  _TestService(this.id);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(Services.reset);

  // ── Singleton behavior ────────────────────────────────────────────────

  group('singleton resolution', () {
    test('resolve returns same instance on repeated calls', () {
      final instance = _TestService(1);
      Services.override<_TestService>(() => instance);
      final a = Services.resolve<_TestService>();
      final b = Services.resolve<_TestService>();
      expect(identical(a, b), isTrue);
      expect(identical(a, instance), isTrue);
    });
  });

  // ── Override ──────────────────────────────────────────────────────────

  group('override', () {
    test('override replaces the resolved instance', () {
      final first = _TestService(1);
      Services.override<_TestService>(() => first);
      final original = Services.resolve<_TestService>();

      final second = _TestService(2);
      Services.override<_TestService>(() => second);
      final resolved = Services.resolve<_TestService>();
      expect(identical(resolved, second), isTrue);
      expect(identical(resolved, original), isFalse);
    });

    test('override clears cached instance so next resolve uses factory', () {
      final first = _TestService(1);
      Services.override<_TestService>(() => first);
      Services.resolve<_TestService>();

      // Override with a counting factory to verify the cache was cleared
      var factoryCallCount = 0;
      Services.override<_TestService>(() {
        factoryCallCount++;
        return _TestService(99);
      });
      Services.resolve<_TestService>();
      expect(factoryCallCount, 1);
    });
  });

  // ── Reset ─────────────────────────────────────────────────────────────

  group('reset', () {
    test('reset clears overrides and cached instances', () {
      final mock = _TestService(1);
      Services.override<_TestService>(() => mock);
      expect(identical(Services.resolve<_TestService>(), mock), isTrue);

      Services.reset();

      // After reset, resolve without an override throws StateError
      // because _TestService has no default factory.
      expect(
        () => Services.resolve<_TestService>(),
        throwsStateError,
      );
    });

    test('after reset, new override works again', () {
      final first = _TestService(1);
      Services.override<_TestService>(() => first);
      expect(identical(Services.resolve<_TestService>(), first), isTrue);

      Services.reset();

      final second = _TestService(2);
      Services.override<_TestService>(() => second);
      expect(identical(Services.resolve<_TestService>(), second), isTrue);
    });
  });

  // ── Unknown type ──────────────────────────────────────────────────────

  group('unknown type', () {
    test('resolve throws StateError for unregistered type', () {
      expect(() => Services.resolve<Set<int>>(), throwsStateError);
    });
  });
}
