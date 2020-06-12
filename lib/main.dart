import 'dart:convert' show json;
import 'dart:io' show WebSocket;
import 'dart:math';
import 'dart:ui' as ui;

import 'package:intl/intl.dart' show DateFormat;
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
      debugShowCheckedModeBanner: false,
      home: Material(
        color: Color(0xFF0E0E0E),
        child: SizedBox.expand(
          child: Chart(),
        ),
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
  Ticker ticker;

  final int intervalDuration = 1000;
  final double maxCurrentTickOffset = 150;
  final double quoteBarWidth = 60;
  final double timeBarHeight = 20;

  List<Tick> ticks = [];
  List<Tick> visibleTicks = [];

  int nowEpoch;
  int rightBoundEpoch; // for panning
  double intervalWidth = 25; // for scaling
  double _prevIntervalWidth;
  double currentTickOffset = 100;
  int panToCurrentAnimationStartEpoch;
  double verticalPaddingHeightPercentage = 0.1;
  double quoteGridInterval = 1;

  AnimationController _currentTickAnimationController;
  Animation _currentTickAnimation;

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
    _initTickStream();

    nowEpoch = DateTime.now().millisecondsSinceEpoch;
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
          (response) {
            final data = Map<String, dynamic>.from(json.decode(response));
            final epoch = data['tick']['epoch'] * 1000;
            final quote = data['tick']['quote'];
            _onNewTick(epoch, quote.toDouble());
          },
          onDone: () => print('Done!'),
          onError: (e) => throw new Exception(e),
        );
        ws.add(json.encode({'ticks': 'OTC_AS51'}));
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

    _currentTickAnimationController.reset();
    _currentTickAnimationController.forward();
  }

  void _onNewFrame(_) {
    setState(() {
      final prevEpoch = nowEpoch;
      nowEpoch = DateTime.now().millisecondsSinceEpoch;
      final elapsedMs = nowEpoch - prevEpoch;
      if (rightBoundEpoch > prevEpoch) {
        rightBoundEpoch += elapsedMs; // autopanning
      }
      if (canvasSize != null) {
        _updateVisibleTicks();
        _recalculateQuoteBoundTargets();
        _recalculateQuoteGridInterval();
      }
    });
  }

  void _setupAnimations() {
    _currentTickAnimationController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 300),
    );
    _currentTickAnimation = CurvedAnimation(
      parent: _currentTickAnimationController,
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
    _currentTickAnimationController.dispose();
    super.dispose();
  }

  void _updateVisibleTicks() {
    final leftBoundEpoch = rightBoundEpoch - pxToMs(canvasSize.width);

    var start = ticks.indexWhere((tick) => leftBoundEpoch < tick.epoch);
    var end = ticks.lastIndexWhere((tick) => tick.epoch < rightBoundEpoch);

    if (start == -1 || end == -1) return;

    if (start > 0) start -= 1;
    if (end < ticks.length - 1) end += 1;

    visibleTicks = ticks.sublist(start, end + 1);
  }

  void _recalculateQuoteBoundTargets() {
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

  void _recalculateQuoteGridInterval() {
    final chartAreaHeight = canvasSize.height - _topPadding - _bottomPadding;
    final quoteRange = topBoundQuoteTarget - bottomBoundQuoteTarget;
    if (quoteRange <= 0) return;

    final k = chartAreaHeight / quoteRange;

    double _distanceBetweenLines() => k * quoteGridInterval;

    if (_distanceBetweenLines() < 100) {
      quoteGridInterval *= 2;
    } else if (_distanceBetweenLines() / 2 >= 100) {
      quoteGridInterval /= 2;
    }
  }

  int pxToMs(double px) {
    return (px / intervalWidth * intervalDuration).toInt();
  }

  double msToPx(int ms) {
    return ms / intervalDuration * intervalWidth;
  }

  Tick _getAnimatedCurrentTick() {
    if (ticks.length < 2) return null;

    final lastTick = ticks[ticks.length - 1];
    final secondLastTick = ticks[ticks.length - 2];

    final epochDiff = lastTick.epoch - secondLastTick.epoch;
    final quoteDiff = lastTick.quote - secondLastTick.quote;

    final animatedEpochDiff = (epochDiff * _currentTickAnimation.value).toInt();
    final animatedQuoteDiff = quoteDiff * _currentTickAnimation.value;

    return Tick(
      secondLastTick.epoch + animatedEpochDiff,
      secondLastTick.quote + animatedQuoteDiff,
    );
  }

  double get _verticalPadding =>
      verticalPaddingHeightPercentage * (canvasSize.height - timeBarHeight);

  double get _topPadding => _verticalPadding;

  double get _bottomPadding => _verticalPadding + timeBarHeight;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        ScaleAndPanGestureDetector(
          onScaleAndPanStart: (details) {
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

              if (details.localPosition.dx > canvasSize.width - quoteBarWidth) {
                verticalPaddingHeightPercentage =
                    ((_verticalPadding + details.delta.dy) /
                            (canvasSize.height - timeBarHeight))
                        .clamp(0.05, 0.49);
              }
            });
          },
          onScaleUpdate: (details) {
            setState(() {
              intervalWidth =
                  (_prevIntervalWidth * details.scale).clamp(3.0, 30.0);

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
                ticks: visibleTicks,
                animatedCurrentTick: _getAnimatedCurrentTick(),
                endsWithCurrentTick:
                    visibleTicks.isNotEmpty && visibleTicks.last == ticks.last,
                intervalDuration: intervalDuration,
                intervalWidth: intervalWidth,
                rightBoundEpoch: rightBoundEpoch,
                topBoundQuote: _topBoundQuoteAnimationController.value,
                bottomBoundQuote: _bottomBoundQuoteAnimationController.value,
                quoteGridInterval: quoteGridInterval,
                timeGridInterval: intervalDuration * 30,
                topPadding: _topPadding,
                bottomPadding: _bottomPadding,
                quoteBarWidth: quoteBarWidth,
              ),
            );
          }),
        ),
        if (rightBoundEpoch < nowEpoch)
          Positioned(
            bottom: 30 + timeBarHeight,
            right: 30 + quoteBarWidth,
            child: _buildScrollToNowButton(),
          )
      ],
    );
  }

  IconButton _buildScrollToNowButton() {
    return IconButton(
      icon: Icon(Icons.arrow_forward, color: Colors.white),
      onPressed: _scrollToNow,
    );
  }

  void _scrollToNow() {
    rightBoundEpoch = nowEpoch + pxToMs(maxCurrentTickOffset);
    currentTickOffset = maxCurrentTickOffset;
  }
}

