package io.github.caolib.kira

import dev.dint.cryptography_flutter.CryptographyFlutterPlugin
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMethodCodec

/** Keep the package's native crypto implementation, but not its UI-thread queue.
 *
 * cryptography_flutter 2.3.4 registers a synchronous Android MethodCallHandler.
 * PBKDF2's 600,000 iterations must not block the platform/UI thread. Rebind the
 * registered plugin to Flutter's serial background TaskQueue; the wire API and
 * algorithms remain the package's implementation, with no weaker fallback.
 */
internal object BackupCryptoChannel {
    fun configure(engine: FlutterEngine) {
        val plugin = engine.plugins.get(CryptographyFlutterPlugin::class.java)
        if (plugin is CryptographyFlutterPlugin) {
            val messenger = engine.dartExecutor.binaryMessenger
            MethodChannel(
                messenger,
                "cryptography_flutter",
                StandardMethodCodec.INSTANCE,
                messenger.makeBackgroundTaskQueue()
            ).setMethodCallHandler(plugin)
        }
    }
}
