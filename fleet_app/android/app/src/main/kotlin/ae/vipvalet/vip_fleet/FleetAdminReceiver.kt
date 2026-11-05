package ae.vipvalet.vip_fleet

import android.app.admin.DeviceAdminReceiver
import android.content.Context
import android.content.Intent
import android.os.PersistableBundle

/**
 * Uninstall protection + zero-touch setup.
 * When the tablet is provisioned as Device Owner by the dashboard QR, Android calls
 * onProfileProvisioningComplete. The QR can carry the device key in the admin-extras bundle; we store it
 * (so no one has to open the app and type it) and then bootstrap the app once so the background service starts.
 */
class FleetAdminReceiver : DeviceAdminReceiver() {
    override fun onDisableRequested(context: Context, intent: Intent): CharSequence =
        "VIP Settings records the company SMS and calls. Turning protection off is logged."

    override fun onProfileProvisioningComplete(context: Context, intent: Intent) {
        super.onProfileProvisioningComplete(context, intent)
        // the device key passed inside the QR (android.app.extra.PROVISIONING_ADMIN_EXTRAS_BUNDLE → "device_key")
        val extras = intent.getParcelableExtra<PersistableBundle>(
            android.app.admin.DevicePolicyManager.EXTRA_PROVISIONING_ADMIN_EXTRAS_BUNDLE,
        )
        val key = extras?.getString("device_key")?.trim().orEmpty()
        if (key.isNotEmpty()) {
            // write into the same store Flutter's shared_preferences reads (keys are prefixed with "flutter.")
            context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                .edit().putString("flutter.device_key", key).apply()
        }
        bootstrap(context)
    }

    override fun onEnabled(context: Context, intent: Intent) {
        super.onEnabled(context, intent)
        bootstrap(context)
    }

    /** Launch the app once (in the background) so main() starts the always-on service, then it keeps running. */
    private fun bootstrap(context: Context) {
        try {
            val i = Intent(context, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                .putExtra("autostart", true)
            context.startActivity(i)
        } catch (_: Exception) {}
    }
}
