package ae.vipvalet.vip_fleet

import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val admin = ComponentName(this, FleetAdminReceiver::class.java)
        val dpm = getSystemService(DEVICE_POLICY_SERVICE) as DevicePolicyManager
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "vip_fleet/native").setMethodCallHandler { call, result ->
            when (call.method) {
                "info" -> result.success(
                    mapOf(
                        "android_id" to (Settings.Secure.getString(contentResolver, Settings.Secure.ANDROID_ID) ?: ""),
                        "model" to "${Build.MANUFACTURER} ${Build.MODEL}".trim(),
                        "os" to (Build.VERSION.RELEASE ?: ""),
                    ),
                )
                "adminActive" -> result.success(dpm.isAdminActive(admin))
                "adminRequest" -> {
                    val i = Intent(DevicePolicyManager.ACTION_ADD_DEVICE_ADMIN)
                        .putExtra(DevicePolicyManager.EXTRA_DEVICE_ADMIN, admin)
                        .putExtra(DevicePolicyManager.EXTRA_ADD_EXPLANATION, "Keeps VIP Fleet on this company device.")
                    startActivity(i)
                    result.success(true)
                }
                "adminRemove" -> {
                    try {
                        dpm.removeActiveAdmin(admin)
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                "appSettings" -> {
                    startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName")))
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }
}
