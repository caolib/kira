import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/models/user_manager.dart';
import 'package:kira/utils/app_update.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    setupSecureCredentialStoreForTest();
    SharedPreferences.setMockInitialValues({});
    await UserManager().init();
    PackageInfo.setMockInitialValues(
      appName: 'Kira',
      packageName: 'com.example.kira',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
    AppUpdateService.state.value = const AppUpdateState.idle();
    AppUpdateService.hasUnseenUpdate.value = false;
  });

  tearDown(() {
    AppUpdateService.state.value = const AppUpdateState.idle();
    AppUpdateService.hasUnseenUpdate.value = false;
    teardownSecureCredentialStoreForTest();
  });

  for (final hasPreviousCheck in [false, true]) {
    testWidgets(
      'failed startup retries without advancing last success ($hasPreviousCheck)',
      (tester) async {
        const key = ValueKey('update-host');
        await tester.pumpWidget(wrapWithApp(const SizedBox(key: key)));
        final context = tester.element(find.byKey(key));
        var requests = 0;
        final interceptor = InterceptorsWrapper(
          onRequest: (options, handler) {
            requests++;
            if (requests == 1) {
              handler.reject(
                DioException(requestOptions: options, error: 'offline'),
              );
            } else {
              handler.resolve(
                Response<Object?>(
                  requestOptions: options,
                  statusCode: 200,
                  data: {'tag_name': 'v1.0.0', 'assets': <Object>[]},
                ),
              );
            }
          },
        );
        AppUpdateService.dioForTesting.interceptors.insert(0, interceptor);
        addTearDown(
          () => AppUpdateService.dioForTesting.interceptors.remove(interceptor),
        );

        // Dio error handling and the shared logger queue need a real async zone.
        await tester.runAsync(() async {
          final user = UserManager();
          await user.setUpdateCheckFrequency(UpdateCheckFrequency.weekly);
          final old = hasPreviousCheck
              ? DateTime.now().subtract(const Duration(days: 8))
              : null;
          if (old != null) {
            await user.recordUpdateCheckSuccess('stable', at: old);
          }
          await AppUpdateService.checkOnStartup(context);
          expect(AppUpdateService.state.value.status, AppUpdateStatus.failed);
          expect(AppUpdateService.state.value.errorDetail, contains('offline'));
          expect(user.isUpdateCheckDue(), isTrue);
          expect(
            (await SharedPreferences.getInstance()).getInt(
              'auto_check_update_last_success_stable',
            ),
            old?.millisecondsSinceEpoch,
          );
          await user.init();
          await AppUpdateService.checkOnStartup(context);
          expect(requests, 2);
          expect(AppUpdateService.state.value.status, AppUpdateStatus.latest);
          expect(user.isUpdateCheckDue(), isFalse);
        });
        await tester.pumpAndSettle();
      },
    );
  }
}
