import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'scale_and_pan_gesture_detector.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIOverlays([]);
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        backgroundColor: Color(0xFF0E0E0E),
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
  int rightBoundEpoch; // for panning
  double intervalWidth = 25; // for scaling
  double _prevIntervalWidth;
  double currentTickOffset = 100;
  int panToCurrentAnimationStartEpoch;

  AnimationController _lastTickAnimationController;
  Animation _lastTickAnimation;

  /// Quote range animation.
  double canvasWidth; // to determine the range of visible ticks
  double topBoundQuoteTarget = 60;
  double bottomBoundQuoteTarget = 30;
  final quotePadding = 10;
  final quoteBoundsAnimationDuration = const Duration(milliseconds: 300);
  AnimationController _topBoundQuoteAnimationController;
  AnimationController _bottomBoundQuoteAnimationController;

  @override
  void initState() {
    super.initState();
    nowEpoch = DateTime.now().millisecondsSinceEpoch;
    rightBoundEpoch = nowEpoch + pxToMs(currentTickOffset);

    ticker = this.createTicker((elapsed) {
      setState(() {
        final prevEpoch = nowEpoch;
        nowEpoch = DateTime.now().millisecondsSinceEpoch;
        final elapsedMs = nowEpoch - prevEpoch;
        if (rightBoundEpoch > prevEpoch) {
          rightBoundEpoch += elapsedMs; // autopanning
        }
        recalculateQuoteBoundTargets();
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

    _topBoundQuoteAnimationController = AnimationController.unbounded(
      value: topBoundQuoteTarget,
      vsync: this,
      duration: quoteBoundsAnimationDuration,
    );
    _bottomBoundQuoteAnimationController = AnimationController.unbounded(
      value: bottomBoundQuoteTarget,
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

  void recalculateQuoteBoundTargets() {
    if (canvasWidth == null) return;
    final leftBoundEpoch = rightBoundEpoch - pxToMs(canvasWidth);
    final visibleTickQuotes = ticks
        .where((tick) =>
            tick.epoch <= rightBoundEpoch && tick.epoch >= leftBoundEpoch)
        .map((tick) => tick.quote);

    final minQuote = visibleTickQuotes.reduce(min);
    final maxQuote = visibleTickQuotes.reduce(max);

    if (minQuote - quotePadding != bottomBoundQuoteTarget) {
      bottomBoundQuoteTarget = minQuote - quotePadding;
      _bottomBoundQuoteAnimationController.animateTo(
        bottomBoundQuoteTarget,
        curve: Curves.easeOut,
      );
    }
    if (maxQuote + quotePadding != topBoundQuoteTarget) {
      topBoundQuoteTarget = maxQuote + quotePadding;
      _topBoundQuoteAnimationController.animateTo(
        topBoundQuoteTarget,
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
    return ScaleAndPanGestureDetector(
      onScaleOrPanStart: (details) {
        _prevIntervalWidth = intervalWidth;
      },
      onPanUpdate: (details) {
        setState(() {
          rightBoundEpoch -= pxToMs(details.delta.dx);
          final upperLimit = nowEpoch + pxToMs(maxCurrentTickOffset);
          rightBoundEpoch = rightBoundEpoch.clamp(0, upperLimit);

          if (rightBoundEpoch > nowEpoch) {
            currentTickOffset = msToPx(rightBoundEpoch - nowEpoch);
          }
        });
      },
      onScaleUpdate: (details) {
        setState(() {
          intervalWidth = (_prevIntervalWidth * details.scale).clamp(3.0, 50.0);

          if (rightBoundEpoch > nowEpoch) {
            rightBoundEpoch = nowEpoch + pxToMs(currentTickOffset);
          }
        });
      },
      child: LayoutBuilder(builder: (context, constraints) {
        canvasWidth = constraints.maxWidth;

        return CustomPaint(
          size: Size.infinite,
          painter: ChartPainter(
            data: ticks,
            intervalWidth: intervalWidth,
            intervalDuration: intervalDuration,
            rightBoundEpoch: rightBoundEpoch,
            topBoundQuote: _topBoundQuoteAnimationController.value,
            bottomBoundQuote: _bottomBoundQuoteAnimationController.value,
            lastTickAnimationProgress: _lastTickAnimation.value,
          ),
        );
      }),
    );
  }
}

class ChartPainter extends CustomPainter {
  ChartPainter({
    this.data,
    this.intervalWidth,
    this.intervalDuration,
    this.rightBoundEpoch,
    this.bottomBoundQuote,
    this.topBoundQuote,
    this.lastTickAnimationProgress,
  });

  static final lineColor = Paint()
    ..color = Colors.white.withOpacity(0.9)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1;

  final List<Tick> data;
  final double intervalWidth;
  final int intervalDuration;
  final int rightBoundEpoch;
  final double bottomBoundQuote;
  final double topBoundQuote;
  final double lastTickAnimationProgress;

  Canvas canvas;
  Size size;

  Offset _toCanvasOffset(Tick tick) {
    return Offset(
      _epochToX(tick.epoch),
      _quoteToY(tick.quote),
    );
  }

  double _epochToX(int epoch) {
    return size.width -
        (rightBoundEpoch - epoch) / intervalDuration * intervalWidth;
  }

  double _quoteToY(double quote) {
    return size.height -
        (quote - bottomBoundQuote) /
            (topBoundQuote - bottomBoundQuote) *
            size.height;
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas = canvas;
    size = size;

    Path path = Path();

    final firstPoint = _toCanvasOffset(data.first);
    path.moveTo(firstPoint.dx, firstPoint.dy);

    for (var i = 1; i < data.length - 1; i++) {
      final point = _toCanvasOffset(data[i]);
      path.lineTo(point.dx, point.dy);
    }

    final lastPoint = _toCanvasOffset(data.last);
    final secondLastPoint = _toCanvasOffset(data[data.length - 2]);
    final lastPointAnimated = secondLastPoint +
        (lastPoint - secondLastPoint) * lastTickAnimationProgress;
    path.lineTo(lastPointAnimated.dx, lastPointAnimated.dy);
    canvas.drawPath(path, lineColor);

    path.lineTo(lastPointAnimated.dx, size.height);
    path.lineTo(0, size.height);
    _paintLineArea(path);

    _paintArrow(lastPointAnimated);
  }

  void _paintLineArea(Path areaPath) {
    canvas.drawPath(
      areaPath,
      Paint()
        ..style = PaintingStyle.fill
        ..shader = ui.Gradient.linear(
          Offset(0, 0),
          Offset(0, size.height),
          [
            Colors.white.withOpacity(0.2),
            Colors.white.withOpacity(0.01),
          ],
        ),
    );
  }

  void _paintArrow(Offset lastPoint) {
    canvas.drawCircle(lastPoint, 3, Paint()..color = Colors.pink);
    canvas.drawLine(
      lastPoint,
      Offset(size.width, lastPoint.dy),
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
