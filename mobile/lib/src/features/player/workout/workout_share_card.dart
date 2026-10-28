import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/display_language/workout_copy.dart';
import '../../../core/analytics_client.dart';
import '../../../core/models.dart';
import '../../../core/personal_records.dart';

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
    final bool cardioOnly =
        stats.workingSets == 0 && stats.cardioMinutes != null;
    final String volume =
        NumberFormat('#,##0', 'en').format(stats.totalVolumeKg.round());
    return AspectRatio(
      aspectRatio: 9 / 16,
      child: Directionality(
        textDirection: _arabic ? ui.TextDirection.rtl : ui.TextDirection.ltr,
        child: MediaQuery(
          data:
              MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
          child: _buildCardSurface(cardioOnly: cardioOnly, volume: volume),
        ),
      ),
    );
  }

  Widget _buildCardSurface(
          {required bool cardioOnly, required String volume}) =>
      DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[
              Color(0xff102b54),
              Color(0xff07162d),
              Color(0xff010814),
            ],
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            if (photoBytes case final Uint8List photo)
              Positioned.fill(
                child: Image(
                  image: ResizeImage(
                    MemoryImage(photo),
                    width: 1080,
                    height: 1920,
                    policy: ResizeImagePolicy.fit,
                  ),
                  fit: BoxFit.cover,
                  alignment: Alignment.center,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            if (photoBytes != null)
              const Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: <Color>[
                        Color(0x33010814),
                        Color(0x66010814),
                        Color(0xf2010814),
                      ],
                      stops: <double>[0, 0.52, 1],
                    ),
                  ),
                ),
              ),
            Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.only(top: 36),
                child: Image.asset('assets/brand/mayos-lockup-white.png',
                    width: 190, fit: BoxFit.contain),
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(34, 24, 34, 42),
                child:
                    _buildCardDetails(cardioOnly: cardioOnly, volume: volume),
              ),
            ),
          ],
        ),
      );

  Widget _buildCardDetails(
          {required bool cardioOnly, required String volume}) =>
      Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (_prExerciseCount > 0) _buildPrBadge(),
          if (_dayName case final String name) _buildDayName(name),
          const SizedBox(height: 28),
          _buildStatsRow(cardioOnly: cardioOnly, volume: volume),
        ],
      );

  Widget _buildPrBadge() => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Text(
          '🏆 ${_copy.shareCardPrCount(_prExerciseCount)}',
          style: const TextStyle(
            color: Color(0xffffd166),
            fontSize: 30,
            fontWeight: FontWeight.w700,
          ),
        ),
      );

  Widget _buildDayName(String name) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Text(
          name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 54,
            height: 1.05,
            fontWeight: FontWeight.w700,
          ),
        ),
      );

  String? get _dayName {
    final String? name = dayName?.trim();
    return name == null || name.isEmpty || name == 'Day' ? null : name;
  }

  Widget _buildStatsRow({required bool cardioOnly, required String volume}) =>
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (_duration case final String durationLabel)
            _stat(durationLabel, _copy.duration.toUpperCase()),
          if (cardioOnly)
            _stat(_cardioMinutes, _copy.cardio.toUpperCase())
          else ...<Widget>[
            _stat('$volume kg', _copy.totalVolume.toUpperCase()),
            _stat('${stats.workingSets}', _copy.workingSets.toUpperCase()),
          ],
        ],
      );

  Widget _stat(String value, String label) => Expanded(
        child: Padding(
          padding: const EdgeInsetsDirectional.only(end: 6),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(value,
                    maxLines: 1,
                    textDirection: ui.TextDirection.ltr,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 34,
                        fontWeight: FontWeight.w700)),
                ),
                const SizedBox(height: 6),
                Text(label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Color(0xffb6c4d8),
                        fontSize: 15,
                        fontWeight: FontWeight.w600)),
              ]),
        ),
      );
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

/// Captures an off-screen card locally and opens the platform share sheet.
Future<bool> shareWorkoutCard(
    BuildContext context, WorkoutShareCard card) async {
  final Uint8List pngBytes = await _captureWorkoutCard(context, card);
  final ShareResult result = await SharePlus.instance.share(
    ShareParams(files: <XFile>[
      XFile.fromData(
        pngBytes,
        mimeType: 'image/png',
        name: 'mayos-workout.png',
      ),
    ]),
  );
  return result.status != ShareResultStatus.dismissed;
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

Future<Uint8List> _captureWorkoutCard(
    BuildContext context, WorkoutShareCard card) async {
  if (card.photoBytes case final Uint8List photo) {
    await precacheImage(
      ResizeImage(MemoryImage(photo), width: 1080, height: 1920,
          policy: ResizeImagePolicy.fit),
      context,
    );
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
      child: RepaintBoundary(key: boundaryKey, child: card),
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
