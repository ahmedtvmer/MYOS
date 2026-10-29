import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

import 'workout_photo_adapter_stub.dart'
    if (dart.library.js_interop) 'workout_photo_adapter_web.dart' as platform;

class WorkoutPhotoSize {
  const WorkoutPhotoSize(this.width, this.height);

  final int width;
  final int height;

  @override
  bool operator ==(Object other) => other is WorkoutPhotoSize &&
      width == other.width && height == other.height;

  @override
  int get hashCode => Object.hash(width, height);
}

WorkoutPhotoSize workoutPhotoResizeSize(int width, int height) {
  final double scale = <double>[1, 1080 / width, 1920 / height]
      .reduce((double smaller, double candidate) => smaller < candidate ? smaller : candidate);
  return WorkoutPhotoSize((width * scale).round(), (height * scale).round());
}

Future<Uint8List> prepareWorkoutPhoto(XFile photo) =>
    platform.prepareWorkoutPhoto(photo);
