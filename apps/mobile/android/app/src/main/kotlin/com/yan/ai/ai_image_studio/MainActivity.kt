package com.yan.ai.ai_image_studio

import android.content.Context
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraExtensionCharacteristics
import android.hardware.camera2.CameraManager
import android.os.Build
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "yan.camera/capabilities",
        ).setMethodCallHandler { call, result ->
            if (call.method != "getCapabilities") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            runCatching { cameraCapabilities() }
                .onSuccess(result::success)
                .onFailure { result.error("camera-capabilities", it.message, null) }
        }
    }

    private fun cameraCapabilities(): Map<String, Any> {
        val manager = getSystemService(Context.CAMERA_SERVICE) as CameraManager
        val lensTypes = linkedSetOf<String>()
        val extensionModes = linkedSetOf<String>()
        var hasFlash = false
        var supportsMultiCamera = false

        manager.cameraIdList.forEach { cameraId ->
            val characteristics = manager.getCameraCharacteristics(cameraId)
            hasFlash = hasFlash ||
                (characteristics.get(CameraCharacteristics.FLASH_INFO_AVAILABLE) == true)
            when (characteristics.get(CameraCharacteristics.LENS_FACING)) {
                CameraCharacteristics.LENS_FACING_FRONT -> lensTypes += "front"
                CameraCharacteristics.LENS_FACING_BACK -> lensTypes += "back"
                CameraCharacteristics.LENS_FACING_EXTERNAL -> lensTypes += "external"
            }
            val capabilities = characteristics.get(
                CameraCharacteristics.REQUEST_AVAILABLE_CAPABILITIES,
            ) ?: intArrayOf()
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P &&
                capabilities.contains(
                    CameraCharacteristics.REQUEST_AVAILABLE_CAPABILITIES_LOGICAL_MULTI_CAMERA,
                )
            ) {
                supportsMultiCamera = true
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val extensions = manager
                    .getCameraExtensionCharacteristics(cameraId)
                    .supportedExtensions
                extensions.forEach { extension ->
                    extensionModes += when (extension) {
                        CameraExtensionCharacteristics.EXTENSION_AUTOMATIC -> "auto"
                        CameraExtensionCharacteristics.EXTENSION_BOKEH -> "portrait"
                        CameraExtensionCharacteristics.EXTENSION_FACE_RETOUCH -> "retouch"
                        CameraExtensionCharacteristics.EXTENSION_HDR -> "hdr"
                        CameraExtensionCharacteristics.EXTENSION_NIGHT -> "night"
                        else -> "extension-$extension"
                    }
                }
            }
        }
        return mapOf(
            "platform" to "android",
            "lensTypes" to lensTypes.toList(),
            "extensionModes" to extensionModes.toList(),
            "hasFlash" to hasFlash,
            "supportsMultiCamera" to supportsMultiCamera,
        )
    }
}
