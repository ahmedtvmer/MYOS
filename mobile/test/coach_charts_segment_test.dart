import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myos_mobile/src/core/api_client.dart';
import 'package:myos_mobile/src/core/display_language/controller.dart';
import 'package:myos_mobile/src/core/token_store.dart';
import 'package:myos_mobile/src/features/coach/coach_charts_segment.dart';
import 'package:myos_mobile/src/providers.dart';
import 'support/fake_myos_api.dart';

void main() {
  testWidgets('empty chart explains missing history accessibly', (WidgetTester tester) async {
    final FakeMyosApi fake = _fake();
    await tester.pumpWidget(_app(fake, 'en'));
    await tester.pumpAndSettle();
    expect(find.text('No weight or adherence data for this period.'), findsOneWidget);
  });

  testWidgets('Arabic chart is RTL and includes adherence bars', (WidgetTester tester) async {
    final FakeMyosApi fake = _fake()
      ..coachPlayerNutrition['adherence_days'] = List<Map<String, dynamic>>.generate(28, (int i) => <String, dynamic>{'date': DateTime(2026, 10, 1).add(Duration(days: i)).toIso8601String().substring(0, 10), 'value': i == 3 ? 'off' : null})
      ..coachPlayerNutrition['weight_trend'] = <Map<String, dynamic>>[{'date': '2026-10-15', 'weight_kg': 80.0}, {'date': '2026-10-20', 'weight_kg': 79.0}]
      ..coachPlayerNutrition['planned_weekly_rate_pct'] = -0.5;
    await tester.pumpWidget(_app(fake, 'ar'));
    await tester.pumpAndSettle();
    expect(find.text('الوزن والالتزام الغذائي · آخر 28 يومًا'), findsOneWidget);
    expect(find.textContaining('2026-10-15'), findsOneWidget);
    expect(find.byWidgetPredicate((Widget widget) => widget is Directionality && widget.textDirection == TextDirection.rtl), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);
  });

  testWidgets('adherence remains visible without weight history', (WidgetTester tester) async {
    final FakeMyosApi fake = _fake()
      ..coachPlayerNutrition['adherence_days'] = List<Map<String, dynamic>>.generate(28, (int i) => <String, dynamic>{'date': DateTime(2026, 10, 1).add(Duration(days: i)).toIso8601String().substring(0, 10), 'value': i == 27 ? 'off' : null});
    await tester.pumpWidget(_app(fake, 'en'));
    await tester.pumpAndSettle();
    expect(find.textContaining('off'), findsOneWidget);
    expect(find.text('No weight or adherence data for this period.'), findsNothing);
    expect(find.textContaining('0 days on target, 0 days roughly on target and 1 day off'), findsOneWidget);
  });

  testWidgets('adherence remains visible without weight history', (WidgetTester tester) async {
    final FakeMyosApi fake = _fake()
      ..coachPlayerNutrition['adherence_days'] = List<Map<String, dynamic>>.generate(28, (int i) => <String, dynamic>{'date': DateTime(2026, 10, 1).add(Duration(days: i)).toIso8601String().substring(0, 10), 'value': i == 27 ? 'off' : null});
    await tester.pumpWidget(_app(fake, 'en'));
    await tester.pumpAndSettle();
    expect(find.textContaining('off'), findsOneWidget);
    expect(find.text('No weight or adherence data for this period.'), findsNothing);
  });
}

FakeMyosApi _fake() => FakeMyosApi()
  ..issuedToken = 'coach-token'
  ..currentUsername = 'chart-coach'
  ..tokenValid = true;

Widget _app(FakeMyosApi fake, String language) => ProviderScope(
  overrides: <Override>[
    apiClientProvider.overrideWith((ref) {
      final InMemoryTokenStore tokens = InMemoryTokenStore()..save('coach-token');
      return ApiClient(tokens: tokens, baseUrl: 'http://test.local', adapter: fake.adapter);
    }),
    systemDisplayLanguageProvider.overrideWithValue(language),
  ],
  child: MaterialApp(home: const Scaffold(body: CoachChartsSegment(assignmentId: 'assignment-1'))),
);
