package com.samionyx.ppg_recorder_app

import android.graphics.ImageFormat
import android.media.Image
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaExtractor
import android.media.MediaFormat
import java.io.File
import java.io.IOException
import java.nio.ByteBuffer
import kotlin.math.max
import kotlin.math.min

/** Failure with a stable error code forwarded to Dart. */
class VideoDecodeException(val code: String, message: String) : Exception(message)

/** Per-frame ROI channel means of a decoded video plus decode details. */
class DecodedSignal(
    private val timestampsUs: LongArray,
    private val red: DoubleArray,
    private val green: DoubleArray,
    private val blue: DoubleArray,
    private val width: Int,
    private val height: Int,
    private val rotationDegrees: Int,
    private val durationUs: Long,
    private val colorConversion: String,
    private val decoderName: String,
) {
    /** Method-channel representation (typed arrays map to Int64List/Float64List). */
    fun toMap(): Map<String, Any> = mapOf(
        "timestampsUs" to timestampsUs,
        "red" to red,
        "green" to green,
        "blue" to blue,
        "width" to width,
        "height" to height,
        "rotationDegrees" to rotationDegrees,
        "durationUs" to durationUs,
        "colorConversion" to colorConversion,
        "decoderName" to decoderName,
    )
}

/**
 * Decodes every frame of a video with MediaExtractor + MediaCodec and
 * averages R/G/B over a centred [roiSize] x [roiSize] square — the same ROI
 * the Sphygma app uses. Timestamps are the container presentation times.
 *
 * YUV→RGB uses the matrix (BT.601 / BT.709 / BT.2020) and range
 * (full / limited) reported by the decoder, so channel values are correct
 * for the actual encoding rather than assumed.
 */
class VideoSignalDecoder(private val roiSize: Int) {

    private companion object {
        const val TIMEOUT_US = 10_000L
        const val MAX_IDLE_ITERATIONS = 1_500 // ~15-30 s without progress
        const val PROGRESS_EVERY_FRAMES = 10
    }

    /** One plane of a YUV frame with its addressing parameters. */
    private class Plane(
        val buffer: ByteBuffer,
        val offset: Int,
        val rowStride: Int,
        val pixelStride: Int,
    ) {
        private val limit = buffer.limit()

        /** Unsigned byte at (x, y) in this plane's own coordinates, or -1. */
        fun at(x: Int, y: Int): Int {
            val index = offset + y * rowStride + x * pixelStride
            return if (index in 0 until limit) buffer.get(index).toInt() and 0xFF else -1
        }
    }

    /** YUV→RGB coefficients. */
    private class YuvMatrix(
        val yOffset: Double,
        val yScale: Double,
        val rV: Double,
        val gU: Double,
        val gV: Double,
        val bU: Double,
        val description: String,
    )

