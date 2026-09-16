package xyz.extera.next

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.PowerManager

import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

// FlutterFragmentActivity rather than FlutterActivity: local_auth drives
// androidx BiometricPrompt, which requires a FragmentActivity host.
class MainActivity : FlutterFragmentActivity() {

    override fun attachBaseContext(base: Context) {
        super.attachBaseContext(base)
    }

    override fun provideFlutterEngine(context: Context): FlutterEngine? {
        return provideEngine(this)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        // Do nothing, because the engine is configured in provideEngine.
    }

    companion object {
        private const val POWER_SAVE_METHOD_CHANNEL =
            "xyz.extera.next/power_save_mode"
        private const val POWER_SAVE_EVENT_CHANNEL =
            "xyz.extera.next/power_save_mode_changes"

        var engine: FlutterEngine? = null

        fun provideEngine(context: Context): FlutterEngine {
            engine?.let { return it }

            val eng = FlutterEngine(context, emptyArray(), true, false)
            configurePowerSaveModeChannels(context.applicationContext, eng)
            engine = eng
            return eng
        }

        private fun configurePowerSaveModeChannels(
            context: Context,
            engine: FlutterEngine,
        ) {
            val powerManager =
                context.getSystemService(Context.POWER_SERVICE) as PowerManager

            MethodChannel(
                engine.dartExecutor.binaryMessenger,
                POWER_SAVE_METHOD_CHANNEL,
            ).setMethodCallHandler { call, result ->
                when (call.method) {
                    "isPowerSaveMode" -> result.success(powerManager.isPowerSaveMode)
                    else -> result.notImplemented()
                }
            }

            EventChannel(
                engine.dartExecutor.binaryMessenger,
                POWER_SAVE_EVENT_CHANNEL,
            ).setStreamHandler(object : EventChannel.StreamHandler {
                private var receiver: BroadcastReceiver? = null

                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    events.success(powerManager.isPowerSaveMode)
                    if (receiver != null) return

                    receiver = object : BroadcastReceiver() {
                        override fun onReceive(receiverContext: Context?, intent: Intent?) {
                            if (intent?.action == PowerManager.ACTION_POWER_SAVE_MODE_CHANGED) {
                                events.success(powerManager.isPowerSaveMode)
                            }
                        }
                    }.also {
                        context.registerReceiver(
                            it,
                            IntentFilter(PowerManager.ACTION_POWER_SAVE_MODE_CHANGED),
                        )
                    }
                }

                override fun onCancel(arguments: Any?) {
                    val registeredReceiver = receiver ?: return
                    receiver = null
                    try {
                        context.unregisterReceiver(registeredReceiver)
                    } catch (_: IllegalArgumentException) {
                        // Already unregistered by the framework/process teardown.
                    }
                }
            })
        }
    }
}
