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
  double intervalWidth = 25;
  double prevIntervalWidth = 25;
  double nowOffset = 100;
  List<ChartTick> ticks = [
    ChartTick(DateTime.now().millisecondsSinceEpoch - 2000, 50),
    ChartTick(DateTime.now().millisecondsSinceEpoch - 1000, 50),
  ];
  Ticker ticker;
  int lastTickArrivedTimestamp;

  int fingers = 0;
  Offset lastFocalPoint;

  @override
  void initState() {
    super.initState();
    lastTickArrivedTimestamp = ticks.last.time;
    ticker = this.createTicker((elapsed) {
      setState(() {
        now = DateTime.now().millisecondsSinceEpoch;
      });
    });
    ticker.start();

    Timer.periodic(Duration(seconds: 1), (timer) {
      setState(() {
        lastTickArrivedTimestamp = DateTime.now().millisecondsSinceEpoch;
        ticks.add(ChartTick(
          lastTickArrivedTimestamp,
          rng.nextDouble() * 100,
        ));
      });
    });
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
          print(details);
          lastFocalPoint = details.focalPoint;
        },
        onScaleUpdate: (ScaleUpdateDetails details) {
          if (fingers == 1) {
            final delta = details.focalPoint - lastFocalPoint;
            lastFocalPoint = details.focalPoint;
            setState(() {
              nowOffset -= delta.dx;
            });
          } else {
            intervalWidth =
                (prevIntervalWidth * details.horizontalScale).clamp(5.0, 100.0);
          }
        },
        onScaleEnd: (ScaleEndDetails details) {
          print(details);
          print(fingers);
          prevIntervalWidth = intervalWidth;
        },
        child: LayoutBuilder(
          builder: (context, constraints) {
            return CustomPaint(
              size: Size.infinite,
              painter: ChartPainter(
                nowOffset: nowOffset,
                intervalWidth: intervalWidth,
                data: ticks,
                // TODO: pass right edge timestamp instead, so you can look at old section of the chart without it scrolling past you
                now: now,
                lastTick: lastTickArrivedTimestamp,
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
    this.intervalWidth,
    this.data,
    this.now,
    this.nowOffset,
    this.lastTick,
  });

  static final lineColor = Paint()
    ..color = Colors.white
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1;

  final List<ChartTick> data;
  final double intervalWidth;
  final double nowOffset;
  final int now;
  final int lastTick;

  final int intervalDuration = 1000;
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
    final nowX = canvasSize.width - nowOffset;
    return nowX - (now - time) / intervalDuration * intervalWidth;
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

    final lastTickProgress = ((now - lastTick) / 200).clamp(0, 1);
    final last = _toCanvasOffset(data.last);
    final prev = _toCanvasOffset(data[data.length - 2]);
    final progressOffset = prev + (last - prev) * lastTickProgress.toDouble();
    path.lineTo(progressOffset.dx, progressOffset.dy);

    canvas.drawLine(
      Offset(_timeToX(now), 0),
      Offset(_timeToX(now), size.height),
      Paint()..color = Colors.yellow,
    );

    canvas.drawPath(path, lineColor);
    canvas.drawCircle(progressOffset, 3, Paint()..color = Colors.pink);
    canvas.drawLine(
      progressOffset,
      Offset(size.width, progressOffset.dy),
      Paint()
        ..color = Colors.pink
        ..strokeWidth = 1,
    );
    canvas.drawRect(
      Rect.fromLTRB(size.width - 60, progressOffset.dy - 10, size.width,
          progressOffset.dy + 10),
      Paint()..color = Colors.pink,
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
