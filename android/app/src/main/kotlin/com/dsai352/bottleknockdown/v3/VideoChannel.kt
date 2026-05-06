package com.dsai352.bottleknockdown.v3

import android.graphics.*
import android.media.*
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

class VideoChannel : MethodChannel.MethodCallHandler {

    private val executor = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "extractFrames" -> {
                val videoPath = call.argument<String>("videoPath")!!
                val outputDir  = call.argument<String>("outputDir")!!
                val fps        = call.argument<Int>("fps") ?: 5
                // Max pixel dimension for extracted frames (shorter Dart decode)
                val maxDim     = call.argument<Int>("maxDim") ?: 640
                executor.execute {
                    try {
                        val count = extractFrames(videoPath, outputDir, fps, maxDim)
                        main.post { result.success(count) }
                    } catch (e: Exception) {
                        Log.e("VideoChannel", "extractFrames error", e)
                        main.post { result.error("EXTRACT_ERROR", e.message, null) }
                    }
                }
            }
            "annotateAndEncode" -> {
                val framesDir  = call.argument<String>("framesDir")!!
                val outputPath = call.argument<String>("outputPath")!!
                val fps        = call.argument<Int>("fps") ?: 5
                @Suppress("UNCHECKED_CAST")
                val annotations = call.argument<List<Map<String, Any>>>("annotations") ?: emptyList()
                executor.execute {
                    try {
                        annotateAndEncode(framesDir, outputPath, fps, annotations)
                        main.post { result.success(null) }
                    } catch (e: Exception) {
                        Log.e("VideoChannel", "annotateAndEncode error", e)
                        main.post { result.error("ENCODE_ERROR", e.message, null) }
                    }
                }
            }
            else -> result.notImplemented()
        }
    }

    // -------------------------------------------------------------------------
    // Frame extraction — 5 fps, resized to maxDim px (fast Dart decode later)
    // -------------------------------------------------------------------------

    private fun extractFrames(videoPath: String, outputDir: String, fps: Int, maxDim: Int): Int {
        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(videoPath)
            val durationMs = retriever.extractMetadata(
                MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLong() ?: 0L
            val rotation = retriever.extractMetadata(
                MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)?.toIntOrNull() ?: 0
            val frameCount = (durationMs * fps / 1000).toInt()

            Log.i("VideoChannel", "extract: dur=${durationMs}ms frames=$frameCount fps=$fps maxDim=$maxDim rot=$rotation")

            var saved = 0
            for (i in 0 until frameCount) {
                val timeUs = i.toLong() * 1_000_000L / fps
                var bmp = retriever.getFrameAtTime(timeUs,
                    MediaMetadataRetriever.OPTION_CLOSEST) ?: continue

                // Rotate if needed
                if (rotation != 0) {
                    val m = Matrix().apply { postRotate(rotation.toFloat()) }
                    val rotated = Bitmap.createBitmap(bmp, 0, 0, bmp.width, bmp.height, m, true)
                    if (rotated != bmp) bmp.recycle()
                    bmp = rotated
                }

                // Downscale to maxDim — huge speedup for Dart JPEG decode
                val scale = maxDim.toFloat() / maxOf(bmp.width, bmp.height)
                if (scale < 1f) {
                    val scaled = Bitmap.createScaledBitmap(
                        bmp, (bmp.width * scale).toInt(), (bmp.height * scale).toInt(), true)
                    bmp.recycle()
                    bmp = scaled
                }

                val file = File("$outputDir/frame_${i.toString().padStart(6, '0')}.jpg")
                file.outputStream().use { bmp.compress(Bitmap.CompressFormat.JPEG, 85, it) }
                bmp.recycle()
                saved++
            }
            Log.i("VideoChannel", "extract: saved=$saved")
            saved
        } finally {
            retriever.release()
        }
    }

    // -------------------------------------------------------------------------
    // Native annotate + encode — draws overlays in Android Canvas (fast!)
    // then pipes directly into H.264 MediaCodec.  No Dart image ops needed.
    //
    // Annotation map format (per frame):
    //   'boxes'  : List<Map> each with l,t,r,b (double), label (String), cr/cg/cb (int)
    //   'car'    : Map with l,t,r,b (double) — omitted if no car
    //   'traj'   : List<Double> flat x0,y0,x1,y1,… trajectory points
    //   'fallen' : Int  — HUD fallen count
    //   'total'  : Int  — HUD total count
    // -------------------------------------------------------------------------

    private fun annotateAndEncode(
        framesDir: String,
        outputPath: String,
        fps: Int,
        annotations: List<Map<String, Any>>,
    ) {
        val files = File(framesDir).listFiles { _, n -> n.endsWith(".jpg") }
            ?.sortedBy { it.name }?.takeIf { it.isNotEmpty() } ?: return

        // Build frame-index → annotation lookup
        val annotByIdx = annotations.associateBy { (it["idx"] as? Int) ?: 0 }

        // Read first frame for dimensions
        val first = BitmapFactory.decodeFile(files[0].absolutePath)
        val W = first.width; val H = first.height
        first.recycle()

        // Paints
        val boxPaint  = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE; strokeWidth = 3f }
        val fillPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.FILL }
        val textPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.WHITE; textSize = H * 0.028f; typeface = Typeface.DEFAULT_BOLD
        }
        val trajPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.rgb(100, 150, 255); style = Paint.Style.STROKE
            strokeWidth = 4f; strokeJoin = Paint.Join.ROUND; strokeCap = Paint.Cap.ROUND
        }
        val hudBg = Paint().apply { color = Color.argb(180, 0, 0, 0) }
        val hudText = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.WHITE; textSize = H * 0.032f; typeface = Typeface.DEFAULT_BOLD
        }
        val hudRed = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.rgb(255, 100, 100); textSize = H * 0.032f; typeface = Typeface.DEFAULT_BOLD
        }

        // Encoder setup
        val format = MediaFormat.createVideoFormat(MediaFormat.MIMETYPE_VIDEO_AVC, W, H).apply {
            setInteger(MediaFormat.KEY_BIT_RATE, 4_000_000)
            setInteger(MediaFormat.KEY_FRAME_RATE, fps)
            setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1)
            setInteger(MediaFormat.KEY_COLOR_FORMAT,
                MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface)
        }
        val encoder = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_VIDEO_AVC)
        encoder.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
        val surface = encoder.createInputSurface()
        val muxer   = MediaMuxer(outputPath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)

        var trackIndex = -1; var muxerStarted = false
        val info = MediaCodec.BufferInfo()
        val frameDurUs = 1_000_000L / fps

        encoder.start()
        try {
            for ((idx, file) in files.withIndex()) {
                val orig = BitmapFactory.decodeFile(file.absolutePath) ?: continue
                val bmp  = orig.copy(Bitmap.Config.ARGB_8888, true)
                orig.recycle()

                val canvas = Canvas(bmp)
                val annot  = annotByIdx[idx]

                if (annot != null) {
                    @Suppress("UNCHECKED_CAST")

                    // Draw car trajectory
                    val traj = annot["traj"] as? List<Double>
                    if (traj != null && traj.size >= 4) {
                        val pts = FloatArray(traj.size) { traj[it].toFloat() }
                        for (k in 0 until pts.size - 2 step 2) {
                            canvas.drawLine(pts[k], pts[k+1], pts[k+2], pts[k+3], trajPaint)
                        }
                    }

                    // Draw bounding boxes
                    val boxes = annot["boxes"] as? List<Map<String, Any>>
                    boxes?.forEach { box ->
                        val l  = (box["l"] as? Double)?.toFloat() ?: 0f
                        val t  = (box["t"] as? Double)?.toFloat() ?: 0f
                        val r  = (box["r"] as? Double)?.toFloat() ?: 0f
                        val b  = (box["b"] as? Double)?.toFloat() ?: 0f
                        val cr = (box["cr"] as? Int) ?: 0
                        val cg = (box["cg"] as? Int) ?: 255
                        val cb = (box["cb"] as? Int) ?: 0
                        val label = (box["label"] as? String) ?: ""

                        boxPaint.color = Color.rgb(cr, cg, cb)
                        canvas.drawRect(l, t, r, b, boxPaint)

                        // Label background + text
                        val tw = textPaint.measureText(label)
                        val th = textPaint.textSize
                        val pad = 6f
                        fillPaint.color = Color.rgb(cr / 2, cg / 2, cb / 2)
                        canvas.drawRect(l, t - th - pad * 2, l + tw + pad * 2, t, fillPaint)
                        canvas.drawText(label, l + pad, t - pad, textPaint)
                    }

                    // Draw car box
                    val car = annot["car"] as? Map<String, Any>
                    if (car != null) {
                        val l = (car["l"] as? Double)?.toFloat() ?: 0f
                        val t = (car["t"] as? Double)?.toFloat() ?: 0f
                        val r = (car["r"] as? Double)?.toFloat() ?: 0f
                        val b = (car["b"] as? Double)?.toFloat() ?: 0f
                        boxPaint.color = Color.rgb(50, 100, 255)
                        canvas.drawRect(l, t, r, b, boxPaint)
                        fillPaint.color = Color.rgb(0, 50, 150)
                        val tw = textPaint.measureText("CAR")
                        canvas.drawRect(l, t - textPaint.textSize - 12f, l + tw + 12f, t, fillPaint)
                        canvas.drawText("CAR", l + 6f, t - 6f, textPaint)
                    }

                    // HUD panel
                    val fallen = (annot["fallen"] as? Int) ?: 0
                    val total  = (annot["total"]  as? Int) ?: 0
                    val hudH = hudText.textSize * 2 + 48f
                    canvas.drawRect(8f, 8f, 360f, 8f + hudH, hudBg)
                    canvas.drawText("Total: $total",    20f, 8f + hudText.textSize + 8f, hudText)
                    canvas.drawText("Knocked: $fallen", 20f, 8f + hudText.textSize * 2 + 24f, hudRed)
                }

                // Feed annotated bitmap → encoder surface
                val sc = surface.lockHardwareCanvas()
                sc.drawBitmap(bmp, 0f, 0f, null)
                surface.unlockCanvasAndPost(sc)
                bmp.recycle()

                drainEncoder(encoder, muxer, info, frameDurUs * idx,
                    trackIndex, muxerStarted).also { (ti, ms) ->
                    trackIndex = ti; muxerStarted = ms
                }
            }

            encoder.signalEndOfInputStream()
            drainEncoder(encoder, muxer, info, frameDurUs * files.size,
                trackIndex, muxerStarted, eos = true)
        } finally {
            encoder.stop(); encoder.release(); surface.release()
            if (muxerStarted) muxer.stop()
            muxer.release()
        }
    }

    private fun drainEncoder(
        encoder: MediaCodec, muxer: MediaMuxer, info: MediaCodec.BufferInfo,
        ptsUs: Long, trackIndexIn: Int, muxerStartedIn: Boolean, eos: Boolean = false,
    ): Pair<Int, Boolean> {
        var trackIndex = trackIndexIn; var muxerStarted = muxerStartedIn
        while (true) {
            val outIdx = encoder.dequeueOutputBuffer(info, 10_000L)
            when {
                outIdx == MediaCodec.INFO_TRY_AGAIN_LATER -> if (!eos) break else continue
                outIdx == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                    trackIndex = muxer.addTrack(encoder.outputFormat)
                    muxer.start(); muxerStarted = true
                }
                outIdx >= 0 -> {
                    if (muxerStarted && info.size > 0) {
                        info.presentationTimeUs = ptsUs
                        muxer.writeSampleData(trackIndex, encoder.getOutputBuffer(outIdx)!!, info)
                    }
                    encoder.releaseOutputBuffer(outIdx, false)
                    if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) break
                }
            }
        }
        return Pair(trackIndex, muxerStarted)
    }
}
