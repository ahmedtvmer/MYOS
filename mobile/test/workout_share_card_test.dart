import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mayos_mobile/src/core/personal_records.dart';
import 'package:mayos_mobile/src/features/player/workout/workout_share_card.dart';

void main() {
  testWidgets('card shows lifting stats, day and exercise-count PR badge',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: WorkoutShareCard(
          languageCode: 'en',
          dayName: 'Push A',
          duration: Duration(minutes: 72),
          stats: WorkoutSummaryStats(
              exercisesDone: 2, workingSets: 6, totalVolumeKg: 12345.6),
          records: <WorkoutRecord>[
            WorkoutRecord(
                exerciseName: 'Bench Press',
                exerciseId: 'bench_press',
                kind: PrRecordKind.weight,
                value: 100,
                reps: 5),
            WorkoutRecord(
                exerciseName: 'Bench Press',
                exerciseId: 'bench_press',
                kind: PrRecordKind.e1rm,
                value: 110,
                reps: 5),
            WorkoutRecord(
                exerciseName: 'Row',
                exerciseId: 'row_a',
                kind: PrRecordKind.mostReps,
                value: 20,
                reps: 20),
            WorkoutRecord(
                exerciseName: 'Row',
                exerciseId: 'row_b',
                kind: PrRecordKind.mostReps,
                value: 22,
                reps: 22),
          ],
        ),
      ),
    ));
    expect(find.text('🏆 3 PRs'), findsOneWidget);
    expect(find.text('Push A'), findsOneWidget);
    expect(find.text('1h 12m'), findsOneWidget);
    expect(find.text('12,346 kg'), findsOneWidget);
    expect(find.text('6'), findsOneWidget);
    expect(find.text('DURATION'), findsOneWidget);
    expect(find.text('TOTAL VOLUME'), findsOneWidget);
    expect(find.text('TICKED WORKING SETS'), findsOneWidget);
    expect(find.textContaining('Body weight'), findsNothing);
    expect(find.textContaining('Calories'), findsNothing);
    expect(find.textContaining('سعرات'), findsNothing);
  });

  testWidgets('cardio-only card shows minutes and omits lifting stats and PRs',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: WorkoutShareCard(
          languageCode: 'ar',
          dayName: 'Day',
          duration: Duration(minutes: 58),
          stats: WorkoutSummaryStats(
              exercisesDone: 0,
              workingSets: 0,
              totalVolumeKg: 0,
              cardioMinutes: 30,
              cardioCaloriesKcal: 500),
          records: <WorkoutRecord>[],
        ),
      ),
    ));
    expect(find.text('30 دقائق'), findsOneWidget);
    expect(find.text('58د'), findsOneWidget);
    expect(find.text('المدة'), findsOneWidget);
    expect(find.text('تمارين اللياقة'), findsOneWidget);
    expect(find.text('🏆 0 PRs'), findsNothing);
    expect(find.text('Day'), findsNothing);
    expect(find.textContaining('سعرات'), findsNothing);
  });

  testWidgets('Arabic card at 2x text scale keeps the generic day out',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(720, 1280);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final GlobalKey boundaryKey = GlobalKey();
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (BuildContext context) {
        return MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2)),
          child: Scaffold(
            body: RepaintBoundary(
              key: boundaryKey,
              child: WorkoutShareCard(
                languageCode: 'ar',
                dayName: 'Day',
                duration: Duration(minutes: 72),
                stats: WorkoutSummaryStats(
                    exercisesDone: 1, workingSets: 3, totalVolumeKg: 1000),
                records: <WorkoutRecord>[],
              ),
            ),
          ),
        );
      }),
    ));
    expect(find.text('Day'), findsNothing);
    expect(tester.takeException(), isNull);
    expect(find.text('72د'), findsNothing);
    expect(find.text('1س 12د'), findsOneWidget);
    final RenderRepaintBoundary boundary = boundaryKey.currentContext!
        .findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 3);
    expect(image.width, 1080);
    expect(image.height, 1920);
    image.dispose();
  });
}
