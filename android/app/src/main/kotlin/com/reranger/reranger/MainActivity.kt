package com.reranger.reranger

import android.app.Activity
import android.content.Intent
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.reranger.app/photo_picker"
    private var pendingResult: MethodChannel.Result? = null
    private val PICK_IMAGE_REQUEST_CODE = 4242

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "pickImage") {
                if (pendingResult != null) {
                    result.error("ALREADY_ACTIVE", "An image picker request is already in progress.", null)
                    return@setMethodCallHandler
                }
                pendingResult = result
                try {
                    val intent = Intent(Intent.ACTION_GET_CONTENT).apply {
                        type = "image/*"
                        addCategory(Intent.CATEGORY_OPENABLE)
                        putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("image/jpeg", "image/png", "image/webp"))
                    }
                    startActivityForResult(Intent.createChooser(intent, "Select Image"), PICK_IMAGE_REQUEST_CODE)
                } catch (e: Exception) {
                    pendingResult = null
                    result.error("PICK_FAILED", "Failed to launch system image picker: ${e.message}", null)
                }
            } else {
                result.notImplemented()
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == PICK_IMAGE_REQUEST_CODE) {
            val result = pendingResult
            pendingResult = null

            if (resultCode == Activity.RESULT_OK && data?.data != null) {
                val uri: Uri = data.data!!
                try {
                    val cacheDir = applicationContext.cacheDir
                    val mimeType = contentResolver.getType(uri)
                    val ext = when (mimeType) {
                        "image/jpeg" -> ".jpg"
                        "image/webp" -> ".webp"
                        else -> ".png"
                    }
                    val destinationFile = File(cacheDir, "picked_${System.currentTimeMillis()}$ext")
                    val inputStream = contentResolver.openInputStream(uri)
                    if (inputStream == null) {
                        result?.error("STREAM_ERROR", "Could not open stream for selected image URI", null)
                        return
                    }
                    inputStream.use { input ->
                        FileOutputStream(destinationFile).use { output ->
                            input.copyTo(output)
                        }
                    }
                    result?.success(destinationFile.absolutePath)
                } catch (e: Exception) {
                    result?.error("CACHE_ERROR", "Failed to cache selected image: ${e.message}", null)
                }
            } else {
                result?.success(null)
            }
        }
    }
}
