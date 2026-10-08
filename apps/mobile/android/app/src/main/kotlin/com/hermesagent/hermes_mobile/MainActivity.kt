package com.hermesagent.hermes_mobile

import android.content.Intent
import com.hermesagent.hermes_mobile.nowplaying.NowPlayingController
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        HermesAudioPlugin.bind(flutterEngine, this)
        AssistantRolePlugin.bind(flutterEngine, this)
        NowPlayingController.init(applicationContext, flutterEngine.dartExecutor.binaryMessenger)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        AssistantRolePlugin.onActivityResult(requestCode, resultCode)
    }
}
