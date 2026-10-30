import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../api/manga/manga_api.dart';
import '../api/network/network_api.dart';
import '../api/user/user_api.dart';
import '../models/user_manager.dart';
import '../utils/data_cache.dart';
import '../utils/network_auto_test_scheduler.dart';
import '../utils/network_latency_tester.dart';

/// Provides the shared [UserManager] singleton.
final userManagerProvider = Provider<UserManager>((ref) => UserManager());

/// Provides the shared [ApiClient] singleton.
final apiClientProvider = Provider<ApiClient>((ref) => ApiClient());

/// Shortcut provider for [MangaApi].
final mangaApiProvider = Provider<MangaApi>((ref) => ApiClient().manga);

/// Shortcut provider for [UserApi].
final userApiProvider = Provider<UserApi>((ref) => ApiClient().user);

/// Shortcut provider for [NetworkApi].
final networkApiProvider = Provider<NetworkApi>((ref) => ApiClient().network);

final networkLatencyTesterProvider = Provider<NetworkLatencyTester>((ref) {
  final tester = NetworkLatencyTester(
    api: ref.read(networkApiProvider),
    settings: ref.read(userManagerProvider).network,
  );
  ref.onDispose(tester.dispose);
  return tester;
});

final networkAutoTestSchedulerProvider = Provider<NetworkAutoTestScheduler>((
  ref,
) {
  final scheduler = NetworkAutoTestScheduler(
    settings: ref.read(userManagerProvider).network,
    tester: ref.read(networkLatencyTesterProvider),
  );
  final user = ref.read(userManagerProvider);
  user.addListener(scheduler.refreshSettings);
  ref.onDispose(() {
    user.removeListener(scheduler.refreshSettings);
    scheduler.dispose();
  });
  return scheduler;
});

/// Provides the shared [DataCache] singleton.
final dataCacheProvider = Provider<DataCache>((ref) => DataCache());
