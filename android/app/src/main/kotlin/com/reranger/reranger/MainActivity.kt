package com.reranger.reranger

import android.app.Activity
import android.content.ContentValues
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    private val PICKER_CHANNEL = "com.reranger.app/photo_picker"
    private val STORAGE_CHANNEL = "com.reranger.app/storage"
    private val MEDIA_CHANNEL = "com.reranger.app/media"

    private var pendingResult: MethodChannel.Result? = null
    private val PICK_IMAGE_REQUEST_CODE = 4242

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // 1. Photo Picker Channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PICKER_CHANNEL).setMethodCallHandler { call, result ->
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

        // 2. Storage Directory Channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, STORAGE_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getFilesDirectory" -> {
                    result.success(applicationContext.filesDir.absolutePath)
                }
                "getCacheDirectory" -> {
                    result.success(applicationContext.cacheDir.absolutePath)
                }
                else -> result.notImplemented()
            }
        }

        // 3. Media Save & Share Channel (DEF-025)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, MEDIA_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "saveImageToGallery" -> {
                    val filePath = call.argument<String>("filePath")
                    val title = call.argument<String>("title") ?: "reranger_export_${System.currentTimeMillis()}"
                    val mimeType = call.argument<String>("mimeType") ?: "image/png"

                    if (filePath == null) {
                        result.error("INVALID_ARGUMENT", "filePath must not be null", null)
                        return@setMethodCallHandler
                    }

                    try {
                        val srcFile = File(filePath)
                        if (!srcFile.exists()) {
                            result.error("FILE_NOT_FOUND", "Source export file does not exist at $filePath", null)
                            return@setMethodCallHandler
                        }

                        val resolver = applicationContext.contentResolver
                        val contentValues = ContentValues().apply {
                            put(MediaStore.Images.Media.DISPLAY_NAME, title)
                            put(MediaStore.Images.Media.MIME_TYPE, mimeType)
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                                put(MediaStore.Images.Media.RELATIVE_PATH, Environment.DIRECTORY_PICTURES + File.separator + "Reranger")
                                put(MediaStore.Images.Media.IS_PENDING, 1)
                            }
                        }

                        val uri = resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, contentValues)
                        if (uri == null) {
                            result.error("INSERT_FAILED", "Failed to create MediaStore entry", null)
                            return@setMethodCallHandler
                        }

                        FileInputStream(srcFile).use { input ->
                            resolver.openOutputStream(uri).use { output ->
                                if (output == null) {
                                    result.error("STREAM_FAILED", "Failed to open MediaStore output stream", null)
                                    return@setMethodCallHandler
                                }
                                input.copyTo(output)
                            }
                        }

                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                            contentValues.clear()
                            contentValues.put(MediaStore.Images.Media.IS_PENDING, 0)
                            resolver.update(uri, contentValues, null, null)
                        }

                        result.success(uri.toString())
                    } catch (e: Exception) {
                        result.error("SAVE_FAILED", "Failed saving to gallery: ${e.message}", null)
                    }
                }
                "shareImage" -> {
                    val filePath = call.argument<String>("filePath")
                    val mimeType = call.argument<String>("mimeType") ?: "image/png"
                    val subject = call.argument<String>("subject") ?: "Share Image"

                    if (filePath == null) {
                        result.error("INVALID_ARGUMENT", "filePath must not be null", null)
                        return@setMethodCallHandler
                    }

                    try {
                        val file = File(filePath)
                        if (!file.exists()) {
                            result.error("FILE_NOT_FOUND", "File does not exist at $filePath", null)
                            return@setMethodCallHandler
                        }

                        val uri = FileProvider.getUriForFile(
                            this,
                            "${applicationContext.packageName}.fileprovider",
                            file
                        )

                        val shareIntent = Intent(Intent.ACTION_SEND).apply {
                            type = mimeType
                            putExtra(Intent.EXTRA_STREAM, uri)
                            putExtra(Intent.EXTRA_SUBJECT, subject)
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        }

                        val chooser = Intent.createChooser(shareIntent, subject)
                        chooser.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(chooser)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SHARE_FAILED", "Failed to invoke system share: ${e.message}", null)
                    }
                }
                else -> result.notImplemented()
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
