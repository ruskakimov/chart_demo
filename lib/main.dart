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

  double quoteMin = 30;
  double quoteMax = 60;
  double quoteMinTarget = 30;
  double quoteMaxTarget = 60;
  int quoteAnimationStartEpoch;
  int panToCurrentAnimationStartEpoch;

  @override
  void initState() {
    super.initState();
    nowEpoch = DateTime.now().millisecondsSinceEpoch;
    rightEdgeEpoch = nowEpoch + pxToMs(currentTickOffset);

    ticker = this.createTicker((elapsed) {
      setState(() {
        final prevNowEpoch = nowEpoch;
        nowEpoch = DateTime.now().millisecondsSinceEpoch;
        final elapsedMs = nowEpoch - prevNowEpoch;
        if (rightEdgeEpoch > prevNowEpoch) {
          rightEdgeEpoch += elapsedMs; // autopanning
        }
        animateQuoteRange(elapsedMs);
        animatePanToCurrentTick(elapsedMs);
      });
    });
    ticker.start();

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
    });
  }

  void animateQuoteRange(int elapsedMs) {
    if (quoteAnimationStartEpoch == null) return;
    final remainingAnimationTime = 200 - (nowEpoch - quoteAnimationStartEpoch);
    if (remainingAnimationTime <= 0) return;

    final quoteMinSpeed = (quoteMinTarget - quoteMin) / remainingAnimationTime;
    final quoteMaxSpeed = (quoteMaxTarget - quoteMax) / remainingAnimationTime;

    quoteMin += quoteMinSpeed * elapsedMs;
    quoteMax += quoteMaxSpeed * elapsedMs;
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

  void recalculateTargetQuoteRange(double chartWidth) {
    final leftEdgeEpoch = rightEdgeEpoch - pxToMs(chartWidth);
    var newQuoteMin = double.infinity;
    var newQuoteMax = double.negativeInfinity;
    ticks.where((tick) {
      return tick.epoch <= rightEdgeEpoch && tick.epoch >= leftEdgeEpoch;
    }).forEach((tick) {
      newQuoteMin = min(newQuoteMin, tick.quote);
      newQuoteMax = max(newQuoteMax, tick.quote);
    });
    newQuoteMin -= 10;
    newQuoteMax += 10;
    if (newQuoteMin != quoteMinTarget) {
      quoteMinTarget = newQuoteMin;
      quoteAnimationStartEpoch = nowEpoch;
    }
    if (newQuoteMax != quoteMaxTarget) {
      quoteMaxTarget = newQuoteMax;
      quoteAnimationStartEpoch = nowEpoch;
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
            // TODO: Use velocity for panning innertia.
          },
          child: LayoutBuilder(builder: (context, constraints) {
            recalculateTargetQuoteRange(constraints.maxWidth);

            return CustomPaint(
              size: Size.infinite,
              painter: ChartPainter(
                data: ticks,
                intervalWidth: intervalWidth,
                intervalDuration: intervalDuration,
                rightEdgeEpoch: rightEdgeEpoch,
                quoteMin: quoteMin,
                quoteMax: quoteMax,
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
    this.quoteMin,
    this.quoteMax,
  });

  static final lineColor = Paint()
    ..color = Colors.white
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1;

  final List<Tick> data;
  final double intervalWidth;
  final int intervalDuration;
  final int rightEdgeEpoch;
  final double quoteMin;
  final double quoteMax;

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
        (quote - quoteMin) / (quoteMax - quoteMin) * canvasSize.height;
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

    final lastTickAnimationProgress =
        ((DateTime.now().millisecondsSinceEpoch - data.last.epoch) / 200)
            .clamp(0, 1);
    final last = _toCanvasOffset(data.last);
    final prev = _toCanvasOffset(data[data.length - 2]);
    final lastTickOffset =
        prev + (last - prev) * lastTickAnimationProgress.toDouble();
    path.lineTo(lastTickOffset.dx, lastTickOffset.dy);
    canvas.drawPath(path, lineColor);

    path.lineTo(lastTickOffset.dx, size.height);
    path.lineTo(0, size.height);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.fill
        ..shader = ui.Gradient.linear(
          Offset(0, (_quoteToY(quoteMax) + _quoteToY(quoteMin)) / 2),
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
