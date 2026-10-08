package com.hermesagent.hermes_mobile

import android.app.Activity
import android.app.role.RoleManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Lets Flutter query and request the system "digital assistant" role so the user
 * can make Hermes their phone's default assistant.
 *
 * The assistant OS plumbing (VoiceInteractionService, ASSIST intent, overlay,
 * recognition service) is already declared in the manifest — this only adds the
 * enrollment/status flow that was missing.
 *
 * Mirrors [HermesAudioPlugin]'s object/bind pattern. Because requesting the role
 * needs an Activity result, [MainActivity] forwards [onActivityResult] here.
 */
object AssistantRolePlugin {
    private const val CHANNEL = "hermes/assistant_role"
    const val REQUEST_ROLE = 0xA551 // "ASSI"

    private var pendingResult: MethodChannel.Result? = null

    fun bind(engine: FlutterEngine, activity: Activity) {
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "isDefaultAssistant" -> result.success(isDefaultAssistant(activity))
                "requestAssistantRole" -> requestAssistantRole(activity, result)
                "openAssistantSettings" -> result.success(openAssistantSettings(activity))
                else -> result.notImplemented()
            }
        }
    }

    /** True when Hermes currently holds the assistant role. */
    private fun isDefaultAssistant(context: Context): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val roleManager = context.getSystemService(RoleManager::class.java)
            if (roleManager != null && roleManager.isRoleAvailable(RoleManager.ROLE_ASSISTANT)) {
                return roleManager.isRoleHeld(RoleManager.ROLE_ASSISTANT)
            }
        }
        // Pre-Q / role unavailable: compare the secure "voice_interaction_service"
        // setting against our VoiceInteractionService component.
        return try {
            val current = Settings.Secure.getString(
                context.contentResolver, "voice_interaction_service",
            ) ?: return false
            val ours = ComponentName(
                context.packageName,
                "${context.packageName}.HermesVoiceInteractionService",
            )
            val flattened = current.contains(context.packageName) &&
                (current == ours.flattenToString() || current == ours.flattenToShortString())
            flattened || current.contains("${context.packageName}/")
        } catch (e: SecurityException) {
            false
        }
    }

    /**
     * Launches the system role-request dialog when possible. Returns immediately
     * with `"unsupported"` when the OEM/OS does not expose ROLE_ASSISTANT as
     * user-requestable, so Dart can fall back to [openAssistantSettings].
     * Otherwise the boolean granted/denied result is delivered from
     * [onActivityResult].
     */
    private fun requestAssistantRole(activity: Activity, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            result.success("unsupported")
            return
        }
        val roleManager = activity.getSystemService(RoleManager::class.java)
        if (roleManager == null || !roleManager.isRoleAvailable(RoleManager.ROLE_ASSISTANT)) {
            result.success("unsupported")
            return
        }
        if (roleManager.isRoleHeld(RoleManager.ROLE_ASSISTANT)) {
            result.success("granted")
            return
        }
        // Only one request in flight; replace any stale pending result.
        pendingResult?.success("cancelled")
        pendingResult = result
        try {
            val intent = roleManager.createRequestRoleIntent(RoleManager.ROLE_ASSISTANT)
            activity.startActivityForResult(intent, REQUEST_ROLE)
        } catch (e: Exception) {
            pendingResult = null
            result.success("unsupported")
        }
    }

    /** Opens the OS assistant/voice-input picker so the user can select Hermes. */
    private fun openAssistantSettings(context: Context): Boolean {
        val candidates = listOf(
            Settings.ACTION_VOICE_INPUT_SETTINGS,
            "android.settings.MANAGE_DEFAULT_APPS_SETTINGS",
        )
        for (action in candidates) {
            try {
                val intent = Intent(action).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                context.startActivity(intent)
                return true
            } catch (e: Exception) {
                // Try the next candidate.
            }
        }
        return false
    }

    /** Forwarded from MainActivity.onActivityResult. */
    fun onActivityResult(requestCode: Int, resultCode: Int) {
        if (requestCode != REQUEST_ROLE) return
        val result = pendingResult ?: return
        pendingResult = null
        result.success(if (resultCode == Activity.RESULT_OK) "granted" else "denied")
    }
}
