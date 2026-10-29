import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../../core/display_language/workout_copy.dart';
import '../../../core/analytics_client.dart';
import '../../../core/models.dart';
import '../../../core/personal_records.dart';
import 'workout_card_action_adapter.dart';
import 'workout_card_action_platform.dart';

/// A device-rendered 9:16 workout card. Its inputs are the immutable summary
/// captured when Finish was tapped; sensitive profile and cardio calorie data
/// are deliberately not inputs to this view.
class WorkoutShareCard extends StatelessWidget {
  const WorkoutShareCard({
    required this.languageCode,
    required this.dayName,
    this.duration,
    required this.stats,
    required this.records,
    this.prCount,
    this.photoBytes,
    super.key,
  });

  final String languageCode;
  final String? dayName;
  final Duration? duration;
  final WorkoutSummaryStats stats;
  final List<WorkoutRecord> records;
  final int? prCount;
  final Uint8List? photoBytes;

  bool get _arabic => languageCode == 'ar';
  WorkoutCopy get _copy => WorkoutCopy(languageCode);

  String? get _duration {
    final Duration? elapsed = duration;
    if (elapsed == null) return null;
    final int minutes = elapsed.inMinutes;
    if (minutes >= 60) {
      final int hours = minutes ~/ 60;
      final int remainder = minutes % 60;
      return '$hours${_arabic ? 'س' : 'h'}${remainder == 0 ? '' : ' $remainder${_arabic ? 'د' : 'm'}'}';
    }
    return '$minutes${_arabic ? 'د' : 'm'}';
  }

  String get _cardioMinutes => _arabic
      ? '${NumberFormat('#,##0', 'en').format(stats.cardioMinutes!)} ${_copy.minutes}'
      : '${NumberFormat('#,##0', 'en').format(stats.cardioMinutes!)} min';

  int get _prExerciseCount => prCount ?? records
      .map((WorkoutRecord r) => r.exerciseId ?? r.exerciseName)
      .toSet()
      .length;

