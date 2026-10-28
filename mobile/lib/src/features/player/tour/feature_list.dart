import '../../../core/models.dart';
import '../../../router.dart';
import 'tour_targets.dart';

/// The shared Feature list used by the Tour and later discovery surfaces.
const int tourCurrentVersion = 1;

bool isTourEligible(Account account, {int currentVersion = tourCurrentVersion}) =>
    account.tourSeenVersion < currentVersion &&
    (currentVersion == 1 || account.tourCreatedVersion >= currentVersion);

class FeatureEntry {
  const FeatureEntry({
    required this.id,
    required this.titleEn,
    required this.sentenceEn,
    required this.titleAr,
    required this.sentenceAr,
    required this.target,
    required this.location,
    required this.appVersion,
    required this.audience,
  });

  final String id;
  final String titleEn;
  final String sentenceEn;
  final String titleAr;
  final String sentenceAr;
  final String target;
  final TourTargetLocation location;
  final String appVersion;
  final String audience;
}

const List<FeatureEntry> featureList = <FeatureEntry>[
  FeatureEntry(
    id: 'home',
    titleEn: 'Home',
    sentenceEn: 'See your next workout and start training.',
    titleAr: 'الرئيسية',
    sentenceAr: 'اطّلع على تمرينك التالي وابدأ التدريب.',
    target: 'home',
    location: TourShellTabLocation(tabIndex: 0),
    appVersion: '0.1.0',
    audience: 'lifter',
  ),
  FeatureEntry(
    id: 'program',
    titleEn: 'Program',
    sentenceEn: 'Review your training days and exercises.',
    titleAr: 'البرنامج التدريبي',
    sentenceAr: 'راجع أيام برنامجك التدريبي وتمارينه.',
    target: 'program',
    location: TourShellTabLocation(tabIndex: 0),
    appVersion: '0.1.0',
    audience: 'lifter',
  ),
  FeatureEntry(
    id: 'profile',
    titleEn: 'Profile',
    sentenceEn: 'Review the training details that shape your program.',
    titleAr: 'الملف الشخصي',
    sentenceAr: 'راجع تفاصيل التدريب التي تحدد برنامجك.',
    target: 'profile',
    location: TourRouteLocation(profilePath),
    appVersion: '0.1.0',
    audience: 'lifter',
  ),
];

const List<String> tourV1StopIds = <String>['home', 'program'];
const int tourV1StopCount = 7;
