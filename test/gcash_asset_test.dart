// test/gcash_asset_test.dart
//
// Sinisiguro na ang brand asset ng GCash (`assets/images/gcash.png`) ay
// tunay na naka-bundle at kayang i-decode — kung hindi, tahimik na fallback
// icon ang lumalabas sa Payment Method / Transaction / Receipt.
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('assets/images/gcash.png: naka-bundle at valid na PNG', () async {
    final data = await rootBundle.load('assets/images/gcash.png');
    expect(data.lengthInBytes, greaterThan(1000));

    // PNG signature — hindi lang basta file na naka-.png ang extension.
    final bytes = data.buffer.asUint8List();
    expect(bytes.sublist(0, 8),
        [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);

    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    expect(frame.image.width, greaterThan(0));
    expect(frame.image.height, greaterThan(0));
    frame.image.dispose();
    codec.dispose();
  });
}
