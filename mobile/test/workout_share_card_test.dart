import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mayos_mobile/src/core/models.dart';
import 'package:mayos_mobile/src/core/personal_records.dart';
import 'package:mayos_mobile/src/features/player/workout/workout_share_card.dart';
import 'package:mayos_mobile/src/features/player/workout/workout_card_action_adapter.dart';
import 'package:mayos_mobile/src/features/player/workout/workout_card_web_action_adapter.dart';
import 'support/fake_analytics_client.dart';

void main() {
  test('share analytics records only approved properties once and respects opt-out', () {
    final FakeAnalyticsClient analytics = FakeAnalyticsClient();
    analytics.shareCardShared(source: 'finish', hasPhoto: true, photoSource: 'camera');
    expect(analytics.events, hasLength(1));
    expect(analytics.events.single, <String, Object>{
      'event': 'share_card_shared',
      'properties': <String, Object>{
        'source': 'finish',
        'has_photo': true,
        'photo_source': 'camera',
      },
    });

    analytics.setEnabled(false);
    analytics.shareCardShared(source: 'home', hasPhoto: false, photoSource: 'none');
    expect(analytics.events, hasLength(1));
  });

  testWidgets('share card shows the performed date in English and Arabic', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: WorkoutShareCard(
      languageCode: 'en', dayName: 'Push A', performedDate: DateTime(2026, 10, 28),
      stats: const WorkoutSummaryStats(exercisesDone: 0, workingSets: 0, totalVolumeKg: 0),
      records: const <WorkoutRecord>[],
    ))));
    expect(find.text('Wed, 28 Oct 2026'), findsOneWidget);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: WorkoutShareCard(
      languageCode: 'ar', dayName: 'Push A', performedDate: DateTime(2026, 10, 28),
      stats: const WorkoutSummaryStats(exercisesDone: 0, workingSets: 0, totalVolumeKg: 0),
      records: const <WorkoutRecord>[],
    ))));
    expect(find.text('الأربعاء 28 أكتوبر 2026'), findsOneWidget);
  });

  test('share flow tracks completion once, but not dismissal or opt-out', () async {
    final FakeAnalyticsClient analytics = FakeAnalyticsClient();
    final WorkoutPhotoChoiceResult photo = WorkoutPhotoChoiceResult.noPhoto();
    int calls = 0;
    await shareWorkoutCardAndTrack(
      share: () async { calls++; return true; }, analytics: analytics,
      source: 'finish', photo: photo,
    );
    expect(calls, 1);
    expect(analytics.events.single['properties'], <String, Object>{
      'source': 'finish', 'has_photo': false, 'photo_source': 'none',
    });
    await shareWorkoutCardAndTrack(
      share: () async { calls++; return false; }, analytics: analytics,
      source: 'home', photo: photo,
    );
    expect(analytics.events, hasLength(1));
    analytics.setEnabled(false);
    await shareWorkoutCardAndTrack(
      share: () async { calls++; return true; }, analytics: analytics,
      source: 'home', photo: photo,
    );
    expect(analytics.events, hasLength(1));
    expect(calls, 3);
  });


  testWidgets('preview waits for Share or Save tap and closing cancels',
      (WidgetTester tester) async {
    int shares = 0;
    int saves = 0;
    bool? result;
    await tester.pumpWidget(MaterialApp(home: Builder(
      builder: (BuildContext context) => Scaffold(
        body: TextButton(onPressed: () async {
          result = await showWorkoutCardPreview(
            context, Uint8List.fromList(<int>[137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 1, 0, 0, 0, 1, 8, 6, 0, 0, 0, 31, 21, 196, 137, 0, 0, 0, 13, 73, 68, 65, 84, 120, 156, 99, 248, 207, 192, 240, 31, 0, 5, 0, 1, 255, 137, 153, 61, 29, 0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130]), languageCode: 'en',
            share: () async { shares++; return true; },
            save: () async { saves++; return true; },
          );
        }, child: const Text('open')),
      ),
    )));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Share'), findsOneWidget);
    expect(find.text('Save image'), findsOneWidget);
    expect(shares, 0);
    expect(saves, 0);
    await tester.tap(find.text('Save image'));
    await tester.pumpAndSettle();
    expect(saves, 1);
    expect(shares, 0);
    expect(result, isTrue);
  });

  testWidgets('share failure in preview shows a localized error',
      (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(home: Builder(
      builder: (BuildContext context) => Scaffold(
        body: TextButton(onPressed: () => showWorkoutCardPreview(
          context, Uint8List.fromList(<int>[137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 1, 0, 0, 0, 1, 8, 6, 0, 0, 0, 31, 21, 196, 137, 0, 0, 0, 13, 73, 68, 65, 84, 120, 156, 99, 248, 207, 192, 240, 31, 0, 5, 0, 1, 255, 137, 153, 61, 29, 0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130]), languageCode: 'en',
          share: () async => throw StateError('share failed'),
          save: () async => true,
        ), child: const Text('open')),
      ),
    )));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('workoutCard.share')));
    await tester.pumpAndSettle();
    expect(find.text('Could not create or share the image. Try again.'), findsAtLeastNWidgets(1));
    expect(find.text('Save image'), findsOneWidget);
  });

  testWidgets('capture timeout reports a localized error',
      (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(home: Builder(
      builder: (BuildContext context) => Scaffold(body: TextButton(
        onPressed: () => captureAndPreviewWorkoutCard(context, const WorkoutShareCard(
          languageCode: 'ar', dayName: null, stats: WorkoutSummaryStats(
            exercisesDone: 0, workingSets: 0, totalVolumeKg: 0), records: <WorkoutRecord>[]),
          capture: () => Completer<Uint8List>().future,
          captureTimeout: const Duration(milliseconds: 1)), child: const Text('capture'))),
    )));
    await tester.tap(find.text('capture'));
    await tester.pump(const Duration(milliseconds: 5));
    await tester.pump();
    expect(find.textContaining('تعذر إنشاء الصورة'), findsAtLeastNWidgets(1));
    expect(find.text('Share'), findsNothing);
  });

  testWidgets('closing preview invokes neither share nor save',
      (WidgetTester tester) async {
    int calls = 0;
    await tester.pumpWidget(MaterialApp(home: Builder(
      builder: (BuildContext context) => Scaffold(
        body: TextButton(onPressed: () => showWorkoutCardPreview(
          context, Uint8List.fromList(<int>[137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 1, 0, 0, 0, 1, 8, 6, 0, 0, 0, 31, 21, 196, 137, 0, 0, 0, 13, 73, 68, 65, 84, 120, 156, 99, 248, 207, 192, 240, 31, 0, 5, 0, 1, 255, 137, 153, 61, 29, 0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130]), languageCode: 'en',
          share: () async { calls++; return true; },
          save: () async { calls++; return true; },
        ), child: const Text('open')),
      ),
    )));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(calls, 0);
  });

  testWidgets('Home latest workout omits unknown duration but keeps session stats',
      (WidgetTester tester) async {
    final LatestSession session = LatestSession.fromJson(<String, dynamic>{
      'session_id': 'latest',
      'session_date': '2026-10-29',
      'split_name': 'Upper 1',
      'duration_seconds': null,
      'working_sets': 3,
      'volume_kg': 1500,
      'cardio_minutes': 0,
      'pr_count': 0,
    });
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: latestSessionShareCard(
          session: session,
          languageCode: 'en',
        ),
      ),
    ));
    expect(find.text('Duration'), findsNothing);
    expect(find.text('0m'), findsNothing);
    expect(find.text('1,500'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('Finish share card continues to show its elapsed duration',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: WorkoutShareCard(
          languageCode: 'en',
          dayName: 'Upper 1',
          duration: Duration(minutes: 58),
          stats: WorkoutSummaryStats(
              exercisesDone: 1, workingSets: 3, totalVolumeKg: 1500),
          records: <WorkoutRecord>[],
        ),
      ),
    ));
    expect(find.text('58m'), findsOneWidget);
    expect(find.text('Duration'), findsOneWidget);
  });

  testWidgets('photo background keeps its source aspect ratio when decoded',
      (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: WorkoutShareCard(
          languageCode: 'en',
          dayName: null,
          duration: Duration(minutes: 1),
          stats: WorkoutSummaryStats(
              exercisesDone: 1, workingSets: 1, totalVolumeKg: 10),
          records: <WorkoutRecord>[],
          photoBytes: Uint8List.fromList(<int>[1, 2, 3]),
        ),
      ),
    ));
    final Image photo = tester.widget<Image>(find.byType(Image).first);
    expect(photo.fit, BoxFit.cover);
    expect(photo.alignment, Alignment.center);
    final ResizeImage decoded = photo.image as ResizeImage;
    expect(decoded.policy, ResizeImagePolicy.fit);
  });

  testWidgets('large stat values never use ellipsis in Arabic at 2x scale',
      (WidgetTester tester) async {
    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(textScaler: TextScaler.linear(2)),
      child: const MaterialApp(home: Scaffold(body: WorkoutShareCard(
        languageCode: 'ar', dayName: null, duration: Duration(minutes: 72),
        stats: WorkoutSummaryStats(exercisesDone: 1, workingSets: 3, totalVolumeKg: 12345),
        records: <WorkoutRecord>[],
      ))),
    ));
    final RenderParagraph volume = tester.renderObject(find.text('12,345'));
    expect(volume.didExceedMaxLines, isFalse);
    for (final String piece in <String>['د', '12', 'س', '1']) {
      expect(tester.renderObject<RenderParagraph>(find.text(piece)).didExceedMaxLines, isFalse);
    }
  });


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
    expect(find.text('3 personal records'), findsOneWidget);
    expect(find.text('Push A'), findsOneWidget);
    expect(find.text('1h 12m'), findsOneWidget);
    expect(find.text('12,346'), findsOneWidget);
    expect(find.text('6'), findsOneWidget);
    expect(find.text('Duration'), findsOneWidget);
    expect(find.text('Volume kg'), findsOneWidget);
    expect(find.text('Sets'), findsOneWidget);
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
    expect(tester.getTopLeft(find.text('د')).dx,
        lessThan(tester.getTopLeft(find.text('58')).dx),
        reason: 'Arabic duration unit sits to the left of its number');
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
    // Visual order left to right: د 12  س 1 (each unit left of its number,
    // hours on the right where an Arabic reader starts).
    final double minUnit = tester.getTopLeft(find.text('د')).dx;
    final double mins = tester.getTopLeft(find.text('12')).dx;
    final double hourUnit = tester.getTopLeft(find.text('س')).dx;
    final double hours = tester.getTopLeft(find.text('1')).dx;
    expect(minUnit < mins && mins < hourUnit && hourUnit < hours, isTrue);
    final RenderRepaintBoundary boundary = boundaryKey.currentContext!
        .findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 3);
    expect(image.width, 1080);
    expect(image.height, 1920);
    image.dispose();
  });
  testWidgets('card uses the approved signature layout and explicit typography',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SizedBox(
      width: 360, child: WorkoutShareCard(
        languageCode: 'en', dayName: 'Push A', duration: Duration(minutes: 58),
        stats: WorkoutSummaryStats(exercisesDone: 3, workingSets: 18,
          totalVolumeKg: 8420), records: <WorkoutRecord>[], prCount: 6),
    ))));
    expect(find.textContaining('🏆'), findsNothing);
    expect(find.text('6 personal records'), findsOneWidget);
    expect(find.text('Volume kg'), findsOneWidget);
    expect(find.text('Duration'), findsOneWidget);
    expect(find.text('Sets'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('workoutCard.logo')), findsOneWidget);
    for (final Text text in tester.widgetList<Text>(find.byType(Text))) {
      expect(text.style?.fontFamily, isNotNull, reason: 'Every card text owns its font style');
      expect(text.style?.decoration, isNot(TextDecoration.underline));
    }
  });

  testWidgets('Arabic card keeps large values on one line and mirrors signature',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SizedBox(
      width: 360, child: WorkoutShareCard(
        languageCode: 'ar', dayName: 'يوم الدفع', duration: Duration(minutes: 72),
        stats: WorkoutSummaryStats(exercisesDone: 3, workingSets: 18,
          totalVolumeKg: 12345), records: <WorkoutRecord>[], prCount: 1),
    ))));
    expect(find.text('12,345'), findsOneWidget);
    expect(find.text('الوزن كجم'), findsOneWidget);
    // Visual order left to right: د 12  س 1 (each unit left of its number,
    // hours on the right where an Arabic reader starts).
    final double minUnit = tester.getTopLeft(find.text('د')).dx;
    final double mins = tester.getTopLeft(find.text('12')).dx;
    final double hourUnit = tester.getTopLeft(find.text('س')).dx;
    final double hours = tester.getTopLeft(find.text('1')).dx;
    expect(minUnit < mins && mins < hourUnit && hourUnit < hours, isTrue);
    expect(tester.widget<Directionality>(find.byType(Directionality).last).textDirection,
      TextDirection.rtl);
    final Text volume = tester.widget<Text>(find.text('12,345'));
    expect(volume.maxLines, 1);
  });

  testWidgets('RTL mirrors the logo into the bottom-left signature position',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SizedBox(
      width: 360, child: WorkoutShareCard(languageCode: 'ar', dayName: null,
        stats: WorkoutSummaryStats(exercisesDone: 0, workingSets: 0,
          totalVolumeKg: 0), records: <WorkoutRecord>[]),
    ))));
    final Align logoPlacement = tester.widget<Align>(
      find.byKey(const ValueKey<String>('workoutCard.logoPlacement')));
    expect(logoPlacement.alignment.resolve(TextDirection.rtl), Alignment.bottomLeft);
  });

  testWidgets('capture actions keep Save distinct from Share',
      (WidgetTester tester) async {
    final _FakeWorkoutCardActions actions = _FakeWorkoutCardActions();
    await tester.pumpWidget(MaterialApp(home: Builder(
      builder: (BuildContext context) => Scaffold(body: TextButton(
        onPressed: () => captureAndPreviewWorkoutCard(context,
          const WorkoutShareCard(languageCode: 'en', dayName: 'Push A',
            stats: WorkoutSummaryStats(exercisesDone: 0, workingSets: 0,
              totalVolumeKg: 0), records: <WorkoutRecord>[]),
          capture: () async => Uint8List.fromList(<int>[
             137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82,
             0, 0, 0, 1, 0, 0, 0, 1, 8, 6, 0, 0, 0, 31, 21, 196, 137, 0,
             0, 0, 13, 73, 68, 65, 84, 120, 156, 99, 248, 207, 192, 240, 31,
             0, 5, 0, 1, 255, 137, 153, 61, 29, 0, 0, 0, 0, 73, 69, 78, 68,
             174, 66, 96, 130]),
          actionAdapter: actions), child: const Text('open'))),
    )));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('workoutCard.save')));
    await tester.pumpAndSettle();
    expect(actions.saves, 1);
    expect(actions.shares, 0);
  });

  testWidgets('pending share ignores a second tap callback',
      (WidgetTester tester) async {
    final Completer<bool> completion = Completer<bool>();
    int calls = 0;
    await tester.pumpWidget(MaterialApp(home: Builder(
      builder: (BuildContext context) => Scaffold(body: TextButton(
        onPressed: () => showWorkoutCardPreview(context, _validPngBytes(),
          languageCode: 'en', share: () { calls++; return completion.future; },
          save: () async => true), child: const Text('open'))),
    )));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final FilledButton shareButton = tester.widget<FilledButton>(
      find.byKey(const ValueKey<String>('workoutCard.share')));
    shareButton.onPressed!();
    shareButton.onPressed!();
    await tester.pump();
    expect(calls, 1);
    completion.complete(true);
    await tester.pumpAndSettle();
  });

  testWidgets('pending share blocks system Back',
      (WidgetTester tester) async {
    final Completer<bool> completion = Completer<bool>();
    await tester.pumpWidget(MaterialApp(home: Builder(
      builder: (BuildContext context) => Scaffold(body: TextButton(
        onPressed: () => showWorkoutCardPreview(context, _validPngBytes(),
          languageCode: 'en', share: () => completion.future,
          save: () async => true), child: const Text('open'))),
    )));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    tester.widget<FilledButton>(find.byKey(const ValueKey<String>('workoutCard.share')))
        .onPressed!();
    await tester.pump();
    expect(tester.widget<PopScope<dynamic>>(find.byType(PopScope)).canPop, isFalse);
    await Navigator.of(tester.element(
      find.byKey(const ValueKey<String>('workoutCard.share')))).maybePop();
    await tester.pump();
    expect(find.byKey(const ValueKey<String>('workoutCard.share')), findsOneWidget);
    completion.complete(true);
    await tester.pumpAndSettle();
  });

  testWidgets('photo decode failure shows localized share error',
      (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(home: Builder(
      builder: (BuildContext context) => Scaffold(body: TextButton(
        onPressed: () => shareWorkoutCard(context, WorkoutShareCard(
          languageCode: 'ar', dayName: null,
          stats: const WorkoutSummaryStats(exercisesDone: 0, workingSets: 0,
            totalVolumeKg: 0), records: const <WorkoutRecord>[],
          photoBytes: Uint8List.fromList(<int>[1, 2, 3]))),
        child: const Text('open'))),
    )));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.textContaining('تعذر إنشاء الصورة'), findsAtLeastNWidgets(1));
    expect(find.text('Share'), findsNothing);
  });

  test('web share calls the prepared share path synchronously and treats dismissal as incomplete', () async {
    final _FakeWebBindings bindings = _FakeWebBindings();
    final WebWorkoutCardActionAdapter actions = WebWorkoutCardActionAdapter(bindings);
    final Future<bool> pendingShare = actions.share();
    expect(bindings.shareCalls, 1);
    expect(bindings.downloadCalls, 0);
    bindings.shareCompletion.complete();
    expect(await pendingShare, isTrue);

    bindings.shareError = const WorkoutCardShareDismissed();
    expect(await actions.share(), isFalse);
    expect(bindings.downloadCalls, 0);
  });

  test('web Share falls back to Save when canShare is unavailable', () async {
    final _FakeWebBindings bindings = _FakeWebBindings()..canShareUnavailable = true;
    final WebWorkoutCardActionAdapter actions = WebWorkoutCardActionAdapter(bindings);
    expect(await actions.share(), isTrue);
    expect(bindings.shareCalls, 0);
    expect(bindings.downloadCalls, 1);
  });

  test('web Share falls back to Save when file sharing is unavailable', () async {
    final _FakeWebBindings bindings = _FakeWebBindings()..canShareFile = false;
    final WebWorkoutCardActionAdapter actions = WebWorkoutCardActionAdapter(bindings);
    expect(await actions.share(), isTrue);
    expect(bindings.shareCalls, 0);
    expect(bindings.downloadCalls, 1);
  });

}


