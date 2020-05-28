import 'dart:async';
import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

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
  int now = DateTime.now().millisecondsSinceEpoch;
  final double intervalDuration = 1000;

  List<ChartTick> ticks = [
    ChartTick(DateTime.now().millisecondsSinceEpoch - 2000, 50),
    ChartTick(DateTime.now().millisecondsSinceEpoch - 1000, 50),
  ];
  Ticker ticker;

  int rightEdgeTime; // horizontal panning
  Offset lastFocalPoint;

  double intervalWidth = 25; // scaling
  double prevIntervalWidth;
  double pxBetweenNowAndRightEdge = 100;
  double maxPxBetweenNowAndRightEdge = 150;
  int fingers = 0;

  @override
  void initState() {
    super.initState();
    rightEdgeTime = now + pxToMs(pxBetweenNowAndRightEdge);
    ticker = this.createTicker((elapsed) {
      setState(() {
        final prev = now;
        now = DateTime.now().millisecondsSinceEpoch;
        if (rightEdgeTime > prev) {
          rightEdgeTime += now - prev;
        }
      });
    });
    ticker.start();

    Timer.periodic(Duration(seconds: 1), (timer) {
      setState(() {
        ticks.add(ChartTick(
          DateTime.now().millisecondsSinceEpoch,
          rng.nextDouble() * 100,
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
    return Listener(
      onPointerDown: (event) {
        fingers += 1;
      },
      onPointerCancel: (event) {
        fingers -= 1;
      },
      onPointerUp: (event) {
        fingers -= 1;
      },
      child: GestureDetector(
        onScaleStart: (details) {
          lastFocalPoint = details.focalPoint;
          prevIntervalWidth = intervalWidth;
          if (rightEdgeTime > now) {
            pxBetweenNowAndRightEdge = msToPx(rightEdgeTime - now);
          }
        },
        onScaleUpdate: (ScaleUpdateDetails details) {
          if (fingers == 1) {
            final delta = details.focalPoint - lastFocalPoint;
            lastFocalPoint = details.focalPoint;
            setState(() {
              rightEdgeTime -= pxToMs(delta.dx);
              if (rightEdgeTime - now > pxToMs(maxPxBetweenNowAndRightEdge)) {
                rightEdgeTime = now + pxToMs(maxPxBetweenNowAndRightEdge);
              }
            });
          } else {
            intervalWidth =
                (prevIntervalWidth * details.horizontalScale).clamp(5.0, 100.0);
            if (rightEdgeTime > now) {
              rightEdgeTime = now + pxToMs(pxBetweenNowAndRightEdge);
            }
          }
        },
        onScaleEnd: (ScaleEndDetails details) {
          // TODO: use velocity for panning innertia
        },
        child: LayoutBuilder(
          builder: (context, constraints) {
            return CustomPaint(
              size: Size.infinite,
              painter: ChartPainter(
                data: ticks,
                intervalWidth: intervalWidth,
                intervalDuration: intervalDuration,
                rightEdgeTime: rightEdgeTime,
              ),
            );
          },
        ),
      ),
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

  final List<ChartTick> data;
  final double intervalWidth;
  final double intervalDuration;
  final int rightEdgeTime;

  Size canvasSize;
  double priceMin = 0;
  double priceMax = 100;

  Offset _toCanvasOffset(ChartTick tick) {
    return Offset(
      _timeToX(tick.time),
      _priceToY(tick.price),
    );
  }

  double _timeToX(int time) {
    return canvasSize.width -
        (rightEdgeTime - time) / intervalDuration * intervalWidth;
  }

  double _priceToY(double price) {
    return canvasSize.height -
        (price - priceMin) / (priceMax - priceMin) * canvasSize.height;
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvasSize = size;

    Path path = Path();

    final first = _toCanvasOffset(data.first);
    path.moveTo(first.dx, first.dy);
    data
        .skip(1)
        .take(data.length - 2)
        .map((tick) => _toCanvasOffset(tick))
        .forEach((offset) => path.lineTo(offset.dx, offset.dy));

    final lastTickAnimationProgress =
        ((DateTime.now().millisecondsSinceEpoch - data.last.time) / 200)
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

class ChartTick {
  final int time;
  final double price;

  ChartTick(this.time, this.price);
}
