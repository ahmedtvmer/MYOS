import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api_client.dart';
import '../../../core/display_language/controller.dart';
import '../../../core/display_language/nutrition_copy.dart';
import '../../../core/models.dart';
import '../../../providers.dart';

class NutritionTab extends ConsumerStatefulWidget {
  const NutritionTab({super.key});

  @override
  ConsumerState<NutritionTab> createState() => _NutritionTabState();
}

class _NutritionTabState extends ConsumerState<NutritionTab> {
  NutritionPlanState? _plan;
  String _sex = 'male';
  bool _sexConfirmed = false;
  String _activity = 'mostly_sitting';
  bool _pregnancy = false;
  bool _condition = false;
  bool _eatingDisorder = false;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final NutritionPlanState plan = await ref.read(apiClientProvider).nutrition();
      if (mounted) {
        setState(() { _plan = plan; _sex = plan.sex ?? 'male';
          _activity = plan.dailyActivity ?? _activity; _loading = false; _error = null; });
      }
    } on ApiException catch (error) {
      if (mounted) setState(() { _error = error.message; _loading = false; });
    }
  }

  Future<void> _save() async {
    setState(() { _saving = true; _error = null; });
    try {
      final NutritionPlanState plan = await ref.read(apiClientProvider).setupNutrition(
        sex: _sex,
        sexConfirmed: _sexConfirmed,
        dailyActivity: _activity,
        screening: <String, bool>{
          'pregnant_or_breastfeeding': _pregnancy,
          'medical_condition': _condition,
          'eating_disorder': _eatingDisorder,
        },
      );
      if (mounted) setState(() { _plan = plan; _saving = false; });
    } on ApiException catch (error) {
      if (mounted) setState(() { _error = error.message; _saving = false; });
    }
  }

  Future<void> _editActivity(NutritionCopy copy) async {
    final String? selectedActivity = await _chooseActivity(copy);
    if (selectedActivity == null || !mounted) return;
    await _saveActivity(selectedActivity);
  }

  Future<String?> _chooseActivity(NutritionCopy copy) {
    String selected = _activity;
    return showDialog<String>(context: context, builder: (BuildContext context) =>
      AlertDialog(title: Text(copy.dailyActivity), content: DropdownButtonFormField<String>(
        initialValue: selected,
        items: <DropdownMenuItem<String>>[
          DropdownMenuItem(value: 'mostly_sitting', child: Text(copy.mostlySitting)),
          DropdownMenuItem(value: 'on_feet', child: Text(copy.onFeet)),
          DropdownMenuItem(value: 'physical_job', child: Text(copy.physicalJob)),
        ], onChanged: (String? value) { if (value != null) selected = value; }),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(context), child: Text(copy.cancel)),
          FilledButton(onPressed: () => Navigator.pop(context, selected), child: Text(copy.updateTargets)),
        ]));
  }

  Future<void> _saveActivity(String activity) async {
    setState(() { _saving = true; _error = null; });
    try {
      final NutritionPlanState plan = await ref.read(apiClientProvider).updateNutritionActivity(activity);
      if (mounted) setState(() { _activity = activity; _plan = plan; _saving = false; });
    } on ApiException catch (error) {
      if (mounted) setState(() { _error = error.message; _saving = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool arabic = ref.watch(displayLanguageProvider) == 'ar';
    final NutritionCopy copy = NutritionCopy(arabic ? 'ar' : 'en');
    return Directionality(
      textDirection: arabic ? TextDirection.rtl : TextDirection.ltr,
      child: _content(context, copy),
    );
  }

  Widget _content(BuildContext context, NutritionCopy copy) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return _loadError(context, copy);
    if (_plan?.state == 'not_started') return _setupForm(context, copy);
    if (_plan?.state == 'incomplete') return _incomplete(context, copy);
    if (_plan?.state == 'ready') {
      return _targets(context, copy, Theme.of(context).colorScheme, Theme.of(context).textTheme);
    }
    return _blocked(context, copy);
  }

  Widget _setupForm(BuildContext context, NutritionCopy copy) => ListView(
        padding: const EdgeInsets.all(24),
        children: <Widget>[
          Text(copy.setup,
              style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 16),
          _sexConfirmation(copy),
          const SizedBox(height: 16),
          _activityQuestion(copy),
          const SizedBox(height: 16),
          _healthCheck(copy),
          _setupButton(copy),
        ],
      );

  Widget _sexConfirmation(NutritionCopy copy) => Column(children: <Widget>[
    Text(copy.confirmSex),
    DropdownButtonFormField<String>(initialValue: _sex,
      items: <DropdownMenuItem<String>>[
        DropdownMenuItem(value: 'male', child: Text(copy.male)),
        DropdownMenuItem(value: 'female', child: Text(copy.female)),
      ], onChanged: (String? value) { if (value != null) setState(() => _sex = value); }),
    CheckboxListTile(value: _sexConfirmed,
      onChanged: (bool? value) => setState(() => _sexConfirmed = value ?? false),
      title: Text(copy.confirm)),
  ]);

  Widget _activityQuestion(NutritionCopy copy) => Column(children: <Widget>[
    Text(copy.activityQuestion),
    DropdownButtonFormField<String>(initialValue: _activity,
      items: <DropdownMenuItem<String>>[
        DropdownMenuItem(value: 'mostly_sitting', child: Text(copy.mostlySitting)),
        DropdownMenuItem(value: 'on_feet', child: Text(copy.onFeet)),
        DropdownMenuItem(value: 'physical_job', child: Text(copy.physicalJob)),
      ], onChanged: (String? value) { if (value != null) setState(() => _activity = value); }),
  ]);

  Widget _healthCheck(NutritionCopy copy) => Column(children: <Widget>[
    Text(copy.healthCheck),
    CheckboxListTile(value: _pregnancy,
      onChanged: (bool? value) => setState(() => _pregnancy = value ?? false),
      title: Text(copy.pregnancy)),
    CheckboxListTile(value: _condition,
      onChanged: (bool? value) => setState(() => _condition = value ?? false),
      title: Text(copy.condition)),
    CheckboxListTile(value: _eatingDisorder,
      onChanged: (bool? value) => setState(() => _eatingDisorder = value ?? false),
      title: Text(copy.eatingDisorder)),
  ]);

  Widget _setupButton(NutritionCopy copy) => FilledButton(
    onPressed: _saving || !_sexConfirmed ? null : _save,
    child: Text(_saving ? copy.saving : copy.showTargets));

  Widget _blocked(BuildContext context, NutritionCopy copy) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_plan?.state == 'under_18' ? copy.under18 : copy.dietitian,
              textAlign: TextAlign.center),
        ),
      );

  Widget _targets(BuildContext context, NutritionCopy copy, ColorScheme colors, TextTheme text) {
    final Map<String, dynamic> targets = _plan!.targets ?? <String, dynamic>{};
    final List<(String, String, Color)> macroCards = <(String, String, Color)>[
      (copy.protein, 'protein_g', colors.primary),
      (copy.carbs, 'carbs_g', colors.tertiary),
      (copy.fat, 'fat_g', colors.secondary),
    ];
    return ListView(
      padding: const EdgeInsets.all(24),
      children: <Widget>[
        Text(copy.tab, style: text.headlineMedium),
        _activityRow(copy),
        const SizedBox(height: 20),
        _plate(targets, macroCards, copy, text),
        const SizedBox(height: 12),
        Text(copy.macrosTitle, style: text.titleMedium),
        ..._macroCards(targets, macroCards),
        const SizedBox(height: 12),
        Text(copy.reason(_plan!.goalReason, _plan!.goal ?? 'maintain'), textAlign: TextAlign.center),
        if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
      ],
    );
  }

  Widget _activityRow(NutritionCopy copy) => ListTile(
    title: Text(copy.dailyActivity), subtitle: Text(copy.activityLabel(_activity)),
    trailing: const Icon(Icons.edit), onTap: _saving ? null : () => _editActivity(copy));

  Widget _plate(Map<String, dynamic> targets,
      List<(String, String, Color)> macroCards, NutritionCopy copy, TextTheme text) {
    final int calories = (targets['calories'] as num? ?? 0).round();
    final List<Color> colors = macroCards.map(((String, String, Color) macro) => macro.$3).toList();
    final List<double> caloriesByMacro = <double>[
      (targets['protein_g'] as num? ?? 0) * 4,
      (targets['carbs_g'] as num? ?? 0) * 4,
      (targets['fat_g'] as num? ?? 0) * 9,
    ];
    return SizedBox(height: 220, child: Center(child: CustomPaint(
      size: const Size.square(210), painter: _PlatePainter(colors, caloriesByMacro),
      child: SizedBox(width: 210, height: 210, child: Center(child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[Text('$calories', style: text.headlineLarge), Text(copy.calories)],
      ))),
    )));
  }

  List<Widget> _macroCards(Map<String, dynamic> targets,
      List<(String, String, Color)> macroCards) => <Widget>[
    for (final (String label, String key, Color color) in macroCards)
      Card(child: ListTile(leading: CircleAvatar(backgroundColor: color, radius: 8),
        title: Text(label), trailing: Text('${targets[key] ?? 0} g'))),
  ];

  Widget _loadError(BuildContext context, NutritionCopy copy) => Center(child: Padding(
    padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
      Text(_error ?? '', textAlign: TextAlign.center),
      const SizedBox(height: 12), OutlinedButton(onPressed: () { setState(() { _loading = true; _error = null; }); _load(); }, child: Text(copy.retry)),
    ])));

  Widget _incomplete(BuildContext context, NutritionCopy copy) => Center(child: Padding(
    padding: const EdgeInsets.all(24), child: Text(_plan?.message ?? copy.incomplete, textAlign: TextAlign.center)));
}

class _PlatePainter extends CustomPainter {
  const _PlatePainter(this.colors, this.values);
  final List<Color> colors;
  final List<double> values;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect rect = Offset.zero & size;
    final Paint paint = Paint()..style = PaintingStyle.stroke..strokeWidth = 20;
    final double total = values.fold<double>(0, (double a, double b) => a + b);
    double start = -1.5708;
    for (int i = 0; i < colors.length; i++) {
      paint.color = colors[i];
      final double sweep = total == 0 ? 0 : 6.2832 * values[i] / total;
      canvas.drawArc(rect.deflate(12), start, sweep, false, paint);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_PlatePainter oldDelegate) =>
      oldDelegate.colors != colors || oldDelegate.values != values;
}
