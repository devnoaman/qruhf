import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qruhf_example/main.dart';

void main() {
  testWidgets(
    'reader controls and diagnostics render on tablet-sized narrow viewport',
    (tester) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('qruhf/events'),
            (_) async => null,
          );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('qruhf/methods'),
            (call) async => call.method == 'initialize'
                ? {
                    'model': 'PAD',
                    'device': 'S917',
                    'androidVersion': '9',
                    'uhfReady': true,
                    'barcodeEnabled': true,
                    'barcodeConnected': true,
                    'powerDbm': 20,
                  }
                : null,
          );
      tester.view.physicalSize = const Size(800, 1280);
      tester.view.devicePixelRatio = 2.1875;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const ReaderApp());
      await tester.pumpAndSettle();
      expect(find.text('Scan barcode'), findsOneWidget);
      expect(find.text('Start inventory'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
