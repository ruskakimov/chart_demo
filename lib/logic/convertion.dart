import 'package:meta/meta.dart';

double epochToCanvasX({
  @required int epoch,
  @required int canvasWidthEpoch,
  @required double canvasWidth,
  @required double msPerPx,
}) {
  return canvasWidth - (canvasWidthEpoch - epoch) / msPerPx;
}
