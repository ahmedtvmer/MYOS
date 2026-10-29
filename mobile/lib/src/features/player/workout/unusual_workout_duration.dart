/// Whether a workout duration should be confirmed before finishing.
bool needsWorkoutDurationConfirmation({
  required int durationSeconds,
  int? lastSessionDurationSeconds,
}) {
  if (durationSeconds < 5 * 60) return true;
  final int threshold = lastSessionDurationSeconds == null || lastSessionDurationSeconds <= 0
      ? 3 * 60 * 60
      : lastSessionDurationSeconds * 2;
  return durationSeconds > threshold;
}
