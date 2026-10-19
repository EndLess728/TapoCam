package com.endless.tapocam

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.view.KeyEvent
import android.view.View
import android.view.WindowManager
import android.widget.Button
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.TextView
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.rtsp.RtspMediaSource
import androidx.media3.ui.PlayerView
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.asCoroutineDispatcher
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.util.concurrent.Executors

class MainActivity : AppCompatActivity() {
    private lateinit var prefs: Prefs
    private lateinit var playerView: PlayerView
    private lateinit var status: TextView
    private lateinit var spinner: ProgressBar
    private lateinit var hint: TextView
    private lateinit var panel: View
    private lateinit var menu: LinearLayout
    private lateinit var toast: TextView

    private var player: ExoPlayer? = null
    private var onvif: Onvif? = null
    private var presets: List<Preset> = emptyList()
    private var controlError: String? = null
    private var failures = 0

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    // One thread keeps camera commands in order (move → stop).
    private val camThread = Executors.newSingleThreadExecutor().asCoroutineDispatcher()
    private val retry = Runnable { startStream() }
    private val hideHint = Runnable { hint.animate().alpha(0f).duration = 600 }
    private val hideToast = Runnable { toast.visibility = View.GONE }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        setContentView(R.layout.activity_main)
        prefs = Prefs(this)
        playerView = findViewById(R.id.player)
        status = findViewById(R.id.status)
        spinner = findViewById(R.id.spinner)
        hint = findViewById(R.id.hint)
        panel = findViewById(R.id.panel)
        menu = findViewById(R.id.menu)
        toast = findViewById(R.id.toast)
        applyIntentConfig(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if (applyIntentConfig(intent)) connect()
    }

    /** Lets the Mac push settings: adb shell am start -n com.endless.tapocam/.MainActivity --es host … --es user … --es password … */
    private fun applyIntentConfig(intent: Intent?): Boolean {
        val host = intent?.getStringExtra("host") ?: return false
        prefs.host = host
        intent.getStringExtra("user")?.let { prefs.user = it }
        intent.getStringExtra("password")?.let { prefs.password = it }
        return true
    }

    override fun onStart() {
        super.onStart()
        if (!prefs.isConfigured) {
            startActivity(Intent(this, SettingsActivity::class.java))
            return
        }
        connect()
    }

    override fun onStop() {
        super.onStop()
        playerView.removeCallbacks(retry)
        player?.release()
        player = null
    }

    override fun onDestroy() {
        super.onDestroy()
        scope.cancel()
        camThread.close()
    }

    private fun connect() {
        failures = 0
        startStream()
        connectControls()
        showHint()
    }

    // region Video

    private fun startStream() {
        playerView.removeCallbacks(retry)
        player?.release()
        showStatus(getString(R.string.connecting, prefs.host), busy = true)

        val loadControl = DefaultLoadControl.Builder()
            .setBufferDurationsMs(500, 2000, 250, 250)
            .build()
        val p = ExoPlayer.Builder(this).setLoadControl(loadControl).build()
        p.volume = if (prefs.muted) 0f else 1f
        val source = RtspMediaSource.Factory()
            .setForceUseRtpTcp(true)
            .setTimeoutMs(8000)
            .createMediaSource(MediaItem.fromUri(Uri.parse(prefs.rtspUrl())))
        p.setMediaSource(source)
        p.addListener(object : Player.Listener {
            override fun onPlaybackStateChanged(state: Int) {
                if (state == Player.STATE_READY) {
                    failures = 0
                    hideStatus()
                }
                if (state == Player.STATE_ENDED) scheduleRetry(getString(R.string.stream_ended))
            }

            override fun onPlayerError(error: PlaybackException) {
                scheduleRetry(explain(error), isAuthError(error))
            }
        })
        p.playWhenReady = true
        p.prepare()
        playerView.player = p
        player = p
    }

