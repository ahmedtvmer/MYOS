import 'dart:typed_data';

import 'package:share_plus/share_plus.dart';

import 'workout_card_action_adapter.dart';

WorkoutCardActionAdapter createWorkoutCardActionAdapter(Uint8List pngBytes) =>
    _NativeWorkoutCardActions(pngBytes);

class _NativeWorkoutCardActions implements WorkoutCardActionAdapter {
  _NativeWorkoutCardActions(this.pngBytes);

  final Uint8List pngBytes;

  @override
  Future<bool> share() => _shareThroughSystem(pngBytes);

  @override
  Future<bool> save() => _shareThroughSystem(pngBytes);

  @override
  void dispose() {}
}

Future<bool> _shareThroughSystem(Uint8List pngBytes) async {
  final ShareResult result = await SharePlus.instance.share(
    ShareParams(files: <XFile>[
      XFile.fromData(pngBytes, mimeType: 'image/png', name: 'mayos-workout.png'),
    ]),
  );
  return result.status != ShareResultStatus.dismissed;
}
