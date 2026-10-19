package com.endless.tapocam

import android.util.Base64
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest
import java.security.SecureRandom
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

data class Preset(val token: String, val name: String)

class OnvifException(message: String) : Exception(message)

/**
 * Minimal ONVIF client for Tapo cameras (port 2020, camera-account credentials):
 * PTZ moves and presets. All calls block, so run them off the main thread.
 */
class Onvif(private val host: String, private val user: String, private val password: String) {
    private val deviceUrl = "http://$host:2020/onvif/device_service"
    private var ptzUrl = deviceUrl
    private var mediaUrl = deviceUrl
    private var profile: String? = null
    private var clockOffsetMs = 0L
    private var continuousSupported = true

    fun connect() {
        syncClock()
        val caps = post(deviceUrl, "<tds:GetCapabilities><tds:Category>All</tds:Category></tds:GetCapabilities>")
        xaddr(caps, "Media")?.let { mediaUrl = it }
        xaddr(caps, "PTZ")?.let { ptzUrl = it }
        val profiles = post(mediaUrl, "<trt:GetProfiles/>")
        profile = Regex("""Profiles[^>]*token="([^"]+)"""").find(profiles)?.groupValues?.get(1)
            ?: throw OnvifException("Camera returned no media profiles")
    }

    /** Starts moving at the given velocity (-1..1). Call [stop] when the key is released. */
    fun move(pan: Float, tilt: Float) {
        if (continuousSupported) {
            try {
                post(ptzUrl, """<tptz:ContinuousMove><tptz:ProfileToken>$profile</tptz:ProfileToken>
                    <tptz:Velocity><tt:PanTilt x="$pan" y="$tilt"/></tptz:Velocity></tptz:ContinuousMove>""")
                return
            } catch (e: OnvifException) {
                continuousSupported = false
            }
        }
        step(pan * 0.1f, tilt * 0.1f)
    }

    fun step(pan: Float, tilt: Float) {
        post(ptzUrl, """<tptz:RelativeMove><tptz:ProfileToken>$profile</tptz:ProfileToken>
            <tptz:Translation><tt:PanTilt x="$pan" y="$tilt"/></tptz:Translation></tptz:RelativeMove>""")
    }

    fun stop() {
        if (!continuousSupported) return
        post(ptzUrl, """<tptz:Stop><tptz:ProfileToken>$profile</tptz:ProfileToken>
            <tptz:PanTilt>true</tptz:PanTilt><tptz:Zoom>false</tptz:Zoom></tptz:Stop>""")
    }

    fun presets(): List<Preset> {
        val xml = post(ptzUrl, "<tptz:GetPresets><tptz:ProfileToken>$profile</tptz:ProfileToken></tptz:GetPresets>")
        return Regex("""<[\w-]*:?Preset\b[^>]*token="([^"]+)"[^>]*>.*?<[\w-]*:?Name>([^<]*)</""", RegexOption.DOT_MATCHES_ALL)
            .findAll(xml).map { Preset(it.groupValues[1], unescape(it.groupValues[2])) }.toList()
    }

    fun gotoPreset(p: Preset) {
        post(ptzUrl, """<tptz:GotoPreset><tptz:ProfileToken>$profile</tptz:ProfileToken>
            <tptz:PresetToken>${escape(p.token)}</tptz:PresetToken></tptz:GotoPreset>""")
    }

    fun savePreset(name: String) {
        post(ptzUrl, """<tptz:SetPreset><tptz:ProfileToken>$profile</tptz:ProfileToken>
            <tptz:PresetName>${escape(name)}</tptz:PresetName></tptz:SetPreset>""")
    }

    fun removePreset(p: Preset) {
        post(ptzUrl, """<tptz:RemovePreset><tptz:ProfileToken>$profile</tptz:ProfileToken>
            <tptz:PresetToken>${escape(p.token)}</tptz:PresetToken></tptz:RemovePreset>""")
    }

    // WS-Security digests include a timestamp, so align with the camera's clock first.
    private fun syncClock() {
        try {
            val xml = post(deviceUrl, "<tds:GetSystemDateAndTime/>", auth = false)
            val utc = Regex("""UTCDateTime>(.*?)</[\w:]*UTCDateTime""", RegexOption.DOT_MATCHES_ALL).find(xml)?.groupValues?.get(1) ?: return
            fun field(n: String) = Regex("""$n>(\d+)<""").find(utc)?.groupValues?.get(1)?.toInt() ?: 0
            val cal = java.util.Calendar.getInstance(TimeZone.getTimeZone("UTC")).apply {
                clear()
                set(field("Year"), field("Month") - 1, field("Day"), field("Hour"), field("Minute"), field("Second"))
            }
            clockOffsetMs = cal.timeInMillis - System.currentTimeMillis()
        } catch (_: Exception) {
        }
    }

    private fun xaddr(caps: String, service: String): String? =
        Regex("""<[\w-]*:?$service>\s*<[\w-]*:?XAddr>([^<]+)<""").find(caps)?.groupValues?.get(1)?.trim()

    private fun security(): String {
        val nonce = ByteArray(16).also { SecureRandom().nextBytes(it) }
        val created = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.US)
            .apply { timeZone = TimeZone.getTimeZone("UTC") }
            .format(Date(System.currentTimeMillis() + clockOffsetMs))
        val sha = MessageDigest.getInstance("SHA-1")
        sha.update(nonce); sha.update(created.toByteArray()); sha.update(password.toByteArray())
        val digest = Base64.encodeToString(sha.digest(), Base64.NO_WRAP)
        return """<s:Header><Security s:mustUnderstand="1" xmlns="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-secext-1.0.xsd">
            <UsernameToken><Username>${escape(user)}</Username>
            <Password Type="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-username-token-profile-1.0#PasswordDigest">$digest</Password>
            <Nonce EncodingType="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-soap-message-security-1.0#Base64Binary">${Base64.encodeToString(nonce, Base64.NO_WRAP)}</Nonce>
            <Created xmlns="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-utility-1.0.xsd">$created</Created>
            </UsernameToken></Security></s:Header>"""
    }