    /**
     * Tapo cameras block an IP for a while after repeated failed logins — and keep blocking while the
     * attempts continue — so auth failures wait a minute and other failures back off gradually.
     */
    private fun scheduleRetry(message: String, authError: Boolean = false) {
        failures++
        val delaySec = if (authError) 60 else minOf(3 shl minOf(failures - 1, 4), 30)
        showStatus("$message\n\n${getString(R.string.retrying_in, delaySec)}", busy = false)
        playerView.removeCallbacks(retry)
        playerView.postDelayed(retry, delaySec * 1000L)
    }

    private fun isAuthError(e: PlaybackException) =
        generateSequence(e as Throwable) { it.cause }.any { "401" in (it.message ?: "") || "Unauthorized" in (it.message ?: "") }

    private fun explain(e: PlaybackException): String {
        val text = generateSequence(e as Throwable) { it.cause }.joinToString(" ") { it.message ?: "" }
        return when {
            isAuthError(e) -> getString(R.string.err_auth)
            e.errorCode == PlaybackException.ERROR_CODE_IO_NETWORK_CONNECTION_FAILED ||
                e.errorCode == PlaybackException.ERROR_CODE_IO_NETWORK_CONNECTION_TIMEOUT ||
                "timed out" in text || "ECONNREFUSED" in text || "EHOSTUNREACH" in text -> getString(R.string.err_unreachable, prefs.host)
            else -> e.errorCodeName + (e.message?.let { ": $it" } ?: "")
        }
    }

    private fun showStatus(text: String, busy: Boolean) {
        status.text = text
        status.visibility = View.VISIBLE
        spinner.visibility = if (busy) View.VISIBLE else View.GONE
    }

    private fun hideStatus() {
        status.visibility = View.GONE
        spinner.visibility = View.GONE
    }

    // endregion

    // region Camera control

    private fun connectControls() {
        val cam = Onvif(prefs.host, prefs.user, prefs.password)
        onvif = null
        scope.launch {
            try {
                withContext(camThread) { cam.connect() }
                onvif = cam
                controlError = null
                presets = withContext(camThread) { runCatching { cam.presets() }.getOrDefault(emptyList()) }
            } catch (e: Exception) {
                controlError = e.message
            }
            if (panel.visibility == View.VISIBLE) buildMenu()
        }
    }

    private fun camera(action: Onvif.() -> Unit) {
        val cam = onvif ?: run { flash(controlError ?: getString(R.string.controls_not_ready)); return }
        scope.launch {
            try {
                withContext(camThread) { cam.action() }
            } catch (e: Exception) {
                flash(e.message ?: "Camera error")
            }
        }
    }

    private fun refreshPresets() {
        val cam = onvif ?: return
        scope.launch {
            presets = withContext(camThread) { runCatching { cam.presets() }.getOrDefault(presets) }
            if (panel.visibility == View.VISIBLE) buildMenu()
        }
    }

    // endregion