  @override
  Widget build(BuildContext context) {
    final bool cardioOnly = stats.workingSets == 0 && stats.cardioMinutes != null;
    final String volume = NumberFormat('#,##0', 'en').format(stats.totalVolumeKg.round());
    final TextStyle baseStyle = TextStyle(fontFamily: _arabic ? 'IBMPlexSansArabic' : 'Inter', color: Colors.white);
    return AspectRatio(aspectRatio: 9 / 16, child: Material(type: MaterialType.transparency,
      child: DefaultTextStyle(style: baseStyle, child: Directionality(
        textDirection: _arabic ? ui.TextDirection.rtl : ui.TextDirection.ltr,
        child: MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
          child: _buildCardSurface(cardioOnly: cardioOnly, volume: volume)),
      )),
    ));
  }

  Widget _buildCardSurface({required bool cardioOnly, required String volume}) => DecoratedBox(
    decoration: const BoxDecoration(gradient: RadialGradient(
      center: Alignment(0.6, -0.9), radius: 1.2,
      colors: <Color>[Color(0xff16305A), Color(0xff0A1422), Color(0xff070F1A)],
      stops: <double>[0, .55, 1])),
    child: Stack(fit: StackFit.expand, children: <Widget>[
      if (photoBytes case final Uint8List photo)
        Positioned.fill(child: Image(image: ResizeImage(MemoryImage(photo), width: 1080, height: 1920,
          policy: ResizeImagePolicy.fit), fit: BoxFit.cover, alignment: Alignment.center,
          errorBuilder: (_, __, ___) => const SizedBox.shrink())),
      const Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(
        begin: Alignment.topCenter, end: Alignment.bottomCenter,
        colors: <Color>[Color(0x59070F1A), Color(0x00070F1A), Color(0xeb070F1A)],
        stops: <double>[0, .45, 1])))),
      Align(key: const ValueKey<String>('workoutCard.logoPlacement'),
        alignment: AlignmentDirectional.bottomEnd, child: Padding(
        padding: const EdgeInsetsDirectional.only(end: 26, bottom: 23),
        child: Image.asset('assets/brand/mayos-lockup-white.png',
          key: const ValueKey<String>('workoutCard.logo'), height: 37, fit: BoxFit.contain))),
      Align(alignment: Alignment.bottomCenter, child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(26, 24, 26, 77),
        child: _buildCardDetails(cardioOnly: cardioOnly, volume: volume))),
    ]));

  Widget _buildCardDetails({required bool cardioOnly, required String volume}) => Column(
    mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      if (_prExerciseCount > 0) _buildPrBadge(),
      if (_dayName case final String name) _buildDayName(name),
      const SizedBox(height: 20),
      _buildStatsRow(cardioOnly: cardioOnly, volume: volume),
    ]);

  Widget _buildPrBadge() => Padding(padding: const EdgeInsets.only(bottom: 11),
    child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
      const Icon(Icons.emoji_events_outlined, key: ValueKey<String>('workoutCard.trophy'),
        color: Color(0xffF2C94C), size: 20),
      const SizedBox(width: 8),
      Flexible(child: FittedBox(fit: BoxFit.scaleDown, alignment: AlignmentDirectional.centerStart,
        child: Text(_prCopy, maxLines: 1, style: TextStyle(fontFamily: _arabic ? 'IBMPlexSansArabic' : 'Inter',
          color: const Color(0xffF2C94C), fontSize: 16.4, fontWeight: FontWeight.w600)))),
    ]));

  String get _prCopy => _arabic
      ? '${NumberFormat('#,##0', 'en').format(_prExerciseCount)} ${_prExerciseCount == 1 ? 'رقم قياسي' : 'أرقام قياسية'}'
      : '${NumberFormat('#,##0', 'en').format(_prExerciseCount)} personal records';

  Widget _buildDayName(String name) => Padding(padding: const EdgeInsets.only(bottom: 20),
    child: Text(name, maxLines: 2, overflow: TextOverflow.ellipsis,
      style: TextStyle(color: Colors.white, fontFamily: _arabic ? 'IBMPlexSansArabic' : 'Montserrat',
        fontSize: 43, height: 1.02, fontWeight: FontWeight.w800)));

  String? get _dayName {
    final String? name = dayName?.trim();
    return name == null || name.isEmpty || name == 'Day' ? null : name;
  }

  Widget _buildStatsRow({required bool cardioOnly, required String volume}) {
    final List<(String, String)> values = <(String, String)>[];
    if (_duration case final String elapsed) values.add((elapsed, _arabic ? _copy.duration : 'Duration'));
    if (cardioOnly) {
      values.add((_cardioMinutes, _copy.cardio));
    } else {
      values.add((volume, _arabic ? 'الوزن كجم' : 'Volume kg'));
      values.add(('${stats.workingSets}', _arabic ? 'المجموعات' : 'Sets'));
    }
    return Container(padding: const EdgeInsets.only(top: 14),
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0x47f3f6fb)))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
      for (int i = 0; i < values.length; i++)
        Expanded(child: Container(
          padding: EdgeInsetsDirectional.only(start: i == 0 ? 0 : 14, end: 8),
          decoration: i == 0 ? null : const BoxDecoration(
            border: BorderDirectional(start: BorderSide(color: Color(0x33f3f6fb)))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            FittedBox(fit: BoxFit.scaleDown, alignment: AlignmentDirectional.centerStart,
              child: Text(values[i].$1, maxLines: 1, textDirection: ui.TextDirection.ltr,
                style: TextStyle(color: Colors.white, fontFamily: _arabic ? 'IBMPlexSansArabic' : 'Montserrat',
                  fontSize: 24.3, fontWeight: FontWeight.w700))),
            const SizedBox(height: 3),
            Text(values[i].$2, maxLines: 2, overflow: TextOverflow.ellipsis,
              style: TextStyle(color: const Color(0xffC9D3E1),
                fontFamily: _arabic ? 'IBMPlexSansArabic' : 'Inter', fontSize: 14.3,
                fontWeight: FontWeight.w500)),
          ]))),
    ]));
  }

}

