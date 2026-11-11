package tech.aura.aura_gym;

import android.app.Activity;
import android.app.Application;
import android.content.Intent;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;

import com.denovo.app.top.business.models.ManualEntryRequestModel;
import com.denovo.app.top.sdk.CardTopService;
import com.denovo.app.top.sdk.ToPService;
import com.denovo.app.top.sdk.models.SdkThemeConfig;
import com.denovo.app.top.sdk.types.PaymentMode;
import com.denovo.app.top.sdk.types.PaymentType;

import org.json.JSONObject;

import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;
import java.util.Collections;
import java.util.HashMap;
import java.util.IdentityHashMap;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.atomic.AtomicBoolean;

import io.flutter.plugin.common.MethodChannel;

/**
 * Dejavoo Tap to Pay (TOP SDK), following
 * https://docs.ipospays.com/tap-to-pay-on-android/in-app-sdk-israel
 * and Dejavoo's sample app (github.com/dejavoo-integration/Tap-to-Pay-on-Android-In-App-SDK).
 *
 * Only compiled when the Dejavoo Maven credentials are in local.properties (see app/build.gradle);
 * otherwise src/notop/java provides a stub with the same API.
 *
 * TOP SDK builds differ from each other and from the docs:
 *  - the sample's build has performTransaction(input, sessionKey, listener) with the custom object
 *    inside input as "CustomObject"; the Israel doc shows performTransaction(input, sessionKey,
 *    customObject, listener). It is called through reflection so either shape compiles and works.
 *  - the sample's listener has onTransactionSuccess, the Israel doc has onTransactionResponse.
 *    Both are implemented without @Override so either interface compiles.
 * Every outcome carries a "diagnostics" map (request, raw SDK JSON, exceptions) for the report.
 */
final class TopPaymentHandler {
    static final boolean AVAILABLE = true;
    private static final String SDK = BuildConfig.DEJAVOO_SDK + " [" + BuildConfig.DEJAVOO_ENV + "]";
    private static final String TOP_PARAMS = "com.denovo.app.top.sdk.utils.TOPParams";

    private final Activity activity;
    private final Handler mainHandler = new Handler(Looper.getMainLooper());
    private ToPService topService;
    private CardTopService cardTopService; // manual entry in progress

    // All of the SDK's own screens (card screen, result screens, ...) live in this package.
    private static final String SDK_SCREEN_PACKAGE = "com.denovo.app.top.";
    private Application.ActivityLifecycleCallbacks screenWatcher;
    private Object screenWatchOwner;
    private volatile boolean sdkScreenShown;
    // The current transaction's SDK screens not yet closed. Main thread only (lifecycle
    // callbacks and the method channel both run there).
    private final Set<Activity> openSdkScreens = Collections.newSetFromMap(new IdentityHashMap<>());

    TopPaymentHandler(Activity activity) {
        this.activity = activity;
    }

    private ToPService service() {
        if (topService == null) {
            // (activity, false) also saves IS_SKINLESS_SDK=false in the SDK's persistent
            // preferences. Manual entry's CardTopService creates ToPService(activity, true),
            // which saves true; the one-argument constructor never resets it, so after one
            // manual entry every tap sale opened no card screen and never answered, even
            // after a reboot, until the app's data was cleared.
            topService = new ToPService(activity, false);
        }
        return topService;
    }

    /**
     * Ends a manual entry: releases its SoftPOS engine and NFC dispatch (CardTopService.release
     * also clears the SDK's global engine) and drops the tap service, so the next tap sale starts
     * from a fresh ToPService in tap (non-skinless) mode.
     */
    private void releaseManualEntry() {
        CardTopService manual = cardTopService;
        cardTopService = null;
        topService = null;
        if (manual == null) return;
        mainHandler.post(() -> {
            try {
                manual.release();
            } catch (Throwable t) {
                Log.e("POS", " => TOP manual entry release threw", t);
            }
        });
    }

    /** True once the current transaction opened any SDK screen (e.g. the "tap your card" screen). */
    boolean sdkScreenShown() {
        return sdkScreenShown;
    }

    /**
     * True once the current transaction's SDK screens were all closed again. The system Back
     * button on the card screen just finishes it (UICardPresentScreen.onBackPressed, SDK 3.0.5.6)
     * without calling the listener, so the Dart side treats this, without an answer, as a cancel.
     */
    boolean sdkScreensClosed() {
        return sdkScreenShown && openSdkScreens.isEmpty();
    }

    /** Drops the SDK service object so the next call starts from a fresh one (used before a retry). */
    void resetService() {
        topService = null;
    }

