import 'package:flutter/material.dart';

class ScaleAndPanGestureDetector extends StatefulWidget {
  const ScaleAndPanGestureDetector({
    Key key,
    this.child,
    this.onScaleOrPanStart,
    this.onScaleUpdate,
    this.onPanUpdate,
    this.onScaleOrPanEnd,
  }) : super(key: key);

  final Widget child;

  final GestureScaleStartCallback onScaleOrPanStart;

  final GestureScaleUpdateCallback onScaleUpdate;

  final GestureDragUpdateCallback onPanUpdate;

  final GestureScaleEndCallback onScaleOrPanEnd;

  @override
  _ScaleAndPanGestureDetectorState createState() =>
      _ScaleAndPanGestureDetectorState();
}

class _ScaleAndPanGestureDetectorState
    extends State<ScaleAndPanGestureDetector> {
  int _fingers = 0;
  Offset _lastFocalPoint;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (event) {
        _fingers += 1;
      },
      onPointerCancel: (event) {
        _fingers -= 1;
      },
      onPointerUp: (event) {
        _fingers -= 1;
      },
      child: GestureDetector(
        onScaleStart: (details) {
          _lastFocalPoint = details.focalPoint;

          if (widget.onScaleOrPanStart != null) {
            widget.onScaleOrPanStart(details);
          }
        },
        onScaleUpdate: (details) {
          if (_fingers == 1 && widget.onPanUpdate != null) {
            widget.onPanUpdate(DragUpdateDetails(
              delta: details.focalPoint - _lastFocalPoint,
              globalPosition: details.focalPoint,
              localPosition: details.localFocalPoint,
            ));

            _lastFocalPoint = details.focalPoint;
          } else if (widget.onScaleUpdate != null) {
            widget.onScaleUpdate(details);
          }
        },
        onScaleEnd: (details) {
          if (widget.onScaleOrPanEnd != null) {
            widget.onScaleOrPanEnd(details);
          }
        },
        child: widget.child,
      ),
    );
  }
}
