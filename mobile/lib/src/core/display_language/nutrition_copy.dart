class NutritionCopy {
  const NutritionCopy(this.languageCode);
  final String languageCode;
  bool get isArabic => languageCode == 'ar';
  String get tab => isArabic ? 'التغذية' : 'Nutrition';
  String get setup => isArabic ? 'إعداد الأهداف الغذائية' : 'Set up Nutrition targets';
  String get confirmSex => isArabic ? 'أكد الجنس لحساب الأهداف الغذائية.' : 'Confirm your sex for Nutrition targets.';
  String get confirm => isArabic ? 'أؤكد' : 'I confirm';
  String get male => isArabic ? 'ذكر' : 'Male';
  String get female => isArabic ? 'أنثى' : 'Female';
  String get dailyActivity => isArabic ? 'النشاط اليومي' : 'Daily activity';
  String get activityQuestion => isArabic ? 'ما طبيعة النشاط اليومي؟' : 'What is your Daily activity?';
  String get mostlySitting => isArabic ? 'أجلس معظم اليوم' : 'Mostly sitting';
  String get onFeet => isArabic ? 'أقف معظم اليوم' : 'On my feet';
  String get physicalJob => isArabic ? 'عمل بدني' : 'Physical job';
  String activityLabel(String? value) => switch (value) {
        'on_feet' => onFeet,
        'physical_job' => physicalJob,
        _ => mostlySitting,
      };
  String get healthCheck => isArabic ? 'فحص صحي قصير' : 'A short health check';
  String get pregnancy => isArabic ? 'هل أنتِ حامل أو مرضعة؟' : 'Are you pregnant or breastfeeding?';
  String get condition => isArabic ? 'هل لديك حالة صحية تؤثر في الغذاء؟' : 'Do you have a medical condition that affects diet?';
  String get eatingDisorder => isArabic ? 'هل عانيت من اضطراب في الأكل؟' : 'Do you have a current or past eating disorder?';
  String get showTargets => isArabic ? 'عرض الأهداف الغذائية' : 'Show my targets';
  String get saving => isArabic ? 'جارٍ الحفظ…' : 'Saving…';
  String get retry => isArabic ? 'إعادة المحاولة' : 'Retry';
  String get calories => isArabic ? 'سعرة حرارية' : 'kcal';
  String get protein => isArabic ? 'البروتين' : 'Protein';
  String get carbs => isArabic ? 'الكربوهيدرات' : 'Carbohydrates';
  String get fat => isArabic ? 'الدهون' : 'Fat';
  String get macrosTitle => isArabic ? 'الماكروز' : 'Macros';
  String get howTodayWent => isArabic ? 'كيف كان يومك؟' : 'How did today go?';
  String get onTarget => isArabic ? 'على الهدف' : 'On target';
  String get roughly => isArabic ? 'تقريبًا' : 'Roughly';
  String get off => isArabic ? 'بعيد عن الهدف' : 'Off';
  String get lastSevenDays => isArabic ? 'آخر 7 أيام' : 'Last 7 days';
  String get latestWeight => isArabic ? 'أحدث وزن' : 'Latest weight';
  String get targetWeight => isArabic ? 'الوزن المستهدف' : 'Target weight';
  String get coachSees => isArabic ? 'مدربك يرى الالتزام الغذائي.' : 'Your coach sees your Nutrition adherence.';
  String get kilograms => isArabic ? 'كجم' : 'kg';
  String adherenceLabel(String? value) => switch (value) {
        'on_target' => onTarget,
        'roughly' => roughly,
        'off' => off,
        _ => isArabic ? 'غير مسجل' : 'Unlogged',
      };
  String get cancel => isArabic ? 'إلغاء' : 'Cancel';
  String get updateTargets => isArabic ? 'تحديث الأهداف الغذائية' : 'Update Nutrition targets';
  String get dietitian => isArabic ? 'لن يحدد ميوس أهدافًا غذائية. يُرجى التحدث إلى اختصاصي تغذية مسجل.' : 'MYOS will not set calorie targets. Please speak with a registered dietitian.';
  String get under18 => isArabic ? 'لا يحدد ميوس أهدافًا غذائية تلقائية لمن هم دون 18 عامًا.' : 'MYOS does not set automatic Nutrition targets for players under 18.';
  String get incomplete => isArabic ? 'أكمل الملف التدريبي قبل إعداد الأهداف الغذائية.' : 'Complete your Training profile before setting Nutrition targets.';
  String goal(String value) => isArabic
      ? <String, String>{'lose': 'خسارة الوزن', 'gain': 'زيادة الوزن', 'maintain': 'الحفاظ على الوزن'}[value] ?? value
      : value[0].toUpperCase() + value.substring(1);
  String reason(Map<String, dynamic>? data, String goalValue) {
    final String label = goal(goalValue);
    switch (data?['code']) {
      case 'target_weight':
        return isArabic
            ? 'تم اختيار هدف التغذية $label لأن الوزن المستهدف هو ${data?['target_weight_kg']} كجم.'
            : 'Set to $label because your Target weight is ${data?['target_weight_kg']} kg.';
      case 'current_goal':
        return isArabic
            ? 'تم اختيار هدف التغذية $label لأن هدفك يقول «${data?['goal_text']}».'
            : 'Set to $label because your goal says “${data?['goal_text']}”.';
      default:
        return isArabic ? 'هدف التغذية $label لأن الملف التدريبي لا يحدد هدفًا للوزن.'
            : 'Set to $label because your Training profile has no weight goal.';
    }
  }
}
