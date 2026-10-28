part of '../coach_program_draft_screen.dart';

enum _ProgramDraftDayAction { moveUp, moveDown, duplicate, remove }

class _ProgramDraftDayCard extends StatelessWidget {
  const _ProgramDraftDayCard({
    required this.index,
    required this.dayCount,
    required this.day,
    required this.busy,
    required this.dayNameError,
    required this.cardioError,
    required this.dayError,
    required this.buildWarmupCard,
    required this.buildExerciseCard,
    required this.onReorderExercises,
    required this.onChanged,
    required this.onMove,
    required this.onDuplicate,
    required this.onRemove,
    required this.onAddWarmup,
    required this.onAddExercise,
  });

  final int index;
  final int dayCount;
  final _DraftDayEditor day;
  final bool busy;
  final String? dayNameError;
  final String? cardioError;
  final String? dayError;
  final Widget Function(int movementIndex) buildWarmupCard;
  final Widget Function(int exerciseIndex) buildExerciseCard;
  final void Function(int oldIndex, int newIndex) onReorderExercises;
  final ValueChanged<String> onChanged;
  final ValueChanged<int> onMove;
  final VoidCallback onDuplicate;
  final VoidCallback onRemove;
  final VoidCallback onAddWarmup;
  final VoidCallback onAddExercise;

