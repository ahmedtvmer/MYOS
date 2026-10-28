import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myos_mobile/src/core/display_language/catalog.dart';
import 'package:myos_mobile/src/core/display_language/controller.dart';
import 'package:myos_mobile/src/features/player/tour/feature_list.dart';
import 'package:myos_mobile/src/features/player/tour/feature_guide_screen.dart';

void main() {
  testWidgets('Feature guide lists every lifter entry in English and Arabic',
      (WidgetTester tester) async {
    for (final String language in <String>['en', 'ar']) {
      await tester.pumpWidget(ProviderScope(
        key: ValueKey<String>(language),
        overrides: <Override>[
          displayLanguageProvider.overrideWith(
            (ref) => _TestDisplayLanguage(language),
          ),
          programFeatureAvailabilityProvider.overrideWith(
            (ref) => const ProgramFeatureAvailability(
              playerControlsProgram: true,
            ),
          ),
        ],
        child: const MaterialApp(home: FeatureGuideScreen()),
      ));
      await tester.pumpAndSettle();
      final bool isArabic = language == 'ar';
      final List<FeatureEntry> entries = featureList
          .where((FeatureEntry item) => item.audience == 'lifter')
          .toList();
      for (int index = 0; index < entries.length; index++) {
        final FeatureEntry entry = entries[index];
        final Finder card = find.byType(Card).at(index);
        expect(
          find.descendant(
            of: card,
            matching: find.text(isArabic ? entry.titleAr : entry.titleEn),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: card,
            matching: find.text(isArabic ? entry.sentenceAr : entry.sentenceEn),
          ),
          findsOneWidget,
        );
      }
      expect(find.text(isArabic ? 'أرني' : 'Show me'), findsNWidgets(entries.length));
    }
  });

  test('Feature guide copy is available in both display languages', () {
    for (final FeatureEntry entry in featureList.where(
      (FeatureEntry item) => item.audience == 'lifter',
    )) {
      expect(entry.titleEn, isNotEmpty);
      expect(entry.sentenceEn, isNotEmpty);
      expect(entry.titleAr, isNotEmpty);
      expect(entry.sentenceAr, isNotEmpty);
    }
    expect(const MyosCopy('en').featureGuideTitle, 'Feature guide');
    expect(const MyosCopy('ar').featureGuideTitle, 'دليل الميزات');
    expect(const MyosCopy('en').showMe, 'Show me');
    expect(const MyosCopy('ar').showMe, 'أرني');
  });
}

class _TestDisplayLanguage extends StateNotifier<String>
    implements DisplayLanguageController {
  _TestDisplayLanguage(super.state);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

