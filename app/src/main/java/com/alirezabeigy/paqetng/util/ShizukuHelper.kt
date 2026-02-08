package com.alirezabeigy.paqetng.util

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.util.Log
import rikka.shizuku.Shizuku
import rikka.shizuku.ShizukuProvider
import java.io.IOException

/**
 * Helper class for Shizuku integration to replace root requirements.
 */
object ShizukuHelper {

    private const val TAG = "ShizukuHelper"
    private const val SHIZUKU_PACKAGE = "moe.shizuku.privileged.api"

    /**
     * Check if Shizuku is installed.
     */
    fun isShizukuInstalled(context: Context): Boolean {
        return try {
            context.packageManager.getPackageInfo(SHIZUKU_PACKAGE, 0)
            true
        } catch (e: PackageManager.NameNotFoundException) {
            false
        }
    }

    /**
     * Check if Shizuku is available and has permission.
     */
    fun isShizukuAvailable(): Boolean {
        return Shizuku.pingBinder() && Shizuku.checkSelfPermission() == PackageManager.PERMISSION_GRANTED
    }

    /**
     * Request Shizuku permission.
     */
    fun requestPermission(context: Context) {
        if (Shizuku.shouldShowRequestPermissionRationale()) {
            Log.i(TAG, "Requesting Shizuku permission")
            Shizuku.requestPermission(0)
        } else {
            // Open Shizuku app
            val intent = context.packageManager.getLaunchIntentForPackage(SHIZUKU_PACKAGE)
            if (intent != null) {
                context.startActivity(intent)
            }
        }
    }

    /**
     * Execute a shell command using Shizuku.
     * Returns the output as String, or null if failed.
     */
    fun executeCommand(command: String): String? {
        if (!isShizukuAvailable()) return null

        return try {
            val process = Shizuku.newProcess(arrayOf("sh", "-c", command), null, null)
            val output = process.inputStream.bufferedReader().readText()
            val error = process.errorStream.bufferedReader().readText()
            val exitCode = process.waitFor()

            if (exitCode != 0) {
                Log.w(TAG, "Command failed: $command, exitCode=$exitCode, error=$error")
                return null
            }
            output
        } catch (e: IOException) {
            Log.w(TAG, "Failed to execute command with Shizuku: $command", e)
            null
        }
    }

    /**
     * Check if privileged execution is available (Shizuku or root).
     */
    fun isPrivilegedExecutionAvailable(): Boolean {
        return isShizukuAvailable() || isRootAvailable()
    }

    /**
     * Execute a command with privileged access (Shizuku preferred, fallback to root).
     */
    fun executePrivilegedCommand(command: String): String? {
        return executeCommand(command) ?: executeRootCommand(command)
    }

    /**
     * Check if root is available (fallback method).
     */
    private fun isRootAvailable(): Boolean {
        return try {
            val process = Runtime.getRuntime().exec(arrayOf("su", "-c", "id"))
            val exitCode = process.waitFor()
            exitCode == 0
        } catch (e: Exception) {
            false
        }
    }

    /**
     * Execute command with root (fallback).
     */
    private fun executeRootCommand(command: String): String? {
        return try {
            val process = Runtime.getRuntime().exec(arrayOf("su", "-c", command))
            val output = process.inputStream.bufferedReader().readText()
            val exitCode = process.waitFor()
            if (exitCode != 0) null else output
        } catch (e: Exception) {
            null
        }
    }
}