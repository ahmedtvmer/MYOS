import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../providers.dart';
import '../../../router.dart';
import '../workout/active_workout_controller.dart';
import 'feature_list.dart';
import 'spotlight_overlay.dart';
import 'tour_controller.dart';
import 'tour_targets.dart';

class TourOverlayHost extends ConsumerStatefulWidget {
  const TourOverlayHost({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<TourOverlayHost> createState() => _TourOverlayHostState();
}

class _TourOverlayHostState extends ConsumerState<TourOverlayHost> {
  bool _requiresHomeReopen = false;
  bool _leftHomeAfterBlock = false;
  bool _suspendScheduled = false;
  bool _resumeScheduled = false;
  bool _routeRebuildScheduled = false;
  GoRouter? _observedRouter;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final GoRouter router = ref.read(routerProvider);
    if (_observedRouter == router) return;
    _observedRouter?.routerDelegate.removeListener(_onRouteChanged);
    _observedRouter = router;
    router.routerDelegate.addListener(_onRouteChanged);
  }

  void _onRouteChanged() {
    if (!mounted || _routeRebuildScheduled) return;
    _routeRebuildScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _routeRebuildScheduled = false;
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final TourSession? tour = ref.watch(tourControllerProvider);
    final Map<String, TourTargetHandle> targets =
        ref.watch(tourTargetRegistryProvider);
    final ActiveWorkoutState workout =
        ref.watch(activeWorkoutControllerProvider);
    final bool streaming = ref.watch(playerChatStreamingProvider);
    final int shellTabIndex = ref.watch(playerShellTabProvider);
    final GoRouter router = ref.watch(routerProvider);
    final String routePath =
        router.routerDelegate.currentConfiguration.uri.path;
    final bool homeIsCurrent =
        routePath == homePath && shellTabIndex == PlayerShellTab.home.index;
    final bool blocked = !workout.ready ||
        workout.hasWorkout ||
        (tour != null && !tour.singleStop && streaming);
    _syncBlocker(tour, blocked, homeIsCurrent);
    FeatureEntry? entry;
    if (tour != null) {
      for (final FeatureEntry feature in featureList) {
        if (feature.id == tour.featureId) {
          entry = feature;
          break;
        }
      }
    }
    final TourTargetHandle? handle =
        entry == null ? null : targets[entry.target];
    final bool locationIsCurrent =
        entry != null && entry.location.matches(routePath, shellTabIndex);
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        widget.child,
        if (tour != null &&
            tour.visible &&
            !blocked &&
            locationIsCurrent &&
            handle != null &&
            handle.location == entry.location)
          SpotlightOverlay(
            targetKey: handle.key,
            entry: entry,
            step: tour.index,
            stopCount: tour.singleStop ? 1 : tourV1StopCount,
            dotsCount: tour.stopIds.length,
            onSkip: () => unawaited(
              ref.read(tourControllerProvider.notifier).skip(),
            ),
            onBack: () => unawaited(
              ref.read(tourControllerProvider.notifier).back(),
            ),
            onNext: () => unawaited(
              ref.read(tourControllerProvider.notifier).next(),
            ),
          ),
      ],
    );
  }

  void _syncBlocker(
    TourSession? tour,
    bool blocked,
    bool homeIsCurrent,
  ) {
    if (tour == null) {
      _requiresHomeReopen = false;
      _leftHomeAfterBlock = false;
      return;
    }
    if (blocked) {
      if (!tour.singleStop) {
        _requiresHomeReopen = true;
        _leftHomeAfterBlock = !homeIsCurrent;
      }
      if (tour.visible && !_suspendScheduled) {
        _suspendScheduled = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _suspendScheduled = false;
          if (mounted && ref.read(tourControllerProvider) == tour) {
            ref.read(tourControllerProvider.notifier).suspend();
          }
        });
      }
      return;
    }
    if (_requiresHomeReopen && !homeIsCurrent) {
      _leftHomeAfterBlock = true;
    }
    if (!_requiresHomeReopen || !_leftHomeAfterBlock || !homeIsCurrent ||
        tour.visible || _resumeScheduled) {
      return;
    }
    _requiresHomeReopen = false;
    _leftHomeAfterBlock = false;
    _resumeScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _resumeScheduled = false;
      if (!mounted) return;
      final GoRouter router = ref.read(routerProvider);
      final ActiveWorkoutState currentWorkout =
          ref.read(activeWorkoutControllerProvider);
      if (router.routerDelegate.currentConfiguration.uri.path == homePath &&
          ref.read(playerShellTabProvider) == PlayerShellTab.home.index &&
          currentWorkout.ready &&
          !currentWorkout.hasWorkout &&
          !ref.read(playerChatStreamingProvider)) {
        unawaited(ref.read(tourControllerProvider.notifier).resume());
      }
    });
  }

  @override
  void dispose() {
    _observedRouter?.routerDelegate.removeListener(_onRouteChanged);
    super.dispose();
  }
}
