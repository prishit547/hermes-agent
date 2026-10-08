package com.hermesagent.hermes_mobile.nowplaying

import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.ServiceCompat

/**
 * A `mediaPlayback` foreground service that keeps Hermes music playback alive
 * while the app is backgrounded or the screen is locked, and hosts the
 * lock-screen media notification built by [NowPlayingController].
 *
 * The actual audio player lives in the Flutter engine (just_audio). This service
 * exists purely to (a) hold the foreground promise so Android won't kill the
 * process, and (b) relay media-button intents to the controller's MediaSession.
 */
class NowPlayingService : Service() {
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val notification = NowPlayingController.buildNotification(this)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            ServiceCompat.startForeground(
                this,
                NowPlayingController.NOTIF_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK,
            )
        } else {
            startForeground(NowPlayingController.NOTIF_ID, notification)
        }
        if (intent != null) NowPlayingController.handleMediaButton(intent)
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
        super.onDestroy()
    }
}
