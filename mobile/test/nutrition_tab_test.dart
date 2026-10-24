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
    final FakeMyosApi fake = _fake()
      ..nutritionState = <String, dynamic>{'state': 'not_started', 'targets': null,
        'adherence_days': List<Map<String, dynamic>>.generate(7, (int index) => <String, dynamic>{
          'date': '2026-10-${24 - index}', 'value': index == 0 ? 'roughly' : null}),
        'latest_weight': 70.0, 'target_weight': 65.0, 'coach_sees_adherence': true};
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
    await tester.drag(find.byType(ListView), const Offset(0, -1200));
    await tester.pumpAndSettle();
    expect(tester.widgetList<Tooltip>(find.byType(Tooltip)), hasLength(7));
    expect(find.text('Your coach sees your Nutrition adherence.'), findsOneWidget);
    expect(find.textContaining('70.0'), findsOneWidget);
    expect(find.textContaining('65.0'), findsOneWidget);
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

  for (final ThemeData theme in <ThemeData>[ThemeData.light(), ThemeData.dark()]) {
    testWidgets('adherence control and seven-day strip render in both themes', (WidgetTester tester) async {
      final FakeMyosApi fake = _fake()
        ..nutritionState = <String, dynamic>{'state': 'ready', 'goal': 'maintain',
          'goal_reason': <String, dynamic>{'code': 'default'}, 'daily_activity': 'mostly_sitting',
          'targets': <String, dynamic>{'calories': 2000, 'protein_g': 140, 'carbs_g': 220, 'fat_g': 70},
          'adherence_days': List<Map<String, dynamic>>.generate(7, (int index) => <String, dynamic>{
            'date': '2026-10-${24 - index}', 'value': <String?>['on_target', 'roughly', 'off', null][index % 4],
          }),
          'latest_weight': 70.5, 'target_weight': 65, 'coach_sees_adherence': true};
      await tester.pumpWidget(_app(fake, 'en', theme));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView), const Offset(0, -1200));
      await tester.pumpAndSettle();
      final List<Tooltip> adherenceTooltips = tester.widgetList<Tooltip>(find.byType(Tooltip)).toList();
      expect(adherenceTooltips, hasLength(7));
      expect(adherenceTooltips.map((Tooltip tooltip) => tooltip.message), contains('2026-10-24: On target'));
      expect(adherenceTooltips.map((Tooltip tooltip) => tooltip.message), contains('2026-10-21: Unlogged'));
      expect(find.byIcon(Icons.circle), findsAtLeastNWidgets(1));
      expect(find.byIcon(Icons.change_history), findsAtLeastNWidgets(1));
      expect(find.byIcon(Icons.square), findsAtLeastNWidgets(1));
      expect(find.byIcon(Icons.circle_outlined), findsAtLeastNWidgets(1));
      expect(tester.widgetList<Icon>(find.byIcon(Icons.circle)).every(
        (Icon mark) => mark.color == theme.colorScheme.primary), isTrue);
      expect(tester.widgetList<Icon>(find.byIcon(Icons.change_history)).every(
        (Icon mark) => mark.color == theme.colorScheme.tertiary), isTrue);
      expect(tester.widgetList<Icon>(find.byIcon(Icons.square)).every(
        (Icon mark) => mark.color == theme.colorScheme.error), isTrue);
      expect(tester.widgetList<Icon>(find.byIcon(Icons.circle_outlined)).every(
        (Icon mark) => mark.color == theme.colorScheme.outlineVariant), isTrue);
      expect(find.text('How did today go?'), findsOneWidget);
      expect(find.text('On target'), findsOneWidget);
      expect(find.text('Roughly'), findsOneWidget);
      expect(find.text('Off'), findsOneWidget);
      await tester.ensureVisible(find.text('Off'));
      await tester.tap(find.text('Off'));
      await tester.pumpAndSettle();
      expect(tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Off')).selected, isTrue);
      await tester.tap(find.text('On target'));
      await tester.pumpAndSettle();
      expect(fake.nutritionAdherenceValues, <String>['off', 'on_target']);
      expect(tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'On target')).selected, isTrue);
      expect(find.text('Your coach sees your Nutrition adherence.'), findsOneWidget);
      expect(find.textContaining('70.5'), findsOneWidget);
      expect(find.textContaining('65'), findsOneWidget);
    });
  }

  testWidgets('Arabic adherence uses glossary copy and RTL', (WidgetTester tester) async {
    final FakeMyosApi fake = _fake()
      ..nutritionState = <String, dynamic>{'state': 'ready', 'goal': 'maintain',
        'goal_reason': <String, dynamic>{'code': 'default'},
        'targets': <String, dynamic>{'calories': 2000, 'protein_g': 140, 'carbs_g': 220, 'fat_g': 70},
        'adherence_days': List<Map<String, dynamic>>.generate(7, (int index) => <String, dynamic>{
          'date': '2026-10-${24 - index}', 'value': <String?>['on_target', 'roughly', 'off', null][index % 4]})};
    await tester.pumpWidget(_app(fake, 'ar', ThemeData.light()));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -1200));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('كيف كان يومك؟'));
    expect(find.text('كيف كان يومك؟'), findsOneWidget);
    expect(find.text('على الهدف'), findsOneWidget);
    expect(find.text('مدربك يرى الالتزام الغذائي.'), findsNothing);
    final Iterable<String?> tooltipMessages = tester.widgetList<Tooltip>(find.byType(Tooltip))
        .map((Tooltip tooltip) => tooltip.message);
    expect(tooltipMessages, contains('2026-10-24: على الهدف'));
    expect(tooltipMessages, contains('2026-10-23: تقريبًا'));
    expect(tooltipMessages, contains('2026-10-22: بعيد عن الهدف'));
    expect(tooltipMessages, contains('2026-10-21: غير مسجل'));
    expect(tooltipMessages.any((String? message) =>
      message != null && <String>['on_target', 'roughly', 'off', 'unlogged']
          .any(message.contains)), isFalse);
    expect(tester.widget<Directionality>(find.byType(Directionality).last).textDirection, TextDirection.rtl);
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

