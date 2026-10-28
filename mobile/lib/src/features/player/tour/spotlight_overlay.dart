import 'package:flutter/material.dart';

import '../../../core/display_language/catalog.dart';
import '../../../core/display_language/copy_context.dart';
import '../../../core/theme/myos_theme.dart';
import 'feature_list.dart';

/// Highlights a registered widget inside the Player shell's visible body.
class SpotlightOverlay extends StatefulWidget {
  const SpotlightOverlay({
    required this.targetKey,
    required this.entry,
    required this.step,
    required this.stopCount,
    required this.dotsCount,
    required this.onSkip,
    required this.onBack,
    required this.onNext,
    super.key,
  });

  final GlobalKey targetKey;
  final FeatureEntry entry;
  final int step;
  final int stopCount;
  final int dotsCount;
  final VoidCallback onSkip;
  final VoidCallback onBack;
  final VoidCallback onNext;

  @override
  State<SpotlightOverlay> createState() => _SpotlightOverlayState();
}

class _SpotlightGeometry {
  const _SpotlightGeometry({
    required this.target,
    required this.bodySize,
    required this.cardHeight,
    required this.cardTop,
    required this.pointerTop,
    required this.pointerLeft,
    required this.belowTarget,
  });

  final Rect target;
  final Size bodySize;
  final double cardHeight;
  final double cardTop;
  final double pointerTop;
  final double pointerLeft;
  final bool belowTarget;
}

