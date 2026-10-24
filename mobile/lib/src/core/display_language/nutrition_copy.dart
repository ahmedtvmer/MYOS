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
  String get setByCoach => isArabic ? 'حدّدها مدربك' : 'Set by your coach';
  String get kilograms => isArabic ? 'كجم' : 'kg';
  String adherenceLabel(String? value) => switch (value) {
        'on_target' => onTarget,
        'roughly' => roughly,
        'off' => off,
        _ => isArabic ? 'غير مسجل' : 'Unlogged',
      };
  String get cancel => isArabic ? 'إلغاء' : 'Cancel';
  String get updateTargets => isArabic ? 'تحديث الأهداف الغذائية' : 'Update Nutrition targets';
  String get adjust => isArabic ? 'تعديل' : 'Adjust';
  String get saveGoal => isArabic ? 'حفظ هدف التغذية' : 'Save Nutrition goal';
  String get weeklyChange => isArabic ? 'التغير الأسبوعي' : 'Weekly change';
  String weeklyRate(double value) {
    final String sign = value < 0 ? '−' : value > 0 ? '+' : '';
    final String amount = value.abs().toStringAsFixed(1);
    return isArabic ? '$sign$amount كجم أسبوعيًا' : '$sign$amount kg a week';
  }
  String formatDate(String value) {
    final DateTime date = DateTime.parse(value);
    if (!isArabic) {
      const List<String> months = <String>[
        'January', 'February', 'March', 'April', 'May', 'June',
        'July', 'August', 'September', 'October', 'November', 'December',
      ];
      return '${months[date.month - 1]} ${date.day}, ${date.year}';
    }
    const List<String> months = <String>[
      'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
      'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر',
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }
  String get reachTarget => isArabic ? 'تاريخ الوصول إلى الوزن المستهدف' : 'Target weight date';
  String get floorWarning => isArabic ? 'يحدّ الحد الأدنى للسعرات من معدل التغير الأسبوعي الفعلي.' : 'The Calorie floor applies; this is your real weekly rate.';
  String get gainWarning => isArabic ? 'وزنك المستهدف أقل من وزنك الحالي.' : 'Your Target weight is below your current weight.';
  String get updateOffer => isArabic ? 'تغير هدفك. هل تريد تحديث هدف التغذية؟' : 'Your goal changed. Update your Nutrition goal?';
  String get accept => isArabic ? 'تحديث' : 'Update';
  String get dismiss => isArabic ? 'لاحقًا' : 'Later';
  String get continueLabel => isArabic ? 'متابعة' : 'Continue';
  String stop(String goalValue, String pace) => '${goal(goalValue)} · ${isArabic ? <String, String>{'light': 'خفيف', 'moderate': 'متوسط', 'aggressive': 'قوي'}[pace] : pace[0].toUpperCase() + pace.substring(1)}';
  String get dietitian => isArabic ? 'لن يحدد ميوس أهدافًا غذائية. يُرجى التحدث إلى اختصاصي تغذية مسجل.' : 'MYOS will not set calorie targets. Please speak with a registered dietitian.';
  String get under18 => isArabic ? 'لا يحدد ميوس أهدافًا غذائية تلقائية لمن هم دون 18 عامًا.' : 'MYOS does not set automatic Nutrition targets for players under 18.';
  String get incomplete => isArabic ? 'أكمل الملف التدريبي قبل إعداد الأهداف الغذائية.' : 'Complete your Training profile before setting Nutrition targets.';
  String get coachSetByPlayer => isArabic ? 'حدده اللاعب' : 'Set by player';
  String get coachSetByYou => isArabic ? 'حددته أنت' : 'Set by you';
  String get coachTakeoverTitle => isArabic ? 'تولي أهداف التغذية' : 'Take over Nutrition targets';
  String get coachTakeoverPrompt => isArabic ? 'سيصبح لك حق تعديل أهداف التغذية لهذا اللاعب طوال مدة التعيين.' : 'You will control this Player’s Nutrition targets while the Assignment is active.';
  String get coachConfirmTakeover => isArabic ? 'تولي الأهداف' : 'Take over targets';
  String get coachTargets => isArabic ? 'أهداف التغذية' : 'Nutrition targets';
  String get coachSaveTargets => isArabic ? 'حفظ الأهداف' : 'Save targets';
  String get coachCalorieFloor => isArabic ? 'الحد الأدنى للسعرات' : 'Calorie floor';
  String get coachTargetCalories => isArabic ? 'السعرات' : 'Calories';
  String get coachUseDayTargets => isArabic ? 'أهداف منفصلة لأيام التدريب والراحة' : 'Separate training-day and rest-day targets';
  String get coachTrainingDay => isArabic ? 'يوم التدريب' : 'Training day';
  String get coachRestDay => isArabic ? 'يوم الراحة' : 'Rest day';
  String get coachAdherence14 => isArabic ? 'الالتزام الغذائي · آخر 14 يومًا' : 'Nutrition adherence · last 14 days';
  String get coachWeightTrend => isArabic ? 'اتجاه الوزن' : 'Weight trend';
  String get coachNextPaceCheck => isArabic ? 'فحص الوتيرة القادم' : 'Next pace check';
  String get coachPaceCheckPending => isArabic ? 'بعد 21 يومًا من تسجيل الوزن' : 'After 21 days of weigh-ins';
  String coachPaceCheckValue(String? value) => switch (value) {
    'after_21_days_of_weigh_ins' => coachPaceCheckPending,
    _ => value ?? coachPaceCheckPending,
  };
  String get coachNutritionSaved => isArabic ? 'تم حفظ أهداف التغذية.' : 'Nutrition targets saved.';
  String? coachValidationError(String message) {
    if (message.contains('Training profile')) {
      return isArabic ? 'أكمل الملف التدريبي للاعب قبل إعداد الأهداف الغذائية.'
          : "Complete the Player's Training profile before setting Nutrition targets.";
    }
    if (message.contains('registered dietitian')) {
      return isArabic ? 'لا يمكن إعداد الأهداف الغذائية؛ يُرجى التحدث مع اختصاصي تغذية مسجل.'
          : 'Nutrition targets are blocked. Please speak with a registered dietitian.';
    }
    if (message.contains('under 18')) {
      return isArabic ? 'لا يمكن إعداد أهداف خسارة الوزن للاعب دون 18 عامًا.'
          : 'Players under 18 may only have Maintain or Gain targets.';
    }
    if (message.contains('Confirm that you are taking over')) {
      return isArabic ? 'أكد تولي مسؤولية أهداف التغذية.'
          : 'Confirm that you are taking over Nutrition authority.';
    }
    if (message.contains('Set Nutrition targets') || message.contains('must include calories')) {
      return isArabic ? 'أدخل أهداف السعرات والماكروز.' : 'Set Nutrition targets with calories and Macros.';
    }
    final RegExpMatch? floor = RegExp(r'floor of (\d+) kcal').firstMatch(message);
    if (floor != null) {
      final String amount = floor.group(1)!;
      return isArabic ? 'يجب ألا تقل السعرات عن الحد الأدنى البالغ $amount.'
          : 'Calories must meet the Calorie floor of $amount kcal.';
    }
    if (message.contains('within 5%')) {
      return isArabic ? 'يجب أن تتوافق سعرات الماكروز مع الهدف ضمن 5٪.'
          : 'Calories from Macros must be within 5% of the target.';
    }
    final RegExpMatch? rate = RegExp(r'not exceed ([\d.]+)%').firstMatch(message);
    if (rate != null) {
      final String amount = rate.group(1)!;
      return isArabic ? 'يجب ألا تتجاوز الوتيرة الأسبوعية $amount٪ من وزن الجسم.'
          : 'The weekly rate must not exceed $amount% of bodyweight.';
    }
    if (message.contains('must be a whole number') || message.contains('valid ')) {
      return isArabic ? 'أدخل السعرات والماكروز كأعداد صحيحة غير سالبة.'
          : 'Enter calories and Macros as whole numbers; Macro values cannot be negative.';
    }
    return null;
  }
  String get coachGoal => isArabic ? 'هدف التغذية' : 'Nutrition goal';
  String get coachMacroCalories => isArabic ? 'السعرات المحسوبة من الماكروز' : 'Calories from Macros';
  String coachWeightValue(String date, Object weight) => isArabic
      ? '\u2066$date · $weight\u2069 كجم' : '$date · $weight kg';
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
      case 'player_choice':
        return isArabic ? 'اخترت هدف التغذية $label.' : 'You chose $label as your Nutrition goal.';
      default:
        return isArabic ? 'هدف التغذية $label لأن الملف التدريبي لا يحدد هدفًا للوزن.'
            : 'Set to $label because your Training profile has no weight goal.';
    }
  }
}
