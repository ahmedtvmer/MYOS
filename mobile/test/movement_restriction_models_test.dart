import 'package:flutter_test/flutter_test.dart';
import 'package:myos_mobile/src/core/models.dart';
import 'package:myos_mobile/src/core/display_language/message_resolver.dart';

void main() {
  test('program exercise keeps its slot for restriction annotation refresh', () {
    final ProgramExercise exercise = ProgramExercise.fromJson(<String, dynamic>{
      'exercise_id': '43',
      'exercise_name': 'Back Squat',
      'slot_key': 'quad_compound',
    });
    expect(exercise.toJson()['slot_key'], 'quad_compound');
  });

  test('onboarding intake preserves server-saved restrictions and suggestions', () {
    final OnboardingIntake intake = OnboardingIntake.fromJson(<String, dynamic>{
      'status': 'in_progress', 'disclosure_acknowledged': true,
      'fields': <dynamic>[], 'profile_rebuild_fields': <dynamic>[],
      'progress': <String, dynamic>{},
      'movement_restrictions': <String>['Knee flexion'],
      'suggested_movement_restrictions': <String>['Deep hip flexion'],
    });
    expect(intake.movementRestrictions, <String>['Knee flexion']);
    expect(intake.suggestedMovementRestrictions, <String>['Deep hip flexion']);
  });

  test('prescription restriction annotation survives cache round-trip', () {
    final PrescriptionTarget target = PrescriptionTarget.fromJson(<String, dynamic>{
      'exercise_id': 'curl', 'exercise_name': 'Leg curl', 'is_barbell': false,
      'effective_sets': 3, 'target_rpe_cap': 8.5, 'projected_weight': 10,
      'movement_restriction': <String, dynamic>{'label': 'Knee flexion'},
    });
    final PrescriptionTarget cached = PrescriptionTarget.fromJson(target.toJson());
    expect(cached.movementRestriction, 'Knee flexion');
  });

  test('coach restriction conflicts remain visible in English and Arabic', () {
    final CoachAlert alert = CoachAlert.fromJson(<String, dynamic>{
      'alert_id': 'a', 'assignment_id': 'x', 'player_username': 'p',
      'kind': 'profile_change', 'state': 'new', 'created_at': '',
      'profile_changes': <String, dynamic>{'movement_restrictions': <String, dynamic>{'before': [], 'after': ['Knee flexion']}},
      'movement_restriction_conflicts': <dynamic>[<String, dynamic>{'restriction': 'Knee flexion', 'exercise_name': 'Leg curl'}],
      'message_code': 'coach_alert.profile_change.v1',
    });
    expect(resolveCoachAlertDescription(alert, 'en'), contains('Leg curl'));
    expect(resolveCoachAlertDescription(alert, 'ar'), contains('Leg curl'));
  });
}
