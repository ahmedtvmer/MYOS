import 'package:flutter_test/flutter_test.dart';
import 'package:myos_mobile/src/features/player/tour/feature_list.dart';
import 'package:myos_mobile/src/router.dart';

void main() {
  test('Feature list copy, targets, and Tour stop ids are valid', () {
    const Set<String> targetIds = <String>{'home', 'program', 'profile'};
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
    expect(featureList.last.location.matches(profilePath, 0), isTrue);
    for (final String stopId in tourV1StopIds) {
      expect(ids, contains(stopId));
    }
  });
}