class ChartPainter extends CustomPainter {
  ChartPainter({
    this.ticks,
    this.animatedCurrentTick,
    this.endsWithCurrentTick,
    this.intervalDuration,
    this.intervalWidth,
    this.rightBoundEpoch,
    this.topBoundQuote,
    this.bottomBoundQuote,
    this.quoteGridInterval,
    this.timeGridInterval,
    this.quoteBarWidth,
    this.topPadding,
    this.bottomPadding,
  });

  final lineColor = Paint()
    ..color = Colors.white.withOpacity(0.8)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1;
  final coralColor = Color(0xFFFF444F);

  final List<Tick> ticks;
  final Tick animatedCurrentTick;
  final bool endsWithCurrentTick;

  final int intervalDuration;
  final double intervalWidth;

  final int rightBoundEpoch;

  final double topBoundQuote;
  final double bottomBoundQuote;

  final double quoteGridInterval;
  final int timeGridInterval;

  final double quoteBarWidth;

  final double topPadding;
  final double bottomPadding;

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
    if (ticks.length < 2) return;
    this.canvas = canvas;
    this.size = size;

    if (endsWithCurrentTick) {
      ticks.removeLast();
      ticks.add(animatedCurrentTick);
    }

    final gridLineQuotes = _calcGridLineQuotes();
    final gridLineEpochs = _calcGridLineEpochs();
    _paintTimeGridLines(gridLineEpochs);
    _paintQuoteGridLines(gridLineQuotes);

    _paintLine();

