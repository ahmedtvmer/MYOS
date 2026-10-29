import 'dart:typed_data';

import 'workout_card_action_adapter.dart';
import 'workout_card_action_platform_stub.dart'
    if (dart.library.js_interop) 'workout_card_action_platform_web.dart'
    as platform;

WorkoutCardActionAdapter createWorkoutCardActionAdapter(Uint8List pngBytes) =>
    platform.createWorkoutCardActionAdapter(pngBytes);
