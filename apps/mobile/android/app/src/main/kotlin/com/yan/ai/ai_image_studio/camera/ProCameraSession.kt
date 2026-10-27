package com.yan.ai.ai_image_studio.camera

import android.app.Activity
import android.content.Context
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.hardware.camera2.CaptureRequest
import android.hardware.camera2.params.RggbChannelVector
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Size
import android.view.Surface
import androidx.camera.camera2.interop.Camera2CameraControl
import androidx.camera.camera2.interop.Camera2CameraInfo
import androidx.camera.camera2.interop.CaptureRequestOptions
import androidx.camera.core.Camera
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageCapture
import androidx.camera.core.ImageCaptureException
import androidx.camera.core.Preview
import androidx.camera.core.resolutionselector.AspectRatioStrategy
import androidx.camera.core.resolutionselector.ResolutionSelector
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.lifecycle.LifecycleOwner
import com.google.common.util.concurrent.ListenableFuture
import io.flutter.view.TextureRegistry
import java.io.File
import java.util.concurrent.ExecutionException
import java.util.concurrent.Executor
import kotlin.math.ln
import kotlin.math.pow

/**
 * P0 专业模式会话：CameraX 预览 + 自动拍照。
 *
 * 手动参数会在 P1 通过 Camera2CameraControl.addCaptureRequestOptions 接入，
 * 当前先验证与 camera 插件会话互斥切换、纹理预览和 JPEG 输出。
 */
