package ae.vipvalet.vip_calls

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
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

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
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