    /**
     * Records which SDK screens the transaction of [owner] opens and when, in its diagnostics.
     * A transaction that opens none is stuck before reading a card (the Dart side then
     * re-registers and retries); no card can be charged without the SDK's card screen.
     */
    private void watchSdkScreens(Object owner, Map<String, Object> diagnostics) {
        stopWatchingSdkScreens(screenWatchOwner);
        sdkScreenShown = false;
        openSdkScreens.clear();
        final long startedAt = System.currentTimeMillis();
        final StringBuilder screens = new StringBuilder();
        screenWatcher = new Application.ActivityLifecycleCallbacks() {
            @Override
            public void onActivityCreated(Activity a, Bundle savedInstanceState) {
                String name = a.getClass().getName();
                if (!name.startsWith(SDK_SCREEN_PACKAGE)) return;
                long afterMs = System.currentTimeMillis() - startedAt;
                synchronized (diagnostics) {
                    if (!sdkScreenShown) diagnostics.put("sdkScreenAfterMs", afterMs);
                    screens.append(name.substring(SDK_SCREEN_PACKAGE.length()))
                            .append(" @").append(afterMs).append("ms | ");
                    diagnostics.put("sdkScreens", screens.toString());
                }
                openSdkScreens.add(a);
                sdkScreenShown = true;
            }

            // A screen counts as closed once it is finishing (paused for good), not only when
            // destroyed, which can come a few hundred ms later.
            @Override
            public void onActivityPaused(Activity a) {
                if (a.isFinishing()) closed(a);
            }

            @Override
            public void onActivityDestroyed(Activity a) {
                closed(a);
            }

            private void closed(Activity a) {
                if (!openSdkScreens.remove(a) || !openSdkScreens.isEmpty()) return;
                synchronized (diagnostics) {
                    diagnostics.put("sdkScreensClosedAfterMs", System.currentTimeMillis() - startedAt);
                }
            }

            @Override public void onActivityStarted(Activity a) {}
            @Override public void onActivityResumed(Activity a) {}
            @Override public void onActivityStopped(Activity a) {}
            @Override public void onActivitySaveInstanceState(Activity a, Bundle outState) {}
        };
        screenWatchOwner = owner;
        activity.getApplication().registerActivityLifecycleCallbacks(screenWatcher);
    }

    /** Stops watching, unless a newer transaction (another owner) took over the watch. */
    private void stopWatchingSdkScreens(Object owner) {
        if (screenWatcher == null || owner != screenWatchOwner) return;
        activity.getApplication().unregisterActivityLifecycleCallbacks(screenWatcher);
        screenWatcher = null;
        screenWatchOwner = null;
    }

    void registerDevice(String tpn, String merchantCode, MethodChannel.Result result) {
        Map<String, Object> diagnostics = newDiagnostics("registerDevice");
        if (cardTopService != null) {
            diagnostics.put("releasedPendingManualEntry", true);
            releaseManualEntry();
        }
        diagnostics.put("request", "tpn=" + tpn + ", merchantCode=" + mask(merchantCode));
        Reply reply = new Reply(result, diagnostics);
        try {
            service().registerDevice(tpn, merchantCode, new ToPService.OnRegisterListener() {
                @Override
                public void onRegisterSuccess(JSONObject successObject) {
                    reply.success("onRegisterSuccess", successObject);
                }

                @Override
                public void onRegisterError(JSONObject errorObject) {
                    reply.error("onRegisterError", errorObject, "REGISTER_ERROR", "Device registration failed");
                }

                @Override
                public void onProcess(String message) {
                    Log.i("POS", " => TOP register progress: " + message);
                    reply.progress(message);
                }
            });
        } catch (Throwable t) {
            reply.exception("registerDevice", t, "REGISTER_ERROR");
        }
    }

