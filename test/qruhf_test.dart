import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qruhf/qruhf.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('qruhf/methods');
  final calls = <MethodCall>[];
  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'initialize') {
        return {
          'model': 'PAD',
          'uhfReady': true,
          'barcodeConnected': true,
          'barcodeEnabled': true,
          'powerDbm': 20
        };
      }
      if (call.method == 'scanBarcode') {
        return {
          'text': 'QR-123',
          'bytes': Uint8List.fromList([81, 82]),
          'source': 'service',
          'timestamp': 1000
        };
      }
      return null;
    });
  });
  tearDown(() => TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, null));
  test('capabilities preserve independent reader availability', () async {
    final info = await Qruhf.instance.initialize();
    expect(info.uhfReady, isTrue);
    expect(info.barcodeEnabled, isTrue);
    expect(info.powerDbm, 20);
  });
  test('barcode preserves raw bytes and source', () async {
    final scan = await Qruhf.instance.scanBarcode();
    expect(scan!.text, 'QR-123');
    expect(scan.bytes, [81, 82]);
    expect(scan.source, 'service');
  });
  test('power rejects out-of-range values before calling hardware', () async {
    expect(() => Qruhf.instance.setPower(-1), throwsRangeError);
    expect(() => Qruhf.instance.setPower(31), throwsRangeError);
    expect(calls, isEmpty);
    await Qruhf.instance.setPower(20);
    expect(calls.single.arguments, {'dbm': 20});
  });
  test('tag keeps negative dBm and nullable metadata', () {
    final tag =
        UhfTag.fromMap({'epc': '0011AABB', 'rssiDbm': -54, 'timestamp': 1000});
    expect(tag.epc, '0011AABB');
    expect(tag.rssiDbm, -54);
    expect(tag.frequencyKhz, isNull);
  });
}
