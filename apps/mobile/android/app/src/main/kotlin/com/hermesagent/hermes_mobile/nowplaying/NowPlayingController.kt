package com.hermesagent.hermes_mobile.nowplaying

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.support.v4.media.MediaMetadataCompat
import android.support.v4.media.session.MediaSessionCompat
import android.support.v4.media.session.PlaybackStateCompat
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.media.session.MediaButtonReceiver
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.Executors

/**
 * Android side of the Hermes music "now playing" bridge (MethodChannel
 * `hermes/now_playing`). Owns a [MediaSessionCompat] + a MediaStyle notification
 * so playback shows on the lock screen / Quick Settings / headset, and — via
 * [NowPlayingService] — a `mediaPlayback` foreground service that keeps music
 * alive while backgrounded.
 *
 * Transport buttons are forwarded to Dart; the app controls the actual player.
 */
object NowPlayingController {
    private const val CHANNEL = "hermes/now_playing"
    private const val NOTIF_CHANNEL_ID = "hermes_now_playing"
    const val NOTIF_ID = 0x1D2E

    private var appContext: Context? = null
    private var channel: MethodChannel? = null
    private var session: MediaSessionCompat? = null
    private var started = false

    private var title = "Hermes"
    private var artist: String? = null
    private var durationMs = 0L
    private var positionMs = 0L
    private var playing = false
    private var hasNext = false
    private var hasPrev = false

