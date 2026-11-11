/// Built-in Senter barcode and EPC Gen2 UHF reader integration for Android.
library;

import 'package:flutter/services.dart';

/// A barcode captured by the installed Senter service (not a camera scanner).
class BarcodeScan {
  BarcodeScan.fromMap(Map<Object?, Object?> value)
      : text = value['text'] as String,
        bytes = value['bytes'] as Uint8List,
        source = value['source'] as String,
        timestamp =
            DateTime.fromMillisecondsSinceEpoch(value['timestamp'] as int);
  final String text;
  final Uint8List bytes;

  /// `service` for a requested scan, `broadcast` for a configured physical key.
  final String source;
  final DateTime timestamp;
}

/// One observation. Repeated EPCs are deliberately delivered to the consumer.
class UhfTag {
  UhfTag.fromMap(Map<Object?, Object?> value)
      : epc = value['epc'] as String,
        rssiDbm = value['rssiDbm'] as int?,
        frequencyKhz = value['frequencyKhz'] as int?,
        antenna = value['antenna'] as int?,
        timestamp =
            DateTime.fromMillisecondsSinceEpoch(value['timestamp'] as int);
  final String epc;
  final int? rssiDbm;
  final int? frequencyKhz;
  final int? antenna;
  final DateTime timestamp;
}

/// Firmware and reader capability information. Unsupported fields can be null.
class ReaderInfo {
  ReaderInfo.fromMap(Map<Object?, Object?> map)
      : values = Map<String, Object?>.unmodifiable(map.cast<String, Object?>());
  final Map<String, Object?> values;
  String get model => values['model'] as String? ?? 'Unknown';
  bool get uhfReady => values['uhfReady'] == true;
  bool get barcodeConnected => values['barcodeConnected'] == true;
  bool get barcodeEnabled => values['barcodeEnabled'] == true;
  int? get powerDbm => values['powerDbm'] as int?;
  String? get firmware => values['firmware'] as String?;
}

/// Status, completed inventory rounds, and recoverable reader errors.
class ReaderEvent {
  ReaderEvent.fromMap(Map<Object?, Object?> value)
      : type = value['type'] as String,
        state = value['state'] as String?,
        message = value['message'] as String?,
        values =
            Map<String, Object?>.unmodifiable(value.cast<String, Object?>());
  final String type;
  final String? state;
  final String? message;
  final Map<String, Object?> values;
}

/// One process-wide hardware controller. Subscribe before starting an operation.
///
/// Call [initialize], then [scanBarcode] or [startInventory]. Stop inventory
/// before querying/changing power. Call [close] when finished; initialize can
/// reopen it. The native implementation stops UHF when its Activity stops.
class Qruhf {
  Qruhf._();
  static final Qruhf instance = Qruhf._();
  static const _methods = MethodChannel('qruhf/methods');
  static const _channel = EventChannel('qruhf/events');
  late final Stream<Map<Object?, Object?>> _events = _channel
      .receiveBroadcastStream()
      .map((value) => (value as Map).cast<Object?, Object?>());

  late final Stream<BarcodeScan> barcodes = _events
      .where((value) => value['type'] == 'barcode')
      .map(BarcodeScan.fromMap);
  late final Stream<UhfTag> tags =
      _events.where((value) => value['type'] == 'tag').map(UhfTag.fromMap);
  late final Stream<ReaderEvent> events = _events
      .where((value) => value['type'] != 'tag' && value['type'] != 'barcode')
      .map(ReaderEvent.fromMap);

  /// Opens both readers independently; inspect the returned capabilities/errors.
  Future<ReaderInfo> initialize() async => ReaderInfo.fromMap(
        (await _methods.invokeMapMethod<Object?, Object?>('initialize'))!,
      );
  Future<ReaderInfo> getInfo() async => ReaderInfo.fromMap(
        (await _methods.invokeMapMethod<Object?, Object?>('getInfo'))!,
      );

  /// Triggers the built-in scanner. Null means its scan window expired.
  /// The same successful result is also emitted on [barcodes].
  Future<BarcodeScan?> scanBarcode() async {
    final result =
        await _methods.invokeMapMethod<Object?, Object?>('scanBarcode');
    return result == null ? null : BarcodeScan.fromMap(result);
  }

  Future<void> startInventory() =>
      _methods.invokeMethod<void>('startInventory');

  /// Completes after the current short inventory round has ended.
  Future<void> stopInventory() => _methods.invokeMethod<void>('stopInventory');

  /// Sets temporary output power; does not write the reader's flash settings.
  Future<void> setPower(int dbm) {
    if (dbm < 0 || dbm > 30) {
      throw RangeError.range(dbm, 0, 30, 'dbm');
    }
    return _methods.invokeMethod<void>('setPower', {'dbm': dbm});
  }

  /// Opens the vendor's settings, for optional physical-key broadcast mode.
  Future<void> openBarcodeSettings() =>
      _methods.invokeMethod<void>('openBarcodeSettings');
  Future<void> close() => _methods.invokeMethod<void>('close');
}
