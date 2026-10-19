package com.endless.tapocam

import android.os.Bundle
import android.widget.Button
import android.widget.EditText
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

class SettingsActivity : AppCompatActivity() {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_settings)
        val prefs = Prefs(this)
        val host = findViewById<EditText>(R.id.host)
        val user = findViewById<EditText>(R.id.user)
        val password = findViewById<EditText>(R.id.password)
        val find = findViewById<Button>(R.id.find)
        val found = findViewById<TextView>(R.id.found)
        val save = findViewById<Button>(R.id.save)

        host.setText(prefs.host)
        user.setText(prefs.user)
        password.setText(prefs.password)

        fun scan() {
            find.isEnabled = false
            found.text = getString(R.string.searching)
            scope.launch {
                val hosts = Discovery.scan()
                find.isEnabled = true
                found.text = if (hosts.isEmpty()) getString(R.string.none_found)
                else getString(R.string.found_cameras, hosts.joinToString(", "))
                if (host.text.isBlank() && hosts.isNotEmpty()) {
                    host.setText(hosts.first())
                    user.requestFocus()
                }
            }
        }
        find.setOnClickListener { scan() }
        save.setOnClickListener {
            prefs.host = host.text.toString()
            prefs.user = user.text.toString()
            prefs.password = password.text.toString()
            if (prefs.isConfigured) finish()
            else found.text = getString(R.string.fill_all)
        }
        if (prefs.host.isEmpty()) scan()
        (if (prefs.host.isEmpty()) find else user).requestFocus()
    }

    override fun onDestroy() {
        super.onDestroy()
        scope.cancel()
    }
}
