import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mayos_mobile/src/core/personal_records.dart';
import 'package:mayos_mobile/src/features/player/workout/pr_celebration.dart';

WorkoutRecord _record(PrRecordKind kind, double value, int reps) => WorkoutRecord(
      exerciseName: 'Bench Press',
      kind: kind,
      value: value,
      reps: reps,
    );

void main() {
  testWidgets('PR celebration picks weight first and advances after two seconds',
      (WidgetTester tester) async {
    bool advanced = false;
    await tester.pumpWidget(MaterialApp(
      home: PrCelebration(
        records: <WorkoutRecord>[
          _record(PrRecordKind.mostReps, 20, 20),
          _record(PrRecordKind.e1rm, 140, 5),
          _record(PrRecordKind.weight, 100, 5),
        ],
        languageCode: 'en',
        onComplete: () => advanced = true,
      ),
    ));
    expect(find.text('New PR!'), findsOneWidget);
    expect(find.text('Bench Press · 100 kg × 5'), findsOneWidget);
    expect(advanced, isFalse);
    await tester.pump(const Duration(milliseconds: 1999));
    expect(advanced, isFalse);
    await tester.pump(const Duration(milliseconds: 1));
    expect(advanced, isTrue);
  });

  testWidgets('reduce motion keeps trophy and text and omits confetti',
      (WidgetTester tester) async {
    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(disableAnimations: true),
      child: MaterialApp(
        home: PrCelebration(
          records: <WorkoutRecord>[_record(PrRecordKind.mostReps, 20, 20)],
          languageCode: 'ar',
          onComplete: () {},
        ),
      ),
    ));
    expect(find.byIcon(Icons.emoji_events), findsOneWidget);
    expect(find.text('رقم قياسي جديد!'), findsOneWidget);
    expect(find.text('Bench Press · 20 تكرار'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('prCelebration.confetti')), findsNothing);
  });
}
