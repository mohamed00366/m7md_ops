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
