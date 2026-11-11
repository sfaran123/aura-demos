package tech.aura.aura_gym;

import android.app.Activity;
import android.content.Intent;

import java.util.HashMap;
import java.util.Map;

import io.flutter.plugin.common.MethodChannel;

/**
 * Stub used when this build has no Dejavoo TOP SDK: the Dejavoo Maven credentials are not in
 * android/local.properties (see app/build.gradle). Add them and rebuild to get the real
 * implementation from src/top/java.
 */
final class TopPaymentHandler {
    static final boolean AVAILABLE = false;
    private static final String MESSAGE =
            "Tap to Pay (TOP SDK) is not included in this build: the Dejavoo Maven credentials for dejavoo.env were missing when the app was built.";

    TopPaymentHandler(Activity activity) {
    }

    void registerDevice(String tpn, String merchantCode, MethodChannel.Result result) {
        result.error("TOP_NOT_CONFIGURED", MESSAGE, details("registerDevice"));
    }

    void performTransaction(String type, String amount, String sessionKey, String lang,
                            Map<String, Object> customObject, MethodChannel.Result result) {
        result.error("TOP_NOT_CONFIGURED", MESSAGE, details("performTransaction"));
    }

    void startManualEntry(String tpn, String amount, String lang, String name, String phone,
                          String email, MethodChannel.Result result) {
        result.error("TOP_NOT_CONFIGURED", MESSAGE, details("startManualEntry"));
    }

    boolean onActivityResult(int requestCode, int resultCode, Intent data) {
        return false;
    }

    boolean sdkScreenShown() {
        return false;
    }

    boolean sdkScreensClosed() {
        return false;
    }

    void resetService() {
    }

    private static Map<String, Object> details(String stage) {
        Map<String, Object> diagnostics = new HashMap<>();
        diagnostics.put("stage", stage);
        diagnostics.put("sdk", "none (built without TOP SDK)");
        Map<String, Object> details = new HashMap<>();
        details.put("diagnostics", diagnostics);
        return details;
    }
}
