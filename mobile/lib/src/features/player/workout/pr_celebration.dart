import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/display_language/workout_copy.dart';
import '../../../core/personal_records.dart';

/// Short, non-interactive finish moment. It never participates in saving.
class PrCelebration extends StatefulWidget {
  const PrCelebration({required this.records, required this.languageCode, required this.onComplete, super.key});

  final List<WorkoutRecord> records;
  final String languageCode;
  final VoidCallback onComplete;

  @override
  State<PrCelebration> createState() => _PrCelebrationState();
}

class _PrCelebrationState extends State<PrCelebration> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(seconds: 2), widget.onComplete);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  WorkoutRecord _headline() {
    int priority(PrRecordKind kind) => switch (kind) {
          PrRecordKind.weight => 0,
          PrRecordKind.e1rm => 1,
          PrRecordKind.mostReps => 2,
        };
    final List<WorkoutRecord> sorted = [...widget.records]
      ..sort((WorkoutRecord a, WorkoutRecord b) {
        final int byKind = priority(a.kind).compareTo(priority(b.kind));
        return byKind != 0 ? byKind : b.value.compareTo(a.value);
      });
    return sorted.first;
  }

  @override
  Widget build(BuildContext context) {
    final WorkoutRecord record = _headline();
    final bool reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      liveRegion: true,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          const ColoredBox(color: Color(0xff07101f)),
          if (!reduceMotion)
            const IgnorePointer(
              child: CustomPaint(
                key: ValueKey<String>('prCelebration.confetti'),
                painter: _PrConfettiPainter(),
              ),
            ),
          Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
                const Icon(Icons.emoji_events, size: 92, color: Color(0xffffd166)),
                const SizedBox(height: 20),
                Text(WorkoutCopy(widget.languageCode).newPr,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(color: Colors.white)),
                const SizedBox(height: 12),
                Text(WorkoutCopy(widget.languageCode).prHeadline(record),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Colors.white)),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

class _PrConfettiPainter extends CustomPainter {
  const _PrConfettiPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const List<Color> colors = <Color>[Color(0xff2f6bff), Color(0xffffd166), Colors.white];
    final Paint paint = Paint()..style = PaintingStyle.fill;
    for (int i = 0; i < 48; i++) {
      final double x = ((i * 73) % 101) / 100 * size.width;
      final double y = ((i * 47) % 97) / 100 * size.height;
      final double w = 4 + (i % 3) * 2;
      paint.color = colors[i % colors.length].withValues(alpha: .8);
      canvas.drawRect(Rect.fromCenter(center: Offset(x, y), width: w, height: w * 2), paint);
    }
  }

  @override
  bool shouldRepaint(_PrConfettiPainter oldDelegate) => false;
}
