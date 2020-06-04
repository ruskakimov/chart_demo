import 'dart:async';
import 'dart:convert' show json;
import 'dart:io' show WebSocket;
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

  List<Tick> ticks = [];
  List<Tick> visibleTicks = [];

  int nowEpoch;
  int rightBoundEpoch; // for panning
  double intervalWidth = 25; // for scaling
  double _prevIntervalWidth;
  double currentTickOffset = 100;
  int panToCurrentAnimationStartEpoch;

  AnimationController _lastTickAnimationController;
  Animation _lastTickAnimation;

  /// Quote range animation.
  Size canvasSize; // to determine the range of visible ticks
  double topBoundQuoteTarget = 60;
  double bottomBoundQuoteTarget = 30;
  final quoteBoundsAnimationDuration = const Duration(milliseconds: 300);
  AnimationController _topBoundQuoteAnimationController;
  AnimationController _bottomBoundQuoteAnimationController;

  @override
  void initState() {
    super.initState();
    nowEpoch = DateTime.now().millisecondsSinceEpoch;

    _initTickStream();

    rightBoundEpoch = nowEpoch + pxToMs(currentTickOffset);

    ticker = this.createTicker(_onNewFrame);
    ticker.start();

    _setupAnimations();
  }

  void _initTickStream() async {
    WebSocket ws;
    try {
      ws = await WebSocket.connect(
          'wss://ws.binaryws.com/websockets/v3?app_id=1089');

      if (ws?.readyState == WebSocket.open) {
        ws.listen(
          (resposne) {
            final data = Map<String, dynamic>.from(json.decode(resposne));
            final epoch = data['tick']['epoch'] * 1000;
            final quote = data['tick']['quote'];
            print('$nowEpoch $epoch $quote');
            _onNewTick(epoch, quote.toDouble());
          },
          onDone: () => print('Done!'),
          onError: (e) => throw new Exception(e),
        );
        ws.add(json.encode({'ticks': 'R_100'}));
      }
    } catch (e) {
      ws?.close();
      print('Error: $e');
    }
  }

  void _onNewTick(int epoch, double quote) {
    setState(() {
      ticks.add(Tick(epoch, quote));
    });

    _lastTickAnimationController.reset();
    _lastTickAnimationController.forward();
  }

  void _onNewFrame(_) {
    setState(() {
      final prevEpoch = nowEpoch;
      nowEpoch = DateTime.now().millisecondsSinceEpoch;
      final elapsedMs = nowEpoch - prevEpoch;
      if (rightBoundEpoch > prevEpoch) {
        rightBoundEpoch += elapsedMs; // autopanning
      }
      recalculateQuoteBoundTargets();
    });
  }

  void _setupAnimations() {
    _lastTickAnimationController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 300),
    );
    _lastTickAnimationController.value =
        1; // prevent jump on pregenerated ticks
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
  }

  @override
  void dispose() {
    _lastTickAnimationController.dispose();
    super.dispose();
  }

  void recalculateQuoteBoundTargets() {
    if (canvasSize == null) return;

    final leftBoundEpoch = rightBoundEpoch - pxToMs(canvasSize.width);
    visibleTicks = ticks
        .where((tick) =>
            tick.epoch <= rightBoundEpoch + intervalDuration * 2 &&
            tick.epoch >= leftBoundEpoch - intervalDuration * 2)
        .toList();

    if (visibleTicks.isEmpty) return;

    final visibleTickQuotes = visibleTicks.map((tick) => tick.quote);

    final minQuote = visibleTickQuotes.reduce(min);
    final maxQuote = visibleTickQuotes.reduce(max);

    if (minQuote != bottomBoundQuoteTarget) {
      bottomBoundQuoteTarget = minQuote;
      _bottomBoundQuoteAnimationController.animateTo(
        bottomBoundQuoteTarget,
        curve: Curves.easeOut,
      );
    }
    if (maxQuote != topBoundQuoteTarget) {
      topBoundQuoteTarget = maxQuote;
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
    return Stack(
      children: <Widget>[
        ScaleAndPanGestureDetector(
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
              intervalWidth =
                  (_prevIntervalWidth * details.scale).clamp(3.0, 50.0);

              if (rightBoundEpoch > nowEpoch) {
                rightBoundEpoch = nowEpoch + pxToMs(currentTickOffset);
              }
            });
          },
          child: LayoutBuilder(builder: (context, constraints) {
            canvasSize = Size(constraints.maxWidth, constraints.maxHeight);

            return CustomPaint(
              size: Size.infinite,
              painter: ChartPainter(
                data: visibleTicks,
                intervalDuration: intervalDuration,
                intervalWidth: intervalWidth,
                rightBoundEpoch: rightBoundEpoch,
                topBoundQuote: _topBoundQuoteAnimationController.value,
                bottomBoundQuote: _bottomBoundQuoteAnimationController.value,
                topPadding: 30,
                bottomPadding: 30,
                lastTickAnimationProgress: _lastTickAnimation.value,
              ),
            );
          }),
        ),
        if (rightBoundEpoch < nowEpoch)
          Positioned(
            bottom: 30,
            right: 20,
            child: IconButton(
              icon: Icon(Icons.arrow_forward, color: Colors.white),
              onPressed: () {
                rightBoundEpoch = nowEpoch + pxToMs(maxCurrentTickOffset);
                currentTickOffset = maxCurrentTickOffset;
              },
            ),
          )
      ],
    );
  }
}

