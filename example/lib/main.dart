import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qruhf/qruhf.dart';

void main() => runApp(const ReaderApp());

class ReaderApp extends StatelessWidget {
  const ReaderApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'QR + UHF Reader',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff2563eb)),
      scaffoldBackgroundColor: const Color(0xfff3f5f8),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(minimumSize: const Size(48, 52)),
      ),
    ),
    home: const ReaderScreen(),
  );
}

class ReaderScreen extends StatefulWidget {
  const ReaderScreen({super.key});
  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen>
    with WidgetsBindingObserver {
  final reader = Qruhf.instance;
  final subscriptions = <StreamSubscription<dynamic>>[];
  final barcodes = <BarcodeScan>[];
  final tags = <String, ({UhfTag tag, int count})>{};
  ReaderInfo? info;
  bool connecting = false,
      scanning = false,
      barcodeBusy = false,
      changingPower = false;
  String? error;
  String barcodeStatus = 'Point the built-in reader at a code.';
  int rounds = 0, observations = 0;
  double power = 20;
  Timer? refresh;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    subscriptions.add(
      reader.barcodes.listen((scan) {
        if (!mounted) return;
        setState(() {
          barcodes.insert(0, scan);
          if (barcodes.length > 100) barcodes.removeLast();
          barcodeStatus = 'Read successfully • ${scan.source}';
        });
      }, onError: showError),
    );
    subscriptions.add(
      reader.tags.listen((tag) {
        final old = tags[tag.epc];
        if (old == null && tags.length >= 1000) tags.remove(tags.keys.first);
        tags[tag.epc] = (tag: tag, count: (old?.count ?? 0) + 1);
        observations++;
        // Limit redraws during dense inventory while preserving every observation.
        refresh ??= Timer(const Duration(milliseconds: 150), () {
          refresh = null;
          if (mounted) setState(() {});
        });
      }, onError: showError),
    );
    subscriptions.add(
      reader.events.listen((event) {
        if (!mounted) return;
        setState(() {
          if (event.state == 'scanning') scanning = true;
          if (['ready', 'closed', 'error'].contains(event.state)) {
            scanning = false;
          }
          if (event.type == 'error') error = event.message;
          if (event.type == 'inventory') rounds = event.values['rounds'] as int;
        });
      }, onError: showError),
    );
    connect();
  }

  void showError(Object e) {
    if (!mounted) return;
    setState(() => error = e is PlatformException ? e.message : e.toString());
  }

  Future<void> connect() async {
    setState(() {
      connecting = true;
      error = null;
    });
    try {
      final value = await reader.initialize();
      if (!mounted) return;
      setState(() {
        info = value;
        power = (value.powerDbm ?? 20).clamp(0, 30).toDouble();
        error =
            value.values['uhfError'] as String? ??
            value.values['barcodeError'] as String?;
      });
    } catch (e) {
      showError(e);
    } finally {
      if (mounted) setState(() => connecting = false);
    }
  }

  Future<void> scanBarcode() async {
    setState(() {
      barcodeBusy = true;
      error = null;
      barcodeStatus = 'Scanning… hold the code in front of the reader.';
    });
    try {
      final scan = await reader.scanBarcode();
      if (mounted && scan == null) {
        setState(
          () =>
              barcodeStatus = 'No code detected. Reposition it and try again.',
        );
      }
    } catch (e) {
      showError(e);
    } finally {
      if (mounted) setState(() => barcodeBusy = false);
    }
  }

  Future<void> toggleInventory() async {
    try {
      if (scanning) {
        await reader.stopInventory();
      } else {
        setState(() => error = null);
        await reader.startInventory();
      }
    } catch (e) {
      showError(e);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      unawaited(reader.stopInventory().catchError(showError));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final s in subscriptions) {
      unawaited(s.cancel());
    }
    refresh?.cancel();
    unawaited(reader.close());
    super.dispose();
  }