class _SpotlightOverlayState extends State<SpotlightOverlay>
    with WidgetsBindingObserver {
  final GlobalKey _overlayKey = GlobalKey();
  final GlobalKey _cardKey = GlobalKey();
  Size? _lastBodySize;
  _SpotlightGeometry? _geometry;
  bool _measureQueued = false;
  ScrollPosition? _scrollPosition;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didUpdateWidget(SpotlightOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.targetKey != widget.targetKey ||
        oldWidget.entry.id != widget.entry.id ||
        oldWidget.step != widget.step ||
        oldWidget.stopCount != widget.stopCount ||
        oldWidget.dotsCount != widget.dotsCount) {
      _geometry = null;
      _queueMeasure();
    }
  }

  @override
  void didChangeMetrics() {
    _geometry = null;
    _queueMeasure();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollPosition?.removeListener(_onScroll);
    super.dispose();
  }

  void _onScroll() {
    _geometry = null;
    _queueMeasure();
  }

  void _queueMeasure() {
    if (_measureQueued) return;
    _measureQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measureQueued = false;
      if (mounted) _measure();
    });
  }

  void _measure() {
    final RenderObject? overlayRender =
        _overlayKey.currentContext?.findRenderObject();
    final RenderObject? targetRender =
        widget.targetKey.currentContext?.findRenderObject();
    if (overlayRender is! RenderBox ||
        targetRender is! RenderBox ||
        !overlayRender.hasSize ||
        !targetRender.hasSize) {
      return;
    }
    final BuildContext? targetContext = widget.targetKey.currentContext;
    if (targetContext == null) return;
    final ScrollPosition? scrollPosition =
        Scrollable.maybeOf(targetContext)?.position;
    if (_scrollPosition != scrollPosition) {
      _scrollPosition?.removeListener(_onScroll);
      _scrollPosition = scrollPosition;
      _scrollPosition?.addListener(_onScroll);
    }
    final Offset targetGlobal = targetRender.localToGlobal(Offset.zero);
    final Offset targetOrigin = overlayRender.globalToLocal(targetGlobal);
    final Rect target = targetOrigin & targetRender.size;
    final Size bodySize = overlayRender.size;
    final RenderObject? cardRender =
        _cardKey.currentContext?.findRenderObject();
    final double cardHeight = cardRender is RenderBox && cardRender.hasSize
        ? cardRender.size.height
        : 0;
    final double safeCardHeight =
        cardHeight.clamp(0, bodySize.height - 24).toDouble();
    final bool below = target.center.dy < bodySize.height / 2;
    final double preferred = below
        ? target.bottom + 16
        : target.top - safeCardHeight - 16;
    final double top = preferred
        .clamp(12, bodySize.height - safeCardHeight - 12)
        .toDouble();
    final double pointerLeft = (target.center.dx - 8)
        .clamp(16, bodySize.width - 32)
        .toDouble();
    final _SpotlightGeometry next = _SpotlightGeometry(
      target: target,
      bodySize: bodySize,
      cardHeight: safeCardHeight,
      cardTop: top,
      pointerTop: below ? top - 8 : top + safeCardHeight,
      pointerLeft: pointerLeft,
      belowTarget: below,
    );
    if (next.target == _geometry?.target &&
        next.bodySize == _geometry?.bodySize &&
        next.cardHeight == _geometry?.cardHeight &&
        next.cardTop == _geometry?.cardTop) {
      return;
    }
    setState(() => _geometry = next);
    _queueMeasure();
  }

  @override
  Widget build(BuildContext context) {
    final MyosThemeExtension colors = MyosTheme.of(context);
    final MyosCopy copy = displayCopyOf(context);
    return Positioned.fill(
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final Size bodySize = constraints.biggest;
          if (_lastBodySize != bodySize) {
            _lastBodySize = bodySize;
            _geometry = null;
            _queueMeasure();
          }
          final _SpotlightGeometry? geometry = _geometry;
          return SizedBox.expand(
            key: _overlayKey,
            child: Stack(
              clipBehavior: Clip.hardEdge,
              children: <Widget>[
                Positioned.fill(
                  child: CustomPaint(
                    painter: _SpotlightDimmer(geometry?.target),
                  ),
                ),
                if (geometry != null)
                  Positioned.fromRect(
                    rect: geometry.target,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(color: colors.accent, width: 2),
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                Positioned(
                  top: 8,
                  right: Directionality.of(context) == TextDirection.rtl
                      ? null
                      : 8,
                  left: Directionality.of(context) == TextDirection.rtl
                      ? 8
                      : null,
                  child: TextButton(
                    key: const ValueKey<String>('tour_skip'),
                    onPressed: widget.onSkip,
                    style: TextButton.styleFrom(
                      foregroundColor: colors.textPrimary,
                      backgroundColor: colors.surfaceElevated,
                      minimumSize: const Size(64, 44),
                      shape: const StadiumBorder(),
                    ),
                    child: Text(copy.tourSkip),
                  ),
                ),
                if (geometry != null) ...<Widget>[
                  Positioned(
                    top: geometry.pointerTop,
                    left: geometry.pointerLeft,
                    child: CustomPaint(
                      size: const Size(16, 8),
                      painter: _TooltipPointer(
                        pointsUp: geometry.belowTarget,
                        color: colors.surface,
                      ),
                    ),
                  ),
                  Positioned(
                    top: geometry.cardTop,
                    left: 16,
                    right: 16,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: (bodySize.height - 24)
                            .clamp(0, double.infinity)
                            .toDouble(),
                      ),
                      child: Card(
                        key: _cardKey,
                        color: colors.surface,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Text(
                                copy.tourStepLabel(widget.step + 1, widget.stopCount),
                                style: TextStyle(color: colors.textSecondary),
                              ),
                              const SizedBox(height: 8),
                              Flexible(
                                fit: FlexFit.loose,
                                child: SingleChildScrollView(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: <Widget>[
                                      Text(
                                        Directionality.of(context) ==
                                                TextDirection.rtl
                                            ? widget.entry.titleAr
                                            : widget.entry.titleEn,
                                        style: TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.bold,
                                          color: colors.textPrimary,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        Directionality.of(context) ==
                                                TextDirection.rtl
                                            ? widget.entry.sentenceAr
                                            : widget.entry.sentenceEn,
                                        style: TextStyle(
                                          color: colors.textPrimary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: <Widget>[
                                  for (int dot = 0; dot < widget.dotsCount; dot++)
                                    Padding(
                                      padding: const EdgeInsetsDirectional.only(
                                        end: 5,
                                      ),
                                      child: Icon(
                                        Icons.circle,
                                        size: 7,
                                        color: dot == widget.step
                                            ? colors.accent
                                            : colors.borderStrong,
                                      ),
                                    ),
                                  const Spacer(),
                                  OutlinedButton(
                                    key: const ValueKey<String>('tour_back'),
                                    onPressed:
                                        widget.step == 0 ? null : widget.onBack,
                                    style: OutlinedButton.styleFrom(
                                      minimumSize: const Size(64, 44),
                                      foregroundColor: colors.textPrimary,
                                      side: BorderSide(
                                        color: colors.borderStrong,
                                      ),
                                    ),
                                    child: Text(copy.tourBack),
                                  ),
                                  const SizedBox(width: 8),
                                  FilledButton(
                                    key: const ValueKey<String>('tour_next'),
                                    onPressed: widget.onNext,
                                    style: FilledButton.styleFrom(
                                      minimumSize: const Size(80, 44),
                                      backgroundColor: colors.accent,
                                    ),
                                    child: Text(copy.tourNext),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SpotlightDimmer extends CustomPainter {
  const _SpotlightDimmer(this.cutout);

  final Rect? cutout;

  @override
  void paint(Canvas canvas, Size size) {
    final Path shade = Path()..addRect(Offset.zero & size);
    final Rect? rect = cutout;
    if (rect != null) {
      shade.addRRect(RRect.fromRectAndRadius(
        rect.inflate(6),
        const Radius.circular(14),
      ));
      shade.fillType = PathFillType.evenOdd;
    }
    canvas.drawPath(shade, Paint()..color = Colors.black.withValues(alpha: 0.74));
  }

  @override
  bool shouldRepaint(_SpotlightDimmer oldDelegate) =>
      oldDelegate.cutout != cutout;
}

class _TooltipPointer extends CustomPainter {
  const _TooltipPointer({required this.pointsUp, required this.color});

  final bool pointsUp;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Path triangle = Path()
      ..moveTo(0, pointsUp ? size.height : 0)
      ..lineTo(size.width, pointsUp ? size.height : 0)
      ..lineTo(size.width / 2, pointsUp ? 0 : size.height)
      ..close();
    canvas.drawPath(triangle, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_TooltipPointer oldDelegate) =>
      oldDelegate.pointsUp != pointsUp || oldDelegate.color != color;
}
