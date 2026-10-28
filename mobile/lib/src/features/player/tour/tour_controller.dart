import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';

import '../../../core/analytics_client.dart';
import '../../../core/api_client.dart';
import '../../../core/models.dart';
import '../../../providers.dart';
import '../../../router.dart';
import '../auth/auth_controller.dart';
import '../workout/active_workout_controller.dart';
import 'tour_targets.dart';
import 'feature_list.dart';

class TourSession {
  const TourSession({
    required this.stopIds,
    required this.index,
    required this.visible,
    required this.singleStop,
    required this.version,
    this.replay = false,
  });

  final List<String> stopIds;
  final int index;
  final bool visible;
  final bool singleStop;
  final int version;
  final bool replay;

  String get featureId => stopIds[index];

  TourSession copyWith({int? index, bool? visible}) => TourSession(
        stopIds: stopIds,
        index: index ?? this.index,
        visible: visible ?? this.visible,
        singleStop: singleStop,
        version: version,
        replay: replay,
      );
}

abstract interface class TourSeenRetryStore {
  Future<int?> read(String accountId);
  Future<void> write(String accountId, int version);
  Future<void> clear(String accountId);
}

class SecureTourSeenRetryStore implements TourSeenRetryStore {
  SecureTourSeenRetryStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  String _key(String accountId) => 'mayos.tour_seen_pending.$accountId';

  @override
  Future<int?> read(String accountId) async {
    final String? value = await _storage.read(key: _key(accountId));
    return int.tryParse(value ?? '');
  }

  @override
  Future<void> write(String accountId, int version) =>
      _storage.write(key: _key(accountId), value: '$version');

  @override
  Future<void> clear(String accountId) =>
      _storage.delete(key: _key(accountId));
}

final Provider<TourSeenRetryStore> tourSeenRetryStoreProvider =
    Provider<TourSeenRetryStore>((ref) => SecureTourSeenRetryStore());

final Provider<int> tourCurrentVersionProvider =
    Provider<int>((ref) => tourCurrentVersion);

final StateNotifierProvider<TourController, TourSession?>
    tourControllerProvider = StateNotifierProvider<TourController, TourSession?>(
  (ref) => TourController(ref),
);

class TourController extends StateNotifier<TourSession?> {
  TourController(this._ref) : super(null);

  final Ref _ref;
  int _operation = 0;
  bool _starting = false;
  bool _focusing = false;
  String? _pendingAccountId;
  int? _pendingVersion;

  bool hasPendingSeenWriteFor(String accountId) =>
      _pendingAccountId == accountId && _pendingVersion != null;

  Future<void> startTour(int version, {bool replay = false}) async {
    if (state != null || _starting) return;
    final Account? account = _ref.read(authControllerProvider).session?.account;
    if (account == null) return;
    if (!replay && account.tourSeenVersion >= version &&
        _pendingAccountId != account.accountId) {
      return;
    }
    _starting = true;
    final String accountId = account.accountId;
    final TourSeenRetryStore retryStore = _ref.read(tourSeenRetryStoreProvider);
    final AuthController auth = _ref.read(authControllerProvider.notifier);
    final ApiClient api = _ref.read(apiClientProvider);
    try {
      if (!replay && _pendingAccountId == accountId && _pendingVersion != null) {
        await _persistPending(accountId, retryStore, auth: auth, api: api);
        if (!mounted || !auth.ownsAccount(accountId)) return;
        if (_pendingVersion != null && _pendingVersion! >= version) return;
      }
      final int? persisted = replay ? null : await retryStore.read(accountId);
      if (!mounted || !auth.ownsAccount(accountId)) return;
      if (persisted != null) {
        _pendingAccountId = accountId;
        _pendingVersion = persisted;
        await _persistPending(accountId, retryStore, auth: auth, api: api);
        if (persisted >= version && _pendingVersion == null) return;
        if (_pendingVersion != null && _pendingVersion! >= version) return;
      }
    } on Object {
      // A secure-store failure must not prevent the Tour from being offered.
    } finally {
      _starting = false;
    }
    if (!mounted || !auth.ownsAccount(accountId)) return;
    final Account? currentAccount =
        _ref.read(authControllerProvider).session?.account;
    if (!auth.ownsAccount(accountId) ||
        currentAccount == null ||
        (!replay && !isTourEligible(currentAccount, currentVersion: version))) {
      return;
    }
    state = TourSession(
      stopIds: tourV1StopIds,
      index: 0,
      visible: false,
      singleStop: false,
      version: version,
      replay: replay,
    );
    await _focusCurrent(started: true);
  }

  Future<void> showMe(String featureId) async {
    if (!featureList.any((FeatureEntry entry) => entry.id == featureId)) return;
    final ActiveWorkoutState workout =
        _ref.read(activeWorkoutControllerProvider);
    if (!workout.ready || workout.hasWorkout) return;
    _ref.read(analyticsClientProvider).showMeTapped(featureId);
    _operation++;
    state = TourSession(
      stopIds: <String>[featureId],
      index: 0,
      visible: false,
      singleStop: true,
      version: tourCurrentVersion,
    );
    await _focusCurrent();
  }

  Future<void> next() async {
    final TourSession? current = state;
    if (current == null || !current.visible) return;
    if (current.singleStop) {
      state = null;
      return;
    }
    if (current.index == current.stopIds.length - 1) {
      await _dismiss(skipped: false);
      return;
    }
    state = current.copyWith(index: current.index + 1, visible: false);
    await _focusCurrent();
  }

