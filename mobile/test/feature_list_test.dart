import 'package:flutter_test/flutter_test.dart';
import 'package:myos_mobile/src/features/player/tour/feature_list.dart';
import 'package:myos_mobile/src/router.dart';

void main() {
  test('Feature list copy, targets, and Tour stop ids are valid', () {
    const Set<String> targetIds = <String>{'home', 'program', 'assistant', 'nutrition', 'progress', 'profile', 'feature_guide'};
    final Set<String> ids = featureList.map((FeatureEntry entry) => entry.id).toSet();

    expect(ids.length, featureList.length);
    for (final FeatureEntry entry in featureList) {
      expect(entry.titleEn.trim(), isNotEmpty, reason: entry.id);
      expect(entry.sentenceEn.trim(), isNotEmpty, reason: entry.id);
      expect(entry.titleAr.trim(), isNotEmpty, reason: entry.id);
      expect(entry.sentenceAr.trim(), isNotEmpty, reason: entry.id);
      expect(targetIds, contains(entry.target), reason: entry.id);
      expect(entry.appVersion, matches(RegExp(r'^\d+\.\d+\.\d+$')));
      expect(entry.audience, 'lifter');
    }
    expect(tourV1StopIds, <String>['home', 'program', 'assistant', 'nutrition', 'progress', 'profile', 'feature_guide']);
    expect(featureList.length, 7);
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
