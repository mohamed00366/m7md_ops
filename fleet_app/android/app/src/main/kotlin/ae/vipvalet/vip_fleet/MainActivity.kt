package ae.vipvalet.vip_fleet

import android.Manifest
import android.app.admin.DevicePolicyManager
import android.content.pm.PackageManager
import android.content.ComponentName
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var callsResult: MethodChannel.Result? = null

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == CALLS_CODE) {
            val r = callsResult
            callsResult = null
            r?.success(checkSelfPermission(Manifest.permission.READ_CALL_LOG) == PackageManager.PERMISSION_GRANTED)
        }
    }

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
                // the call log: only READ_CALL_LOG + READ_PHONE_STATE
                "callsRequest" -> {
                    if (checkSelfPermission(Manifest.permission.READ_CALL_LOG) == PackageManager.PERMISSION_GRANTED) {
                        result.success(true)
                    } else if (callsResult != null) {
                        result.success(false)
                    } else {
                        callsResult = result
                        requestPermissions(arrayOf(Manifest.permission.READ_CALL_LOG, Manifest.permission.READ_PHONE_STATE), CALLS_CODE)
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

    companion object {
        private const val CALLS_CODE = 7301
    }
}
