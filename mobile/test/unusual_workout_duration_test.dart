import 'package:flutter_test/flutter_test.dart';
import 'package:mayos_mobile/src/features/player/workout/unusual_workout_duration.dart';

void main() {
  test('flags only durations below five minutes', () {
    expect(needsWorkoutDurationConfirmation(durationSeconds: 299), isTrue);
    expect(needsWorkoutDurationConfirmation(durationSeconds: 300), isFalse);
  });

  test('compares with twice the cached latest session duration', () {
    expect(needsWorkoutDurationConfirmation(durationSeconds: 3600, lastSessionDurationSeconds: 1800), isFalse);
    expect(needsWorkoutDurationConfirmation(durationSeconds: 3601, lastSessionDurationSeconds: 1800), isTrue);
  });

  test('uses a three hour fallback only when cached duration is unavailable', () {
    expect(needsWorkoutDurationConfirmation(durationSeconds: 10800), isFalse);
    expect(needsWorkoutDurationConfirmation(durationSeconds: 10801), isTrue);
  });
}
