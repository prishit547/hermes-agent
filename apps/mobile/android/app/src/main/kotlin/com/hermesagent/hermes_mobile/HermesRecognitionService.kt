package com.hermesagent.hermes_mobile

import android.content.Intent
import android.speech.RecognitionService

class HermesRecognitionService : RecognitionService() {
    override fun onStartListening(intent: Intent?, callback: Callback?) {
        // Minimal stub: speech recognition is handled in Flutter/Dart
    }

    override fun onCancel(callback: Callback?) {
        // Minimal stub
    }

    override fun onStopListening(callback: Callback?) {
        // Minimal stub
    }
}
