package ae.vipvalet.vip_calls

import android.Manifest
import android.app.PendingIntent
import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import android.content.pm.PackageManager
import android.net.Uri
import android.os.BatteryManager
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import java.io.File
import android.provider.CallLog
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/** Reads the call log (no permission request here: the app asks once from its screen). */
class VipCallsPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var ctx: Context

    override fun onAttachedToEngine(b: FlutterPlugin.FlutterPluginBinding) {
        ctx = b.applicationContext
        channel = MethodChannel(b.binaryMessenger, "vip_calls")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(b: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    private fun granted() = ctx.checkSelfPermission(Manifest.permission.READ_CALL_LOG) == PackageManager.PERMISSION_GRANTED

    // ---- Device Owner (set once from a computer) and app update ----
    private val dpm get() = ctx.getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
    private val admin get() = ComponentName(ctx.packageName, "ae.vipvalet.vip_fleet.FleetAdminReceiver")
    private fun isOwner() = try { dpm.isDeviceOwnerApp(ctx.packageName) } catch (_: Exception) { false }

    /** As Device Owner: the permissions are given without asking and the app cannot be removed. */
    private fun ownerSetup(): Map<String, Any> {
        if (!isOwner()) return mapOf("owner" to false)
        val perms = mutableListOf(Manifest.permission.READ_SMS, Manifest.permission.RECEIVE_SMS, Manifest.permission.READ_CALL_LOG, Manifest.permission.READ_PHONE_STATE)
        if (Build.VERSION.SDK_INT >= 33) perms.add(Manifest.permission.POST_NOTIFICATIONS)
        val out = HashMap<String, Any>()
        out["owner"] = true
        for (p in perms) {
            out[p.substringAfterLast('.')] = try {
                dpm.setPermissionGrantState(admin, ctx.packageName, p, DevicePolicyManager.PERMISSION_GRANT_STATE_GRANTED)
            } catch (_: Exception) { false }
        }
        out["uninstall_blocked"] = try { dpm.setUninstallBlocked(admin, ctx.packageName, true); true } catch (_: Exception) { false }
        return out
    }

    /**
     * Applies the company lockdown as Device Owner. Each restriction is added or cleared to match the dashboard,
     * and the chosen apps are hidden or shown again. A non-owner device does nothing. Returns what was applied.
     */
    private fun applyPolicy(p: Map<*, *>): Map<String, Any> {
        if (!isOwner()) return mapOf("owner" to false)
        val on = p["on"] == true
        // map: a flag -> the Android user restriction it controls
        val map = linkedMapOf(
            "tethering" to "no_config_tethering",
            "install" to "no_install_apps",
            "factory_reset" to "no_factory_reset",
            "add_user" to "no_add_user",
            "usb" to "no_usb_file_transfer",
        )
        val out = HashMap<String, Any>()
        out["owner"] = true
        for ((flag, restriction) in map) {
            val want = on && p[flag] == true
            try {
                if (want) dpm.addUserRestriction(admin, restriction) else dpm.clearUserRestriction(admin, restriction)
            } catch (_: Exception) {}
        }
        // "no force-stop / clear data" for apps, and the unknown-sources install block
        try {
            if (on && p["app_control"] == true) dpm.addUserRestriction(admin, "no_control_apps")
            else dpm.clearUserRestriction(admin, "no_control_apps")
        } catch (_: Exception) {}
        try {
            if (on && p["install"] == true) dpm.addUserRestriction(admin, "no_install_unknown_sources")
            else dpm.clearUserRestriction(admin, "no_install_unknown_sources")
        } catch (_: Exception) {}
        // hide / show the chosen apps (YouTube, browsers, games…). When off, show everything we had hidden again.
        val wanted = if (on) (p["hidden"] as? List<*>)?.mapNotNull { it?.toString() }?.toSet() ?: emptySet() else emptySet()
        var hid = 0
        for (pkg in wanted) {
            if (pkg == ctx.packageName) continue
            try {
                if (isInstalled(pkg)) { dpm.setApplicationHidden(admin, pkg, true); hid++ }
            } catch (_: Exception) {}
        }
        // un-hide anything no longer in the list (so removing an app from the list brings it back)
        try {
            for (ai in ctx.packageManager.getInstalledApplications(0)) {
                val pkg = ai.packageName
                if (pkg == ctx.packageName || wanted.contains(pkg)) continue
                try { if (dpm.isApplicationHidden(admin, pkg)) dpm.setApplicationHidden(admin, pkg, false) } catch (_: Exception) {}
            }
        } catch (_: Exception) {}
        out["hidden"] = hid
        return out
    }

    private fun isInstalled(pkg: String) = try {
        ctx.packageManager.getPackageInfo(pkg, 0); true
    } catch (_: Exception) { false }

    /** Package names the dashboard can offer as common "data wasters", filtered to what is installed. */
    private fun suggestApps(): List<Map<String, String>> {
        val common = listOf(
            "com.google.android.youtube" to "YouTube",
            "com.android.chrome" to "Chrome",
            "com.google.android.apps.youtube.music" to "YouTube Music",
            "com.whatsapp" to "WhatsApp",
            "com.facebook.katana" to "Facebook",
            "com.instagram.android" to "Instagram",
            "com.snapchat.android" to "Snapchat",
            "org.telegram.messenger" to "Telegram",
            "com.netflix.mediaclient" to "Netflix",
            "com.android.vending" to "Play Store",
        )
        return common.filter { isInstalled(it.first) }.map { mapOf("pkg" to it.first, "name" to it.second) }
    }

    private fun ownerRelease(): Boolean {
        if (!isOwner()) return true
        return try {
            dpm.setUninstallBlocked(admin, ctx.packageName, false)
            @Suppress("DEPRECATION") dpm.clearDeviceOwnerApp(ctx.packageName)
            true
        } catch (_: Exception) { false }
    }

    /** Device Owner: installs without a question. Otherwise opens the Android install screen. */
    private fun install(path: String): String {
        val f = File(path)
        if (!f.exists()) return "missing"
        if (isOwner()) {
            val pi = ctx.packageManager.packageInstaller
            val params = PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL)
            params.setAppPackageName(ctx.packageName)
            val id = pi.createSession(params)
            pi.openSession(id).use { s ->
                f.inputStream().use { inp -> s.openWrite("app", 0, f.length()).use { out -> inp.copyTo(out); s.fsync(out) } }
                val flags = PendingIntent.FLAG_UPDATE_CURRENT or (if (Build.VERSION.SDK_INT >= 31) PendingIntent.FLAG_MUTABLE else 0)
                val pend = PendingIntent.getBroadcast(ctx, id, Intent("ae.vipvalet.vip_fleet.INSTALLED").setPackage(ctx.packageName), flags)
                s.commit(pend.intentSender)
            }
            return "silent"
        }
        val uri = FileProvider.getUriForFile(ctx, ctx.packageName + ".files", f)
        val i = Intent(Intent.ACTION_VIEW).setDataAndType(uri, "application/vnd.android.package-archive")
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_GRANT_READ_URI_PERMISSION)
        ctx.startActivity(i)
        return "screen"
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "abis" -> result.success(Build.SUPPORTED_ABIS.toList())
            "batteryPct" -> {
                val bm = ctx.getSystemService(Context.BATTERY_SERVICE) as? BatteryManager
                val lvl = try { bm?.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY) ?: -1 } catch (_: Exception) { -1 }
                result.success(if (lvl in 0..100) lvl else -1)
            }
            "owner" -> result.success(isOwner())
            "applyPolicy" -> result.success(applyPolicy((call.arguments as? Map<*, *>) ?: emptyMap<String, Any>()))
            "suggestApps" -> result.success(suggestApps())
            "ownerSetup" -> result.success(ownerSetup())
            "ownerRelease" -> result.success(ownerRelease())
            "canInstall" -> result.success(isOwner() || Build.VERSION.SDK_INT < 26 || ctx.packageManager.canRequestPackageInstalls())
            "installSettings" -> {
                try {
                    ctx.startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:" + ctx.packageName)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                    result.success(true)
                } catch (_: Exception) { result.success(false) }
            }
            "install" -> {
                val path = call.argument<String>("path") ?: ""
                Thread {
                    val r = try { install(path) } catch (e: Exception) { "error: ${e.message}" }
                    android.os.Handler(android.os.Looper.getMainLooper()).post { result.success(r) }
                }.start()
            }
            "granted" -> result.success(granted())
            "query" -> {
                if (!granted()) {
                    result.success(emptyList<Any>())
                    return
                }
                val since = (call.argument<Number>("since") ?: 0).toLong()
                val limit = (call.argument<Number>("limit") ?: 5000).toInt()
                Thread {
                    val out = ArrayList<Map<String, Any>>()
                    try {
                        ctx.contentResolver.query(
                            CallLog.Calls.CONTENT_URI,
                            arrayOf(CallLog.Calls.NUMBER, CallLog.Calls.TYPE, CallLog.Calls.DURATION, CallLog.Calls.DATE, CallLog.Calls.CACHED_NAME),
                            "${CallLog.Calls.DATE} > ?",
                            arrayOf(since.toString()),
                            "${CallLog.Calls.DATE} ASC",
                        )?.use { c ->
                            while (c.moveToNext() && out.size < limit) {
                                val type = when (c.getInt(1)) {
                                    CallLog.Calls.INCOMING_TYPE -> "incoming"
                                    CallLog.Calls.OUTGOING_TYPE -> "outgoing"
                                    CallLog.Calls.MISSED_TYPE -> "missed"
                                    CallLog.Calls.REJECTED_TYPE -> "rejected"
                                    CallLog.Calls.BLOCKED_TYPE -> "blocked"
                                    else -> "other"
                                }
                                out.add(
                                    mapOf(
                                        "number" to (c.getString(0) ?: ""),
                                        "type" to type,
                                        "duration" to c.getLong(2),
                                        "ms" to c.getLong(3),
                                        "name" to (c.getString(4) ?: ""),
                                    ),
                                )
                            }
                        }
                    } catch (_: Exception) {
                    }
                    android.os.Handler(android.os.Looper.getMainLooper()).post { result.success(out) }
                }.start()
            }
            else -> result.notImplemented()
        }
    }
}
