import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/display_language/catalog.dart';
import '../../../core/display_language/controller.dart';
import '../../../core/theme/mayos_spacing.dart';
import '../../../core/ui/mayos_scaffold.dart';
import '../../../providers.dart';
import 'feature_list.dart';
import 'tour_controller.dart';

class FeatureGuideScreen extends ConsumerWidget {
  const FeatureGuideScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final MayosCopy copy = MayosCopy(ref.watch(displayLanguageProvider));
    final bool isArabic = copy.isArabic;
    final String? accountId =
        ref.watch(authControllerProvider).session?.account.accountId;
    final ProgramFeatureAvailability availability =
        ref.watch(programFeatureAvailabilityProvider);
    final List<FeatureEntry> entries = ref.watch(featureEntriesProvider)
        .where((FeatureEntry entry) => entry.audience == 'lifter' &&
            entry.release <= currentFeatureRelease &&
            isFeatureAvailableForAccount(entry, accountId, availability))
        .toList(growable: false);
    return MayosScaffold(
      title: copy.featureGuideTitle,
      showBack: true,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(MayosSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            for (final FeatureEntry entry in entries)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(MayosSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(isArabic ? entry.titleAr : entry.titleEn,
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: MayosSpacing.xs),
                      Text(isArabic ? entry.sentenceAr : entry.sentenceEn),
                      Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: TextButton(
                          onPressed: () => ref
                              .read(tourControllerProvider.notifier)
                              .showMe(entry.id),
                          child: Text(copy.showMe),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