class _FakeWorkoutCardActions implements WorkoutCardActionAdapter {
  int shares = 0;
  int saves = 0;
  @override
  Future<bool> share() async { shares++; return true; }
  @override
  Future<bool> save() async { saves++; return true; }
  @override
  void dispose() {}
}

Uint8List _validPngBytes() => Uint8List.fromList(<int>[137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 1, 0, 0, 0, 1, 8, 6, 0, 0, 0, 31, 21, 196, 137, 0, 0, 0, 13, 73, 68, 65, 84, 120, 156, 99, 248, 207, 192, 240, 31, 0, 5, 0, 1, 255, 137, 153, 61, 29, 0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130]);


class _FakeWebBindings implements WorkoutCardWebBindings {
  final Completer<void> shareCompletion = Completer<void>();
  bool canShareFile = true;
  bool canShareUnavailable = false;
  Object? shareError;
  int shareCalls = 0;
  int downloadCalls = 0;
  @override
  bool canShare() {
    if (canShareUnavailable) {
      throw NoSuchMethodError.withInvocation(
        Object(), Invocation.method(#canShare, const <Object?>[]));
    }
    return canShareFile;
  }
  @override
  Future<void> share() {
    shareCalls++;
    if (shareError case final Object error) {
      return Future<void>.error(error);
    }
    return shareCompletion.future;
  }
  @override
  void download() { downloadCalls++; }
  @override
  void dispose() {}
}