    private fun post(url: String, body: String, auth: Boolean = true): String {
        val envelope = """<?xml version="1.0" encoding="UTF-8"?>
            <s:Envelope xmlns:s="http://www.w3.org/2003/05/soap-envelope"
              xmlns:tds="http://www.onvif.org/ver10/device/wsdl" xmlns:trt="http://www.onvif.org/ver10/media/wsdl"
              xmlns:tptz="http://www.onvif.org/ver20/ptz/wsdl" xmlns:tt="http://www.onvif.org/ver10/schema">
            ${if (auth) security() else ""}<s:Body>$body</s:Body></s:Envelope>"""
        val conn = (URL(url).openConnection() as HttpURLConnection).apply {
            requestMethod = "POST"
            connectTimeout = 4000
            readTimeout = 6000
            doOutput = true
            setRequestProperty("Content-Type", "application/soap+xml; charset=utf-8")
        }
        try {
            conn.outputStream.use { it.write(envelope.toByteArray()) }
            val code = conn.responseCode
            val text = (if (code in 200..299) conn.inputStream else conn.errorStream)?.bufferedReader()?.use { it.readText() } ?: ""
            if (code !in 200..299 || text.contains(":Fault>")) {
                val reason = Regex("""<[\w-]*:?Text[^>]*>([^<]+)<""").find(text)?.groupValues?.get(1)
                if (code == 401 || text.contains("NotAuthorized", true))
                    throw OnvifException("Camera rejected the camera account username/password")
                throw OnvifException(reason ?: "ONVIF error HTTP $code")
            }
            return text
        } catch (e: OnvifException) {
            throw e
        } catch (e: Exception) {
            throw OnvifException("Can't reach camera control (${e.message})")
        } finally {
            conn.disconnect()
        }
    }

    private fun escape(s: String) = s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("\"", "&quot;")
    private fun unescape(s: String) = s.replace("&lt;", "<").replace("&gt;", ">").replace("&quot;", "\"").replace("&amp;", "&")
}
