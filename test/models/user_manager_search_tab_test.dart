import 'package:flutter_test/flutter_test.dart';
import 'package:kira/models/user_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 搜索页标签索引的持久化（搜索 = 0，发现 = 1）。
///
/// [SearchPage] 初次建 [TabController] 时读 [UserManager.searchTabIndex]，
/// 所以冷启动能否回到「发现」页完全取决于这里。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late UserManager user;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    user = UserManager();
    await user.init(persistMigrations: false);
    await user.setSearchTabIndex(0);
  });

  test('默认停在搜索页（index 0）', () {
    expect(user.searchTabIndex, 0);
  });

  test('写入后能从偏好里读回来', () async {
    await user.setSearchTabIndex(1);
    expect(user.searchTabIndex, 1);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('search_tab_index'), 1);
  });

  test('init 从偏好恢复上次的标签', () async {
    await user.setSearchTabIndex(1);

    final restored = UserManager();
    await restored.init(persistMigrations: false);

    expect(restored.searchTabIndex, 1);
  });

  test('越界值被夹到合法范围', () async {
    // 脏数据（更早版本写入或手改偏好）不应让 TabController 抛越界。
    await user.setSearchTabIndex(9);
    expect(user.searchTabIndex, 1);

    await user.setSearchTabIndex(-3);
    expect(user.searchTabIndex, 0);

    SharedPreferences.setMockInitialValues({'search_tab_index': 7});
    final restored = UserManager();
    await restored.init(persistMigrations: false);
    expect(restored.searchTabIndex, 1);
  });

  test('设成相同值不重复写盘', () async {
    await user.setSearchTabIndex(1);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('search_tab_index', 0); // 外部篡改，模拟未写入

    await user.setSearchTabIndex(1); // 内存里已是 1，应提前返回
    expect(prefs.getInt('search_tab_index'), 0);
  });
}