  Future<void> back() async {
    final TourSession? current = state;
    if (current == null || !current.visible || current.index == 0) return;
    state = current.copyWith(index: current.index - 1, visible: false);
    await _focusCurrent();
  }

  Future<void> skip() => _dismiss(skipped: true);

  Future<void> finish() => _dismiss(skipped: false);

  void suspend() {
    final TourSession? current = state;
    if (current != null) {
      _operation++;
      state = current.copyWith(visible: false);
    }
  }

  Future<void> resume() async {
    if (state == null || state!.visible || _focusing) return;
    await _focusCurrent();
  }

  Future<void> _focusCurrent({bool started = false}) async {
    final TourSession? current = state;
    if (current == null || _focusing) return;
    _focusing = true;
    final int operation = ++_operation;
    final FeatureEntry entry = featureList.firstWhere(
      (FeatureEntry feature) => feature.id == current.featureId,
    );
    final StateController<int> tabController =
        _ref.read(playerShellTabProvider.notifier);
    final GoRouter router = _ref.read(routerProvider);
    final AuthController auth = _ref.read(authControllerProvider.notifier);
    final AnalyticsClient analytics = _ref.read(analyticsClientProvider);
    final String? accountId =
        _ref.read(authControllerProvider).session?.account.accountId;
    try {
      final ActiveWorkoutState initialWorkout =
          _ref.read(activeWorkoutControllerProvider);
      if (!initialWorkout.ready ||
          initialWorkout.hasWorkout ||
          (!current.singleStop && _ref.read(playerChatStreamingProvider))) {
        return;
      }
      entry.location.navigate(router, tabController);
      TourTargetHandle? target;
      BuildContext? targetContext;
      for (int attempt = 0; attempt < 40; attempt++) {
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted || operation != _operation || state == null) return;
        target = _ref.read(tourTargetRegistryProvider)[entry.target];
        targetContext = target?.key.currentContext;
        if (targetContext != null && targetContext.mounted) break;
      }
      if (target == null || targetContext == null || !targetContext.mounted) {
        state = null;
        return;
      }
      await Scrollable.ensureVisible(
        targetContext,
        alignment: 0.35,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
      );
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || operation != _operation || state == null) return;
      if (!targetContext.mounted) return;
      final String routePath = currentTourRoutePath(router);
      final ActiveWorkoutState workout =
          _ref.read(activeWorkoutControllerProvider);
      if (!entry.location.matches(routePath, tabController.state) ||
          !workout.ready ||
          workout.hasWorkout ||
          (!current.singleStop && _ref.read(playerChatStreamingProvider))) {
        return;
      }
      if (accountId != null && !auth.ownsAccount(accountId)) {
        state = null;
        return;
      }
      state = state!.copyWith(visible: true);
      if (current.singleStop) return;
      if (started) analytics.tourEvent('tour_started', replay: current.replay);
      analytics.tourEvent('tour_step', step: state!.index + 1, replay: current.replay);
    } finally {
      _focusing = false;
    }
  }

  Future<void> _dismiss({required bool skipped}) async {
    final TourSession? current = state;
    if (current == null || !current.visible) return;
    _operation++;
    state = null;
    if (current.singleStop) return;
    final String? accountId =
        _ref.read(authControllerProvider).session?.account.accountId;
    final AuthController auth = _ref.read(authControllerProvider.notifier);
    final TourSeenRetryStore retryStore = _ref.read(tourSeenRetryStoreProvider);
    final ApiClient api = _ref.read(apiClientProvider);
    _ref.read(analyticsClientProvider).tourEvent(
          skipped ? 'tour_skipped' : 'tour_completed', replay: current.replay,
        );
    if (current.replay) return;
    if (accountId == null) return;
    _pendingAccountId = accountId;
    _pendingVersion = current.version;
    auth.confirmTourSeenVersion(accountId, current.version);
    unawaited(
      _queueAndPersist(accountId, current.version, auth, retryStore, api),
    );
  }

  Future<void> _queueAndPersist(
    String accountId,
    int version,
    AuthController auth,
    TourSeenRetryStore retryStore,
    ApiClient api,
  ) async {
    try {
      await retryStore.write(accountId, version);
    } on Object {
      // Keep the in-memory pending marker and retry at the next Home open.
    }
    if (!auth.ownsAccount(accountId)) return;
    await _persistPending(accountId, retryStore, auth: auth, api: api);
  }

  Future<void> _persistPending(
    String accountId,
    TourSeenRetryStore retryStore, {
    AuthController? auth,
    ApiClient? api,
  }) async {
    final int? version = _pendingVersion;
    if (version == null || _pendingAccountId != accountId) return;
    final ApiClient client = api ?? _ref.read(apiClientProvider);
    final AuthController authController = auth ??
        _ref.read(authControllerProvider.notifier);
    try {
      final int savedVersion = await client.markTourSeen(version);
      if (!authController.ownsAccount(accountId)) return;
      authController.confirmTourSeenVersion(accountId, savedVersion);
      _pendingAccountId = null;
      _pendingVersion = null;
      await retryStore.clear(accountId);
    } on ApiException {
      // The Tour stays dismissed; the queued version retries at the next open.
    }
  }
}