  @override
  Widget build(BuildContext context) {
    void onCardioFieldChanged() {
      day.useStructuredCardio = true;
      onChanged('cardio');
    }

    final CoachCopy copy = coachCopyOf(context);
    final MayosThemeExtension colors = MayosTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: MayosSpacing.md),
      child: MayosCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    copy.trainingDayNumber(index + 1),
                    style: MayosTypography.of(context).sectionHeading,
                  ),
                ),
                if (isDesktopLayout(context)) ...<Widget>[
                  IconButton(
                    key: Key('program_draft_day_up_$index'),
                    tooltip: copy.moveDayUp,
                    onPressed: busy || index == 0 ? null : () => onMove(-1),
                    icon: const Icon(Icons.arrow_upward),
                  ),
                  IconButton(
                    key: Key('program_draft_day_down_$index'),
                    tooltip: copy.moveDayDown,
                    onPressed: busy || index == dayCount - 1
                        ? null
                        : () => onMove(1),
                    icon: const Icon(Icons.arrow_downward),
                  ),
                  IconButton(
                    key: Key('program_draft_day_duplicate_$index'),
                    tooltip: copy.duplicateDay,
                    onPressed: busy || dayCount >= ProgramDraftPrescription.maxDays
                        ? null
                        : onDuplicate,
                    icon: const Icon(Icons.copy_outlined),
                  ),
                  IconButton(
                    key: Key('program_draft_day_remove_$index'),
                    tooltip: copy.removeDay,
                    onPressed: busy ? null : onRemove,
                    icon: Icon(Icons.delete_outline, color: colors.danger),
                  ),
                ] else
                  PopupMenuButton<_ProgramDraftDayAction>(
                    key: Key('program_draft_day_menu_$index'),
                    tooltip: copy.dayActions,
                    enabled: !busy,
                    onSelected: (_ProgramDraftDayAction action) {
                      switch (action) {
                        case _ProgramDraftDayAction.moveUp:
                          onMove(-1);
                        case _ProgramDraftDayAction.moveDown:
                          onMove(1);
                        case _ProgramDraftDayAction.duplicate:
                          onDuplicate();
                        case _ProgramDraftDayAction.remove:
                          onRemove();
                      }
                    },
                    itemBuilder: (BuildContext context) =>
                        <PopupMenuEntry<_ProgramDraftDayAction>>[
                      PopupMenuItem<_ProgramDraftDayAction>(
                        key: Key('program_draft_day_move_up_$index'),
                        value: _ProgramDraftDayAction.moveUp,
                        enabled: !busy && index > 0,
                        child: Text(copy.moveDayUp),
                      ),
                      PopupMenuItem<_ProgramDraftDayAction>(
                        key: Key('program_draft_day_move_down_$index'),
                        value: _ProgramDraftDayAction.moveDown,
                        enabled: !busy && index < dayCount - 1,
                        child: Text(copy.moveDayDown),
                      ),
                      PopupMenuItem<_ProgramDraftDayAction>(
                        key: Key('program_draft_day_duplicate_menu_$index'),
                        value: _ProgramDraftDayAction.duplicate,
                        enabled: !busy &&
                            dayCount < ProgramDraftPrescription.maxDays,
                        child: Text(copy.duplicateDay),
                      ),
                      PopupMenuItem<_ProgramDraftDayAction>(
                        key: Key('program_draft_day_remove_menu_$index'),
                        value: _ProgramDraftDayAction.remove,
                        enabled: !busy,
                        child: Text(copy.removeDay,
                            style: TextStyle(color: colors.danger)),
                      ),
                    ],
                    icon: const Icon(Icons.more_vert),
                  ),
              ],
            ),
            TextField(
              key: Key('program_draft_day_name_$index'),
              controller: day.dayName,
              enabled: !busy,
              decoration: InputDecoration(
                labelText: copy.dayName,
                border: const OutlineInputBorder(),
                errorText: dayNameError,
              ),
              onChanged: (_) => onChanged('day_name'),
            ),
            if (dayError != null) _editorErrorText(context, dayError!, colors),
            const SizedBox(height: MayosSpacing.md),
            Text(workoutCopyOf(context).warmup,
                style: MayosTypography.of(context).sectionHeading),
            const SizedBox(height: MayosSpacing.xs),
            for (int movementIndex = 0;
                movementIndex < day.warmups.length;
                movementIndex++)
              buildWarmupCard(movementIndex),
            MayosButton(
              key: Key('program_draft_warmup_add_$index'),
              label: copy.addWarmupMovement,
              icon: Icons.add,
              variant: MayosButtonVariant.tertiary,
              onPressed: busy ? null : onAddWarmup,
            ),
            const SizedBox(height: MayosSpacing.md),
            Text(
              copy.workingSets,
              style: MayosTypography.of(context).sectionHeading,
            ),
            const SizedBox(height: MayosSpacing.xs),
            ReorderableListView.builder(
              buildDefaultDragHandles: false,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: day.exercises.length,
              onReorderItem: onReorderExercises,
              itemBuilder: (BuildContext context, int exerciseIndex) =>
                  KeyedSubtree(
                key: ObjectKey(day.exercises[exerciseIndex]),
                child: buildExerciseCard(exerciseIndex),
              ),
            ),
            MayosButton(
              key: Key('program_draft_add_exercise_$index'),
              label: copy.addExercise,
              icon: Icons.add,
              variant: MayosButtonVariant.secondary,
              onPressed: busy ? null : onAddExercise,
            ),
            const SizedBox(height: MayosSpacing.md),
            DropdownButtonFormField<String>(
              key: Key('program_draft_cardio_machine_$index'),
              initialValue: day.cardioMachine ?? 'none',
              isExpanded: true,
              decoration: InputDecoration(
                labelText: copy.cardioMachine,
                border: const OutlineInputBorder(),
                errorText: cardioError,
              ),
              items: <DropdownMenuItem<String>>[
                DropdownMenuItem<String>(
                  value: 'none',
                  child: Text(
                    copy.cardioNone,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                for (final String machine in _cardioMachines)
                  DropdownMenuItem<String>(
                    value: machine,
                    child: Text(
                      copy.cardioMachineName(machine),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: busy
                  ? null
                  : (String? machine) {
                      day.selectCardioMachine(machine == 'none' ? null : machine);
                      if (day.cardioMachine != null &&
                          day.cardioMinutes.text.isEmpty) {
                        day.cardioMinutes.text = '25';
                      }
                      onChanged('cardio');
                    },
            ),
            if (day.cardioMachine != null) ...<Widget>[
              const SizedBox(height: MayosSpacing.xs),
              Wrap(
                spacing: MayosSpacing.sm,
                runSpacing: MayosSpacing.sm,
                children: <Widget>[
                  _cardioNumberField(
                    index,
                    day.cardioMinutes,
                    copy.cardioMinutesLabel,
                    'minutes',
                    busy,
                    onChanged: onCardioFieldChanged,
                  ),
                  _cardioNumberField(
                    index,
                    day.cardioMinutesMax,
                    copy.cardioMinutesMaxLabel,
                    'minutes_max',
                    busy,
                    onChanged: onCardioFieldChanged,
                    integer: true,
                  ),
                  if (day.cardioMachine == 'treadmill') ...<Widget>[
                    _cardioNumberField(
                      index,
                      day.cardioSpeed,
                      copy.cardioSpeed,
                      'speed_kmh',
                      busy,
                      onChanged: onCardioFieldChanged,
                    ),
                    _cardioNumberField(
                      index,
                      day.cardioIncline,
                      copy.cardioIncline,
                      'incline_pct',
                      busy,
                      onChanged: onCardioFieldChanged,
                    ),
                  ],
                  if (const <String>{'stairmaster', 'bike', 'elliptical'}.contains(day.cardioMachine))
                    _cardioNumberField(
                      index,
                      day.cardioLevel,
                      copy.cardioLevel,
                      'level',
                      busy,
                      onChanged: onCardioFieldChanged,
                      integer: true,
                    ),
                  if (const <String>{'bike', 'rower', 'other'}.contains(day.cardioMachine))
                    _cardioNumberField(
                      index,
                      day.cardioWatts,
                      copy.cardioWatts,
                      'watts',
                      busy,
                      onChanged: onCardioFieldChanged,
                      integer: true,
                    ),
                  if (const <String>{'bike', 'elliptical', 'rower', 'outdoor_walk_run', 'other'}.contains(day.cardioMachine))
                    _cardioNumberField(
                      index,
                      day.cardioDistance,
                      copy.cardioDistance,
                      'distance_m',
                      busy,
                      onChanged: onCardioFieldChanged,
                      integer: true,
                    ),
                ],
              ),
            ],
            if (day.cardio.text.isNotEmpty || !day.useStructuredCardio) ...<Widget>[
              const SizedBox(height: MayosSpacing.xs),
              TextField(
                key: Key('program_draft_cardio_$index'),
                controller: day.cardio,
                enabled: !busy,
                minLines: 1,
                maxLines: 3,
                maxLength: ProgramDraftPrescription.maxProgramNotesLength,
                inputFormatters: <TextInputFormatter>[
                  LengthLimitingTextInputFormatter(
                    ProgramDraftPrescription.maxProgramNotesLength,
                  ),
                ],
                decoration: InputDecoration(
                  labelText: copy.cardioNote,
                  border: const OutlineInputBorder(),
                  errorText: day.cardioMachine == null ? cardioError : null,
                  counterText: '',
                ),
                onChanged: (_) => onChanged('cardio'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

const List<String> _cardioMachines = <String>[
  'treadmill', 'stairmaster', 'bike', 'elliptical', 'rower',
  'outdoor_walk_run', 'other',
];

Widget _cardioNumberField(
  int dayIndex,
  TextEditingController controller,
  String label,
  String field,
  bool busy, {
  required VoidCallback onChanged,
  bool integer = false,
}) => SizedBox(
  width: 150,
  child: TextField(
    key: Key('program_draft_cardio_${field}_$dayIndex'),
    controller: controller,
    enabled: !busy,
    keyboardType: integer
        ? TextInputType.number
        : const TextInputType.numberWithOptions(decimal: true, signed: true),
    inputFormatters: <TextInputFormatter>[
      FilteringTextInputFormatter.allow(RegExp(integer ? r'[0-9]' : r'[0-9.-]')),
    ],
    decoration: InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
      isDense: true,
    ),
    onChanged: (_) => onChanged(),
  ),
);
