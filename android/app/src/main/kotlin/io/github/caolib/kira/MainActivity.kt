package io.github.caolib.kira

import android.content.ComponentName
import android.content.pm.PackageManager
import android.graphics.Color
import android.os.Build
import android.os.Bundle
import android.util.Log
import android.view.KeyEvent
import android.view.WindowManager
import com.alexmercerind.mediakitandroidhelper.MediaKitAndroidHelper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.util.zip.GZIPInputStream

class MainActivity : FlutterActivity() {
    private var volumeChannel: MethodChannel? = null
    private var hlsChannel: MethodChannel? = null
    private var displayModeChannel: MethodChannel? = null
    private var iconChannel: MethodChannel? = null
    private var nativeLibsChannel: MethodChannel? = null
    private var interceptVolume = false

    companion object {
        private const val TAG = "KiraMainActivity"
        private val LAUNCHER_ALIASES = listOf(
            ".LauncherDefault",
            ".LauncherAlt1",
        )
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.statusBarColor = Color.TRANSPARENT
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            window.isStatusBarContrastEnforced = false
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            window.attributes = window.attributes.apply {
                layoutInDisplayCutoutMode =
                    WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_DEFAULT
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        volumeChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "io.github.caolib.kira/volume"
        )
        volumeChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "enable" -> {
                    interceptVolume = true
                    result.success(null)
                }
                "disable" -> {
                    interceptVolume = false
                    result.success(null)
                }
                "enableImmersive" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                        window.attributes = window.attributes.apply {
                            layoutInDisplayCutoutMode =
                                WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
                        }
                    }
                    result.success(null)
                }
                "disableImmersive" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                        window.attributes = window.attributes.apply {
                            layoutInDisplayCutoutMode =
                                WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_DEFAULT
                        }
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        hlsChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "io.github.caolib.kira/hls"
        )
        hlsChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "fetch" -> {
                    val url = call.argument<String>("url")
                    val headers = call.argument<Map<String, String>>("headers") ?: emptyMap()
                    val range = call.argument<String>("range")
                    if (url.isNullOrEmpty()) {
                        result.error("bad_request", "Missing url", null)
                        return@setMethodCallHandler
                    }
                    Thread {
                        try {
                            val response = fetchHlsWithRetry(url, headers, range)
                            runOnUiThread { result.success(response) }
                        } catch (e: Exception) {
                            runOnUiThread {
                                result.error(
                                    "fetch_failed",
                                    "${e.javaClass.simpleName}: ${e.message}",
                                    null
                                )
                            }
                        }
                    }.start()
                }
                else -> result.notImplemented()
            }
        }

        displayModeChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "io.github.caolib.kira/display_mode"
        )
        displayModeChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "setPreferredRefreshRate" -> {
                    val refreshRate = call.argument<Number>("refreshRate")?.toFloat() ?: 0f
                    setWindowPreferredRefreshRate(refreshRate)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        iconChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "io.github.caolib.kira/app_icon"
        )
        iconChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "setAppIcon" -> {
                    val index = call.argument<Int>("index") ?: 0
                    setAppIcon(index)
                    result.success(null)
                }
                "getAppIconIndex" -> {
                    val index = getCurrentIconIndex()
                    result.success(index)
                }
                else -> result.notImplemented()
            }
        }

        nativeLibsChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "io.github.caolib.kira/native_libs"
        )
        nativeLibsChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "getPrimaryAbi" -> {
                    val abis = Build.SUPPORTED_ABIS
                    result.success(if (abis.isNotEmpty()) abis[0] else "arm64-v8a")
                }
                "loadLibraries" -> {
                    val paths = call.argument<List<String>>("paths")
                    if (paths.isNullOrEmpty()) {
                        result.error("bad_request", "Missing paths", null)
                        return@setMethodCallHandler
                    }
                    try {
                        for (path in paths) {
                            System.load(path)
                        }
                        // Critical: media_kit AndroidHelper polls GetJavaVM in a
                        // tight sleep loop until setApplicationContextNative stores
                        // the JavaVM. Without this, the Flutter UI freezes forever.
                        MediaKitAndroidHelper.setApplicationContextJava(applicationContext)
                        Log.i(TAG, "media_kit native libs loaded and JavaVM bound")
                        result.success(null)
                    } catch (e: Throwable) {
                        Log.e(TAG, "loadLibraries failed", e)
                        result.error(
                            "load_failed",
                            "${e.javaClass.simpleName}: ${e.message}",
                            null
                        )
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun setWindowPreferredRefreshRate(refreshRate: Float) {
        val nextRefreshRate = if (refreshRate > 0f) refreshRate else 0f
        window.attributes = window.attributes.apply {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                preferredDisplayModeId = 0
            }
            preferredRefreshRate = nextRefreshRate
        }
    }

    private fun setAppIcon(index: Int) {
        val pm = packageManager
        val packageName = packageName
        val clamped = index.coerceIn(0, LAUNCHER_ALIASES.size - 1)
        for ((i, alias) in LAUNCHER_ALIASES.withIndex()) {
            val fullName = "$packageName$alias"
            val newState = if (i == clamped)
                PackageManager.COMPONENT_ENABLED_STATE_ENABLED
            else
                PackageManager.COMPONENT_ENABLED_STATE_DISABLED
            pm.setComponentEnabledSetting(
                ComponentName(packageName, fullName),
                newState,
                PackageManager.DONT_KILL_APP,
            )
        }
    }

    private fun getCurrentIconIndex(): Int {
        val pm = packageManager
        val packageName = packageName
        for ((i, alias) in LAUNCHER_ALIASES.withIndex()) {
            val fullName = "$packageName$alias"
            val state = pm.getComponentEnabledSetting(
                ComponentName(packageName, fullName)
            )
            if (state == PackageManager.COMPONENT_ENABLED_STATE_ENABLED
                || state == PackageManager.COMPONENT_ENABLED_STATE_DEFAULT
            ) {
                return i
            }
        }
        return 0
    }

    private fun fetchHlsWithRetry(
        url: String,
        headers: Map<String, String>,
        range: String?
    ): Map<String, Any?> {
        var lastError: Exception? = null
        for (attempt in 1..3) {
            try {
                return fetchHls(url, headers, range)
            } catch (e: Exception) {
                lastError = e
                if (attempt < 3) {
                    Thread.sleep((250L * attempt))
                }
            }
        }
        throw lastError ?: IllegalStateException("HLS fetch failed")
    }

    private fun fetchHls(
        url: String,
        headers: Map<String, String>,
        range: String?
    ): Map<String, Any?> {
        val connection = (URL(url).openConnection() as HttpURLConnection).apply {
            requestMethod = "GET"
            connectTimeout = 10000
            readTimeout = 20000
            instanceFollowRedirects = true
            useCaches = false
            headers.forEach { (key, value) -> setRequestProperty(key, value) }
            if (!range.isNullOrEmpty()) {
                setRequestProperty("Range", range)
            }
        }

        try {
            val statusCode = connection.responseCode
            val rawStream = if (statusCode >= 400) {
                connection.errorStream
            } else {
                connection.inputStream
            }
            val body = if (rawStream == null) {
                ByteArray(0)
            } else {
                val inputStream = if (connection.contentEncoding.equals("gzip", ignoreCase = true)) {
                    GZIPInputStream(rawStream)
                } else {
                    rawStream
                }
                inputStream.use { stream ->
                    val buffer = ByteArray(64 * 1024)
                    val output = ByteArrayOutputStream()
                    while (true) {
                        val read = stream.read(buffer)
                        if (read < 0) break
                        output.write(buffer, 0, read)
                    }
                    output.toByteArray()
                }
            }

            return mapOf(
                "statusCode" to statusCode,
                "contentType" to connection.contentType,
                "contentLength" to body.size,
                "acceptRanges" to connection.getHeaderField("Accept-Ranges"),
                "contentRange" to connection.getHeaderField("Content-Range"),
                "body" to body
            )
        } finally {
            connection.disconnect()
        }
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent?): Boolean {
        if (interceptVolume) {
            when (keyCode) {
                KeyEvent.KEYCODE_VOLUME_UP -> {
                    volumeChannel?.invokeMethod("volumeUp", null)
                    return true
                }
                KeyEvent.KEYCODE_VOLUME_DOWN -> {
                    volumeChannel?.invokeMethod("volumeDown", null)
                    return true
                }
            }
        }
        return super.onKeyDown(keyCode, event)
    }

    override fun onKeyUp(keyCode: Int, event: KeyEvent?): Boolean {
        if (interceptVolume &&
            (keyCode == KeyEvent.KEYCODE_VOLUME_UP || keyCode == KeyEvent.KEYCODE_VOLUME_DOWN)
        ) {
            return true
        }
        return super.onKeyUp(keyCode, event)
    }
}
