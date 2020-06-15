import 'package:flutter_test/flutter_test.dart';

import 'package:chart_attempt/logic/convertion.dart';

void main() {
  group('epochToCanvasX should return', () {
    test('[canvasWidth] when [epoch == canvasWidthEpoch]', () {
      expect(
        epochToCanvasX(
          epoch: 123456789,
          canvasWidthEpoch: 123456789,
          canvasWidth: 1234,
          msPerPx: 0.12345,
        ),
        equals(1234),
      );
    });

    test('0 when [epoch == canvasWidthEpoch - canvasWidth * msPerPx]', () {
      expect(
        epochToCanvasX(
          epoch: 512,
          canvasWidthEpoch: 1024,
          canvasWidth: 1024,
          msPerPx: 0.5,
        ),
        equals(0),
      );
    });
  });
}
