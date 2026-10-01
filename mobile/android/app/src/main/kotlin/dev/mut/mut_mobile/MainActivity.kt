package dev.mut.mut_mobile

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.provider.OpenableColumns
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.security.MessageDigest
import java.util.concurrent.Executors

/** SAF only: no storage permission, plaintext cache, arbitrary path or HTTP API. */
class MainActivity : FlutterActivity() {
    private val io = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var channel: MethodChannel? = null
    private var pending: Operation? = null
    // Never reuse a request code within this activity: an old picker can still
    // deliver its result after cancellation and a subsequent unlock.
    private var nextRequest = 301

    private class Operation(
        val result: MethodChannel.Result,
        val requestCode: Int,
        val maximum: Int,
        val output: ByteArray? = null,
        val verify: Boolean = false,
    ) {
        val deadline = SystemClock.elapsedRealtime() + 5 * 60 * 1000L
        @Volatile var cancelled = false
        var timeout: Runnable? = null
        fun checkActive() {
            if (cancelled || SystemClock.elapsedRealtime() >= deadline) {
                throw InterruptedException("cancelled")
            }
        }
        fun wipe() = synchronized(this) {
            cancelled = true
            output?.fill(0)
        }
    }

    private class WipingBuffer : ByteArrayOutputStream() {
        fun wipe() { buf.fill(0); reset() }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dev.mut/documents")
        channel!!.setMethodCallHandler { call, result ->
            // Cancellation must remain available while a picker or IO is busy.
            if (call.method == "cancel") {
                cancelPending()
                result.success(null)
                return@setMethodCallHandler
            }
            if (call.method != "pick" && call.method != "save") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            if (pending != null) {
                result.error("busy", "A document operation is already running.", null)
                return@setMethodCallHandler
            }
            if (nextRequest > 65535) {
                result.error("picker", "Restart the app before selecting another document.", null)
                return@setMethodCallHandler
            }
            val saving = call.method == "save"
            val bytes = if (saving) call.argument<ByteArray>("bytes") else null
            if (saving && (bytes == null || bytes.size > 256 * 1024 * 1024)) {
                bytes?.fill(0)
                result.error("limit", "Document exceeds the size limit.", null)
                return@setMethodCallHandler
            }
            val operation = Operation(
                result, nextRequest++,
                if (call.argument<Boolean>("backup") == true) 256 * 1024 * 1024 else 32 * 1024 * 1024,
                bytes, call.argument<Boolean>("verify") == true,
            )
            pending = operation
            val timeout = Runnable {
                if (pending === operation) {
                    cancelPending()
                    channel?.invokeMethod("background", null)
                }
            }
            operation.timeout = timeout
            main.postDelayed(timeout, 5 * 60 * 1000L)
            val intent = Intent(if (saving) Intent.ACTION_CREATE_DOCUMENT else Intent.ACTION_OPEN_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = if (saving && operation.verify) "application/zip" else if (saving) "application/octet-stream" else "*/*"
                if (saving) {
                    val name = (call.argument<String>("name") ?: "mut-export")
                        .replace('/', '_').replace('\\', '_').filter { it.code >= 32 }.take(180)
                    putExtra(Intent.EXTRA_TITLE, name)
                }
            }
            try { startActivityForResult(intent, operation.requestCode) }
            catch (_: Exception) { completeError(operation, "picker", "No document provider is available.") }
        }
    }

