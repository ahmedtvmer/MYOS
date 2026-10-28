import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:myos_mobile/src/features/player/tour/feature_list.dart';
import 'package:myos_mobile/src/features/player/tour/tour_targets.dart';
import 'package:myos_mobile/src/router.dart';

void main() {
  test('Feature list check reports entries missing Arabic copy', () {
    final List<String> errors = validateFeatureEntries(
      <FeatureEntry>[
        FeatureEntry(
          id: 'missing_arabic',
          titleEn: 'Feature',
          sentenceEn: 'A feature sentence.',
          titleAr: '   ',
          sentenceAr: 'جملة الميزة.',
          target: 'home',
          location: const TourShellTabLocation(tabIndex: 0),
          release: 0,
          audience: 'lifter',
        ),
      ],
      validTargetIds: <String>{'home'},
    );

    expect(errors, contains(contains('titleAr')));
  });

  test('Feature list copy, targets, and Tour stop ids are valid', () {
    const Set<String> targetIds = <String>{'home', 'program', 'assistant', 'nutrition', 'progress', 'profile', 'feature_guide', 'whats_new_weak_points', 'whats_new_movements_to_avoid', 'whats_new_add_exercises', 'whats_new_assistant_why', 'whats_new_edit_program_chat'};
    final Set<String> ids = featureList.map((FeatureEntry entry) => entry.id).toSet();

    expect(ids.length, featureList.length);
    expect(
      validateFeatureEntries(featureList, validTargetIds: targetIds),
      isEmpty,
    );
    expect(tourV1StopIds, <String>['home', 'program', 'assistant', 'nutrition', 'progress', 'profile', 'feature_guide']);
    expect(featureList.length, 12);
    const Map<String, String> releaseOneTargets = <String, String>{
      'weak_points': 'whats_new_weak_points',
      'movements_to_avoid': 'whats_new_movements_to_avoid',
      'add_exercises': 'whats_new_add_exercises',
      'assistant_why': 'whats_new_assistant_why',
      'edit_program_chat': 'whats_new_edit_program_chat',
    };
    for (final MapEntry<String, String> expected in releaseOneTargets.entries) {
      final FeatureEntry entry = featureList.firstWhere((FeatureEntry item) => item.id == expected.key);
      expect(entry.target, expected.value, reason: entry.id);
    }
    expect(featureList.firstWhere((FeatureEntry item) => item.id == 'assistant_why').location.matches(chatPath, 0), isTrue);
    expect(featureList.firstWhere((FeatureEntry item) => item.id == 'edit_program_chat').location.matches(chatPath, 0), isTrue);
    final String serverAccounts = File('../database/registry/accounts.py').readAsStringSync();
    expect(serverAccounts, contains('CURRENT_FEATURE_RELEASE = $currentFeatureRelease'));
    expect(featureList.last.location.matches(profilePath, 0), isTrue);
    expect(featureList.firstWhere((entry) => entry.id == 'program').location
        .matches('/home', 1), isTrue);
    expect(featureList.firstWhere((entry) => entry.id == 'assistant').location
        .matches('/home', 0), isTrue);
    expect(featureList.firstWhere((entry) => entry.id == 'nutrition').location
        .matches('/home', 2), isTrue);
    expect(featureList.firstWhere((entry) => entry.id == 'progress').location
        .matches('/home', 3), isTrue);
    for (final String stopId in tourV1StopIds) {
      expect(ids, contains(stopId));
    }
  });
}
