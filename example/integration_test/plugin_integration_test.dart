import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:qruhf/qruhf.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'physical Senter reader initialization, inventory, stop, power and reopen',
    (tester) async {
      final reader = Qruhf.instance;
      final events = <ReaderEvent>[];
      final tags = <UhfTag>[];
      final eventSub = reader.events.listen(events.add);
      final tagSub = reader.tags.listen(tags.add);
      try {
        final info = await reader.initialize();
        // ignore: avoid_print
        print('DEVICE_INFO ${info.values}');
        expect(info.uhfReady, isTrue, reason: info.values.toString());
        expect(info.barcodeConnected, isTrue);
        expect(info.barcodeEnabled, isTrue);
        expect(info.firmware, isNotNull);
        final original = info.powerDbm!;
        await reader.setPower(original == 20 ? 19 : 20);
        expect((await reader.getInfo()).powerDbm, original == 20 ? 19 : 20);
        await reader.setPower(original);
        await reader.startInventory();
        await Future<void>.delayed(const Duration(seconds: 5));
        await reader.stopInventory();
        final stopped = await reader.getInfo();
        expect(stopped.values['inventoryRunning'], isFalse);
        expect(stopped.values['inventoryRounds'] as int, greaterThan(0));
        expect(events.where((e) => e.type == 'error'), isEmpty);
        // ignore: avoid_print
        print(
          'HARDWARE_RESULT rounds=${stopped.values['inventoryRounds']} tags=${tags.length}',
        );
        await reader.close();
        expect((await reader.initialize()).uhfReady, isTrue);
      } finally {
        await reader.close();
        await eventSub.cancel();
        await tagSub.cancel();
      }
    },
  );
}
