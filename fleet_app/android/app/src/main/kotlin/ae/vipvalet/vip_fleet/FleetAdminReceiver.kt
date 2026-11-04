package ae.vipvalet.vip_fleet

import android.app.admin.DeviceAdminReceiver
import android.content.Context
import android.content.Intent

/** Uninstall protection: while this admin is active, Android does not let the app be removed. */
class FleetAdminReceiver : DeviceAdminReceiver() {
    override fun onDisableRequested(context: Context, intent: Intent): CharSequence =
        "VIP Fleet records the company SMS and calls. Turning protection off is logged."
}
