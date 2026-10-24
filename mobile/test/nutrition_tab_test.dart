import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myos_mobile/src/core/api_client.dart';
import 'package:myos_mobile/src/core/display_language/controller.dart';
import 'package:myos_mobile/src/core/token_store.dart';
import 'package:myos_mobile/src/features/player/nutrition/nutrition_tab.dart';
import 'package:myos_mobile/src/providers.dart';

import 'support/fake_myos_api.dart';

void main() {
  testWidgets('setup saves activity and shows plate targets', (WidgetTester tester) async {
    final FakeMyosApi fake = _fake();
    await tester.pumpWidget(_app(fake, 'en', ThemeData.light()));
    await tester.pumpAndSettle();
    expect(find.text('Confirm your sex for Nutrition targets.'), findsOneWidget);
    expect(find.text('What is your Daily activity?'), findsOneWidget);
    await tester.tap(find.text('I confirm'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show my targets'));
    await tester.pumpAndSettle();
    expect(find.text('2000'), findsOneWidget);
    expect(find.text('Protein'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(find.textContaining('Training profile'), findsOneWidget);
    expect(fake.lastNutritionSetupBody?['sex'], 'female');
    expect(fake.lastNutritionSetupBody?['sex_confirmed'], isTrue);
  });

  testWidgets('positive screening shows referral and no targets', (WidgetTester tester) async {
    final FakeMyosApi fake = _fake();
    await tester.pumpWidget(_app(fake, 'en', ThemeData.dark()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('I confirm'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Are you pregnant or breastfeeding?'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show my targets'));
    await tester.pumpAndSettle();
    expect(fake.lastNutritionSetupBody?['screening'], containsPair('pregnant_or_breastfeeding', true));
    expect(find.textContaining('registered dietitian'), findsOneWidget);
    expect(find.text('2000'), findsNothing);
  });

  testWidgets('under-18 state displays no targets', (WidgetTester tester) async {
    final FakeMyosApi fake = _fake()
      ..nutritionState = <String, dynamic>{'state': 'under_18', 'targets': null};
    await tester.pumpWidget(_app(fake, 'en', ThemeData.light()));
    await tester.pumpAndSettle();
    expect(find.textContaining('under 18'), findsOneWidget);
    expect(find.text('Show my targets'), findsNothing);
  });

  testWidgets('Arabic setup is right to left', (WidgetTester tester) async {
    await tester.pumpWidget(_app(_fake(), 'ar', ThemeData.light()));
    await tester.pumpAndSettle();
    expect(find.text('إعداد الأهداف الغذائية'), findsOneWidget);
    final Directionality direction = tester.widget(find.byType(Directionality).last);
    expect(direction.textDirection, TextDirection.rtl);
  });

  testWidgets('saved plate renders in dark theme and Arabic', (WidgetTester tester) async {
    final FakeMyosApi fake = _fake()
      ..nutritionState = <String, dynamic>{
      'state': 'ready', 'goal': 'lose', 'goal_reason': <String, dynamic>{'code': 'current_goal', 'goal_text': 'fat loss'},
        'targets': <String, dynamic>{'calories': 1800, 'protein_g': 140,
          'carbs_g': 170, 'fat_g': 60},
      };
    await tester.pumpWidget(_app(fake, 'ar', ThemeData.dark()));
    await tester.pumpAndSettle();
    expect(find.text('التغذية'), findsOneWidget);
    expect(find.text('البروتين'), findsOneWidget);
    expect(find.text('الماكروز'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(find.textContaining('هدف التغذية'), findsOneWidget);
    expect(find.text('1800'), findsOneWidget);
  });

  testWidgets('nutrition load error offers retry without referral', (WidgetTester tester) async {
    final FakeMyosApi fake = _fake()..nutritionLoadFails = true;
    await tester.pumpWidget(_app(fake, 'en', ThemeData.light()));
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsOneWidget);
    expect(find.textContaining('dietitian'), findsNothing);
    fake.nutritionLoadFails = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Set up Nutrition targets'), findsOneWidget);
  });

  testWidgets('incomplete state shows server message without setup form', (WidgetTester tester) async {
    final FakeMyosApi fake = _fake()
      ..nutritionState = <String, dynamic>{'state': 'incomplete', 'targets': null,
        'message': 'Complete your Training profile before setting Nutrition targets.'};
    await tester.pumpWidget(_app(fake, 'en', ThemeData.light()));
    await tester.pumpAndSettle();
    expect(find.text('Complete your Training profile before setting Nutrition targets.'), findsOneWidget);
    expect(find.text('Confirm your sex for Nutrition targets.'), findsNothing);
  });

  testWidgets('ready targets let the Player change Daily activity', (WidgetTester tester) async {
    final FakeMyosApi fake = _fake()
      ..nutritionState = <String, dynamic>{'state': 'ready', 'goal': 'maintain',
        'goal_reason': <String, dynamic>{'code': 'default'}, 'daily_activity': 'mostly_sitting',
        'targets': <String, dynamic>{'calories': 2000, 'protein_g': 140, 'carbs_g': 220, 'fat_g': 70}};
    await tester.pumpWidget(_app(fake, 'en', ThemeData.light()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Daily activity'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Physical job'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Update Nutrition targets'));
    await tester.pumpAndSettle();
    expect(fake.lastNutritionActivity, 'physical_job');
    expect(find.text('Physical job'), findsOneWidget);
  });
}

FakeMyosApi _fake() => FakeMyosApi()
  ..issuedToken = 'nutrition-token'
  ..currentUsername = 'nutrition-player'
  ..tokenValid = true
  ..gender = 'female'
  ..profileExists = true;

Widget _app(FakeMyosApi fake, String language, ThemeData theme) => ProviderScope(
      overrides: <Override>[
        apiClientProvider.overrideWith((ref) {
          final InMemoryTokenStore tokens = InMemoryTokenStore();
          tokens.save('nutrition-token');
          return ApiClient(tokens: tokens, baseUrl: 'http://test.local', adapter: fake.adapter);
        }),
        systemDisplayLanguageProvider.overrideWithValue(language),
      ],
      child: MaterialApp(theme: theme, home: const Scaffold(body: NutritionTab())),
    );

