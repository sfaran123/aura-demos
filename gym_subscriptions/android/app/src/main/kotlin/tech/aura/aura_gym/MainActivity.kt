package tech.aura.aura_gym

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Dejavoo Tap to Pay (TOP SDK - In-App SDK Israel), the same calls as the AURA POS app.
 * TopPaymentHandler (Java) comes from src/top/java when the build includes the SDK (Dejavoo
 * Maven credentials in android/local.properties), otherwise from src/notop/java.
 *
 * Kept at the path `flutter create` uses (CI runs it): an existing file is left alone.
 */
class MainActivity : FlutterActivity() {
    private var topPaymentHandler: TopPaymentHandler? = null

    private fun top(): TopPaymentHandler =
        topPaymentHandler ?: TopPaymentHandler(this).also { topPaymentHandler = it }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "isTopAvailable" -> result.success(TopPaymentHandler.AVAILABLE)
                // "sandbox", "prod", or "none" (built without the SDK); see app/build.gradle.kts.
                "topEnvironment" -> result.success(BuildConfig.DEJAVOO_ENV)
                "registerDevice" -> top().registerDevice(call.argument("tpn"), call.argument("merchantCode"), result)
                "performTransaction" -> top().performTransaction(
                    call.argument("type"), call.argument("amount"), call.argument("sessionKey"),
                    call.argument("lang"), call.argument("customObject"), result
                )
                // Manual card entry (sales only); the result arrives via onActivityResult below.
                "startManualEntry" -> top().startManualEntry(
                    call.argument("tpn"), call.argument("amount"), call.argument("lang"),
                    call.argument("name"), call.argument("phone"), call.argument("email"), result
                )
                // Start-up watchdog: has the current sale opened any SDK screen yet?
                "topSdkScreenShown" -> result.success(top().sdkScreenShown())
                // Back on the card screen closes it without any SDK callback.
                "topSdkScreensClosed" -> result.success(top().sdkScreensClosed())
                // Before an automatic retry: start from a fresh SDK service object.
                "resetTopService" -> {
                    top().resetService()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    @Deprecated("Deprecated in Android; the Tap to Pay manual entry form still reports here.")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (topPaymentHandler?.onActivityResult(requestCode, resultCode, data) == true) return
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
    }

    private companion object {
        const val CHANNEL = "tech.aura.gym/top"
    }
}
