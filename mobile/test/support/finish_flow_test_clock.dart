/// Advances the injected workout clock by one minute per read. Workout tests
/// that exercise a normal Finish flow then cross the five-minute prompt
/// boundary through their existing interactions, without waiting in real time.
DateTime Function() finishFlowTestClock() {
  DateTime now = DateTime.now();
  return () {
    final DateTime current = now;
    now = now.add(const Duration(minutes: 1));
    return current;
  };
}

