import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/display_language/catalog.dart';
import '../../../core/display_language/controller.dart';
import '../../../core/theme/myos_spacing.dart';
import '../../../core/theme/myos_theme.dart';
import '../../../core/ui/myos_icon_chip.dart';
import '../../../providers.dart';
import '../../../core/ui/myos_scaffold.dart';
import 'feature_list.dart';
import 'tour_controller.dart';

class WhatsNewFeatureRow extends StatelessWidget {
  const WhatsNewFeatureRow({
    super.key,
    required this.entry,
    required this.copy,
    required this.onShowMe,
  });

  final FeatureEntry entry;
  final MyosCopy copy;
  final VoidCallback onShowMe;

  IconData get _icon => switch (entry.id) {
        'weak_points' => Icons.fitness_center,
        'assistant_why' => Icons.chat_bubble_outline,
        'add_exercises' => Icons.add_circle_outline,
        'edit_program_chat' => Icons.edit_note,
        'movements_to_avoid' => Icons.block_outlined,
        _ => Icons.auto_awesome_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final MyosThemeExtension colors = MyosTheme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(MyosSpacing.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            MyosIconChip(
              child: Icon(_icon, color: colors.accent),
            ),
            const SizedBox(width: MyosSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    copy.isArabic ? entry.titleAr : entry.titleEn,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: MyosSpacing.xxs),
                  Text(copy.isArabic ? entry.sentenceAr : entry.sentenceEn),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: TextButton(onPressed: onShowMe, child: Text(copy.showMe)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class WhatsNewScreen extends ConsumerStatefulWidget {
  const WhatsNewScreen({super.key});

  @override
  ConsumerState<WhatsNewScreen> createState() => _WhatsNewScreenState();
}

class _WhatsNewScreenState extends ConsumerState<WhatsNewScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final List<FeatureEntry> allEntries = ref.read(featureEntriesProvider);
      final String? accountId =
          ref.read(authControllerProvider).session?.account.accountId;
      final ProgramFeatureAvailability availability =
          ref.read(programFeatureAvailabilityProvider);
      final Set<int> releases = allEntries
          .where((FeatureEntry entry) =>
              entry.release > 0 &&
              entry.release <= currentFeatureRelease &&
              isFeatureAvailableForAccount(entry, accountId, availability))
          .map((FeatureEntry entry) => entry.release)
          .toSet();
      if (releases.isEmpty) return;
      ref.read(analyticsClientProvider).whatsNewOpened(
            releaseCount: releases.length,
            highestRelease: releases.reduce((int a, int b) => a > b ? a : b),
            source: 'profile',
          );
    });
  }

  @override
  Widget build(BuildContext context) {
    final MyosCopy copy = MyosCopy(ref.watch(displayLanguageProvider));
    final List<FeatureEntry> entries = ref.watch(featureEntriesProvider);
    final String? accountId =
        ref.watch(authControllerProvider).session?.account.accountId;
    final ProgramFeatureAvailability availability =
        ref.watch(programFeatureAvailabilityProvider);
    final List<int> releases = entries
        .where((FeatureEntry entry) =>
            entry.release > 0 &&
            entry.release <= currentFeatureRelease &&
            isFeatureAvailableForAccount(entry, accountId, availability))
        .map((FeatureEntry entry) => entry.release)
        .toSet()
        .toList()
      ..sort((int first, int second) => second.compareTo(first));
    return MyosScaffold(
      title: copy.whatsNewTitle,
      showBack: true,
      body: ListView(
        padding: const EdgeInsets.all(MyosSpacing.md),
        children: <Widget>[
          for (final int release in releases) ...<Widget>[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: MyosSpacing.sm),
              child: Text(
                copy.whatsNewRelease(release),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            for (final FeatureEntry entry in entries.where(
              (FeatureEntry candidate) =>
                  candidate.audience == 'lifter' &&
                  candidate.release == release &&
                  candidate.release <= currentFeatureRelease &&
                  isFeatureAvailableForAccount(
                      candidate, accountId, availability),
            ))
              WhatsNewFeatureRow(
                entry: entry,
                copy: copy,
                onShowMe: () => ref
                    .read(tourControllerProvider.notifier)
                    .showMe(entry.id, source: 'whats_new'),
              ),
          ],
        ],
      ),
    );
  }
}