    fun decode(path: String, onProgress: (Double) -> Unit): DecodedSignal {
        val file = File(path)
        if (!file.exists() || file.length() == 0L) {
            throw VideoDecodeException("FILE_NOT_FOUND", "Video file is missing or empty.")
        }

        val extractor = MediaExtractor()
        var codec: MediaCodec? = null
        try {
            extractor.setDataSource(path)
            var trackIndex = -1
            var inputFormat: MediaFormat? = null
            for (i in 0 until extractor.trackCount) {
                val format = extractor.getTrackFormat(i)
                if (format.getString(MediaFormat.KEY_MIME)?.startsWith("video/") == true) {
                    trackIndex = i
                    inputFormat = format
                    break
                }
            }
            if (trackIndex < 0 || inputFormat == null) {
                throw VideoDecodeException("NO_VIDEO_TRACK", "The file contains no video track.")
            }
            extractor.selectTrack(trackIndex)

            val mime = inputFormat.getString(MediaFormat.KEY_MIME)!!
            val durationUs = if (inputFormat.containsKey(MediaFormat.KEY_DURATION)) {
                inputFormat.getLong(MediaFormat.KEY_DURATION)
            } else 0L
            val rotation = if (inputFormat.containsKey(MediaFormat.KEY_ROTATION)) {
                inputFormat.getInteger(MediaFormat.KEY_ROTATION)
            } else 0

            inputFormat.setInteger(
                MediaFormat.KEY_COLOR_FORMAT,
                MediaCodecInfo.CodecCapabilities.COLOR_FormatYUV420Flexible,
            )
            val decoder = MediaCodec.createDecoderByType(mime)
            codec = decoder
            decoder.configure(inputFormat, null, null, 0)
            decoder.start()

            var outputFormat: MediaFormat = decoder.outputFormat
            var matrix = resolveMatrix(outputFormat, inputFormat)
            val timestamps = ArrayList<Long>(1024)
            val reds = ArrayList<Double>(1024)
            val greens = ArrayList<Double>(1024)
            val blues = ArrayList<Double>(1024)
            var frameWidth = 0
            var frameHeight = 0

            val info = MediaCodec.BufferInfo()
            var inputDone = false
            var outputDone = false
            var idle = 0

            while (!outputDone) {
                var progressed = false

                if (!inputDone) {
                    val inIndex = decoder.dequeueInputBuffer(TIMEOUT_US)
                    if (inIndex >= 0) {
                        val buffer = decoder.getInputBuffer(inIndex)
                            ?: throw VideoDecodeException("DECODER_ERROR", "No input buffer.")
                        val size = extractor.readSampleData(buffer, 0)
                        if (size < 0) {
                            decoder.queueInputBuffer(
                                inIndex, 0, 0, 0L, MediaCodec.BUFFER_FLAG_END_OF_STREAM,
                            )
                            inputDone = true
                        } else {
                            decoder.queueInputBuffer(inIndex, 0, size, extractor.sampleTime, 0)
                            extractor.advance()
                        }
                        progressed = true
                    }
                }

                val outIndex = decoder.dequeueOutputBuffer(info, TIMEOUT_US)
                when {
                    outIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                        outputFormat = decoder.outputFormat
                        matrix = resolveMatrix(outputFormat, inputFormat)
                        progressed = true
                    }
                    outIndex >= 0 -> {
                        progressed = true
                        try {
                            val isConfig = info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0
                            if (info.size > 0 && !isConfig) {
                                val rgb = sampleOutput(decoder, outIndex, outputFormat, matrix)
                                timestamps.add(info.presentationTimeUs)
                                reds.add(rgb[0])
                                greens.add(rgb[1])
                                blues.add(rgb[2])
                                frameWidth = rgb[3].toInt()
                                frameHeight = rgb[4].toInt()
                                if (durationUs > 0 && timestamps.size % PROGRESS_EVERY_FRAMES == 0) {
                                    onProgress(
                                        (info.presentationTimeUs.toDouble() / durationUs)
                                            .coerceIn(0.0, 1.0),
                                    )
                                }
                            }
                        } finally {
                            decoder.releaseOutputBuffer(outIndex, false)
                        }
                        if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) {
                            outputDone = true
                        }
                    }
                }

                if (progressed) {
                    idle = 0
                } else if (++idle > MAX_IDLE_ITERATIONS) {
                    throw VideoDecodeException("DECODER_TIMEOUT", "The video decoder stopped responding.")
                }
            }

            if (timestamps.isEmpty()) {
                throw VideoDecodeException("NO_FRAMES", "No frames could be decoded from the video.")
            }
            onProgress(1.0)

