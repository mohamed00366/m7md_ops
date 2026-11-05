package ae.vipvalet.vip_fleet

import android.app.Activity
import android.app.admin.DevicePolicyManager
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.os.PersistableBundle

/**
 * Required for QR / fully-managed provisioning on Android 10+ (API 29+). Without an activity that answers
 * GET_PROVISIONING_MODE and ADMIN_POLICY_COMPLIANCE, setup fails with "Can't set up device". We also read the
 * device key the QR carried and store it for the Flutter app, then report success. No UI.
 */
class ProvisioningActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // store the device key baked into the QR (admin-extras bundle → "device_key")
        try {
            val extras = intent.getParcelableExtra<PersistableBundle>(
                DevicePolicyManager.EXTRA_PROVISIONING_ADMIN_EXTRAS_BUNDLE,
            )
            val key = extras?.getString("device_key")?.trim().orEmpty()
            if (key.isNotEmpty()) {
                getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                    .edit().putString("flutter.device_key", key).apply()
            }
        } catch (_: Exception) {}

        val result = Intent()
        if (intent.action == DevicePolicyManager.ACTION_GET_PROVISIONING_MODE) {
            result.putExtra(
                DevicePolicyManager.EXTRA_PROVISIONING_MODE,
                DevicePolicyManager.PROVISIONING_MODE_FULLY_MANAGED_DEVICE,
            )
        }
        setResult(RESULT_OK, result)
        finish()
    }
}