    _paintTimestamps(gridLineEpochs);
    _paintQuotes(gridLineQuotes);
    _paintArrow(currentTick: animatedCurrentTick);
  }

  void _paintLine() {
    Path path = Path();
    final firstPoint = _toCanvasOffset(ticks.first);
    path.moveTo(firstPoint.dx, firstPoint.dy);

    ticks.skip(1).forEach((tick) {
      final point = _toCanvasOffset(tick);
      path.lineTo(point.dx, point.dy);
    });

    canvas.drawPath(path, lineColor);

    _paintLineArea(linePath: path);
  }

  void _paintLineArea({Path linePath}) {
    linePath.lineTo(
      _epochToX(ticks.last.epoch),
      size.height,
    );
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

  List<double> _calcGridLineQuotes() {
    final pixelToQuote = (topBoundQuote - bottomBoundQuote) /
        (size.height - topPadding - bottomPadding);
    final topEdgeQuote = topBoundQuote + topPadding * pixelToQuote;
    final bottomEdgeQuote = bottomBoundQuote - bottomPadding * pixelToQuote;
    final gridLineQuotes = <double>[];
    for (var q = topEdgeQuote - topEdgeQuote % quoteGridInterval;
        q > bottomEdgeQuote;
        q -= quoteGridInterval) {
      if (q < topEdgeQuote) gridLineQuotes.add(q);
    }
    return gridLineQuotes;
  }

  List<int> _calcGridLineEpochs() {
    final pixelToEpoch = intervalDuration / intervalWidth;
    final firstRight =
        (rightBoundEpoch - rightBoundEpoch % timeGridInterval).toInt();
    final leftBoundEpoch = rightBoundEpoch - size.width * pixelToEpoch;
    final epochs = <int>[];
    for (int epoch = firstRight;
        epoch > leftBoundEpoch;
        epoch -= timeGridInterval) {
      epochs.add(epoch);
    }
    return epochs;
  }

  void _paintQuoteGridLines(List<double> gridLineQuotes) {
    gridLineQuotes.forEach((quote) {
      final y = _quoteToY(quote);
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        Paint()..color = Colors.white12,
      );
    });
  }

  void _paintTimeGridLines(List<int> gridLineEpochs) {
    gridLineEpochs.forEach((epoch) {
      final x = _epochToX(epoch);
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        Paint()..color = Colors.white12,
      );
    });
  }

  void _paintQuotes(List<double> gridLineQuotes) {
    gridLineQuotes.forEach((quote) {
      _paintQuote(quote);
    });
  }

  void _paintTimestamps(List<int> gridLineEpochs) {
    gridLineEpochs.forEach((epoch) {
      _paintTimestamp(epoch);
    });
  }

  void _paintTimestamp(int epoch) {
    final time = DateTime.fromMillisecondsSinceEpoch(epoch);
    final label = DateFormat('Hms').format(time);
    TextSpan span = TextSpan(
      style: TextStyle(
        color: Colors.white30,
        fontSize: 12,
      ),
      text: label,
    );
    TextPainter tp = TextPainter(
      text: span,
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    );
    tp.layout();
    tp.paint(
      canvas,
      Offset(_epochToX(epoch) - tp.width / 2, size.height - tp.height - 4),
    );
  }

  void _paintQuote(double quote) {
    TextSpan span = TextSpan(
      style: TextStyle(
        color: Colors.white30,
        fontSize: 12,
      ),
      text: '${quote.toStringAsFixed(2)}',
    );
    TextPainter tp = TextPainter(
      text: span,
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    );
    tp.layout(minWidth: quoteBarWidth, maxWidth: quoteBarWidth);
    final y = _quoteToY(quote);
    tp.paint(canvas, Offset(size.width - quoteBarWidth, y - 6));
  }

  void _paintArrow({Tick currentTick}) {
    final offset = _toCanvasOffset(currentTick);
    canvas.drawCircle(offset, 3, Paint()..color = coralColor);
    canvas.drawLine(
      Offset(0, offset.dy),
      Offset(size.width, offset.dy),
      Paint()
        ..color = Colors.white24
        ..strokeWidth = 1,
    );
    _paintArrowHead(y: offset.dy, quote: currentTick.quote);
  }

  void _paintArrowHead({double y, double quote}) {
    final triangleWidth = 8;
    final height = 24;

    final path = Path();
    path.moveTo(size.width - quoteBarWidth - triangleWidth, y);
    path.lineTo(size.width - quoteBarWidth, y - height / 2);
    path.lineTo(size.width, y - height / 2);
    path.lineTo(size.width, y + height / 2);
    path.lineTo(size.width - quoteBarWidth, y + height / 2);
    path.lineTo(size.width - quoteBarWidth - triangleWidth, y);
    canvas.drawPath(
      path,
      Paint()
        ..color = coralColor
        ..style = PaintingStyle.fill,
    );

    TextSpan span = TextSpan(
      style: TextStyle(
        color: Colors.white,
        fontSize: 12,
        fontWeight: FontWeight.bold,
      ),
      text: '${quote.toStringAsFixed(2)}',
    );
    TextPainter tp = TextPainter(
      text: span,
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    );
    tp.layout(minWidth: quoteBarWidth, maxWidth: quoteBarWidth);
    tp.paint(
      canvas,
      Offset(size.width - quoteBarWidth, y - 6),
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
