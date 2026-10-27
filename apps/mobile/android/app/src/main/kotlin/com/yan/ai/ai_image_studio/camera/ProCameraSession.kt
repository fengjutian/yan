package com.yan.ai.ai_image_studio.camera

import android.app.Activity
import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Size
import android.view.Surface
import androidx.camera.camera2.interop.Camera2CameraInfo
import androidx.camera.core.Camera
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageCapture
import androidx.camera.core.ImageCaptureException
import androidx.camera.core.Preview
import androidx.camera.core.resolutionselector.AspectRatioStrategy
import androidx.camera.core.resolutionselector.ResolutionSelector
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.lifecycle.LifecycleOwner
import io.flutter.view.TextureRegistry
import java.io.File
import java.util.concurrent.Executor

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
                    cameraProvider.unbindAll()
                    producer.release()
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
                callback(
                    mapOf(
                        "textureId" to producer.id(),
                        "width" to resolution.width,
                        "height" to resolution.height,
                        "sensorOrientation" to
                            boundCamera.cameraInfo.sensorRotationDegrees,
                        "minZoom" to (zoomState?.minZoomRatio?.toDouble() ?: 1.0),
                        "maxZoom" to (zoomState?.maxZoomRatio?.toDouble() ?: 1.0),
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

    private fun cleanup() {
        runCatching { provider?.unbindAll() }
        surfaceProducer?.release()
        surfaceProducer = null
        preview = null
        imageCapture = null
        camera = null
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
    }
}