    void performTransaction(String type, String amount, String sessionKey, String lang,
                            Map<String, Object> customObject, MethodChannel.Result result) {
        Map<String, Object> diagnostics = newDiagnostics("performTransaction");
        Reply reply = new Reply(result, diagnostics);
        // A manual entry that never reported back (e.g. the form was left open) must not
        // keep the SDK in manual / skinless mode for this tap sale.
        if (cardTopService != null) {
            diagnostics.put("releasedPendingManualEntry", true);
            releaseManualEntry();
        }
        try {
            JSONObject input = new JSONObject();
            input.put("type", type);
            if (amount != null) {
                input.put("amount", amount);
            }
            Object langValue = topParam("HEBREW".equals(lang) || "iw".equals(lang) ? "HEBREW" : "ENGLISH");
            if (lang != null && langValue != null) {
                input.put("lang", langValue);
            }
            JSONObject custom = new JSONObject(customObject != null ? customObject : new HashMap<>());

            ToPService.OnTransactionListener listener = new ToPService.OnTransactionListener() {
                // Name used by the sample app's SDK build
                public void onTransactionSuccess(JSONObject successObject) {
                    reply.success("onTransactionSuccess", successObject);
                }

                // Name used by the Israel doc
                public void onTransactionResponse(JSONObject successObject) {
                    reply.success("onTransactionResponse", successObject);
                }

                public void onTransactionError(JSONObject errorObject) {
                    reply.error("onTransactionError", errorObject, "TRANSACTION_ERROR", "Transaction failed");
                }

                public void onRegisterNeeded(JSONObject errorObject) {
                    reply.registerNeeded(errorObject);
                }
            };

            Method method = findPerformTransaction();
            Object[] args;
            if (method.getParameterTypes().length == 4) {
                Class<?> customType = method.getParameterTypes()[2];
                Object customArg = customType.isAssignableFrom(HashMap.class)
                        ? new HashMap<>(customObject != null ? customObject : new HashMap<>())
                        : custom;
                args = new Object[]{input, sessionKey, customArg, listener};
            } else {
                input.put("CustomObject", custom);
                args = new Object[]{input, sessionKey, listener};
            }
            diagnostics.put("request", input.toString());
            diagnostics.put("customObject", custom.toString());
            diagnostics.put("sdkMethod", method.toGenericString());
            diagnostics.put("stage", "performTransaction");
            Log.i("POS", " => TOP request: " + input);
            watchSdkScreens(reply, diagnostics);
            method.invoke(service(), args);
        } catch (InvocationTargetException e) {
            reply.exception("performTransaction", e.getCause() != null ? e.getCause() : e, "TRANSACTION_SETUP_ERROR");
        } catch (Throwable t) {
            reply.exception("performTransaction", t, "TRANSACTION_SETUP_ERROR");
        }
    }

    /**
     * Manual card entry (sales only), following the skinless SDK doc
     * (docs.ipospays.com/tap-to-pay-on-android/skinless-sdk#manual-entry-integration):
     * CardTopService in KEY_IN mode opens the SDK's own card form, so card data never
     * reaches the app. The result comes back through onActivityResult -> delegate.
     */
    void startManualEntry(String tpn, String amount, String lang, String name, String phone,
                          String email, MethodChannel.Result result) {
        Map<String, Object> diagnostics = newDiagnostics("startManualEntry");
        diagnostics.put("request", "tpn=" + tpn + ", amount=" + amount + ", lang=" + lang);
        Reply reply = new Reply(result, diagnostics);
        try {
            ToPService.IposgoDelegate delegate = new ToPService.IposgoDelegate() {
                @Override
                public void didReceiveSuccessData(String message, JSONObject successObject) {
                    releaseManualEntry();
                    reply.success("didReceiveSuccessData", successObject);
                }

                @Override
                public void onProcess(String message, String time) {
                    Log.i("POS", " => TOP manual entry progress: " + message);
                    reply.progress(message);
                }

                @Override
                public void didReceiveError(JSONObject errorObject, Integer code) {
                    releaseManualEntry();
                    reply.error("didReceiveError", errorObject, String.valueOf(code), "Manual entry failed");
                }
            };

            ManualEntryRequestModel request = new ManualEntryRequestModel();
            request.local = "HEBREW".equals(lang) || "iw".equals(lang) || "he".equals(lang) ? "he" : "en";
            request.amount = amount;
            request.tpn = tpn;
            request.name = name != null ? name : "";
            request.phoneNumber = phone != null ? phone : "";
            request.email = email != null ? email : "";
            request.holderId = "";
            request.paymentType = PaymentType.REGULAR.toString();
            request.minQuantity = "";
            request.maxQuantity = "";

            if (cardTopService != null) releaseManualEntry();
            cardTopService = new CardTopService(activity, delegate, PaymentMode.KEY_IN);
            diagnostics.put("stage", "startManualEntry");
            cardTopService.startManualEntry(activity, request,
                    new SdkThemeConfig(0xFF6A4BE0, 0xFFFFFFFF));
        } catch (Throwable t) {
            releaseManualEntry();
            reply.exception("startManualEntry", t, "MANUAL_ENTRY_SETUP_ERROR");
        }
    }

    /** MainActivity forwards activity results here; true when it was the manual entry form. */
    boolean onActivityResult(int requestCode, int resultCode, Intent data) {
        if (cardTopService == null || requestCode != CardTopService.getManualEntryRequestCode()) {
            return false;
        }
        return cardTopService.onManualEntryActivityResult(requestCode, resultCode, data);
    }