    @Deprecated("Used for the Flutter activity's SAF bridge")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        val operation = pending ?: return
        if (requestCode != operation.requestCode) return
        if (SystemClock.elapsedRealtime() >= operation.deadline) {
            cancelPending()
            channel?.invokeMethod("background", null)
            return
        }
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            complete(operation, if (operation.output != null) false else null)
            return
        }
        io.execute {
            try {
                operation.checkActive()
                if (operation.output == null) {
                    var name = "Imported file"
                    contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE), null, null, null)?.use { cursor ->
                        if (cursor.moveToFirst()) {
                            val nameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                            if (nameIndex >= 0) name = cursor.getString(nameIndex) ?: name
                            val sizeIndex = cursor.getColumnIndex(OpenableColumns.SIZE)
                            if (sizeIndex >= 0 && !cursor.isNull(sizeIndex) && cursor.getLong(sizeIndex) > operation.maximum) {
                                throw IllegalArgumentException("size")
                            }
                        }
                    }
                    val bytes = readBounded(uri, operation)
                    runOnUiThread {
                        if (pending === operation && !operation.cancelled && SystemClock.elapsedRealtime() < operation.deadline) {
                            complete(operation, mapOf("name" to name, "bytes" to bytes))
                        } else {
                            cancelExpired(operation)
                        }
                        bytes.fill(0)
                    }
                } else {
                    writeDocument(uri, operation)
                    runOnUiThread {
                        if (SystemClock.elapsedRealtime() >= operation.deadline) cancelExpired(operation)
                        else complete(operation, true)
                    }
                }
            } catch (_: InterruptedException) {
                runOnUiThread { cancelExpired(operation) }
            } catch (_: IllegalArgumentException) {
                runOnUiThread { completeError(operation, "limit", "File exceeds the supported size limit.") }
            } catch (_: Exception) {
                runOnUiThread { completeError(operation, "document", "Cannot read, write or verify the selected document.") }
            }
        }
    }

    private fun writeDocument(uri: Uri, operation: Operation) {
        val bytes = operation.output ?: throw IllegalStateException("missing")
        operation.checkActive()
        contentResolver.openOutputStream(uri, "wt")?.use { stream ->
            var offset = 0
            while (offset < bytes.size) {
                // Cancellation takes this same monitor: after it acknowledges,
                // no chunk can write plaintext, even from an already-running IO task.
                synchronized(operation) {
                    operation.checkActive()
                    val count = minOf(65536, bytes.size - offset)
                    stream.write(bytes, offset, count)
                    offset += count
                }
            }
            operation.checkActive()
            stream.flush()
        } ?: throw IllegalStateException("write")
        if (operation.verify) {
            val digest = MessageDigest.getInstance("SHA-256")
            val expected = synchronized(operation) {
                operation.checkActive()
                digest.digest(bytes)
            }
            contentResolver.openInputStream(uri)?.use { stream ->
                val buffer = ByteArray(65536)
                try {
                    var total = 0L
                    while (true) {
                        operation.checkActive()
                        val count = stream.read(buffer)
                        if (count < 0) break
                        total += count
                        if (total > bytes.size) throw IllegalStateException("verify")
                        digest.update(buffer, 0, count)
                    }
                    if (total != bytes.size.toLong() || !MessageDigest.isEqual(expected, digest.digest())) {
                        throw IllegalStateException("verify")
                    }
                } finally { buffer.fill(0) }
            } ?: throw IllegalStateException("verify")
        }
    }

    private fun readBounded(uri: Uri, operation: Operation): ByteArray {
        operation.checkActive()
        val stream = contentResolver.openInputStream(uri) ?: throw IllegalStateException("read")
        return stream.use {
            val bytes = WipingBuffer()
            val buffer = ByteArray(65536)
            try {
                while (true) {
                    operation.checkActive()
                    val count = it.read(buffer)
                    if (count < 0) break
                    if (bytes.size().toLong() + count > operation.maximum) throw IllegalArgumentException("size")
                    bytes.write(buffer, 0, count)
                }
                operation.checkActive()
                bytes.toByteArray()
            } finally { buffer.fill(0); bytes.wipe() }
        }
    }

    private fun clearPending(operation: Operation) {
        operation.wipe()
        operation.timeout?.let { main.removeCallbacks(it) }
        if (pending === operation) pending = null
    }
    private fun complete(operation: Operation, value: Any?) {
        if (pending !== operation || operation.cancelled) return
        operation.result.success(value)
        clearPending(operation)
    }
    private fun completeError(operation: Operation, code: String, message: String) {
        if (pending !== operation || operation.cancelled) return
        operation.result.error(code, message, null)
        clearPending(operation)
    }
    private fun cancelPending() {
        val operation = pending ?: return
        clearPending(operation)
        operation.result.success(if (operation.output != null) false else null)
    }
    private fun cancelExpired(operation: Operation) {
        if (pending !== operation) return
        cancelPending()
        channel?.invokeMethod("background", null)
    }
    override fun onStop() {
        super.onStop()
        // An active SAF picker is an explicit document flow. Its native
        // deadline still applies if Dart timers are suspended in background.
        val operation = pending
        if (operation == null) channel?.invokeMethod("background", null)
        else if (SystemClock.elapsedRealtime() >= operation.deadline) cancelExpired(operation)
    }
    override fun onDestroy() {
        cancelPending()
        io.shutdownNow()
        super.onDestroy()
    }
}
