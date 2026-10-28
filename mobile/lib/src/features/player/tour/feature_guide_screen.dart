import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/display_language/catalog.dart';
import '../../../core/display_language/controller.dart';
import '../../../core/theme/myos_spacing.dart';
import '../../../core/ui/myos_scaffold.dart';
import 'feature_list.dart';
import 'tour_controller.dart';

class FeatureGuideScreen extends ConsumerWidget {
  const FeatureGuideScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final MyosCopy copy = MyosCopy(ref.watch(displayLanguageProvider));
    final bool isArabic = copy.isArabic;
    final List<FeatureEntry> entries = featureList
        .where((FeatureEntry entry) => entry.audience == 'lifter')
        .toList(growable: false);
    return MyosScaffold(
      title: copy.featureGuideTitle,
      showBack: true,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(MyosSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            for (final FeatureEntry entry in entries)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(MyosSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(isArabic ? entry.titleAr : entry.titleEn,
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: MyosSpacing.xs),
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
