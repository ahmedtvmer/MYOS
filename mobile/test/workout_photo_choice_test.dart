import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mayos_mobile/src/features/player/workout/workout_share_card.dart';

void main() {
  testWidgets('photo choice supports camera, gallery and no photo in English and Arabic',
      (WidgetTester tester) async {
    final List<ImageSource> picked = <ImageSource>[];
    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(textScaler: TextScaler.linear(2)),
      child: MaterialApp(
        home: Builder(builder: (BuildContext context) {
          return Scaffold(
            body: TextButton(
              onPressed: () => chooseWorkoutPhoto(
                context,
                languageCode: 'en',
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

    await tester.tap(find.text('Choose from gallery'));
    await tester.pumpAndSettle();
    expect(picked.last, ImageSource.gallery);
    expect(find.text('No photo'), findsOneWidget);
    await tester.tap(find.text('No photo'));
    await tester.pumpAndSettle();
  });

  testWidgets('picker denial returns to choices and no photo remains usable',
      (WidgetTester tester) async {
    int attempts = 0;
    Uint8List? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (BuildContext context) {
        return Scaffold(
          body: TextButton(
            onPressed: () async {
              result = await chooseWorkoutPhoto(
                context,
                languageCode: 'ar',
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
    expect(find.text('بدون صورة'), findsOneWidget);
    await tester.tap(find.text('بدون صورة'));
    await tester.pumpAndSettle();
    expect(result, isNull);
  });
}
