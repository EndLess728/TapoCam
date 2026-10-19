package com.endless.tapocam

import android.content.Context

class Prefs(context: Context) {
    private val sp = context.getSharedPreferences("camera", Context.MODE_PRIVATE)

    var host: String
        get() = sp.getString("host", "") ?: ""
        set(v) = sp.edit().putString("host", v.trim()).apply()
    var user: String
        get() = sp.getString("user", "") ?: ""
        set(v) = sp.edit().putString("user", v.trim()).apply()
    var password: String
        get() = sp.getString("password", "") ?: ""
        set(v) = sp.edit().putString("password", v).apply()
    var highQuality: Boolean
        get() = sp.getBoolean("hq", true)
        set(v) = sp.edit().putBoolean("hq", v).apply()
    var muted: Boolean
        get() = sp.getBoolean("muted", true)
        set(v) = sp.edit().putBoolean("muted", v).apply()

    val isConfigured get() = host.isNotEmpty() && user.isNotEmpty() && password.isNotEmpty()

    fun rtspUrl(): String {
        val u = android.net.Uri.encode(user)
        val p = android.net.Uri.encode(password)
        return "rtsp://$u:$p@$host:554/${if (highQuality) "stream1" else "stream2"}"
    }
}
