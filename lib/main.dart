import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'scale_and_pan_gesture_detector.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        backgroundColor: Color(0xFF0E0E0E),
        appBar: AppBar(
          backgroundColor: Colors.black,
          title: Text('Chart demo'),
        ),
        body: Chart(),
      ),
    );
  }
}

class Chart extends StatefulWidget {
  const Chart({
    Key key,
  }) : super(key: key);

  @override
  _ChartState createState() => _ChartState();
}

class _ChartState extends State<Chart> with TickerProviderStateMixin {
  static final rng = Random();
  Ticker ticker;

  final int intervalDuration = 1000;
  final double maxCurrentTickOffset = 150;

  List<Tick> ticks = [
    Tick(DateTime.now().millisecondsSinceEpoch - 2000, 40),
    Tick(DateTime.now().millisecondsSinceEpoch - 1000, 50),
  ];

  int nowEpoch;
  int rightEdgeEpoch; // for panning
  double intervalWidth = 25; // for scaling
  double _prevIntervalWidth;
  double currentTickOffset = 100;
  int panToCurrentAnimationStartEpoch;

  AnimationController _lastTickAnimationController;
  Animation _lastTickAnimation;

  /// Quote range animation.
  double canvasWidth; // to determine the range of visible ticks
  double topEdgeQuoteTarget = 60;
  double bottomEdgeQuoteTarget = 30;
  final quotePadding = 10;
  final quoteBoundsAnimationDuration = const Duration(milliseconds: 300);
  AnimationController _topEdgeQuoteAnimationController;
  AnimationController _bottomEdgeQuoteAnimationController;

  @override
  void initState() {
    super.initState();
    nowEpoch = DateTime.now().millisecondsSinceEpoch;
    rightEdgeEpoch = nowEpoch + pxToMs(currentTickOffset);

    ticker = this.createTicker((elapsed) {
      setState(() {
        final prevEpoch = nowEpoch;
        nowEpoch = DateTime.now().millisecondsSinceEpoch;
        final elapsedMs = nowEpoch - prevEpoch;
        if (rightEdgeEpoch > prevEpoch) {
          rightEdgeEpoch += elapsedMs; // autopanning
        }
        recalculateQuoteBoundTargets();
        animatePanToCurrentTick(elapsedMs);
      });
    });
    ticker.start();

    _lastTickAnimationController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 300),
    );
    _lastTickAnimation = CurvedAnimation(
      parent: _lastTickAnimationController,
      curve: Curves.easeOut,
    );

    _topEdgeQuoteAnimationController = AnimationController.unbounded(
      value: topEdgeQuoteTarget,
      vsync: this,
      duration: quoteBoundsAnimationDuration,
    );
    _bottomEdgeQuoteAnimationController = AnimationController.unbounded(
      value: bottomEdgeQuoteTarget,
      vsync: this,
      duration: quoteBoundsAnimationDuration,
    );

    // Tick stream simulation.
    Timer.periodic(Duration(seconds: 1), (timer) {
      double newPrice = ticks.last.quote;
      if (rng.nextBool()) {
        newPrice += rng.nextDouble() * 20 - 10;
      }
      setState(() {
        ticks.add(Tick(
          DateTime.now().millisecondsSinceEpoch,
          newPrice,
        ));
      });
      _lastTickAnimationController.reset();
      _lastTickAnimationController.forward();
    });
  }

  @override
  void dispose() {
    _lastTickAnimationController.dispose();
    super.dispose();
  }

  void animatePanToCurrentTick(int elapsedMs) {
    if (panToCurrentAnimationStartEpoch == null) return;
    final remainingAnimationTime =
        300 - (nowEpoch - panToCurrentAnimationStartEpoch);
    if (remainingAnimationTime <= 0) return;

    final from = rightEdgeEpoch;
    final to = nowEpoch + pxToMs(maxCurrentTickOffset) + remainingAnimationTime;

    final panSpeed = (to - from) / remainingAnimationTime;

    rightEdgeEpoch += (panSpeed * elapsedMs).ceil();
  }

  void recalculateQuoteBoundTargets() {
    if (canvasWidth == null) return;
    final leftEdgeEpoch = rightEdgeEpoch - pxToMs(canvasWidth);
    final visibleTickQuotes = ticks
        .where((tick) =>
            tick.epoch <= rightEdgeEpoch && tick.epoch >= leftEdgeEpoch)
        .map((tick) => tick.quote);

    final minQuote = visibleTickQuotes.reduce(min);
    final maxQuote = visibleTickQuotes.reduce(max);

    if (minQuote - quotePadding != bottomEdgeQuoteTarget) {
      bottomEdgeQuoteTarget = minQuote - quotePadding;
      _bottomEdgeQuoteAnimationController.animateTo(
        bottomEdgeQuoteTarget,
        curve: Curves.easeOut,
      );
    }
    if (maxQuote + quotePadding != topEdgeQuoteTarget) {
      topEdgeQuoteTarget = maxQuote + quotePadding;
      _topEdgeQuoteAnimationController.animateTo(
        topEdgeQuoteTarget,
        curve: Curves.easeOut,
      );
    }
  }

  int pxToMs(double px) {
    return (px / intervalWidth * intervalDuration).toInt();
  }

  double msToPx(int ms) {
    return ms / intervalDuration * intervalWidth;
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        ScaleAndPanGestureDetector(
          onScaleOrPanStart: (details) {
            _prevIntervalWidth = intervalWidth;
            if (rightEdgeEpoch > nowEpoch) {
              currentTickOffset = msToPx(rightEdgeEpoch - nowEpoch);
            }
          },
          onPanUpdate: (details) {
            setState(() {
              rightEdgeEpoch -= pxToMs(details.delta.dx);
              final upperLimit = nowEpoch + pxToMs(maxCurrentTickOffset);
              rightEdgeEpoch = rightEdgeEpoch.clamp(0, upperLimit);

              if (rightEdgeEpoch > nowEpoch) {
                currentTickOffset = msToPx(rightEdgeEpoch - nowEpoch);
              }
            });
          },
          onScaleUpdate: (details) {
            setState(() {
              intervalWidth =
                  (_prevIntervalWidth * details.scale).clamp(3.0, 50.0);

              if (rightEdgeEpoch > nowEpoch) {
                rightEdgeEpoch = nowEpoch + pxToMs(currentTickOffset);
              }
            });
          },
          onScaleOrPanEnd: (details) {
            // TODO: Use velocity for panning inertia.
          },
          child: LayoutBuilder(builder: (context, constraints) {
            canvasWidth = constraints.maxWidth;

            return CustomPaint(
              size: Size.infinite,
              painter: ChartPainter(
                data: ticks,
                intervalWidth: intervalWidth,
                intervalDuration: intervalDuration,
                rightEdgeEpoch: rightEdgeEpoch,
                topEdgeQuote: _topEdgeQuoteAnimationController.value,
                bottomEdgeQuote: _bottomEdgeQuoteAnimationController.value,
                lastTickAnimationProgress: _lastTickAnimation.value,
              ),
            );
          }),
        ),
        if (rightEdgeEpoch < nowEpoch) _buildForwardButton(),
      ],
    );
  }

  Widget _buildForwardButton() {
    return Positioned(
      bottom: 40,
      right: 20,
      child: IconButton(
        icon: Icon(
          Icons.arrow_forward,
          color: Colors.white,
        ),
        onPressed: _panToCurrentTick,
      ),
    );
  }

  void _panToCurrentTick() {
    panToCurrentAnimationStartEpoch = nowEpoch;
  }
}

