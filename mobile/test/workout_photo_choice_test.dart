import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mayos_mobile/src/features/player/workout/workout_share_card.dart';
import 'support/fake_analytics_client.dart';

void main() {
  testWidgets('photo choice supports camera, gallery and no photo in English and Arabic',
      (WidgetTester tester) async {
    final List<ImageSource> picked = <ImageSource>[];
    final List<String> selectedSources = <String>[];
    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(textScaler: TextScaler.linear(2)),
      child: MaterialApp(
        home: Builder(builder: (BuildContext context) {
          return Scaffold(
            body: TextButton(
              onPressed: () => chooseWorkoutPhoto(
                context,
                languageCode: 'en',
                onSourceSelected: selectedSources.add,
                pickImage: (ImageSource source) async {
                  picked.add(source);
                  return null;
                },
              ),
              child: const Text('open'),
            ),
          );
        }),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Take photo'), findsOneWidget);
    expect(find.text('Choose from gallery'), findsOneWidget);
    expect(find.text('No photo'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Take photo'));
    await tester.pumpAndSettle();
    expect(picked, <ImageSource>[ImageSource.camera]);
    expect(selectedSources, isEmpty);

    await tester.tap(find.text('Choose from gallery'));
    await tester.pumpAndSettle();
    expect(picked.last, ImageSource.gallery);
    expect(selectedSources, isEmpty);
    expect(find.text('No photo'), findsOneWidget);
    await tester.tap(find.text('No photo'));
    await tester.pumpAndSettle();
    expect(selectedSources, <String>['none']);
  });

  testWidgets('picker exception ends the flow and records picker_error',
      (WidgetTester tester) async {
    int attempts = 0;
    final List<String> failureStages = <String>[];
    final FakeAnalyticsClient analytics = FakeAnalyticsClient();
    WorkoutPhotoChoiceResult? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (BuildContext context) {
        return Scaffold(
          body: TextButton(
            onPressed: () async {
              result = await chooseWorkoutPhoto(
                context,
                languageCode: 'ar',
                onFailureStage: (String stage) {
                  failureStages.add(stage);
                  WorkoutShareFlowFeedback(overlay: Overlay.of(context),
                    source: 'home', analytics: analytics, languageCode: 'ar').failed(stage);
                },
                pickImage: (ImageSource source) async {
                  attempts++;
                  throw PlatformException(code: 'photo_access_denied');
                },
              );
            },
            child: const Text('open'),
          ),
        );
      }),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('التقط صورة'), findsOneWidget);
    expect(find.text('اختر من المعرض'), findsOneWidget);
    expect(find.text('بدون صورة'), findsOneWidget);
    await tester.tap(find.text('التقط صورة'));
    await tester.pumpAndSettle();
    expect(attempts, 1);
    expect(failureStages, <String>['picker_error']);
    expect(analytics.events.single['properties'], <String, Object>{
      'source': 'home', 'stage': 'picker_error',
    });
    await tester.pumpAndSettle();
    expect(find.text('بدون صورة'), findsNothing);
    expect(result?.cancelled, isTrue);
  });

  testWidgets('empty gallery result has no failure event and choices remain available', (tester) async {
    final List<String> failureStages = <String>[];
    final FakeAnalyticsClient analytics = FakeAnalyticsClient();
    WorkoutPhotoChoiceResult? choice;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (BuildContext context) => Scaffold(
      body: TextButton(onPressed: () async {
        choice = await chooseWorkoutPhoto(context, languageCode: 'en',
          onFailureStage: (String stage) {
            failureStages.add(stage);
            WorkoutShareFlowFeedback(overlay: Overlay.of(context), source: 'finish',
              analytics: analytics, languageCode: 'en').failed(stage);
          },
          pickImage: (_) async => null);
      }, child: const Text('open')),
    ))));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose from gallery'));
    await tester.pumpAndSettle();
    expect(failureStages, isEmpty);
    expect(analytics.events, isEmpty);
    expect(find.text('No photo'), findsOneWidget);
    await tester.tap(find.text('No photo'));
    await tester.pumpAndSettle();
    expect(choice?.cancelled, isFalse);
  });

  testWidgets('dismissing photo choice is cancelled, distinct from no photo',
      (WidgetTester tester) async {
    WorkoutPhotoChoiceResult? result;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (BuildContext context) => Scaffold(
      body: TextButton(onPressed: () async {
        result = await chooseWorkoutPhoto(context, languageCode: 'en');
      }, child: const Text('open')),
    ))));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.text('No photo'))).pop();
    await tester.pumpAndSettle();
    expect(result?.cancelled, isTrue);
  });

  testWidgets('selected photo survives replacement of the page while picker is open',
      (WidgetTester tester) async {
    final Uint8List photo = Uint8List.fromList(<int>[1, 2, 3]);
    final Completer<XFile?> picker = Completer<XFile?>();
    WorkoutPhotoChoiceResult? result;
    BuildContext? startingContext;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (BuildContext context) {
      startingContext = context;
      return Scaffold(body: TextButton(onPressed: () async {
        result = await chooseWorkoutPhoto(context, languageCode: 'en',
          pickImage: (ImageSource _) => picker.future);
      }, child: const Text('open')));
    })));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose from gallery'));
    await tester.pump();
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Text('replacement page'))));
    await tester.pumpAndSettle();
    expect(startingContext!.mounted, isFalse);
    picker.complete(XFile.fromData(photo));
    await tester.pumpAndSettle();
    expect(await result?.photoFile?.readAsBytes(), orderedEquals(photo));
    expect(result?.cancelled, isFalse);
  });
}
