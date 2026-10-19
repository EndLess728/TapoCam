package com.endless.tapocam

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.withContext
import java.net.Inet4Address
import java.net.InetSocketAddress
import java.net.NetworkInterface
import java.net.Socket

/** Finds Tapo cameras on the local /24 by their ONVIF (2020) and RTSP (554) ports. */
object Discovery {
    suspend fun scan(): List<String> = withContext(Dispatchers.IO) {
        val prefix = localPrefix() ?: return@withContext emptyList()
        coroutineScope {
            (1..254).map { i ->
                async {
                    val h = "$prefix.$i"
                    if (open(h, 2020) && open(h, 554)) h else null
                }
            }.awaitAll().filterNotNull()
        }
    }

    private fun open(host: String, port: Int) = try {
        Socket().use { it.connect(InetSocketAddress(host, port), 1200); true }
    } catch (_: Exception) {
        false
    }

    private fun localPrefix(): String? = NetworkInterface.getNetworkInterfaces().toList()
        .filter { it.isUp && !it.isLoopback }
        .flatMap { it.inetAddresses.toList() }
        .filterIsInstance<Inet4Address>()
        .map { it.hostAddress ?: "" }
        .firstOrNull { it.startsWith("192.168.") || it.startsWith("10.") || it.startsWith("172.") }
        ?.substringBeforeLast('.')
}
