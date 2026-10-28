import 'package:myos_mobile/src/features/player/tour/tour_controller.dart';

class FakeTourSeenRetryStore implements TourSeenRetryStore {
  final Map<String, int> pending = <String, int>{};

  @override
  Future<void> clear(String accountId) async {
    pending.remove(accountId);
  }

  @override
  Future<int?> read(String accountId) async => pending[accountId];

  @override
  Future<void> write(String accountId, int version) async {
    pending[accountId] = version;
  }
}