    // region Remote keys

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (panel.visibility == View.VISIBLE) {
            if (event.keyCode == KeyEvent.KEYCODE_BACK || event.keyCode == KeyEvent.KEYCODE_MENU) {
                if (event.action == KeyEvent.ACTION_UP) closePanel()
                return true
            }
            return super.dispatchKeyEvent(event)
        }
        val dir = when (event.keyCode) {
            KeyEvent.KEYCODE_DPAD_UP -> 0f to 1f
            KeyEvent.KEYCODE_DPAD_DOWN -> 0f to -1f
            KeyEvent.KEYCODE_DPAD_LEFT -> -1f to 0f
            KeyEvent.KEYCODE_DPAD_RIGHT -> 1f to 0f
            else -> null
        }
        if (dir != null) {
            if (event.action == KeyEvent.ACTION_DOWN && event.repeatCount == 0) {
                showHint()
                camera { move(dir.first * 0.5f, dir.second * 0.5f) }
            } else if (event.action == KeyEvent.ACTION_UP) {
                camera { stop() }
            }
            return true
        }
        when (event.keyCode) {
            KeyEvent.KEYCODE_DPAD_CENTER, KeyEvent.KEYCODE_ENTER, KeyEvent.KEYCODE_MENU -> {
                if (event.action == KeyEvent.ACTION_UP) openPanel()
                return true
            }
        }
        return super.dispatchKeyEvent(event)
    }

    private fun showHint() {
        hint.removeCallbacks(hideHint)
        hint.alpha = 1f
        hint.postDelayed(hideHint, 4000)
    }

    private fun flash(message: String) {
        toast.text = message
        toast.visibility = View.VISIBLE
        toast.removeCallbacks(hideToast)
        toast.postDelayed(hideToast, 3500)
    }

    // endregion

    // region Side menu

    private fun openPanel() {
        buildMenu()
        panel.visibility = View.VISIBLE
        (0 until menu.childCount).map { menu.getChildAt(it) }.firstOrNull { it is Button }?.requestFocus()
        refreshPresets()
    }

    private fun closePanel() {
        panel.visibility = View.GONE
    }

    private fun buildMenu() {
        val focusedTag = currentFocus?.tag
        menu.removeAllViews()
        header(getString(R.string.presets))
        when {
            onvif == null && controlError != null -> note(controlError!!)
            onvif == null -> note(getString(R.string.controls_not_ready))
            presets.isEmpty() -> note(getString(R.string.no_presets))
        }
        presets.forEach { p ->
            item("preset:${p.token}", p.name, longClick = { confirmDelete(p) }) {
                camera { gotoPreset(p) }
                flash(getString(R.string.moving_to, p.name))
                closePanel()
            }
        }
        if (onvif != null) item("save", getString(R.string.save_preset)) { promptSavePreset() }

        header(getString(R.string.view))
        item("quality", getString(if (prefs.highQuality) R.string.quality_hd else R.string.quality_sd)) {
            prefs.highQuality = !prefs.highQuality
            startStream()
            buildMenu()
        }
        item("sound", getString(if (prefs.muted) R.string.sound_off else R.string.sound_on)) {
            prefs.muted = !prefs.muted
            player?.volume = if (prefs.muted) 0f else 1f
            buildMenu()
        }
        item("reconnect", getString(R.string.reconnect)) { closePanel(); connect() }
        item("settings", getString(R.string.settings)) {
            closePanel()
            startActivity(Intent(this, SettingsActivity::class.java))
        }
        menu.findViewWithTag<View>(focusedTag)?.requestFocus()
    }

    private fun header(text: String) {
        val v = layoutInflater.inflate(R.layout.menu_header, menu, false) as TextView
        v.text = text
        menu.addView(v)
    }

    private fun note(text: String) {
        val v = layoutInflater.inflate(R.layout.menu_note, menu, false) as TextView
        v.text = text
        menu.addView(v)
    }

    private fun item(tag: String, text: String, longClick: (() -> Unit)? = null, onClick: () -> Unit) {
        val b = layoutInflater.inflate(R.layout.menu_item, menu, false) as Button
        b.tag = tag
        b.text = text
        b.setOnClickListener { onClick() }
        if (longClick != null) b.setOnLongClickListener { longClick(); true }
        menu.addView(b)
    }

    private fun promptSavePreset() {
        val input = EditText(this).apply { hint = getString(R.string.preset_name_hint); setSingleLine() }
        AlertDialog.Builder(this)
            .setTitle(R.string.save_preset)
            .setView(input)
            .setPositiveButton(R.string.save) { _, _ ->
                val name = input.text.toString().trim()
                if (name.isNotEmpty()) {
                    camera { savePreset(name) }
                    flash(getString(R.string.saved_preset, name))
                    refreshPresets()
                }
            }
            .setNegativeButton(android.R.string.cancel, null)
            .show()
    }

    private fun confirmDelete(p: Preset) {
        AlertDialog.Builder(this)
            .setTitle(getString(R.string.delete_preset, p.name))
            .setPositiveButton(R.string.delete) { _, _ ->
                camera { removePreset(p) }
                refreshPresets()
            }
            .setNegativeButton(android.R.string.cancel, null)
            .show()
    }

    // endregion
}