    private var artUrl: String? = null
    private var artBitmap: Bitmap? = null
    private val io = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    fun init(context: Context, messenger: BinaryMessenger) {
        appContext = context.applicationContext
        channel?.setMethodCallHandler(null)
        channel = MethodChannel(messenger, CHANNEL).also { ch ->
            ch.setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> { start(); result.success(null) }
                    "stop" -> { stop(); result.success(null) }
                    "clear" -> { clearTile(); result.success(null) }
                    "update" -> {
                        @Suppress("UNCHECKED_CAST")
                        update(call.arguments as? Map<String, Any?> ?: emptyMap())
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    private fun start() {
        val ctx = appContext ?: return
        ensureSession(ctx)
        createNotifChannel(ctx)
        started = true
        val intent = Intent(ctx, NowPlayingService::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            ctx.startForegroundService(intent)
        } else {
            ctx.startService(intent)
        }
    }

    private fun stop() {
        val ctx = appContext
        started = false
        artUrl = null
        artBitmap = null
        if (ctx != null) ctx.stopService(Intent(ctx, NowPlayingService::class.java))
        session?.isActive = false
        session?.release()
        session = null
    }

    private fun clearTile() {
        title = "Hermes"
        artist = "Nothing playing"
        durationMs = 0
        positionMs = 0
        playing = false
        hasNext = false
        hasPrev = false
        artUrl = null
        artBitmap = null
        pushSessionState()
        refreshNotification()
    }

    private fun ensureSession(ctx: Context): MediaSessionCompat {
        session?.let { return it }
        val s = MediaSessionCompat(ctx, "HermesNowPlaying")
        s.setCallback(object : MediaSessionCompat.Callback() {
            override fun onPlay() = send("play")
            override fun onPause() = send("pause")
            override fun onStop() = send("pause")
            override fun onSkipToNext() = send("next")
            override fun onSkipToPrevious() = send("previous")
            override fun onSeekTo(pos: Long) =
                send("seek", mapOf("positionMs" to pos.toInt()))
        })
        s.isActive = true
        session = s
        return s
    }

    private fun send(method: String, args: Any? = null) {
        main.post { channel?.invokeMethod(method, args) }
    }

    private fun update(args: Map<String, Any?>) {
        title = (args["title"] as? String) ?: "Hermes"
        artist = args["artist"] as? String
        durationMs = (args["durationMs"] as? Number)?.toLong() ?: 0
        positionMs = (args["positionMs"] as? Number)?.toLong() ?: 0
        playing = (args["playing"] as? Boolean) ?: false
        hasNext = (args["hasNext"] as? Boolean) ?: false
        hasPrev = (args["hasPrev"] as? Boolean) ?: false
        val newArt = args["artworkUrl"] as? String
        if (newArt != artUrl) {
            artUrl = newArt
            artBitmap = null
            if (newArt != null) loadArt(newArt)
        }
        pushSessionState()
        refreshNotification()
    }

    private fun pushSessionState() {
        val s = session ?: return
        val meta = MediaMetadataCompat.Builder()
            .putString(MediaMetadataCompat.METADATA_KEY_TITLE, title)
            .putString(MediaMetadataCompat.METADATA_KEY_ARTIST, artist ?: "")
        if (durationMs > 0) meta.putLong(MediaMetadataCompat.METADATA_KEY_DURATION, durationMs)
        artBitmap?.let { meta.putBitmap(MediaMetadataCompat.METADATA_KEY_ALBUM_ART, it) }
        s.setMetadata(meta.build())

        var actions = PlaybackStateCompat.ACTION_PLAY or
            PlaybackStateCompat.ACTION_PAUSE or
            PlaybackStateCompat.ACTION_PLAY_PAUSE or
            PlaybackStateCompat.ACTION_SEEK_TO
        if (hasNext) actions = actions or PlaybackStateCompat.ACTION_SKIP_TO_NEXT
        if (hasPrev) actions = actions or PlaybackStateCompat.ACTION_SKIP_TO_PREVIOUS
        val state = if (playing) PlaybackStateCompat.STATE_PLAYING else PlaybackStateCompat.STATE_PAUSED
        s.setPlaybackState(
            PlaybackStateCompat.Builder()
                .setActions(actions)
                .setState(state, positionMs, if (playing) 1f else 0f)
                .build()
        )
    }

    private fun refreshNotification() {
        val ctx = appContext ?: return
        if (!started) return
        try {
            NotificationManagerCompat.from(ctx).notify(NOTIF_ID, buildNotification(ctx))
        } catch (_: SecurityException) {
            // POST_NOTIFICATIONS denied — FGS still keeps playback alive, just no UI.
        }
    }

    fun buildNotification(ctx: Context): Notification {
        val s = ensureSession(ctx)
        val actions = mutableListOf<NotificationCompat.Action>()
        if (hasPrev) actions.add(action(ctx, android.R.drawable.ic_media_previous, "Previous", PlaybackStateCompat.ACTION_SKIP_TO_PREVIOUS))
        actions.add(
            if (playing) action(ctx, android.R.drawable.ic_media_pause, "Pause", PlaybackStateCompat.ACTION_PAUSE)
            else action(ctx, android.R.drawable.ic_media_play, "Play", PlaybackStateCompat.ACTION_PLAY)
        )
        if (hasNext) actions.add(action(ctx, android.R.drawable.ic_media_next, "Next", PlaybackStateCompat.ACTION_SKIP_TO_NEXT))

        val compact = when {
            hasPrev && hasNext -> intArrayOf(0, 1, 2)
            hasPrev || hasNext -> intArrayOf(0, 1)
            else -> intArrayOf(0)
        }

        val style = androidx.media.app.NotificationCompat.MediaStyle()
            .setMediaSession(s.sessionToken)
            .setShowActionsInCompactView(*compact)

        val builder = NotificationCompat.Builder(ctx, NOTIF_CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(artist ?: "")
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setStyle(style)
            .setOngoing(true)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setCategory(NotificationCompat.CATEGORY_TRANSPORT)
            .setOnlyAlertOnce(true)
        artBitmap?.let { builder.setLargeIcon(it) }
        ctx.packageManager.getLaunchIntentForPackage(ctx.packageName)?.let { launch ->
            builder.setContentIntent(
                PendingIntent.getActivity(
                    ctx, 0, launch,
                    PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
                )
            )
        }
        actions.forEach { builder.addAction(it) }
        return builder.build()
    }

    private fun action(
        ctx: Context,
        icon: Int,
        label: String,
        playbackAction: Long,
    ): NotificationCompat.Action {
        val intent = MediaButtonReceiver.buildMediaButtonPendingIntent(ctx, playbackAction)
        return NotificationCompat.Action.Builder(icon, label, intent).build()
    }

    fun handleMediaButton(intent: Intent) {
        session?.let { MediaButtonReceiver.handleIntent(it, intent) }
    }

    private fun createNotifChannel(ctx: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val mgr = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (mgr.getNotificationChannel(NOTIF_CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            NOTIF_CHANNEL_ID,
            "Music Playback",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "Playback controls while music is playing"
            setShowBadge(false)
            setSound(null, null)
            enableVibration(false)
        }
        mgr.createNotificationChannel(channel)
    }

    private fun loadArt(url: String) {
        io.execute {
            try {
                val conn = (URL(url).openConnection() as HttpURLConnection).apply {
                    connectTimeout = 8000
                    readTimeout = 8000
                    doInput = true
                }
                conn.connect()
                val bmp = conn.inputStream.use { BitmapFactory.decodeStream(it) }
                conn.disconnect()
                main.post {
                    if (bmp != null && url == artUrl) {
                        artBitmap = bmp
                        pushSessionState()
                        refreshNotification()
                    }
                }
            } catch (_: Exception) {
                // Art is best-effort; the tile still shows text + controls.
            }
        }
    }
}