    private static Method findPerformTransaction() throws NoSuchMethodException {
        Method found = null;
        for (Method m : ToPService.class.getMethods()) {
            if (!m.getName().equals("performTransaction")) continue;
            int count = m.getParameterTypes().length;
            if (count == 4) return m;
            if (count == 3) found = m;
        }
        if (found == null) throw new NoSuchMethodException("ToPService.performTransaction not found");
        return found;
    }

    /** Reads a TOPParams constant if this SDK build has it (the Israel build has HEBREW/ENGLISH). */
    private static Object topParam(String name) {
        try {
            return Class.forName(TOP_PARAMS).getField(name).get(null);
        } catch (Throwable ignored) {
            return null;
        }
    }

    private static Map<String, Object> newDiagnostics(String stage) {
        Map<String, Object> diagnostics = new HashMap<>();
        diagnostics.put("sdk", SDK);
        diagnostics.put("stage", stage);
        diagnostics.put("startedAt", System.currentTimeMillis());
        return diagnostics;
    }

    private static String mask(String value) {
        if (value == null || value.length() <= 4) return value;
        return "****" + value.substring(value.length() - 4);
    }

    /** Replies to Flutter exactly once, on the main thread, with diagnostics attached. */
    private final class Reply {
        private final MethodChannel.Result result;
        private final Map<String, Object> diagnostics;
        private final AtomicBoolean replied = new AtomicBoolean(false);
        private final StringBuilder progress = new StringBuilder();

        Reply(MethodChannel.Result result, Map<String, Object> diagnostics) {
            this.result = result;
            this.diagnostics = diagnostics;
        }

        void progress(String message) {
            synchronized (progress) {
                progress.append(message).append(" | ");
            }
        }

        void success(String callback, JSONObject response) {
            Log.i("POS", " => TOP " + callback + ": " + response);
            if (!replied.compareAndSet(false, true)) return;
            finish(callback, response);
            Map<String, Object> map = JsonMaps.toMap(response);
            map.put("diagnostics", diagnostics);
            mainHandler.post(() -> result.success(map));
        }

        void error(String callback, JSONObject errorObject, String fallbackCode, String fallbackMessage) {
            Log.e("POS", " => TOP " + callback + ": " + errorObject);
            if (!replied.compareAndSet(false, true)) return;
            finish(callback, errorObject);
            String code = firstNonEmpty(errorObject, fallbackCode, "error_code", "errorCode", "code");
            String message = firstNonEmpty(errorObject, fallbackMessage, "error_message", "message", "status");
            Map<String, Object> details = JsonMaps.toMap(errorObject);
            details.put("diagnostics", diagnostics);
            mainHandler.post(() -> result.error(code, message, details));
        }

        void registerNeeded(JSONObject errorObject) {
            diagnostics.put("registerNeeded", true);
            error("onRegisterNeeded", errorObject, "990", "Session key expired, re-registration needed");
        }

        void exception(String stage, Throwable t, String code) {
            Log.e("POS", " => TOP " + stage + " threw", t);
            if (!replied.compareAndSet(false, true)) return;
            mainHandler.post(() -> stopWatchingSdkScreens(Reply.this));
            diagnostics.put("stage", stage);
            diagnostics.put("exceptionClass", t.getClass().getName());
            diagnostics.put("exceptionMessage", String.valueOf(t.getMessage()));
            diagnostics.put("stackTrace", Log.getStackTraceString(t));
            diagnostics.put("elapsedMs", elapsed());
            Map<String, Object> details = new HashMap<>();
            details.put("diagnostics", diagnostics);
            mainHandler.post(() -> result.error(code, String.valueOf(t.getMessage()), details));
        }

        private void finish(String callback, JSONObject raw) {
            mainHandler.post(() -> stopWatchingSdkScreens(Reply.this));
            diagnostics.put("stage", callback);
            diagnostics.put("rawResponse", raw != null ? raw.toString() : "null");
            diagnostics.put("elapsedMs", elapsed());
            synchronized (progress) {
                if (progress.length() > 0) diagnostics.put("progress", progress.toString());
            }
        }

        private long elapsed() {
            Object startedAt = diagnostics.get("startedAt");
            return startedAt instanceof Long ? System.currentTimeMillis() - (Long) startedAt : -1;
        }
    }

    private static String firstNonEmpty(JSONObject object, String fallback, String... keys) {
        if (object != null) {
            for (String key : keys) {
                String value = object.optString(key, "");
                if (!value.isEmpty() && !"null".equals(value)) return value;
            }
        }
        return fallback;
    }
}
