package dev.mut.mut_mobile

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Bundle
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
    private var channel: MethodChannel? = null
    private var pending: MethodChannel.Result? = null
    private var limit = 32 * 1024 * 1024
    private var output: ByteArray? = null
    private var verify = false
    private val pickRequest = 301
    private val saveRequest = 302

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
    }
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dev.mut/documents")
        channel!!.setMethodCallHandler { call, result ->
            if (pending != null) {
                result.error("busy", "A document operation is already running.", null)
                return@setMethodCallHandler
            }
            when (call.method) {
                "pick" -> {
                    limit = if (call.argument<Boolean>("backup") == true) 256 * 1024 * 1024 else 32 * 1024 * 1024
                    pending = result
                    val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        type = "*/*"
                    }
                    try { startActivityForResult(intent, pickRequest) }
                    catch (_: Exception) { completeError("picker", "No document provider is available.") }
                }
                "save" -> {
                    val bytes = call.argument<ByteArray>("bytes")
                    if (bytes == null || bytes.size > 256 * 1024 * 1024) {
                        result.error("limit", "Document exceeds the size limit.", null)
                        return@setMethodCallHandler
                    }
                    pending = result
                    output = bytes
                    verify = call.argument<Boolean>("verify") == true
                    val name = (call.argument<String>("name") ?: "mut-export")
                        .replace('/', '_').replace('\\', '_').filter { it.code >= 32 }.take(180)
                    val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        type = if (verify) "application/zip" else "application/octet-stream"
                        putExtra(Intent.EXTRA_TITLE, name)
                    }
                    try { startActivityForResult(intent, saveRequest) }
                    catch (_: Exception) { completeError("picker", "No document provider is available.") }
                }
                else -> result.notImplemented()
            }
        }
    }
    @Deprecated("Used for the Flutter activity's SAF bridge")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != pickRequest && requestCode != saveRequest) return
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            pending?.success(if (requestCode == saveRequest) false else null)
            clearPending()
            return
        }
        io.execute {
            try {
                if (requestCode == pickRequest) {
                    var name = "Imported file"
                    contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE), null, null, null)?.use { cursor ->
                        if (cursor.moveToFirst()) {
                            val nameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                            if (nameIndex >= 0) name = cursor.getString(nameIndex) ?: name
                            val sizeIndex = cursor.getColumnIndex(OpenableColumns.SIZE)
                            if (sizeIndex >= 0 && !cursor.isNull(sizeIndex) && cursor.getLong(sizeIndex) > limit) {
                                throw IllegalArgumentException("size")
                            }
                        }
                    }
                    val bytes = readBounded(uri, limit)
                    runOnUiThread { pending?.success(mapOf("name" to name, "bytes" to bytes)); clearPending() }
                } else {
                    val bytes = output ?: throw IllegalStateException("missing")
                    contentResolver.openOutputStream(uri, "wt")?.use { stream -> stream.write(bytes); stream.flush() }
                        ?: throw IllegalStateException("write")
                    if (verify) {
                        val digest = MessageDigest.getInstance("SHA-256")
                        val expected = digest.digest(bytes)
                        contentResolver.openInputStream(uri)?.use { stream ->
                            val buffer = ByteArray(65536)
                            var total = 0L
                            while (true) {
                                val count = stream.read(buffer)
                                if (count < 0) break
                                total += count
                                if (total > bytes.size) throw IllegalStateException("verify")
                                digest.update(buffer, 0, count)
                            }
                            if (total != bytes.size.toLong() || !MessageDigest.isEqual(expected, digest.digest())) {
                                throw IllegalStateException("verify")
                            }
                        } ?: throw IllegalStateException("verify")
                    }
                    runOnUiThread { pending?.success(true); clearPending() }
                }
            } catch (_: IllegalArgumentException) {
                runOnUiThread { completeError("limit", "File exceeds the supported size limit.") }
            } catch (_: Exception) {
                runOnUiThread { completeError("document", "Cannot read, write or verify the selected document.") }
            }
        }
    }
    private fun readBounded(uri: Uri, maximum: Int): ByteArray {
        val stream = contentResolver.openInputStream(uri) ?: throw IllegalStateException("read")
        return stream.use {
            val bytes = ByteArrayOutputStream()
            val buffer = ByteArray(65536)
            while (true) {
                val count = it.read(buffer)
                if (count < 0) break
                if (bytes.size().toLong() + count > maximum) throw IllegalArgumentException("size")
                bytes.write(buffer, 0, count)
            }
            bytes.toByteArray()
        }
    }
    private fun clearPending() { output?.fill(0); output = null; pending = null }
    private fun completeError(code: String, message: String) { pending?.error(code, message, null); clearPending() }
    override fun onStop() {
        super.onStop()
        if (pending == null) channel?.invokeMethod("background", null)
    }
    override fun onDestroy() {
        completeError("closed", "Document operation was interrupted.")
        io.shutdown()
        super.onDestroy()
    }
}
