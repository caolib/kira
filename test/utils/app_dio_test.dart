import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/utils/app_dio.dart';

void main() {
  test('creates dio with custom interceptors before error logging', () {
    final custom = InterceptorsWrapper();
    final dio = AppDio.create(source: 'test', interceptors: [custom]);
    final customIndex = dio.interceptors.indexOf(custom);

    expect(customIndex, greaterThanOrEqualTo(0));
    expect(customIndex, lessThan(dio.interceptors.length - 1));
  });
}