  Widget panel(String title, IconData icon, List<Widget> children) => Card(
    elevation: 0,
    color: Colors.white,
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    ),
  );

  Widget barcodePanel() => panel('QR & barcode', Icons.qr_code_scanner, [
    Text(barcodeStatus),
    const SizedBox(height: 16),
    FilledButton.icon(
      key: const Key('scanBarcode'),
      onPressed: info?.barcodeEnabled == true && !barcodeBusy
          ? scanBarcode
          : null,
      icon: Icon(barcodeBusy ? Icons.hourglass_top : Icons.qr_code),
      label: Text(barcodeBusy ? 'Scanning…' : 'Scan barcode'),
    ),
    const SizedBox(height: 12),
    if (barcodes.isEmpty)
      const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Text('Your scanned codes will appear here.'),
      ),
    for (final scan in barcodes.take(8))
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(
              scan.text,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            Text(
              '${scan.bytes.length} bytes • ${TimeOfDay.fromDateTime(scan.timestamp).format(context)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    TextButton(
      onPressed: () => reader.openBarcodeSettings().catchError(showError),
      child: const Text('Scanner settings'),
    ),
  ]);

  Widget uhfPanel() => panel('UHF RFID', Icons.sensors, [
    Text(
      scanning
          ? 'Reading nearby EPC Gen2 tags…'
          : 'Hold a UHF tag near the antenna.',
    ),
    const SizedBox(height: 14),
    Wrap(
      spacing: 18,
      runSpacing: 8,
      children: [
        Text(
          '${tags.length} unique tags',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        Text('$observations reads'),
        Text('$rounds rounds'),
      ],
    ),
    const SizedBox(height: 16),
    FilledButton.icon(
      key: const Key('toggleInventory'),
      onPressed: info?.uhfReady == true && !changingPower
          ? toggleInventory
          : null,
      icon: Icon(scanning ? Icons.stop : Icons.play_arrow),
      label: Text(scanning ? 'Stop inventory' : 'Start inventory'),
    ),
    const SizedBox(height: 12),
    Text('Output power: ${power.round()} dBm'),
    Slider(
      value: power,
      min: 0,
      max: 30,
      divisions: 30,
      label: '${power.round()} dBm',
      onChanged: info?.uhfReady == true && !scanning && !changingPower
          ? (v) => setState(() => power = v)
          : null,
      onChangeEnd: (v) async {
        setState(() => changingPower = true);
        try {
          await reader.setPower(v.round());
        } catch (e) {
          showError(e);
        } finally {
          if (mounted) setState(() => changingPower = false);
        }
      },
    ),
    for (final row in tags.values.take(12))
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(
              row.tag.epc,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              '${row.count} reads • ${row.tag.rssiDbm ?? "—"} dBm • ${row.tag.frequencyKhz == null ? "—" : row.tag.frequencyKhz! / 1000} MHz',
            ),
          ],
        ),
      ),
    if (tags.isEmpty)
      const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Text('No tags observed yet.'),
      ),
  ]);

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('QR + UHF Reader'),
      actions: [
        IconButton(
          tooltip: 'Clear results',
          icon: const Icon(Icons.clear_all),
          onPressed: () => setState(() {
            tags.clear();
            barcodes.clear();
            observations = 0;
          }),
        ),
        IconButton(
          tooltip: 'Reconnect readers',
          icon: const Icon(Icons.refresh),
          onPressed: connecting || scanning || barcodeBusy ? null : connect,
        ),
      ],
    ),
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'BUILT-IN READER WORKBENCH',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    info == null
                        ? 'Connecting to your tablet…'
                        : '${info!.model} • ${info!.values['device']} • Android ${info!.values['androidVersion']}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      Chip(
                        label: Text(
                          info?.barcodeEnabled == true
                              ? 'Barcode ready'
                              : 'Barcode unavailable',
                        ),
                      ),
                      Chip(
                        label: Text(
                          info?.uhfReady == true
                              ? 'UHF ${info?.firmware ?? "ready"}'
                              : 'UHF unavailable',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (connecting) const LinearProgressIndicator(),
            if (error != null)
              Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: SelectableText(error!),
                ),
              ),
            LayoutBuilder(
              builder: (context, size) => size.maxWidth >= 760
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: barcodePanel()),
                        Expanded(child: uhfPanel()),
                      ],
                    )
                  : Column(children: [barcodePanel(), uhfPanel()]),
            ),
            ExpansionTile(
              title: const Text('Device diagnostics'),
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: SelectableText(
                    info?.values.entries
                            .map((e) => '${e.key}: ${e.value}')
                            .join('\n') ??
                        'Waiting for device',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
