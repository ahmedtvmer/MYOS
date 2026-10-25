import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myos_mobile/src/core/api_client.dart';
import 'package:myos_mobile/src/core/display_language/controller.dart';
import 'package:myos_mobile/src/core/token_store.dart';
import 'package:myos_mobile/src/features/player/nutrition/nutrition_tab.dart';
import 'package:myos_mobile/src/features/coach/coach_nutrition_segment.dart';
import 'package:myos_mobile/src/features/coach/coach_charts_segment.dart';
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
    expect(find.textContaining('1800'), findsOneWidget);
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

  testWidgets('Coach-held targets show a badge and make Daily activity read-only',
      (WidgetTester tester) async {
    final FakeMyosApi fake = _fake()
      ..nutritionState = <String, dynamic>{'state': 'ready', 'goal': 'maintain',
        'goal_reason': <String, dynamic>{'code': 'default'}, 'daily_activity': 'mostly_sitting',
        'authority': 'coach', 'coach_sees_adherence': true,
        'targets': <String, dynamic>{'calories': 2000, 'protein_g': 140, 'carbs_g': 220, 'fat_g': 70}};
    await tester.pumpWidget(_app(fake, 'en', ThemeData.light()));
    await tester.pumpAndSettle();
    expect(find.text('Set by your coach'), findsOneWidget);
    await tester.tap(find.text('Daily activity'));
    await tester.pumpAndSettle();
    expect(find.text('Update Nutrition targets'), findsNothing);
    expect(find.text('Physical job'), findsNothing);
  });

  testWidgets('Player can see and decide a pending pace proposal', (WidgetTester tester) async {
    final FakeMyosApi fake = _fake()..nutritionState = <String, dynamic>{
      'state': 'ready', 'goal': 'lose', 'goal_reason': <String, dynamic>{'code': 'default'},
      'targets': <String, dynamic>{'calories': 1800, 'protein_g': 140, 'carbs_g': 170, 'fat_g': 60},
      'pace_proposal': <String, dynamic>{'id': 3, 'status': 'pending', 'stale': false,
        'payload': <String, dynamic>{'actual_rate_pct': -0.1, 'planned_rate_pct': -0.5,
          'calorie_change': -250, 'targets': <String, dynamic>{'calories': 1550}}},
    };
    await tester.pumpWidget(_app(fake, 'en', ThemeData.light()));
    await tester.pumpAndSettle();
    expect(find.text('Pace check proposal'), findsOneWidget);
    expect(find.text('Apply'), findsOneWidget);
    expect(find.text('Keep targets'), findsOneWidget);
    await tester.tap(find.text('Keep targets'));
    await tester.pumpAndSettle();
    expect(fake.nutritionPaceDecisions, <String>['kept']);
    expect(fake.nutritionState['targets']?['calories'], 1800);
    expect(find.text('Kept by Player'), findsOneWidget);
  });

  testWidgets('stale pace proposal still offers Keep without Apply', (WidgetTester tester) async {
    final FakeMyosApi fake = _fake()..nutritionState = <String, dynamic>{
      'state': 'ready', 'goal': 'lose', 'authority': 'player',
      'targets': <String, dynamic>{'calories': 1800, 'protein_g': 140, 'carbs_g': 170, 'fat_g': 60},
      'pace_proposal': <String, dynamic>{'id': 3, 'status': 'pending', 'stale': true,
        'payload': <String, dynamic>{'targets': <String, dynamic>{'calories': 1550}}},
    };
    await tester.pumpWidget(_app(fake, 'en', ThemeData.light()));
    await tester.pumpAndSettle();
    expect(find.text('Apply'), findsNothing);
    expect(find.text('Keep targets'), findsOneWidget);
    await tester.tap(find.text('Keep targets'));
    await tester.pumpAndSettle();
    expect(fake.nutritionPaceDecisions, <String>['kept']);
  });

  testWidgets('Coach authority shows Apply and Keep while read-only Coach sees decision only', (WidgetTester tester) async {
    final FakeMyosApi fake = _fake()
      ..coachPlayerNutrition = <String, dynamic>{
        'authority': 'coach', 'goal': 'lose',
        'targets': <String, dynamic>{'calories': 1800, 'protein_g': 140, 'carbs_g': 170, 'fat_g': 60},
        'target_options': <String, dynamic>{'daily': <String, dynamic>{'calories': 1800, 'protein_g': 140, 'carbs_g': 170, 'fat_g': 60}},
        'pace_proposal': <String, dynamic>{'id': 3, 'status': 'pending', 'stale': false,
          'payload': <String, dynamic>{'actual_rate_pct': -0.1, 'planned_rate_pct': -0.5,
            'calorie_change': -250, 'targets': <String, dynamic>{'calories': 1550}}},
      };
    await tester.pumpWidget(_app(fake, 'en', ThemeData.light(), home: const CoachChartsSegment(key: ValueKey<String>('authority-chart'), assignmentId: 'assignment')));
    await tester.pumpAndSettle();
    expect(find.text('Apply'), findsOneWidget);
    expect(find.text('Keep targets'), findsOneWidget);
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(fake.nutritionPaceDecisions, <String>['accepted']);
    expect(fake.coachPlayerNutrition['targets']?['calories'], 1550);
    expect(find.text('Accepted by Coach'), findsOneWidget);
    fake.coachPlayerNutrition = <String, dynamic>{...fake.coachPlayerNutrition,
      'authority': 'player', 'pace_proposal': <String, dynamic>{'id': 3, 'status': 'kept', 'stale': false,
        'payload': <String, dynamic>{'actual_rate_pct': -0.1, 'planned_rate_pct': -0.5,
          'targets': <String, dynamic>{'calories': 1800}}}};
    await tester.pumpWidget(_app(fake, 'en', ThemeData.light(), home: const CoachChartsSegment(key: ValueKey<String>('readonly-chart'), assignmentId: 'assignment')));
    await tester.pumpAndSettle();
    expect(find.text('Kept by Player'), findsOneWidget);
    expect(find.text('Apply'), findsNothing);
  });

  testWidgets('Coach Nutrition content fits inside the Player page scroll view', (WidgetTester tester) async {
    final FakeMyosApi fake = _fake()..coachPlayerNutrition = <String, dynamic>{
      'authority': 'player', 'goal': 'maintain',
      'targets': <String, dynamic>{'calories': 2000, 'protein_g': 140, 'carbs_g': 220, 'fat_g': 70},
    };
    await tester.pumpWidget(_app(fake, 'en', ThemeData.light(), home: ListView(children: <Widget>[
      const Text('Player page'),
      const CoachNutritionSegment(assignmentId: 'assignment'),
    ])));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Player page'), findsOneWidget);
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

  testWidgets('pace dial previews seven stops and shows floor and gain warnings', (WidgetTester tester) async {
    final FakeMyosApi fake = _fake()
      ..nutritionState = <String, dynamic>{'state': 'ready', 'goal': 'maintain', 'intensity': null,
        'goal_reason': <String, dynamic>{'code': 'default'}, 'daily_activity': 'mostly_sitting',
        'targets': <String, dynamic>{'calories': 2000, 'protein_g': 140, 'carbs_g': 220, 'fat_g': 70}};
    await tester.pumpWidget(_app(fake, 'en', ThemeData.light()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Adjust'));
    await tester.pumpAndSettle();
    expect(find.text('Lose · Aggressive'), findsOneWidget);
    expect(find.text('Gain · Aggressive'), findsOneWidget);
    await tester.tap(find.text('Lose · Aggressive'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Calorie floor applies'), findsOneWidget);
    expect(find.textContaining('1800'), findsOneWidget);
    expect(find.text('Protein: 145 g · Carbohydrates: 160 g · Fat: 65 g'), findsOneWidget);
    expect(find.textContaining('Weekly change: −0.4 kg a week'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(find.textContaining('February 1, 2027'), findsOneWidget);
    await tester.tap(find.text('Gain · Light'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Target weight is below'), findsOneWidget);
    expect(find.textContaining('2200'), findsOneWidget);
    expect(find.text('Protein: 130 g · Carbohydrates: 250 g · Fat: 60 g'), findsOneWidget);
    expect(find.textContaining('Weekly change: +0.2 kg a week'), findsOneWidget);
  });

  testWidgets('goal offer accepts through dial and persists dismissal', (WidgetTester tester) async {
    final FakeMyosApi fake = _fake()
      ..nutritionState = <String, dynamic>{'state': 'ready', 'goal': 'maintain', 'intensity': 'moderate',
        'pending_goal': 'lose', 'goal_reason': <String, dynamic>{'code': 'default'},
        'daily_activity': 'mostly_sitting', 'targets': <String, dynamic>{'calories': 2000,
          'protein_g': 140, 'carbs_g': 220, 'fat_g': 70}};
    await tester.pumpWidget(_app(fake, 'en', ThemeData.light()));
    await tester.pumpAndSettle();
    expect(find.text('Your goal changed. Update your Nutrition goal?'), findsOneWidget);
    await tester.tap(find.text('Update').first);
    await tester.pumpAndSettle();
    expect(tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Lose · Moderate')).selected, isTrue);
    expect(tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Lose · Aggressive')).selected, isFalse);
    await tester.ensureVisible(find.text('Save Nutrition goal'));
    await tester.tap(find.text('Save Nutrition goal'));
    await tester.pumpAndSettle();
    expect(find.text('A short health check'), findsOneWidget);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(fake.lastNutritionGoal?['goal'], 'lose');
    expect(fake.lastNutritionGoal?['intensity'], 'moderate');
    expect(find.text('Your goal changed. Update your Nutrition goal?'), findsNothing);

    final FakeMyosApi dismissFake = _fake()
      ..nutritionState = <String, dynamic>{'state': 'ready', 'goal': 'maintain', 'intensity': 'moderate',
        'pending_goal': 'gain', 'goal_reason': <String, dynamic>{'code': 'default'},
        'daily_activity': 'mostly_sitting', 'targets': <String, dynamic>{'calories': 2000,
          'protein_g': 140, 'carbs_g': 220, 'fat_g': 70}};
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(_app(dismissFake, 'en', ThemeData.light()));
    await tester.pumpAndSettle();
    expect(find.text('Your goal changed. Update your Nutrition goal?'), findsOneWidget);
    await tester.tap(find.text('Later'));
    await tester.pumpAndSettle();
    expect(dismissFake.nutritionOfferDismissals, 1);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(_app(dismissFake, 'en', ThemeData.light()));
    await tester.pumpAndSettle();
    expect(find.text('Your goal changed. Update your Nutrition goal?'), findsNothing);
  });

  testWidgets('Coach-held targets have no Adjust action', (WidgetTester tester) async {
    final FakeMyosApi fake = _fake()
      ..nutritionState = <String, dynamic>{'state': 'ready', 'goal': 'gain', 'author': 'Coach',
        'authority': 'coach', 'pending_goal': 'lose',
        'goal_reason': <String, dynamic>{'code': 'default'}, 'daily_activity': 'mostly_sitting',
        'targets': <String, dynamic>{'calories': 2000, 'protein_g': 140, 'carbs_g': 220, 'fat_g': 70}};
    await tester.pumpWidget(_app(fake, 'ar', ThemeData.light()));
    await tester.pumpAndSettle();
    expect(find.text('حدّدها مدربك'), findsOneWidget);
    expect(find.text('تعديل'), findsNothing);
    expect(find.textContaining('تغير هدفك'), findsNothing);
    final FakeMyosApi englishFake = _fake()
      ..nutritionState = <String, dynamic>{'state': 'ready', 'goal': 'gain', 'author': 'Coach', 'authority': 'coach',
        'goal_reason': <String, dynamic>{'code': 'default'}, 'daily_activity': 'mostly_sitting',
        'targets': <String, dynamic>{'calories': 2000, 'protein_g': 140, 'carbs_g': 220, 'fat_g': 70}};
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(_app(englishFake, 'en', ThemeData.light()));
    await tester.pumpAndSettle();
    expect(find.text('Set by your coach'), findsOneWidget);
  });

  testWidgets('Arabic pace dial uses right-to-left layout', (WidgetTester tester) async {
    final FakeMyosApi fake = _fake()
      ..nutritionState = <String, dynamic>{'state': 'ready', 'goal': 'maintain',
        'goal_reason': <String, dynamic>{'code': 'default'}, 'daily_activity': 'mostly_sitting',
        'targets': <String, dynamic>{'calories': 2000, 'protein_g': 140, 'carbs_g': 220, 'fat_g': 70}};
    await tester.pumpWidget(_app(fake, 'ar', ThemeData.light()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('تعديل'));
    await tester.pumpAndSettle();
    expect(find.text('خسارة الوزن · قوي'), findsOneWidget);
    await tester.tap(find.text('خسارة الوزن · قوي'));
    await tester.pumpAndSettle();
    expect(find.textContaining('يحدّ الحد الأدنى للسعرات من معدل التغير الأسبوعي الفعلي.'), findsOneWidget);
    expect(find.textContaining('التغير الأسبوعي: −0.4 كجم أسبوعيًا'), findsOneWidget);
    expect(find.textContaining('تاريخ الوصول إلى الوزن المستهدف: 1 فبراير 2027'), findsOneWidget);
    final Directionality direction = tester.widget(find.byType(Directionality).last);
    expect(direction.textDirection, TextDirection.rtl);
  });
}

FakeMyosApi _fake() => FakeMyosApi()
  ..issuedToken = 'nutrition-token'
  ..currentUsername = 'nutrition-player'
  ..tokenValid = true
  ..gender = 'female'
  ..profileExists = true;

Widget _app(FakeMyosApi fake, String language, ThemeData theme, {Widget? home}) => ProviderScope(
      overrides: <Override>[
        apiClientProvider.overrideWith((ref) {
          final InMemoryTokenStore tokens = InMemoryTokenStore();
          tokens.save('nutrition-token');
          return ApiClient(tokens: tokens, baseUrl: 'http://test.local', adapter: fake.adapter);
        }),
        systemDisplayLanguageProvider.overrideWithValue(language),
      ],
      child: MaterialApp(theme: theme, home: Scaffold(body: home ?? const NutritionTab())),
    );