WorkoutShareCard latestSessionShareCard({
  required LatestSession session,
  required String languageCode,
  Uint8List? photoBytes,
}) =>
    WorkoutShareCard(
      languageCode: languageCode,
      dayName: session.splitName == 'Day' ? null : session.splitName,
      duration: switch (session.durationSeconds) {
        final int seconds when seconds > 0 => Duration(seconds: seconds),
        _ => null,
      },
      stats: WorkoutSummaryStats(
        exercisesDone: 0,
        workingSets: session.workingSets,
        totalVolumeKg: session.volumeKg,
        cardioMinutes: session.cardioMinutes == 0 ? null : session.cardioMinutes,
      ),
      records: const <WorkoutRecord>[],
      prCount: session.prCount,
      photoBytes: photoBytes,
    );

/// Captures the card, then waits for an explicit action in the preview.
Future<bool> shareWorkoutCard(
    BuildContext context, WorkoutShareCard card) =>
    captureAndPreviewWorkoutCard(context, card,
      capture: () => _captureWorkoutCard(context, card));

Future<bool> captureAndPreviewWorkoutCard(
  BuildContext context, WorkoutShareCard card, {
  required Future<Uint8List> Function() capture,
  Duration captureTimeout = const Duration(seconds: 20),
  WorkoutCardActionAdapter? actionAdapter,
}) async {
  final String languageCode = card.languageCode;
  try {
    final Uint8List pngBytes = await capture().timeout(captureTimeout);
    if (!context.mounted) return false;
    final WorkoutCardActionAdapter actions = actionAdapter ??
        createWorkoutCardActionAdapter(pngBytes);
    try {
      return await showWorkoutCardPreview(context, pngBytes,
        languageCode: languageCode, share: actions.share, save: actions.save) ?? false;
    } finally {
      actions.dispose();
    }
  } on TimeoutException {
    if (context.mounted) _showShareError(context, languageCode);
    return false;
  } on Exception {
    if (context.mounted) _showShareError(context, languageCode);
    return false;
  } on Error {
    if (context.mounted) _showShareError(context, languageCode);
    return false;
  }
}

/// Full-screen preview. The platform operation is invoked only by a button tap.
Future<bool?> showWorkoutCardPreview(
  BuildContext context,
  Uint8List pngBytes, {
  required String languageCode,
  required Future<bool> Function() share,
  required Future<bool> Function() save,
}) => showDialog<bool>(
  context: context,
  barrierDismissible: false,
  builder: (BuildContext dialogContext) => _WorkoutCardPreview(
    pngBytes: pngBytes, languageCode: languageCode, share: share, save: save),
);

class _WorkoutCardPreview extends StatefulWidget {
  const _WorkoutCardPreview({required this.pngBytes, required this.languageCode,
    required this.share, required this.save});
  final Uint8List pngBytes;
  final String languageCode;
  final Future<bool> Function() share;
  final Future<bool> Function() save;
  @override
  State<_WorkoutCardPreview> createState() => _WorkoutCardPreviewState();
}

class _WorkoutCardPreviewState extends State<_WorkoutCardPreview> {
  bool _busy = false;
  bool get _ar => widget.languageCode == 'ar';

