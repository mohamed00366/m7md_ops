package ae.vipvalet.vip_fleet

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/** Opens the app for the admin when *#*#1508#*#* is dialed (used when the launcher icon is hidden). */
class SecretCodeReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        try {
            val open = Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            context.startActivity(open)
        } catch (_: Exception) {}
    }
}
