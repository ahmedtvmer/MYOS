import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models.dart';
import '../../../router.dart';
import 'tour_targets.dart';

/// The shared Feature list used by the Tour and later discovery surfaces.
const int tourCurrentVersion = 1;
const int currentFeatureRelease = 1;

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
    required this.release,
    required this.audience,
    this.requiresProgramControl = false,
  });

  final String id;
  final String titleEn;
  final String sentenceEn;
  final String titleAr;
  final String sentenceAr;
  final String target;
  final TourTargetLocation location;
  final int release;
  final String audience;
  final bool requiresProgramControl;
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
    release: 0,
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
    release: 0,
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
    release: 0,
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
    release: 0,
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
    release: 0,
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
    release: 0,
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
    release: 0,
    audience: 'lifter',
  ),
  FeatureEntry(
    id: 'weak_points',
    titleEn: 'Weak points',
    sentenceEn: 'Choose muscles you want your Training program to focus on.',
    titleAr: 'نقاط الضعف',
    sentenceAr: 'اختر العضلات التي تريد أن يركز عليها برنامجك التدريبي.',
    target: 'whats_new_weak_points',
    location: TourRouteLocation(profilePath),
    release: 1,
    audience: 'lifter',
  ),
  FeatureEntry(
    id: 'assistant_why',
    titleEn: 'Ask the assistant why',
    sentenceEn: 'Ask why an exercise or training decision is in your program.',
    titleAr: 'اسأل المساعد عن السبب',
    sentenceAr: 'اسأل عن سبب وجود تمرين أو قرار تدريبي في برنامجك.',
    target: 'whats_new_assistant_why',
    location: TourRouteLocation(chatPath),
    release: 1,
    audience: 'lifter',
  ),
  FeatureEntry(
    id: 'add_exercises',
    titleEn: 'Add exercises in the Program tab',
    sentenceEn: 'Add exercises to a training day from the Program tab.',
    titleAr: 'أضف تمارين من تبويب البرنامج',
    sentenceAr: 'أضف تمارين إلى يوم تدريبي من تبويب البرنامج.',
    target: 'whats_new_add_exercises',
    location: TourShellTabLocation(tabIndex: 1),
    release: 1,
    audience: 'lifter',
    requiresProgramControl: true,
  ),
  FeatureEntry(
    id: 'edit_program_chat',
    titleEn: 'Edit your program from chat',
    sentenceEn: 'Tell the assistant how you want to change your Training program.',
    titleAr: 'عدّل برنامجك عبر المحادثة',
    sentenceAr: 'أخبر المساعد بالتغييرات التي تريدها في برنامجك التدريبي.',
    target: 'whats_new_edit_program_chat',
    location: TourRouteLocation(chatPath),
    release: 1,
    audience: 'lifter',
  ),
  FeatureEntry(
    id: 'movements_to_avoid',
    titleEn: 'Movements to avoid',
    sentenceEn: 'Choose movements your Training program should avoid.',
    titleAr: 'حركات يجب تجنبها',
    sentenceAr: 'اختر الحركات التي يجب أن يتجنبها برنامجك التدريبي.',
    target: 'whats_new_movements_to_avoid',
    location: TourRouteLocation(profilePath),
    release: 1,
    audience: 'lifter',
  ),
];

final Provider<List<FeatureEntry>> featureEntriesProvider =
    Provider<List<FeatureEntry>>((ref) => featureList);

class ProgramFeatureAvailability {
  const ProgramFeatureAvailability({this.accountId, this.playerControlsProgram});

  final String? accountId;
  final bool? playerControlsProgram;
}

final StateProvider<ProgramFeatureAvailability> programFeatureAvailabilityProvider =
    StateProvider<ProgramFeatureAvailability>(
        (ref) => const ProgramFeatureAvailability());

bool isFeatureAvailableForAccount(
  FeatureEntry entry,
  String? accountId,
  ProgramFeatureAvailability availability,
) =>
    !entry.requiresProgramControl ||
    (availability.accountId == accountId &&
        availability.playerControlsProgram == true);

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
