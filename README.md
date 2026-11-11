# qruhf

Flutter plugin for the **built-in Senter barcode/QR scanner and D2 UHF RFID reader**. Includes a complete Android example. This is device hardware integration, not a camera barcode package.


## Requirements

- Senter-compatible Android tablet with a D2 UHF module and the installed `com.senter.barcode.helper` service. Developed on S917 V11 / ST-T010, Android 9 (API 28), ARM64.
- Flutter 3.22+ / Dart 3.4+, Android minSdk 24. The included example was built using Flutter 3.47.6 and Java 17.
- Barcode Scan Helper enabled. Its existing settings are preserved. Close other UHF apps before opening this example; the serial reader has one owner.

## Run the fully configured example

```sh
cd example
flutter pub get
flutter run -d <device-id>
```

On the inspected tablet, use `tool/run_tablet.sh <device-id>` from the package root if ordinary Flutter installation stalls. This script uses the verified non-streaming Android install method.

The example automatically connects, displays diagnostics and offers **Scan barcode**, **Start/Stop inventory**, and a temporary power slider. Present a QR code to the scanner or an EPC Gen2 UHF tag to the antenna. Results are real hardware observations; empty scans are reported as empty.

## Use in another app

```yaml
dependencies:
  qruhf:
    path: /path/to/qruhf
```

```dart
import 'package:qruhf/qruhf.dart';

final reader = Qruhf.instance;
final barcodeSubscription = reader.barcodes.listen((scan) {
  print(scan.text); // Raw bytes are also available.
});
final tagSubscription = reader.tags.listen((tag) {
  print('${tag.epc}: ${tag.rssiDbm} dBm');
});
final statusSubscription = reader.events.listen((event) {
  if (event.type == 'error') print(event.message);
});

final info = await reader.initialize();
if (info.barcodeEnabled) await reader.scanBarcode();
if (info.uhfReady) await reader.startInventory();
// Later:
await reader.stopInventory();
await reader.setPower(20); // Temporary; leaves the saved radio configuration alone.
await reader.close();
await barcodeSubscription.cancel();
await tagSubscription.cancel();
await statusSubscription.cancel();
```

Android registration, package visibility and shrinker rules are supplied by the plugin. Barcode calls bind to the existing service and need no camera permission. `initialize` opens the two readers independently: inspect `uhfReady`, `barcodeEnabled` and error fields rather than assuming both succeeded.

## API and behavior

| API | Behavior |
| --- | --- |
| `initialize()` | Connects barcode service, initializes UHF and returns device/reader info |
| `getInfo()` | Returns capabilities, UHF firmware, cached power, region and completed rounds |
| `scanBarcode()` | Triggers one built-in scan; returns a `BarcodeScan` or null at vendor timeout; also emits successful result |
| `barcodes` | Broadcast stream of text, raw bytes, source, capture timestamp |
| `startInventory()` | Repeated short EPC Gen2 / ISO 18000-6C inventory rounds |
| `stopInventory()` | Stops after the in-flight round; automatically stops when Activity leaves foreground |
| `tags` | Every tag observation: EPC hex, RSSI **in dBm**, frequency in kHz, antenna, timestamp |
| `setPower(0..30)` | Temporary power; reader validates supported values; stop inventory first |
| `events` | Status, round heartbeat, recoverable hardware errors |
| `openBarcodeSettings()` | Opens the installed vendor settings |
| `close()` | Stops inventory, releases UHF and unbinds barcode service; can initialize again |

The SDK converts RSSI using `getRssiByDbm()`, not its unsigned raw RSSI field. EPC bytes preserve leading zeros. Streams preserve repeated observations; the example aggregates them by EPC and bounds its visible history. The example stops inventory in the background.

Physical barcode keys can also be received when the helper is configured to broadcast `com.senter.barcode.scan.action` with `scanResult` / `scanResultBytes`. On-screen scans use the Binder service and do not require switching global keyboard output mode. This broadcast interface is supplied by the device and is not authenticated; do not use barcode broadcasts as proof of identity.

## Scope and portability

Android only. Tested device details are in the report. Other Senter variants require hardware validation; generic Android devices do not contain the required service, serial driver or power controls. The plugin reports unavailable readers rather than pretending it supports them. Tag memory writing, locking and killing are not exposed.

The vendor barcode service determines scan timeout and offers no cancellation method on the observed interface. A scan runs on a separate worker so Flutter stays responsive. A stuck firmware Binder call cannot be cancelled by Dart; close/reopen the app or vendor service if it never returns. UHF rounds have a callback timeout; a firmware call that blocks inside native code remains outside this callback timeout's control.

## Verification

```sh
flutter analyze
flutter test
cd example
flutter test
flutter test integration_test/plugin_integration_test.dart -d <device-id>
```

The hardware test checks real initialization, firmware response, temporary power readback/restoration, inventory round completion, stop, close and reopen. It does not require a tag and therefore does **not** by itself prove a physical tag or QR capture. Those checks are separately documented in the device report.
