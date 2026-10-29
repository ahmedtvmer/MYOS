import 'workout_card_action_adapter.dart';

abstract interface class WorkoutCardWebBindings {
  bool canShare();
  Future<void> share();
  void download();
  void dispose();
}

class WorkoutCardShareDismissed implements Exception {
  const WorkoutCardShareDismissed();
}

class WebWorkoutCardActionAdapter implements WorkoutCardActionAdapter {
  const WebWorkoutCardActionAdapter(this._browser);

  final WorkoutCardWebBindings _browser;

  @override
  Future<bool> share() {
    try {
      if (!_browser.canShare()) return save();
    } on NoSuchMethodError {
      return save();
    }
    return _completeShare(_browser.share());
  }

  Future<bool> _completeShare(Future<void> pendingShare) async {
    try {
      await pendingShare;
      return true;
    } on WorkoutCardShareDismissed {
      return false;
    }
  }

  @override
  Future<bool> save() {
    _browser.download();
    return Future<bool>.value(true);
  }

  @override
  void dispose() => _browser.dispose();
}
