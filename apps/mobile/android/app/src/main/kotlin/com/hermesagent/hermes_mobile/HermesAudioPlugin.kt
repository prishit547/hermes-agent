package com.hermesagent.hermes_mobile

import android.content.Context
import android.media.AudioDeviceInfo
import android.media.AudioManager
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Exposes basic audio-routing control to Flutter so the voice-mode UI can
 * switch between speaker, earpiece and Bluetooth headset output.
 */
object HermesAudioPlugin {
    private const val CHANNEL = "hermes/audio"

    fun bind(engine: FlutterEngine, context: Context) {
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
            when (call.method) {
                "getAudioRoutes" -> result.success(getRoutes(audioManager))
                "setAudioOutput" -> {
                    val output = call.argument<String>("output")
                    result.success(setOutput(audioManager, output))
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun getRoutes(audioManager: AudioManager): List<Map<String, String>> {
        return try {
            val routes = mutableListOf<Map<String, String>>()
            routes.add(mapOf("id" to "speaker", "label" to "Speaker"))

            val hasBluetooth = audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS).any {
                it.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO ||
                it.type == AudioDeviceInfo.TYPE_BLUETOOTH_A2DP ||
                it.type == AudioDeviceInfo.TYPE_BLE_HEADSET
            }
            if (hasBluetooth) {
                routes.add(mapOf("id" to "bluetooth", "label" to "Bluetooth"))
            }
            routes.add(mapOf("id" to "earpiece", "label" to "Earpiece"))
            routes
        } catch (e: SecurityException) {
            listOf(
                mapOf("id" to "speaker", "label" to "Speaker"),
                mapOf("id" to "earpiece", "label" to "Earpiece")
            )
        }
    }

    private fun setOutput(audioManager: AudioManager, output: String?): Boolean {
        return try {
            audioManager.mode = AudioManager.MODE_IN_COMMUNICATION
            when (output) {
                "speaker" -> {
                    audioManager.stopBluetoothSco()
                    audioManager.isBluetoothScoOn = false
                    audioManager.isSpeakerphoneOn = true
                    true
                }
                "earpiece" -> {
                    audioManager.stopBluetoothSco()
                    audioManager.isBluetoothScoOn = false
                    audioManager.isSpeakerphoneOn = false
                    true
                }
                "bluetooth" -> {
                    audioManager.isSpeakerphoneOn = false
                    audioManager.startBluetoothSco()
                    audioManager.isBluetoothScoOn = true
                    true
                }
                else -> false
            }
        } catch (e: SecurityException) {
            false
        }
    }
}
