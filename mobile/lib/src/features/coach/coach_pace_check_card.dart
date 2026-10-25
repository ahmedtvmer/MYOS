import 'package:flutter/material.dart';

import '../../core/display_language/nutrition_copy.dart';
import '../../core/display_language/copy_context.dart';

class CoachPaceCheckCard extends StatelessWidget {
  const CoachPaceCheckCard({super.key, required this.proposal,
    required this.authority, required this.onDecision});

  final Map<String, dynamic> proposal;
  final String authority;
  final Future<void> Function(String decision) onDecision;

  @override
  Widget build(BuildContext context) {
    final NutritionCopy copy = displayCopyOf(context).nutrition;
    final Map<String, dynamic> payload = proposal['payload'] is Map<String, dynamic>
        ? proposal['payload'] as Map<String, dynamic> : <String, dynamic>{};
    final Map<String, dynamic> targets = payload['targets'] is Map<String, dynamic>
        ? payload['targets'] as Map<String, dynamic> : <String, dynamic>{};
    final bool stale = proposal['stale'] == true;
    final bool canDecide = authority == 'coach' && proposal['status'] == 'pending';
    return Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(
      crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Text(copy.paceProposal, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(copy.paceProposalRates(payload['actual_rate_pct'] ?? '—', payload['planned_rate_pct'] ?? '—')),
        Text(copy.paceProposalCalories(targets['calories'] ?? '—', payload['calorie_change'] ?? 0)),
        if (stale) Text(copy.staleProposal),
        if (proposal['status'] != 'pending')
          Text(copy.proposalDecisionBy(proposal['status'] as String?, proposal['decided_by'] as String?)),
        if (payload['floor_limited'] == true) Text(copy.floorWarning),
        if (canDecide) Wrap(spacing: 8, children: <Widget>[
          if (!stale) FilledButton(onPressed: () { onDecision('accepted'); }, child: Text(copy.proposalAccept)),
          OutlinedButton(onPressed: () { onDecision('kept'); }, child: Text(copy.proposalKeep)),
        ]),
      ],
    )));
  }
}