class ChartPainter extends CustomPainter {
  ChartPainter({
    this.data,
    this.intervalDuration,
    this.intervalWidth,
    this.rightBoundEpoch,
    this.topBoundQuote,
    this.bottomBoundQuote,
    this.topPadding,
    this.bottomPadding,
    this.lastTickAnimationProgress,
  });

  static final lineColor = Paint()
    ..color = Colors.white.withOpacity(0.9)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1;

  final List<Tick> data;

  final int intervalDuration;
  final double intervalWidth;

  final int rightBoundEpoch;

  final double topBoundQuote;
  final double bottomBoundQuote;

  final double topPadding;
  final double bottomPadding;

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
    final intervalsFromRightBound =
        (rightBoundEpoch - epoch) / intervalDuration;
    return size.width - intervalsFromRightBound * intervalWidth;
  }

  double _quoteToY(double quote) {
    final quoteBoundRange = topBoundQuote - bottomBoundQuote;
    if (quoteBoundRange == 0) return size.height / 2;
    final boundFraction = (quote - bottomBoundQuote) / quoteBoundRange;
    return topPadding +
        (size.height - topPadding - bottomPadding) * (1 - boundFraction);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (data.length < 2) return;
    this.canvas = canvas;
    this.size = size;

    final lastPointAnimated = _calcLastPointAnimated();
    final path = _paintLine(lineEnd: lastPointAnimated);

    _paintLineArea(linePath: path, lineEnd: lastPointAnimated);
    _paintArrow(lastPoint: lastPointAnimated);
  }

  void _paintNowX__forTesting() {
    final nowX = _epochToX(DateTime.now().millisecondsSinceEpoch);
    canvas.drawLine(Offset(nowX, 0), Offset(nowX, size.height),
        Paint()..color = Colors.yellow);
  }

  Offset _calcLastPointAnimated() {
    final lastPoint = _toCanvasOffset(data.last);
    final secondLastPoint = _toCanvasOffset(data[data.length - 2]);
    return secondLastPoint +
        (lastPoint - secondLastPoint) * lastTickAnimationProgress;
  }

  Path _paintLine({Offset lineEnd}) {
    Path path = Path();

    final firstPoint = _toCanvasOffset(data.first);
    path.moveTo(firstPoint.dx, firstPoint.dy);

    for (var i = 1; i < data.length - 1; i++) {
      final point = _toCanvasOffset(data[i]);
      path.lineTo(point.dx, point.dy);
    }

    path.lineTo(lineEnd.dx, lineEnd.dy);
    canvas.drawPath(path, lineColor);

    return path;
  }

  void _paintLineArea({Path linePath, Offset lineEnd}) {
    linePath.lineTo(lineEnd.dx, size.height);
    linePath.lineTo(0, size.height);
    canvas.drawPath(
      linePath,
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

  void _paintArrow({Offset lastPoint}) {
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
