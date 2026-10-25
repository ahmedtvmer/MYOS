import 'package:flutter/material.dart';

import '../../core/display_language/copy_context.dart';
import '../../core/display_language/nutrition_copy.dart';

class PaceProposalCard extends StatelessWidget {
  const PaceProposalCard({super.key, required this.proposal, required this.canDecide,
    required this.onDecision, this.busy = false});

  final Map<String, dynamic> proposal;
  final bool canDecide;
  final bool busy;
  final Future<void> Function(String decision) onDecision;

  @override
  Widget build(BuildContext context) {
    final NutritionCopy copy = displayCopyOf(context).nutrition;
    final Map<String, dynamic> payload = proposal['payload'] is Map<String, dynamic>
        ? proposal['payload'] as Map<String, dynamic> : <String, dynamic>{};
    final Map<String, dynamic> targets = payload['targets'] is Map<String, dynamic>
        ? payload['targets'] as Map<String, dynamic> : <String, dynamic>{};
    final bool pending = proposal['status'] == 'pending';
    final bool stale = proposal['status'] == 'stale' || (pending && proposal['stale'] == true);
    return Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(
      crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Text(copy.paceProposal, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(copy.paceProposalRates(payload['actual_rate_pct'] ?? '—', payload['planned_rate_pct'] ?? '—')),
        Text(copy.paceProposalCalories(targets['calories'] ?? '—', payload['calorie_change'] ?? 0)),
        if (stale) Text(copy.staleProposal),
        if (!pending && !stale)
          Text(copy.proposalDecisionBy(proposal['status'] as String?, proposal['decided_by'] as String?)),
        if (payload['floor_limited'] == true) Text(copy.floorWarning),
        if (canDecide && (pending || stale)) Wrap(spacing: 8, children: <Widget>[
          if (!stale) FilledButton(onPressed: busy ? null : () { onDecision('accepted'); }, child: Text(copy.proposalAccept)),
          OutlinedButton(onPressed: busy ? null : () { onDecision('kept'); }, child: Text(copy.proposalKeep)),
        ]),
      ],
    )));
  }
}
