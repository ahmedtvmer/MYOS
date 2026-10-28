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
    sentenceEn: 'Edit a day, add exercises, or Replace a movement.',
    titleAr: 'البرنامج التدريبي',
    sentenceAr: 'عدّل يومًا، وأضف تمارين، أو استبدل حركة بخيار آخر.',
    target: 'program',
    location: TourShellTabLocation(tabIndex: 1),
    appVersion: '0.1.0',
    audience: 'lifter',
  ),
  FeatureEntry(
    id: 'assistant',
    titleEn: 'Assistant',
    sentenceEn: 'Ask about your training, including changes to your program.',
    titleAr: 'المساعد',
    sentenceAr: 'اسأل عن تدريبك، بما في ذلك تغييرات برنامجك التدريبي.',
    target: 'assistant',
    location: TourShellTabLocation(tabIndex: 0),
    appVersion: '0.1.0',
    audience: 'lifter',
  ),
  FeatureEntry(
    id: 'nutrition',
    titleEn: 'Nutrition',
    sentenceEn: 'Review your targets, log water, and track body weight.',
    titleAr: 'التغذية',
    sentenceAr: 'راجع أهدافك وسجّل الماء وتابع وزن جسمك.',
    target: 'nutrition',
    location: TourShellTabLocation(tabIndex: 2),
    appVersion: '0.1.0',
    audience: 'lifter',
  ),
  FeatureEntry(
    id: 'progress',
    titleEn: 'Progress',
    sentenceEn: 'Explore your charts and review Checkpoint feedback.',
    titleAr: 'التقدم',
    sentenceAr: 'تابع مخططاتك وراجع ملاحظات محطات التقدم.',
    target: 'progress',
    location: TourShellTabLocation(tabIndex: 3),
    appVersion: '0.1.0',
    audience: 'lifter',
  ),
  FeatureEntry(
    id: 'profile',
    titleEn: 'Profile',
    sentenceEn: 'Review Weak points, Movements to avoid, and equipment in Profile; '
        'change language in Settings.',
    titleAr: 'الملف الشخصي',
    sentenceAr: 'راجع نقاط الضعف والحركات التي يجب تجنبها والمعدات في الملف الشخصي، '
        'وغيّر اللغة من الإعدادات.',
    target: 'profile',
    location: TourRouteLocation(profilePath),
    appVersion: '0.1.0',
    audience: 'lifter',
  ),
  FeatureEntry(
    id: 'feature_guide',
    titleEn: 'Feature guide',
    sentenceEn: 'Find the Feature guide and replay this Tour from Profile.',
    titleAr: 'دليل الميزات',
    sentenceAr: 'افتح دليل الميزات أو أعد الجولة من الملف الشخصي.',
    target: 'feature_guide',
    location: TourRouteLocation(profilePath),
    appVersion: '0.1.0',
    audience: 'lifter',
  ),
];

const List<String> tourV1StopIds = <String>[
  'home',
  'program',
  'assistant',
  'nutrition',
  'progress',
  'profile',
  'feature_guide',
];
const int tourV1StopCount = 7;
