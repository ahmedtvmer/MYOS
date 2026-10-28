import 'package:mayos_mobile/src/features/player/tour/tour_controller.dart';

class FakeWhatsNewSeenRetryStore implements WhatsNewSeenRetryStore {
  final Map<String, int> pending = <String, int>{};

  @override
  Future<void> clear(String accountId) async => pending.remove(accountId);

  @override
  Future<int?> read(String accountId) async => pending[accountId];

  @override
  Future<void> write(String accountId, int release) async {
    pending[accountId] = release;
  }
}
