package com.hermesagent.hermes_mobile

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class AssistantOverlayActivity : FlutterActivity() {
    private val CHANNEL = "hermes/assistant"

    override fun getInitialRoute(): String {
        return "/assistant_overlay"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "dismiss") {
                finish()
                result.success(null)
            } else {
                result.notImplemented()
            }
        }
    }
}
