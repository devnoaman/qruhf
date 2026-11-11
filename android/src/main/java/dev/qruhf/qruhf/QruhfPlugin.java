package dev.qruhf.qruhf;

import android.app.Activity;
import android.app.Application;
import android.content.*;
import android.os.*;
import android.util.Log;
import androidx.annotation.NonNull;
import com.senter.iot.support.openapi.uhf.UhfD2;
import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.embedding.engine.plugins.activity.ActivityAware;
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding;
import io.flutter.plugin.common.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicBoolean;

/** Senter D2 UHF SDK + installed BarcodeHelperService interoperability. */
public class QruhfPlugin implements FlutterPlugin, MethodChannel.MethodCallHandler,
        EventChannel.StreamHandler, ActivityAware, Application.ActivityLifecycleCallbacks {
    private static final String BARCODE_PACKAGE = "com.senter.barcode.helper";
    private static final String BARCODE_SERVICE = BARCODE_PACKAGE + ".service.BarcodeHelperService";
    private static final String BARCODE_TOKEN = "com.senter.iot.barcode.operate.service.IBarcodeOperateService";
    private final Handler main = new Handler(Looper.getMainLooper());
    private final ExecutorService worker = Executors.newSingleThreadExecutor();
    private final ExecutorService barcodeWorker = Executors.newSingleThreadExecutor();
    private final AtomicBoolean scanning = new AtomicBoolean();
    private final AtomicBoolean barcodeBusy = new AtomicBoolean();
    private Context context;
    private Activity activity;
    private MethodChannel methods;
    private EventChannel events;
    private EventChannel.EventSink sink;
    private volatile IBinder barcode;
    private volatile boolean bound;
    private volatile boolean attached;
    private volatile boolean receiverRegistered;
    private CountDownLatch connected = new CountDownLatch(1);
    private UhfD2 uhf;
    private String uhfError;
    private String barcodeError;
    private long rounds;
    private Integer power;
    private String firmware;
    private String region;

    private final ServiceConnection connection = new ServiceConnection() {
        @Override public void onServiceConnected(ComponentName name, IBinder service) {
            barcode = service;
            connected.countDown();
            emit(map("type", "status", "state", "barcodeConnected"));
        }
        @Override public void onServiceDisconnected(ComponentName name) {
            barcode = null;
            emit(map("type", "error", "message", "Barcode service disconnected"));
        }
        @Override public void onNullBinding(ComponentName name) { connected.countDown(); }
        @Override public void onBindingDied(ComponentName name) {
            barcode = null;
            connected.countDown();
        }
    };
    private final BroadcastReceiver receiver = new BroadcastReceiver() {
        @Override public void onReceive(Context c, Intent intent) {
            if (barcodeBusy.get()) return; // Direct requests have their own response.
            byte[] bytes = intent.getByteArrayExtra("scanResultBytes");
            String text = intent.getStringExtra("scanResult");
            if (bytes == null && text != null) bytes = text.getBytes(StandardCharsets.UTF_8);
            if (bytes != null && bytes.length > 0) emit(barcodeResult(bytes, text, "broadcast"));
        }
    };

    @Override public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
        context = binding.getApplicationContext();
        attached = true;
        methods = new MethodChannel(binding.getBinaryMessenger(), "qruhf/methods");
        methods.setMethodCallHandler(this);
        events = new EventChannel(binding.getBinaryMessenger(), "qruhf/events");
        events.setStreamHandler(this);
        ((Application) context).registerActivityLifecycleCallbacks(this);
    }
    @Override public void onListen(Object args, EventChannel.EventSink events) { sink = events; }
    @Override public void onCancel(Object args) { sink = null; scanning.set(false); }

    private void bindBarcode() {
        if (!receiverRegistered) {
            IntentFilter filter = new IntentFilter("com.senter.barcode.scan.action");
            if (Build.VERSION.SDK_INT >= 33) context.registerReceiver(receiver, filter, Context.RECEIVER_EXPORTED);
            else context.registerReceiver(receiver, filter);
            receiverRegistered = true;
        }
        if (bound) return;
        connected = new CountDownLatch(1);
        try {
            Intent intent = new Intent().setComponent(new ComponentName(BARCODE_PACKAGE, BARCODE_SERVICE));
            bound = context.bindService(intent, connection, Context.BIND_AUTO_CREATE);
            if (!bound) { barcodeError = "Senter Barcode Scan Helper service is unavailable"; connected.countDown(); }
        } catch (RuntimeException e) { barcodeError = e.toString(); connected.countDown(); }
    }

    @Override public void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
        switch (call.method) {
            case "initialize":
                bindBarcode();
                work(result, () -> {
                    uhfError = null;
                    try {
                        uhf = UhfD2.getInstance();
                        if (!uhf.isInited() && !uhf.init()) throw new IllegalStateException("UHF initialization failed; close other reader apps and reconnect");
                        refreshUhfInfo();
                    } catch (Exception | LinkageError e) { uhfError = e.toString(); }
                    connected.await(4, TimeUnit.SECONDS);
                    Map<String, Object> info = info();
                    emit(map("type", "status", "state", "initialized"));
                    Log.i("Qruhf", "initialize: " + info);
                    return info;
                });
                break;
            case "getInfo": work(result, this::info); break;
            case "startInventory":
                work(result, () -> {
                    requireUhf();
                    if (scanning.compareAndSet(false, true)) {
                        emit(map("type", "status", "state", "scanning"));
                        worker.execute(this::inventoryRound);
                    }
                    return null;
                });
                break;
            case "stopInventory":
                scanning.set(false);
                work(result, () -> { emit(map("type", "status", "state", "ready")); return null; });
                break;
            case "setPower":
                Number dbm = call.argument("dbm");
                if (dbm == null || dbm.intValue() < 0 || dbm.intValue() > 30) {
                    result.error("invalid_argument", "Power must be 0–30 dBm", null); return;
                }
                work(result, () -> {
                    requireUhf();
                    if (scanning.get()) throw new IllegalStateException("Stop inventory before changing power");
                    if (!Boolean.TRUE.equals(uhf.setOutputPowerTemporarily(dbm.intValue()))) throw new IllegalStateException("Reader rejected power setting");
                    power = uhf.getOutputPower();
                    if (!Objects.equals(power, dbm.intValue())) throw new IllegalStateException("Power readback did not match requested value");
                    return null;
                });
                break;
            case "scanBarcode":
                if (!barcodeBusy.compareAndSet(false, true)) {
                    result.error("busy", "A barcode scan is already running", null); return;
                }
                barcodeWorker.execute(() -> {
                    try {
                        if (!barcodeEnabled()) throw new IllegalStateException("Enable Barcode Scan Helper in its settings first");
                        Bundle bundle = barcodeTransaction();
                        byte[] bytes = bundle == null ? null : bundle.getByteArray("data");
                        Map<String, Object> scan = bytes == null || bytes.length == 0 ? null : barcodeResult(bytes, null, "service");
                        if (scan != null) emit(scan);
                        Log.i("Qruhf", "barcode scan: " + (scan == null ? "no result" : bytes.length + " bytes"));
                        success(result, scan);
                    } catch (Exception e) { failure(result, "barcode_error", e); }
                    finally { barcodeBusy.set(false); }
                });
                break;
            case "openBarcodeSettings":
                try {
                    context.startActivity(new Intent().setComponent(new ComponentName(BARCODE_PACKAGE, BARCODE_PACKAGE + ".SettingsActivity")).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
                    result.success(null);
                } catch (RuntimeException e) { failure(result, "unavailable", e); }
                break;
            case "close":
                scanning.set(false);
                unbindBarcode();
                work(result, () -> { releaseUhf(); emit(map("type", "status", "state", "closed")); return null; });
                break;
            default: result.notImplemented();
        }
    }

    private void inventoryRound() {
        if (!scanning.get()) return;
        final CountDownLatch finished = new CountDownLatch(1);
        final AtomicBoolean accepting = new AtomicBoolean(true);
        final String[] error = {null};
        try {
            // One short round: stop waits for this round, not a 255-round command.
            uhf.iso18k6cRealTimeInventory(1, new UhfD2.UmdOnIso18k6cRealTimeInventory() {
                @Override public void onTagInventory(UhfD2.UII uii, UhfD2.UmdFrequencyPoint frequency, Integer antenna, UhfD2.UmdRssi rssi) {
                    if (!accepting.get() || !scanning.get() || uii == null) return;
                    emit(map("type", "tag", "epc", hex(uii.getEpc().getBytes()),
                        "rssiDbm", rssi == null ? null : rssi.getRssiByDbm(),
                        "frequencyKhz", frequency == null ? null : frequency.getFrequencyByKHz(),
                        "antenna", antenna, "timestamp", System.currentTimeMillis()));
                }
                @Override public void onFinishedSuccessfully(Integer antenna, int count, int reads) { finished.countDown(); }
                @Override public void onFinishedWithError(UhfD2.UmdErrorCode code) {
                    if (code != UhfD2.UmdErrorCode.no_tag_error) error[0] = String.valueOf(code);
                    finished.countDown();
                }
            });
            if (!finished.await(7, TimeUnit.SECONDS)) throw new TimeoutException("UHF round timed out; reconnect the reader");
            if (error[0] != null) throw new IllegalStateException(error[0]);
            rounds++;
            if (rounds == 1 || rounds % 10 == 0) emit(map("type", "inventory", "rounds", rounds));
        } catch (Exception | LinkageError e) {
            scanning.set(false);
            uhfError = e.toString();
            emit(map("type", "error", "state", "error", "message", uhfError));
            Log.e("Qruhf", "inventory failed", e);
            releaseUhf();
        } finally { accepting.set(false); }
        if (scanning.get() && !worker.isShutdown()) worker.execute(this::inventoryRound);
        else emit(map("type", "status", "state", "ready"));
    }

    private void requireUhf() {
        if (uhf == null || !uhf.isInited()) throw new IllegalStateException("Initialize UHF first. " + (uhfError == null ? "" : uhfError));
    }
    private void refreshUhfInfo() {
        power = uhf.getOutputPower();
        UhfD2.UmdFirmwareVersion version = uhf.getFirmwareVersion();
        firmware = version == null ? null : (version.major() & 255) + "." + (version.minor() & 255);
        UhfD2.UmdFrequencyRegionInfo f = uhf.getFrequencyRegion();
        region = f == null ? null : String.valueOf(f.getRegion());
    }
    private Map<String, Object> info() {
        boolean enabled = false;
        try { if (barcode != null) enabled = barcodeEnabled(); }
        catch (Exception e) { barcodeError = e.toString(); }
        return map("manufacturer", Build.MANUFACTURER, "model", Build.MODEL,
            "device", Build.DEVICE, "androidVersion", Build.VERSION.RELEASE, "apiLevel", Build.VERSION.SDK_INT,
            "abis", Arrays.asList(Build.SUPPORTED_ABIS), "uhfReady", uhf != null && uhf.isInited(),
            "barcodeConnected", barcode != null, "barcodeEnabled", enabled,
            "firmware", firmware, "powerDbm", power, "region", region,
            "inventoryRunning", scanning.get(), "inventoryRounds", rounds,
            "uhfError", uhfError, "barcodeError", barcodeError);
    }
    private boolean barcodeEnabled() throws RemoteException {
        IBinder service = barcode;
        if (service == null) throw new IllegalStateException("Barcode service is not connected; call initialize");
        Parcel request = Parcel.obtain(), reply = Parcel.obtain();
        try {
            request.writeInterfaceToken(BARCODE_TOKEN);
            if (!service.transact(1, request, reply, 0)) throw new RemoteException("Unsupported barcode status transaction");
            reply.readException();
            return reply.readInt() != 0;
        } finally { request.recycle(); reply.recycle(); }
    }
    private Bundle barcodeTransaction() throws RemoteException {
        IBinder service = barcode;
        if (service == null) throw new IllegalStateException("Barcode service disconnected");
        Parcel request = Parcel.obtain(), reply = Parcel.obtain();
        try {
            request.writeInterfaceToken(BARCODE_TOKEN);
            if (!service.transact(2, request, reply, 0)) throw new RemoteException("Unsupported barcode scan transaction");
            reply.readException();
            return reply.readInt() != 0 ? Bundle.CREATOR.createFromParcel(reply) : null;
        } finally { request.recycle(); reply.recycle(); }
    }
    private Map<String, Object> barcodeResult(byte[] bytes, String text, String source) {
        return map("type", "barcode", "text", text == null ? new String(bytes, StandardCharsets.UTF_8) : text,
            "bytes", bytes, "source", source, "timestamp", System.currentTimeMillis());
    }
    private void unbindBarcode() {
        if (bound) { context.unbindService(connection); bound = false; }
        barcode = null;
        if (receiverRegistered) { context.unregisterReceiver(receiver); receiverRegistered = false; }
    }
    private void releaseUhf() {
        try { if (uhf != null && uhf.isInited()) uhf.uninit(); }
        catch (Exception | LinkageError e) { Log.w("Qruhf", "UHF release", e); }
    }
    private interface Operation { Object run() throws Exception; }
    private void work(MethodChannel.Result result, Operation operation) {
        worker.execute(() -> {
            try { success(result, operation.run()); }
            catch (Exception | LinkageError e) { failure(result, "reader_error", e); }
        });
    }
    private void success(MethodChannel.Result result, Object value) { main.post(() -> { if (attached) result.success(value); }); }
    private void failure(MethodChannel.Result result, String code, Throwable e) {
        Log.e("Qruhf", code, e);
        main.post(() -> { if (attached) result.error(code, e.getMessage(), e.getClass().getSimpleName()); });
    }
    private void emit(Map<String, Object> event) { main.post(() -> { if (attached && sink != null) sink.success(event); }); }
    private static Map<String, Object> map(Object... entries) {
        Map<String, Object> value = new HashMap<>();
        for (int i = 0; i < entries.length; i += 2) value.put((String) entries[i], entries[i + 1]);
        return value;
    }
    static String hex(byte[] bytes) {
        char[] digits = "0123456789ABCDEF".toCharArray(), out = new char[bytes.length * 2];
        for (int i = 0; i < bytes.length; i++) { out[i * 2] = digits[(bytes[i] & 255) >>> 4]; out[i * 2 + 1] = digits[bytes[i] & 15]; }
        return new String(out);
    }
    @Override public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
        scanning.set(false);
        attached = false;
        sink = null;
        methods.setMethodCallHandler(null);
        events.setStreamHandler(null);
        unbindBarcode();
        ((Application) context).unregisterActivityLifecycleCallbacks(this);
        worker.execute(this::releaseUhf);
        worker.shutdown();
        barcodeWorker.shutdown();
    }
    @Override public void onAttachedToActivity(@NonNull ActivityPluginBinding binding) { activity = binding.getActivity(); }
    @Override public void onReattachedToActivityForConfigChanges(@NonNull ActivityPluginBinding binding) { onAttachedToActivity(binding); }
    @Override public void onDetachedFromActivityForConfigChanges() { scanning.set(false); activity = null; }
    @Override public void onDetachedFromActivity() { scanning.set(false); activity = null; }
    @Override public void onActivityStopped(Activity a) { if (a == activity) scanning.set(false); }
    @Override public void onActivityCreated(Activity a, Bundle b) {}
    @Override public void onActivityStarted(Activity a) {}
    @Override public void onActivityResumed(Activity a) {}
    @Override public void onActivityPaused(Activity a) {}
    @Override public void onActivitySaveInstanceState(Activity a, Bundle b) {}
    @Override public void onActivityDestroyed(Activity a) {}
}
