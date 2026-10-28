import 'package:flutter_test/flutter_test.dart';
import 'package:myos_mobile/src/core/models.dart';

void main() {
  Map<String, dynamic> injury(Object? pending) => <String, dynamic>{
        'id': 'injury-1',
        'body_area': 'knee',
        'catalog_body_parts': <String>['upper legs'],
        'description': 'torn ACL',
        'reported_at': '2026-10-27T10:00:00Z',
        'status': 'reported',
        'clarification_pending': pending,
        'clearances': <dynamic>[],
      };

  test('injury clarification flag accepts the boolean and the legacy 0/1 form', () {
    expect(InjuryRecord.fromJson(injury(true)).clarificationPending, isTrue);
    expect(InjuryRecord.fromJson(injury(1)).clarificationPending, isTrue);
    expect(InjuryRecord.fromJson(injury(0)).clarificationPending, isFalse);
    expect(InjuryRecord.fromJson(injury(null)).clarificationPending, isFalse);
  });
}
