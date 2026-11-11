# QR + UHF Reader example

A complete tablet UI using the local `qruhf` plugin. Opens both readers automatically and displays real barcode captures, EPC tag counts, RSSI, power and diagnostics.

From the project root:

```sh
tool/run_tablet.sh <tablet-adb-serial>
```

This builds the app, installs with the Android 9 compatible non-streaming transfer, and opens **QR + UHF Reader**. Standard `cd example && flutter run -d <serial>` is also available on devices where streamed installation works.

Tap **Scan barcode** while aiming the built-in reader at a code. Scroll to **UHF RFID**, tap **Start inventory**, and present an EPC Gen2 tag. Tap **Stop inventory** before changing temporary output power. Use **Reconnect readers** if a module is unavailable. Close other UHF apps first.

The example stops inventory when it enters the background. Barcode scan duration is controlled by the vendor helper. The settings shortcut opens the installed scanner app if physical-key broadcast configuration is needed.

Tests:

```sh
flutter test
flutter test integration_test/plugin_integration_test.dart -d <serial>
```

For devices that need non-streaming installation, follow the attached-driver test instructions in `../docs/DEVICE_REPORT.md`. Hardware integration asserts command communication, not physical scan success; physical results are documented separately.

The release variant uses a development signing key for local testing. Configure your own application ID and signing key for distribution.
