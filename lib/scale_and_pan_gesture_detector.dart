import 'package:flutter/material.dart';

/// Widget to track pan and scale gestures on one area.
///
/// GestureDetector doesn't allow to use both Pan and Scale gesture.
/// Scale is treated as a super set of Pan. Scale is called even when only 1 finger is touching.
/// Therefore it is possible to keep track of both Pan and Scale, by treating Scale events with 1 finger as Pan.
class ScaleAndPanGestureDetector extends StatefulWidget {
  const ScaleAndPanGestureDetector({
    Key key,
    this.child,
    this.onScaleAndPanStart,
    this.onScaleUpdate,
    this.onPanUpdate,
    this.onScaleAndPanEnd,
  }) : super(key: key);

  final Widget child;

  final GestureScaleStartCallback onScaleAndPanStart;

  final GestureScaleUpdateCallback onScaleUpdate;

  final GestureDragUpdateCallback onPanUpdate;

  final GestureScaleEndCallback onScaleAndPanEnd;

  @override
  _ScaleAndPanGestureDetectorState createState() =>
      _ScaleAndPanGestureDetectorState();
}

class _ScaleAndPanGestureDetectorState
    extends State<ScaleAndPanGestureDetector> {
  int _fingersOnScreen = 0;
  Offset _lastContactPoint;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (event) {
        _fingersOnScreen += 1;
      },
      onPointerCancel: (event) {
        _fingersOnScreen -= 1;
      },
      onPointerUp: (event) {
        _fingersOnScreen -= 1;
      },
      child: GestureDetector(
        onScaleStart: _handleScaleStart,
        onScaleUpdate: _handleScaleUpdate,
        onScaleEnd: _handleScaleEnd,
        child: widget.child,
      ),
    );
  }

  void _handleScaleStart(ScaleStartDetails details) {
    _lastContactPoint = details.focalPoint;

    widget.onScaleAndPanStart?.call(details);
  }

  void _handleScaleUpdate(ScaleUpdateDetails details) {
    if (_fingersOnScreen == 1) {
      _handlePanUpdate(details);
    } else {
      widget.onScaleUpdate?.call(details);
    }
  }

  void _handlePanUpdate(ScaleUpdateDetails details) {
    final currentContactPoint = details.focalPoint;
    final dragUpdateDetails = DragUpdateDetails(
      delta: currentContactPoint - _lastContactPoint,
      globalPosition: currentContactPoint,
      localPosition: details.localFocalPoint,
    );
    _lastContactPoint = details.focalPoint;

    widget.onPanUpdate?.call(dragUpdateDetails);
  }

  void _handleScaleEnd(ScaleEndDetails details) {
    widget.onScaleAndPanEnd?.call(details);
  }
}