            return DecodedSignal(
                timestampsUs = timestamps.toLongArray(),
                red = reds.toDoubleArray(),
                green = greens.toDoubleArray(),
                blue = blues.toDoubleArray(),
                width = frameWidth,
                height = frameHeight,
                rotationDegrees = rotation,
                durationUs = durationUs,
                colorConversion = matrix.description,
                decoderName = decoder.name,
            )
        } catch (e: VideoDecodeException) {
            throw e
        } catch (e: IOException) {
            throw VideoDecodeException("IO_ERROR", e.message ?: "Could not read the video file.")
        } catch (e: MediaCodec.CodecException) {
            throw VideoDecodeException("DECODER_ERROR", e.diagnosticInfo ?: e.toString())
        } catch (e: RuntimeException) {
            throw VideoDecodeException("DECODER_ERROR", e.message ?: e.toString())
        } finally {
            try {
                codec?.stop()
            } catch (ignored: Exception) {
            }
            try {
                codec?.release()
            } catch (ignored: Exception) {
            }
            extractor.release()
        }
    }

    /**
     * Returns [r, g, b, width, height] for output buffer [index], reading the
     * frame through the flexible [Image] API or, if unavailable, the raw
     * buffer for the standard planar / semi-planar layouts.
     */
    private fun sampleOutput(
        codec: MediaCodec,
        index: Int,
        format: MediaFormat,
        matrix: YuvMatrix,
    ): DoubleArray {
        val image: Image? = try {
            codec.getOutputImage(index)
        } catch (ignored: Exception) {
            null
        }
        if (image != null) {
            image.use {
                if (it.format == ImageFormat.YUV_420_888 && it.planes.size >= 3) {
                    val crop = it.cropRect
                    val p = it.planes
                    val rgb = sampleRoi(
                        crop.left, crop.top, crop.right, crop.bottom,
                        Plane(p[0].buffer, 0, p[0].rowStride, p[0].pixelStride),
                        Plane(p[1].buffer, 0, p[1].rowStride, p[1].pixelStride),
                        Plane(p[2].buffer, 0, p[2].rowStride, p[2].pixelStride),
                        matrix,
                    )
                    return doubleArrayOf(
                        rgb[0], rgb[1], rgb[2], crop.width().toDouble(), crop.height().toDouble(),
                    )
                }
            }
        }
        return sampleRawBuffer(codec, index, format, matrix)
    }

    private fun sampleRawBuffer(
        codec: MediaCodec,
        index: Int,
        format: MediaFormat,
        matrix: YuvMatrix,
    ): DoubleArray {
        val buffer = codec.getOutputBuffer(index)
            ?: throw VideoDecodeException("DECODER_ERROR", "No output buffer.")
        val colorFormat = format.getIntegerOr(MediaFormat.KEY_COLOR_FORMAT, -1)
        val width = format.getInteger(MediaFormat.KEY_WIDTH)
        val height = format.getInteger(MediaFormat.KEY_HEIGHT)
        val stride = max(format.getIntegerOr(MediaFormat.KEY_STRIDE, width), width)
        val sliceHeight = max(format.getIntegerOr(MediaFormat.KEY_SLICE_HEIGHT, height), height)
        val left = format.getIntegerOr("crop-left", 0)
        val top = format.getIntegerOr("crop-top", 0)
        val right = format.getIntegerOr("crop-right", width - 1) + 1
        val bottom = format.getIntegerOr("crop-bottom", height - 1) + 1
        val base = buffer.position()
        val lumaSize = stride * sliceHeight
        val y = Plane(buffer, base, stride, 1)

        val (u, v) = when (colorFormat) {
            MediaCodecInfo.CodecCapabilities.COLOR_FormatYUV420SemiPlanar,
            MediaCodecInfo.CodecCapabilities.COLOR_FormatYUV420PackedSemiPlanar -> Pair(
                Plane(buffer, base + lumaSize, stride, 2),
                Plane(buffer, base + lumaSize + 1, stride, 2),
            )
            MediaCodecInfo.CodecCapabilities.COLOR_FormatYUV420Planar,
            MediaCodecInfo.CodecCapabilities.COLOR_FormatYUV420PackedPlanar -> {
                val chromaStride = stride / 2
                val chromaSize = chromaStride * (sliceHeight / 2)
                Pair(
                    Plane(buffer, base + lumaSize, chromaStride, 1),
                    Plane(buffer, base + lumaSize + chromaSize, chromaStride, 1),
                )
            }
            else -> throw VideoDecodeException(
                "UNSUPPORTED_COLOR_FORMAT",
                "Decoder output colour format $colorFormat is not supported.",
            )
        }
        val rgb = sampleRoi(left, top, right, bottom, y, u, v, matrix)
        return doubleArrayOf(
            rgb[0], rgb[1], rgb[2], (right - left).toDouble(), (bottom - top).toDouble(),
        )
    }

    /** Mean RGB over the centred ROI of the visible rectangle [left, right) x [top, bottom). */
    private fun sampleRoi(
        left: Int, top: Int, right: Int, bottom: Int,
        y: Plane, u: Plane, v: Plane,
        m: YuvMatrix,
    ): DoubleArray {
        val half = roiSize / 2
        val cx = (left + right) / 2
        val cy = (top + bottom) / 2
        val x0 = max(left, cx - half)
        val x1 = min(right, cx + half)
        val y0 = max(top, cy - half)
        val y1 = min(bottom, cy + half)
        var rSum = 0.0
        var gSum = 0.0
        var bSum = 0.0
        var count = 0
        for (row in y0 until y1) {
            for (col in x0 until x1) {
                val luma = y.at(col, row)
                val cb = u.at(col / 2, row / 2)
                val cr = v.at(col / 2, row / 2)
                if (luma < 0 || cb < 0 || cr < 0) continue
                val yy = (luma - m.yOffset) * m.yScale
                val du = cb - 128.0
                val dv = cr - 128.0
                rSum += (yy + m.rV * dv).coerceIn(0.0, 255.0)
                gSum += (yy - m.gU * du - m.gV * dv).coerceIn(0.0, 255.0)
                bSum += (yy + m.bU * du).coerceIn(0.0, 255.0)
                count++
            }
        }
        if (count == 0) {
            throw VideoDecodeException("EMPTY_ROI", "The region of interest contained no pixels.")
        }
        return doubleArrayOf(rSum / count, gSum / count, bSum / count)
    }

    /** Picks the YUV→RGB matrix from decoder / container colour metadata. */
    private fun resolveMatrix(output: MediaFormat, input: MediaFormat): YuvMatrix {
        val standard = output.getIntegerOrNull(MediaFormat.KEY_COLOR_STANDARD)
            ?: input.getIntegerOrNull(MediaFormat.KEY_COLOR_STANDARD)
        val range = output.getIntegerOrNull(MediaFormat.KEY_COLOR_RANGE)
            ?: input.getIntegerOrNull(MediaFormat.KEY_COLOR_RANGE)
        val height = input.getIntegerOr(MediaFormat.KEY_HEIGHT, 0)
        val width = input.getIntegerOr(MediaFormat.KEY_WIDTH, 0)

        val assumed = standard == null || range == null
        val std = standard ?: if (min(width, height) >= 720) {
            MediaFormat.COLOR_STANDARD_BT709
        } else {
            MediaFormat.COLOR_STANDARD_BT601_NTSC
        }
        val full = (range ?: MediaFormat.COLOR_RANGE_LIMITED) == MediaFormat.COLOR_RANGE_FULL

        // Full-range chroma coefficients (Kr/Kb from each standard).
        val (name, rV, gU, gV, bU) = when (std) {
            MediaFormat.COLOR_STANDARD_BT709 ->
                Coeffs("BT.709", 1.5748, 0.187324, 0.468124, 1.8556)
            MediaFormat.COLOR_STANDARD_BT2020 ->
                Coeffs("BT.2020", 1.4746, 0.164553, 0.571353, 1.8814)
            else -> Coeffs("BT.601", 1.402, 0.344136, 0.714136, 1.772)
        }
        val chromaScale = if (full) 1.0 else 255.0 / 224.0
        val source = if (assumed) "assumed" else "from stream metadata"
        return YuvMatrix(
            yOffset = if (full) 0.0 else 16.0,
            yScale = if (full) 1.0 else 255.0 / 219.0,
            rV = rV * chromaScale,
            gU = gU * chromaScale,
            gV = gV * chromaScale,
            bU = bU * chromaScale,
            description = "$name ${if (full) "full" else "limited"}-range YUV to RGB " +
                "($source; Android MediaCodec)",
        )
    }

    private data class Coeffs(
        val name: String,
        val rV: Double,
        val gU: Double,
        val gV: Double,
        val bU: Double,
    )

    private fun MediaFormat.getIntegerOrNull(key: String): Int? =
        if (containsKey(key)) {
            try {
                getInteger(key)
            } catch (ignored: Exception) {
                null
            }
        } else null

    private fun MediaFormat.getIntegerOr(key: String, fallback: Int): Int =
        getIntegerOrNull(key) ?: fallback
}