class ChartPainter extends CustomPainter {
  ChartPainter({
    this.data,
    this.intervalWidth,
    this.intervalDuration,
    this.rightEdgeEpoch,
    this.bottomEdgeQuote,
    this.topEdgeQuote,
    this.lastTickAnimationProgress,
  });

  static final lineColor = Paint()
    ..color = Colors.white
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1;

  final List<Tick> data;
  final double intervalWidth;
  final int intervalDuration;
  final int rightEdgeEpoch;
  final double bottomEdgeQuote;
  final double topEdgeQuote;
  final double lastTickAnimationProgress;

  Size canvasSize;

  Offset _toCanvasOffset(Tick tick) {
    return Offset(
      _epochToX(tick.epoch),
      _quoteToY(tick.quote),
    );
  }

  double _epochToX(int epoch) {
    return canvasSize.width -
        (rightEdgeEpoch - epoch) / intervalDuration * intervalWidth;
  }

  double _quoteToY(double quote) {
    return canvasSize.height -
        (quote - bottomEdgeQuote) /
            (topEdgeQuote - bottomEdgeQuote) *
            canvasSize.height;
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvasSize = size;

    final first = _toCanvasOffset(data.first);
    Path path = Path();
    path.moveTo(first.dx, first.dy);
    for (var i = 1; i < data.length - 1; i++) {
      final offset = _toCanvasOffset(data[i]);
      path.lineTo(offset.dx, offset.dy);
    }

    final last = _toCanvasOffset(data.last);
    final prev = _toCanvasOffset(data[data.length - 2]);
    final lastTickOffset = prev + (last - prev) * lastTickAnimationProgress;
    path.lineTo(lastTickOffset.dx, lastTickOffset.dy);
    canvas.drawPath(path, lineColor);

    path.lineTo(lastTickOffset.dx, size.height);
    path.lineTo(0, size.height);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.fill
        ..shader = ui.Gradient.linear(
          Offset(0, (_quoteToY(topEdgeQuote) + _quoteToY(bottomEdgeQuote)) / 2),
          Offset(0, size.height),
          [
            Colors.white24,
            Colors.transparent,
          ],
        ),
    );

    canvas.drawCircle(lastTickOffset, 3, Paint()..color = Colors.pink);
    canvas.drawLine(
      lastTickOffset,
      Offset(size.width, lastTickOffset.dy),
      Paint()
        ..color = Colors.pink
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(ChartPainter oldDelegate) => true;

  @override
  bool shouldRebuildSemantics(ChartPainter oldDelegate) => false;
}

class Tick {
  final int epoch;
  final double quote;

  Tick(this.epoch, this.quote);
}
