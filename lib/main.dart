import 'dart:async';
import 'dart:math';

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

  @override
  void initState() {
    super.initState();
    nowEpoch = DateTime.now().millisecondsSinceEpoch;
    rightEdgeEpoch = nowEpoch + pxToMs(currentTickOffset);

    ticker = this.createTicker((elapsed) {
      setState(() {
        final prevNowEpoch = nowEpoch;
        nowEpoch = DateTime.now().millisecondsSinceEpoch;
        if (rightEdgeEpoch > prevNowEpoch) {
          rightEdgeEpoch += nowEpoch - prevNowEpoch;
        }
      });
    });
    ticker.start();

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
              intervalWidth = (_prevIntervalWidth * details.horizontalScale)
                  .clamp(5.0, 100.0);

              if (rightEdgeEpoch > nowEpoch) {
                rightEdgeEpoch = nowEpoch + pxToMs(currentTickOffset);
              }
            });
          },
          onScaleOrPanEnd: (details) {
            // TODO: use velocity for panning innertia
          },
          child: CustomPaint(
            size: Size.infinite,
            painter: ChartPainter(
              data: ticks,
              intervalWidth: intervalWidth,
              intervalDuration: intervalDuration,
              rightEdgeTime: rightEdgeEpoch,
            ),
          ),
        ),
        if (rightEdgeEpoch < nowEpoch)
          Positioned(
            bottom: 40,
            right: 20,
            child: IconButton(
              icon: Icon(
                Icons.arrow_forward,
                color: Colors.white,
              ),
              onPressed: () {
                rightEdgeEpoch = nowEpoch + pxToMs(maxCurrentTickOffset);
              },
            ),
          ),
      ],
    );
  }
}

class ChartPainter extends CustomPainter {
  ChartPainter({
    this.data,
    this.intervalWidth,
    this.intervalDuration,
    this.rightEdgeTime,
  });

  static final lineColor = Paint()
    ..color = Colors.white
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1;

  final List<Tick> data;
  final double intervalWidth;
  final int intervalDuration;
  final int rightEdgeTime;

  Size canvasSize;
  double quoteMin = 0;
  double quoteMax = 100;

  Offset _toCanvasOffset(Tick tick) {
    return Offset(
      _timeToX(tick.epoch),
      _priceToY(tick.quote),
    );
  }

  int calcLeftEdgeTime() {
    return rightEdgeTime -
        (canvasSize.width / intervalWidth * intervalDuration).toInt();
  }

  void updatePriceRange(int leftEdgeTime) {
    quoteMin = double.infinity;
    quoteMax = double.negativeInfinity;
    data.where((tick) {
      return tick.epoch <= rightEdgeTime && tick.epoch >= leftEdgeTime;
    }).forEach((tick) {
      quoteMin = min(quoteMin, tick.quote);
      quoteMax = max(quoteMax, tick.quote);
    });
    quoteMin -= 10;
    quoteMax += 10;
  }

  double _timeToX(int time) {
    return canvasSize.width -
        (rightEdgeTime - time) / intervalDuration * intervalWidth;
  }

  double _priceToY(double price) {
    return canvasSize.height -
        (price - quoteMin) / (quoteMax - quoteMin) * canvasSize.height;
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvasSize = size;

    final leftEdgeTime = calcLeftEdgeTime();
    updatePriceRange(leftEdgeTime);
    if (quoteMin == double.infinity) return;

    Path path = Path();
    final startIndex = max(
      0,
      data.indexWhere((tick) => tick.epoch >= leftEdgeTime) - 3,
    );

    final first = _toCanvasOffset(data.first);
    path.moveTo(first.dx, first.dy);
    for (var i = startIndex; i < data.length - 1; i++) {
      final offset = _toCanvasOffset(data[i]);
      path.lineTo(offset.dx, offset.dy);
    }

    final lastTickAnimationProgress =
        ((DateTime.now().millisecondsSinceEpoch - data.last.epoch) / 200)
            .clamp(0, 1);
    final last = _toCanvasOffset(data.last);
    final prev = _toCanvasOffset(data[data.length - 2]);
    final lineEndOffset =
        prev + (last - prev) * lastTickAnimationProgress.toDouble();
    path.lineTo(lineEndOffset.dx, lineEndOffset.dy);

    canvas.drawPath(path, lineColor);
    canvas.drawCircle(lineEndOffset, 3, Paint()..color = Colors.pink);
    canvas.drawLine(
      lineEndOffset,
      Offset(size.width, lineEndOffset.dy),
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
