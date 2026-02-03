package com.alirezabeigy.paqetng.data

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.CopyOnWriteArrayList

enum class PacketDirection { TX, RX }

/**
 * A single traffic entry for the packet dump viewer (send or receive activity).
 */
data class PacketDumpEntry(
    val timestamp: String,
    val direction: PacketDirection,
    val packets: Long,
    val bytes: Long
) {
    fun formatBytes(): String {
        return when {
            bytes >= 1_048_576 -> "%.2f MB".format(bytes / 1_048_576.0)
            bytes >= 1024 -> "%.2f KB".format(bytes / 1024.0)
            else -> "$bytes B"
        }
    }
}

/**
 * In-memory buffer for packet dump (TX/RX traffic) for the connected VPN profile.
 * Populated by the VPN service from tun2socks stats.
 */
class PacketDumpBuffer(private val maxEntries: Int = 2000) {

    private val _entries = MutableStateFlow<List<PacketDumpEntry>>(emptyList())
    val entries: StateFlow<List<PacketDumpEntry>> = _entries.asStateFlow()

    private val list = CopyOnWriteArrayList<PacketDumpEntry>()
    private val dateFormat = SimpleDateFormat("HH:mm:ss.SSS", Locale.US)

    private fun timestamp(): String = dateFormat.format(Date())

    @Synchronized
    fun append(direction: PacketDirection, packets: Long, bytes: Long) {
        if (packets <= 0 && bytes <= 0) return
        val entry = PacketDumpEntry(timestamp(), direction, packets, bytes)
        list.add(entry)
        while (list.size > maxEntries) list.removeAt(0)
        _entries.value = list.toList()
    }

    /** Full text for export (newest last). */
    fun getFullText(separator: String = "\n"): String =
        list.joinToString(separator) { e ->
            "${e.timestamp}  ${e.direction.name.padEnd(3)}  ${e.packets} pkts  ${e.formatBytes()}"
        }

    @Synchronized
    fun clear() {
        list.clear()
        _entries.value = emptyList()
    }
}
