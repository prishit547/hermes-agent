package com.hermesagent.hermes_mobile

import android.os.Build
import android.telecom.Connection
import android.telecom.DisconnectCause
import androidx.annotation.RequiresApi

@RequiresApi(Build.VERSION_CODES.M)
class HermesCallConnection : Connection() {

    init {
        connectionCapabilities = CAPABILITY_MUTE or CAPABILITY_SUPPORT_HOLD
        audioModeIsVoip = true
    }

    override fun onDisconnect() {
        super.onDisconnect()
        setDisconnected(DisconnectCause(DisconnectCause.LOCAL))
        destroy()
    }

    override fun onAbort() {
        super.onAbort()
        setDisconnected(DisconnectCause(DisconnectCause.CANCELED))
        destroy()
        setDisconnected(DisconnectCause(DisconnectCause.CANCELED))
    }
}
