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
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.media.MediaMuxer
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.nio.ByteBuffer
import kotlin.concurrent.thread

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
                "saveVideoToGallery" -> {
                    val filePath = call.argument<String>("filePath")
                    val title = call.argument<String>("title") ?: "reranger_timelapse_${System.currentTimeMillis()}"
                    val mimeType = call.argument<String>("mimeType") ?: "video/mp4"

                    if (filePath == null) {
                        result.error("INVALID_ARGUMENT", "filePath must not be null", null)
                        return@setMethodCallHandler
                    }

                    try {
                        val srcFile = File(filePath)
                        if (!srcFile.exists()) {
                            result.error("FILE_NOT_FOUND", "Source video file does not exist at $filePath", null)
                            return@setMethodCallHandler
                        }

                        val resolver = applicationContext.contentResolver
                        val contentValues = ContentValues().apply {
                            put(MediaStore.Video.Media.DISPLAY_NAME, "$title.mp4")
                            put(MediaStore.Video.Media.MIME_TYPE, mimeType)
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                                put(MediaStore.Video.Media.RELATIVE_PATH, Environment.DIRECTORY_MOVIES + File.separator + "Reranger")
                                put(MediaStore.Video.Media.IS_PENDING, 1)
                            }
                        }

                        val uri = resolver.insert(MediaStore.Video.Media.EXTERNAL_CONTENT_URI, contentValues)
                        if (uri == null) {
                            result.error("INSERT_FAILED", "Failed to create MediaStore entry for video", null)
                            return@setMethodCallHandler
                        }

                        FileInputStream(srcFile).use { input ->
                            resolver.openOutputStream(uri).use { output ->
                                if (output == null) {
                                    result.error("STREAM_FAILED", "Failed to open MediaStore video output stream", null)
                                    return@setMethodCallHandler
                                }
                                input.copyTo(output)
                            }
                        }

                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                            contentValues.clear()
                            contentValues.put(MediaStore.Video.Media.IS_PENDING, 0)
                            resolver.update(uri, contentValues, null, null)
                        }

                        result.success(uri.toString())
                    } catch (e: Exception) {
                        result.error("SAVE_FAILED", "Failed saving video to gallery: ${e.message}", null)
                    }
                }
                "encodeFramesToMp4" -> {
                    val framePaths = call.argument<List<String>>("framePaths")
                    val outputPath = call.argument<String>("outputPath")
                    val width = call.argument<Int>("width") ?: 720
                    val height = call.argument<Int>("height") ?: 720
                    val fps = call.argument<Int>("fps") ?: 30
                    val bitRate = call.argument<Int>("bitRate") ?: 3_000_000

                    if (framePaths.isNullOrEmpty() || outputPath == null) {
                        result.error("INVALID_ARGUMENT", "framePaths and outputPath must not be empty", null)
                        return@setMethodCallHandler
                    }

                    thread {
                        try {
                            encodeFramesNative(framePaths, outputPath, width, height, fps, bitRate)
                            runOnUiThread { result.success(outputPath) }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("ENCODE_FAILED", "MediaCodec encoding failed: ${e.message}", null) }
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun encodeFramesNative(
        framePaths: List<String>,
        outputPath: String,
        width: Int,
        height: Int,
        fps: Int,
        bitRate: Int
    ) {
        val evenWidth = if (width % 2 != 0) width - 1 else width
        val evenHeight = if (height % 2 != 0) height - 1 else height

        val format = MediaFormat.createVideoFormat(MediaFormat.MIMETYPE_VIDEO_AVC, evenWidth, evenHeight).apply {
            setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatYUV420SemiPlanar)
            setInteger(MediaFormat.KEY_BIT_RATE, bitRate)
            setInteger(MediaFormat.KEY_FRAME_RATE, fps)
            setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1)
        }

        val encoder = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_VIDEO_AVC)
        encoder.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
        encoder.start()

        val muxer = MediaMuxer(outputPath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
        var trackIndex = -1
        var muxerStarted = false
        val bufferInfo = MediaCodec.BufferInfo()
        val frameDurationUs = (1_000_000L / fps)

        val yuvBuffer = ByteArray(evenWidth * evenHeight * 3 / 2)

        for ((index, path) in framePaths.withIndex()) {
            val bitmap = BitmapFactory.decodeFile(path) ?: continue
            val scaled = if (bitmap.width != evenWidth || bitmap.height != evenHeight) {
                Bitmap.createScaledBitmap(bitmap, evenWidth, evenHeight, true)
            } else {
                bitmap
            }

            // Convert ARGB to NV12 / YUV420SemiPlanar
            bitmapToNV12(scaled, evenWidth, evenHeight, yuvBuffer)
            if (scaled != bitmap) scaled.recycle()
            bitmap.recycle()

            val inputBufferIndex = encoder.dequeueInputBuffer(10_000)
            if (inputBufferIndex >= 0) {
                val inputBuffer = encoder.getInputBuffer(inputBufferIndex)
                inputBuffer?.clear()
                inputBuffer?.put(yuvBuffer)
                val presentationTimeUs = index * frameDurationUs
                val flags = if (index == framePaths.size - 1) MediaCodec.BUFFER_FLAG_END_OF_STREAM else 0
                encoder.queueInputBuffer(inputBufferIndex, 0, yuvBuffer.size, presentationTimeUs, flags)
            }

            // Drain output
            var outputIndex = encoder.dequeueOutputBuffer(bufferInfo, 2500)
            while (outputIndex >= 0) {
                val outBuffer = encoder.getOutputBuffer(outputIndex)
                if (bufferInfo.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0) {
                    bufferInfo.size = 0
                }
                if (bufferInfo.size > 0) {
                    if (!muxerStarted) {
                        trackIndex = muxer.addTrack(encoder.outputFormat)
                        muxer.start()
                        muxerStarted = true
                    }
                    if (outBuffer != null) {
                        outBuffer.position(bufferInfo.offset)
                        outBuffer.limit(bufferInfo.offset + bufferInfo.size)
                        muxer.writeSampleData(trackIndex, outBuffer, bufferInfo)
                    }
                }
                encoder.releaseOutputBuffer(outputIndex, false)
                outputIndex = encoder.dequeueOutputBuffer(bufferInfo, 0)
            }
        }

        encoder.stop()
        encoder.release()
        if (muxerStarted) {
            muxer.stop()
        }
        muxer.release()
    }

    private fun bitmapToNV12(bitmap: Bitmap, width: Int, height: Int, outYuv: ByteArray) {
        val argb = IntArray(width * height)
        bitmap.getPixels(argb, 0, width, 0, 0, width, height)

        var yIndex = 0
        var uvIndex = width * height

        for (j in 0 until height) {
            for (i in 0 until width) {
                val pixel = argb[j * width + i]
                val r = (pixel shr 16) and 0xff
                val g = (pixel shr 8) and 0xff
                val b = pixel and 0xff

                val y = ((66 * r + 129 * g + 25 * b + 128) shr 8) + 16
                outYuv[yIndex++] = y.coerceIn(0, 255).toByte()

                if (j % 2 == 0 && i % 2 == 0) {
                    val u = ((-38 * r - 74 * g + 112 * b + 128) shr 8) + 128
                    val v = ((112 * r - 94 * g - 18 * b + 128) shr 8) + 128
                    outYuv[uvIndex++] = u.coerceIn(0, 255).toByte()
                    outYuv[uvIndex++] = v.coerceIn(0, 255).toByte()
                }
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