class ProCameraSession(
    private val context: Context,
    private val lifecycleOwner: LifecycleOwner,
    private val textureRegistry: TextureRegistry,
) {
    private val mainExecutor: Executor = Executor { command ->
        Handler(Looper.getMainLooper()).post(command)
    }

    private var provider: ProcessCameraProvider? = null
    private var preview: Preview? = null
    private var imageCapture: ImageCapture? = null
    private var surfaceProducer: TextureRegistry.SurfaceProducer? = null
    private var camera: Camera? = null
    private var manualControl: Camera2CameraControl? = null
    private var characteristics: CameraCharacteristics? = null
    private var closed = false

    fun open(lensId: String?, callback: (Map<String, Any>?, Throwable?) -> Unit) {
        if (closed) {
            callback(null, IllegalStateException("session already closed"))
            return
        }
        val future = ProcessCameraProvider.getInstance(context)
        future.addListener({
            try {
                val cameraProvider = future.get()
                // 插件会话必须先释放，否则同一个相机无法被两个 provider 打开。
                cameraProvider.unbindAll()

                val previewUseCase = Preview.Builder()
                    .setTargetRotation(displayRotation())
                    .setResolutionSelector(
                        ResolutionSelector.Builder()
                            .setAspectRatioStrategy(
                                AspectRatioStrategy.RATIO_4_3_FALLBACK_AUTO_STRATEGY
                            )
                            .build()
                    )
                    .build()
                val captureUseCase = ImageCapture.Builder()
                    .setCaptureMode(ImageCapture.CAPTURE_MODE_MINIMIZE_LATENCY)
                    .setTargetRotation(displayRotation())
                    .build()

                val producer = textureRegistry.createSurfaceProducer()
                producer.setSize(DEFAULT_WIDTH, DEFAULT_HEIGHT)
                previewUseCase.setSurfaceProvider(mainExecutor) { request ->
                    if (closed) {
                        request.willNotProvideSurface()
                        return@setSurfaceProvider
                    }
                    val resolution = request.resolution
                    producer.setSize(resolution.width, resolution.height)
                    request.provideSurface(
                        producer.surface,
                        mainExecutor,
                    ) { _ ->
                        // Surface 由 SurfaceProducer 统一释放，单次请求结束无需处理。
                    }
                }

                val boundCamera = cameraProvider.bindToLifecycle(
                    lifecycleOwner,
                    buildSelector(lensId),
                    previewUseCase,
                    captureUseCase,
                )
                if (closed) {
                    runCatching { cameraProvider.unbindAll() }
                    runCatching { producer.release() }
                    callback(null, IllegalStateException("session closed while opening"))
                    return@addListener
                }

                provider = cameraProvider
                preview = previewUseCase
                imageCapture = captureUseCase
                surfaceProducer = producer
                camera = boundCamera

                val resolution = previewUseCase.resolutionInfo?.resolution
                    ?: Size(DEFAULT_WIDTH, DEFAULT_HEIGHT)
                val zoomState = boundCamera.cameraInfo.zoomState.value
                val camera2Info = Camera2CameraInfo.from(boundCamera.cameraInfo)
                val cameraCharacteristics =
                    (context.getSystemService(Context.CAMERA_SERVICE) as CameraManager)
                        .getCameraCharacteristics(camera2Info.cameraId)
                val isoRange = cameraCharacteristics.get(
                    CameraCharacteristics.SENSOR_INFO_SENSITIVITY_RANGE
                )
                val shutterRange = cameraCharacteristics.get(
                    CameraCharacteristics.SENSOR_INFO_EXPOSURE_TIME_RANGE
                )
                val minFocusDiopters = cameraCharacteristics.get(
                    CameraCharacteristics.LENS_INFO_MINIMUM_FOCUS_DISTANCE
                ) ?: 0f
                val awbModes = cameraCharacteristics.get(
                    CameraCharacteristics.CONTROL_AWB_AVAILABLE_MODES
                ) ?: intArrayOf()
                val capabilities = cameraCharacteristics.get(
                    CameraCharacteristics.REQUEST_AVAILABLE_CAPABILITIES
                ) ?: intArrayOf()
                val supportsManual = capabilities.contains(
                    CameraCharacteristics.REQUEST_AVAILABLE_CAPABILITIES_MANUAL_SENSOR
                ) && awbModes.contains(CaptureRequest.CONTROL_AWB_MODE_OFF)

                manualControl = Camera2CameraControl.from(boundCamera.cameraControl)
                characteristics = cameraCharacteristics
                callback(
                    mapOf(
                        "textureId" to producer.id(),
                        "width" to resolution.width,
                        "height" to resolution.height,
                        "sensorOrientation" to
                            boundCamera.cameraInfo.sensorRotationDegrees,
                        "minZoom" to (zoomState?.minZoomRatio?.toDouble() ?: 1.0),
                        "maxZoom" to (zoomState?.maxZoomRatio?.toDouble() ?: 1.0),
                        "supportsManual" to supportsManual,
                        "minIso" to (isoRange?.lower ?: 0),
                        "maxIso" to (isoRange?.upper ?: 0),
                        "minShutterSeconds" to
                            ((shutterRange?.lower ?: 0L) / NANOS_PER_SECOND),
                        "maxShutterSeconds" to
                            ((shutterRange?.upper ?: 0L) / NANOS_PER_SECOND),
                        "minFocusDiopters" to 0.0,
                        "maxFocusDiopters" to minFocusDiopters.toDouble(),
                        "minKelvin" to 2000,
                        "maxKelvin" to 8000,
                    ),
                    null,
                )
            } catch (error: Throwable) {
                cleanup()
                callback(null, error)
            }
        }, mainExecutor)
    }

    fun capture(callback: (String?, Throwable?) -> Unit) {
        val captureUseCase = imageCapture
        if (captureUseCase == null) {
            callback(null, IllegalStateException("session not open"))
            return
        }
        val directory = File(context.cacheDir, "pro-camera").apply { mkdirs() }
        val file = File(directory, "pro-${System.currentTimeMillis()}.jpg")
        val options = ImageCapture.OutputFileOptions.Builder(file).build()
        captureUseCase.takePicture(
            options,
            mainExecutor,
            object : ImageCapture.OnImageSavedCallback {
                override fun onImageSaved(
                    outputFileResults: ImageCapture.OutputFileResults,
                ) {
                    callback(file.absolutePath, null)
                }

                override fun onError(exception: ImageCaptureException) {
                    callback(null, exception)
                }
            },
        )
    }

    fun close() {
        if (closed) return
        closed = true
        cleanup()
    }

    /**
     * 下发专业参数。手动模式关闭 AE，使用 ISO + 快门；半自动只锁 AWB/AF。
     */
    fun setManual(settings: Map<String, Any?>, callback: (Throwable?) -> Unit) {
        val control = manualControl
        val cameraCharacteristics = characteristics
        if (control == null || cameraCharacteristics == null) {
            callback(IllegalStateException("session not open"))
            return
        }
        val mode = settings["mode"] as? String ?: "auto"
        try {
            if (mode == "auto") {
                awaitFuture(control.clearCaptureRequestOptions(), callback)
                return
            }

            val builder = CaptureRequestOptions.Builder()
            if (mode == "manual") {
                val isoRange = cameraCharacteristics.get(
                    CameraCharacteristics.SENSOR_INFO_SENSITIVITY_RANGE
                ) ?: throw IllegalStateException("ISO range unavailable")
                val shutterRange = cameraCharacteristics.get(
                    CameraCharacteristics.SENSOR_INFO_EXPOSURE_TIME_RANGE
                ) ?: throw IllegalStateException("exposure range unavailable")
                val iso = ((settings["iso"] as? Number)?.toInt() ?: isoRange.lower)
                    .coerceIn(isoRange.lower, isoRange.upper)
                val shutterSeconds = (settings["shutterSeconds"] as? Number)?.toDouble()
                    ?: (1.0 / 60.0)
                val exposureNs = (shutterSeconds * NANOS_PER_SECOND).toLong()
                    .coerceIn(shutterRange.lower, shutterRange.upper)
                builder.setCaptureRequestOption(
                    CaptureRequest.CONTROL_AE_MODE,
                    CaptureRequest.CONTROL_AE_MODE_OFF,
                )
                builder.setCaptureRequestOption(
                    CaptureRequest.SENSOR_SENSITIVITY,
                    iso,
                )
                builder.setCaptureRequestOption(
                    CaptureRequest.SENSOR_EXPOSURE_TIME,
                    exposureNs,
                )
            } else {
                builder.setCaptureRequestOption(
                    CaptureRequest.CONTROL_AE_MODE,
                    CaptureRequest.CONTROL_AE_MODE_ON,
                )
            }

            val focusMax = cameraCharacteristics.get(
                CameraCharacteristics.LENS_INFO_MINIMUM_FOCUS_DISTANCE
            ) ?: 0f
            if (focusMax > 0f) {
                val focus = ((settings["focus"] as? Number)?.toDouble() ?: 0.5)
                    .coerceIn(0.0, 1.0)
                builder.setCaptureRequestOption(
                    CaptureRequest.CONTROL_AF_MODE,
                    CaptureRequest.CONTROL_AF_MODE_OFF,
                )
                builder.setCaptureRequestOption(
                    CaptureRequest.LENS_FOCUS_DISTANCE,
                    (focus * focusMax).toFloat(),
                )
            }

            val kelvin = (settings["kelvin"] as? Number)?.toDouble() ?: 5200.0
            val gains = kelvinToGains(kelvin)
            builder.setCaptureRequestOption(
                CaptureRequest.CONTROL_AWB_MODE,
                CaptureRequest.CONTROL_AWB_MODE_OFF,
            )
            builder.setCaptureRequestOption(
                CaptureRequest.COLOR_CORRECTION_GAINS,
                RggbChannelVector(gains.first, 1f, 1f, gains.third),
            )
            awaitFuture(
                control.setCaptureRequestOptions(builder.build()),
                callback,
            )
        } catch (error: Throwable) {
            callback(error)
        }
    }

    private fun awaitFuture(
        future: ListenableFuture<*>,
        callback: (Throwable?) -> Unit,
    ) {
        future.addListener({
            try {
                future.get()
                callback(null)
            } catch (error: ExecutionException) {
                callback(error.cause ?: error)
            } catch (error: Throwable) {
                callback(error)
            }
        }, mainExecutor)
    }

    /** Tanner Helland 近似：Kelvin -> RGB 白点，再归一化为 R/G/B 增益。 */
    private fun kelvinToGains(kelvin: Double): Triple<Float, Float, Float> {
        val temp = kelvin.coerceIn(2000.0, 8000.0) / 100.0
        val red: Double
        val green: Double
        val blue: Double
        if (temp <= 66.0) {
            red = 255.0
            green = 99.4708025861 * ln(temp) - 161.1195681661
            blue = if (temp <= 19.0) {
                0.0
            } else {
                138.5177312231 * ln(temp - 10.0) - 305.0447927307
            }
        } else {
            red = 329.698727446 * (temp - 60.0).pow(-0.1332047592)
            green = 288.1221695283 * (temp - 60.0).pow(-0.0755148492)
            blue = 255.0
        }
        val r = (red / 255.0).coerceIn(0.1, 4.0)
        val g = (green / 255.0).coerceIn(0.1, 4.0)
        val b = (blue / 255.0).coerceIn(0.1, 4.0)
        return Triple((r / g).toFloat(), 1f, (b / g).toFloat())
    }

    private fun cleanup() {
        runCatching { provider?.unbindAll() }
        surfaceProducer?.release()
        surfaceProducer = null
        preview = null
        imageCapture = null
        camera = null
        manualControl = null
        characteristics = null
        provider = null
    }

    private fun buildSelector(lensId: String?): CameraSelector {
        if (lensId.isNullOrBlank()) return CameraSelector.DEFAULT_BACK_CAMERA
        return CameraSelector.Builder()
            .addCameraFilter { cameraInfos ->
                cameraInfos.filter { info ->
                    Camera2CameraInfo.from(info).cameraId == lensId
                }
            }
            .build()
    }

    @Suppress("DEPRECATION")
    private fun displayRotation(): Int {
        val activity = context as? Activity
        val display = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            activity?.display
        } else {
            activity?.windowManager?.defaultDisplay
        }
        return display?.rotation ?: Surface.ROTATION_0
    }

    private companion object {
        const val DEFAULT_WIDTH = 1280
        const val DEFAULT_HEIGHT = 960
        const val NANOS_PER_SECOND = 1_000_000_000.0
    }
}