  Future<void> _run(Future<bool> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final bool complete = await action();
      if (mounted && complete) {
        Navigator.of(context).pop(true);
      } else if (mounted) {
        setState(() => _busy = false);
      }
    } on Exception {
      _reportActionFailure();
    } on Error {
      _reportActionFailure();
    }
  }

  void _reportActionFailure() {
    if (!mounted) return;
    setState(() => _busy = false);
    _showShareError(context, widget.languageCode);
  }

  @override
  Widget build(BuildContext context) => PopScope<dynamic>(
    canPop: !_busy,
    child: Scaffold(
    backgroundColor: const Color(0xff07162d),
    appBar: AppBar(backgroundColor: const Color(0xff07162d),
      leading: IconButton(tooltip: _ar ? 'إغلاق' : 'Close', icon: const Icon(Icons.close),
        onPressed: _busy ? null : () => Navigator.of(context).pop(false))),
    body: SafeArea(child: Column(children: <Widget>[
      Expanded(child: Center(child: Padding(padding: const EdgeInsets.all(12),
        child: AspectRatio(aspectRatio: 9 / 16, child: Image.memory(widget.pngBytes, fit: BoxFit.contain)))),),
      Padding(padding: const EdgeInsets.all(16), child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
        SizedBox(width: double.infinity, child: FilledButton.icon(
          key: const ValueKey<String>('workoutCard.share'), onPressed: _busy ? null : () => _run(widget.share),
          icon: const Icon(Icons.ios_share), label: Text(_ar ? 'مشاركة' : 'Share'))),
        SizedBox(width: double.infinity, child: OutlinedButton.icon(
          key: const ValueKey<String>('workoutCard.save'), onPressed: _busy ? null : () => _run(widget.save),
          icon: const Icon(Icons.download), label: Text(_ar ? 'حفظ الصورة' : 'Save image'))),
      ])),
    ])),
  ));
}

void _showShareError(BuildContext context, String languageCode) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(languageCode == 'ar' ? 'تعذر إنشاء الصورة أو مشاركتها. حاول مرة أخرى.' : 'Could not create or share the image. Try again.'),
  ));
}

Future<bool> shareWorkoutCardAndTrack({
  required Future<bool> Function() share,
  required AnalyticsClient analytics,
  required String source,
  required WorkoutPhotoChoiceResult photo,
}) async {
  final bool completed = await share();
  if (completed) {
    analytics.shareCardShared(
      source: source,
      hasPhoto: photo.photoBytes != null,
      photoSource: photo.source,
    );
  }
  return completed;
}

typedef WorkoutImagePicker = Future<XFile?> Function(ImageSource source);

typedef WorkoutCardShare = Future<bool> Function(
    BuildContext context, WorkoutShareCard card);

final Provider<WorkoutCardShare> workoutCardShareProvider =
    Provider<WorkoutCardShare>((Ref ref) => shareWorkoutCard);

enum _WorkoutPhotoChoice { camera, gallery, none }

@immutable
class WorkoutPhotoChoiceResult {
  const WorkoutPhotoChoiceResult.cancelled()
      : cancelled = true, photoBytes = null, source = 'none';
  const WorkoutPhotoChoiceResult.noPhoto()
      : cancelled = false, photoBytes = null, source = 'none';
  const WorkoutPhotoChoiceResult.photo(this.photoBytes, this.source)
      : cancelled = false;

  final bool cancelled;
  final Uint8List? photoBytes;

  final String source;
}

/// Shows the on-device photo choice. A cancelled or denied picker returns to
/// this sheet, so skipping the photo is always available.
Future<WorkoutPhotoChoiceResult> chooseWorkoutPhoto(
  BuildContext context, {
  required String languageCode,
  WorkoutImagePicker? pickImage,
    void Function(String source)? onSourceSelected,
}) async {
  final WorkoutCopy copy = WorkoutCopy(languageCode);
  final WorkoutImagePicker picker = pickImage ??
      (ImageSource source) => ImagePicker().pickImage(
            source: source,
            maxWidth: 1920,
            maxHeight: 3414,
            imageQuality: 90,
          );
  while (context.mounted) {
    if (!context.mounted) return const WorkoutPhotoChoiceResult.cancelled();
    final _WorkoutPhotoChoice? choice =
        await _showWorkoutPhotoChoices(context, copy);
    if (!context.mounted) return const WorkoutPhotoChoiceResult.cancelled();
    if (choice == null) return const WorkoutPhotoChoiceResult.cancelled();
    if (choice == _WorkoutPhotoChoice.none) {
      onSourceSelected?.call('none');
      return const WorkoutPhotoChoiceResult.noPhoto();
    }
    try {
      final ImageSource source = choice == _WorkoutPhotoChoice.camera
          ? ImageSource.camera
          : ImageSource.gallery;
      final String sourceName = choice == _WorkoutPhotoChoice.camera
          ? 'camera'
          : 'gallery';
      final Uint8List? photoBytes = await _pickWorkoutPhoto(picker, source);
      if (photoBytes != null) {
        onSourceSelected?.call(sourceName);
        return WorkoutPhotoChoiceResult.photo(photoBytes, sourceName);
      }
    } on PlatformException {
      continue;
    }
  }
  return const WorkoutPhotoChoiceResult.cancelled();
}

Future<_WorkoutPhotoChoice?> _showWorkoutPhotoChoices(
    BuildContext context, WorkoutCopy copy) =>
    showModalBottomSheet<_WorkoutPhotoChoice>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext sheetContext) => SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                _photoChoiceTile(
                  sheetContext,
                  _WorkoutPhotoChoice.camera,
                  Icons.photo_camera_outlined,
                  copy.takePhoto,
                ),
                _photoChoiceTile(
                  sheetContext,
                  _WorkoutPhotoChoice.gallery,
                  Icons.photo_library_outlined,
                  copy.choosePhotoFromGallery,
                ),
                _photoChoiceTile(
                  sheetContext,
                  _WorkoutPhotoChoice.none,
                  Icons.block_outlined,
                  copy.noPhoto,
                ),
              ],
            ),
          ),
        ),
      ),
    );

ListTile _photoChoiceTile(BuildContext context, _WorkoutPhotoChoice choice,
        IconData icon, String label) =>
    ListTile(
      leading: Icon(icon),
      title: Text(label),
      onTap: () => Navigator.pop(context, choice),
    );

Future<Uint8List?> _pickWorkoutPhoto(
    WorkoutImagePicker picker, ImageSource source) async {
  final XFile? photoFile = await picker(source);
  return photoFile?.readAsBytes();
}


Future<void> _precacheWorkoutPhoto(Uint8List photo, BuildContext context) {
  final Completer<void> decoded = Completer<void>();
  precacheImage(
    ResizeImage(MemoryImage(photo), width: 1080, height: 1920,
        policy: ResizeImagePolicy.fit),
    context,
    onError: (Object error, StackTrace? stackTrace) {
      if (!decoded.isCompleted) {
        decoded.completeError(error, stackTrace ?? StackTrace.current);
      }
    },
  ).then((_) {
    if (!decoded.isCompleted) decoded.complete();
  });
  return decoded.future;
}

Future<Uint8List> _captureWorkoutCard(
    BuildContext context, WorkoutShareCard card) async {
  if (card.photoBytes case final Uint8List photo) {
    await _precacheWorkoutPhoto(photo, context);
  }
  if (!context.mounted) throw StateError('Share card capture context was removed');
  await precacheImage(const AssetImage('assets/brand/mayos-lockup-white.png'), context);
  if (!context.mounted) throw StateError('Share card capture context was removed');
  final GlobalKey boundaryKey = GlobalKey();
  final OverlayState overlay = Overlay.of(context);
  final OverlayEntry entry = OverlayEntry(
    builder: (BuildContext context) => Positioned(
      left: -1200,
      top: 0,
      width: 360,
      child: Material(type: MaterialType.transparency, child: DefaultTextStyle(
        style: TextStyle(fontFamily: card.languageCode == 'ar' ? 'IBMPlexSansArabic' : 'Inter', color: Colors.white),
        child: RepaintBoundary(key: boundaryKey, child: card))),
    ),
  );
  overlay.insert(entry);
  WidgetsBinding.instance.scheduleFrame();
  try {
    await WidgetsBinding.instance.endOfFrame;
    final RenderRepaintBoundary boundary = boundaryKey.currentContext!
        .findRenderObject()! as RenderRepaintBoundary;
    final ui.Image image = await boundary.toImage(pixelRatio: 3);
    final ByteData? bytes =
        await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (bytes == null) throw StateError('Could not render workout card');
    return bytes.buffer.asUint8List();
  } finally {
    entry.remove();
  }
}
