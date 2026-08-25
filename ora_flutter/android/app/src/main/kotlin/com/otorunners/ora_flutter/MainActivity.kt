package com.otorunners.ora_flutter

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import android.util.Patterns
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel
import java.security.KeyStore
import java.io.ByteArrayOutputStream
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

class MainActivity : FlutterActivity() {
    private var trackingBridge: TrackingBridge? = null
    private var shareChannel: MethodChannel? = null
    private var pendingSharePayload: Map<String, Any?>? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val vault = SecureSessionVault(applicationContext)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            val key = call.argument<String>("key")
            if (key.isNullOrBlank()) {
                result.error("INVALID_ARGUMENT", "A storage key is required.", null)
                return@setMethodCallHandler
            }
            try {
                when (call.method) {
                    "read" -> result.success(vault.read(key))
                    "write" -> {
                        val value = call.argument<String>("value")
                        if (value == null) {
                            result.error("INVALID_ARGUMENT", "A storage value is required.", null)
                        } else {
                            vault.write(key, value)
                            result.success(null)
                        }
                    }
                    "delete" -> {
                        vault.delete(key)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (_: Exception) {
                // Never return the token, plaintext, ciphertext, or exception details to Dart/logs.
                result.error("SECURE_STORAGE_FAILURE", "Secure session storage failed.", null)
            }
        }
        trackingBridge = TrackingBridge(this, flutterEngine.dartExecutor.binaryMessenger).also {
            it.configure()
        }
        shareChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            SHARE_CHANNEL
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "getInitialSharePayload" -> {
                        result.success(pendingSharePayload)
                        pendingSharePayload = null
                    }
                    else -> result.notImplemented()
                }
            }
        }
        captureShareIntent(intent, notifyDart = false)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        captureShareIntent(intent, notifyDart = true)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        trackingBridge?.onRequestPermissionsResult(requestCode)
    }

    override fun onDestroy() {
        trackingBridge?.dispose()
        trackingBridge = null
        shareChannel?.setMethodCallHandler(null)
        shareChannel = null
        pendingSharePayload = null
        super.onDestroy()
    }

    override fun onStop() {
        trackingBridge?.stopPreview()
        super.onStop()
    }

    private fun captureShareIntent(intent: Intent?, notifyDart: Boolean) {
        if (intent?.action != Intent.ACTION_SEND) return
        val sharedText = intent.getStringExtra(Intent.EXTRA_TEXT)?.trim().orEmpty()
        val sharedUrl = Patterns.WEB_URL.matcher(sharedText).let { matcher ->
            if (matcher.find()) matcher.group() else null
        }
        val imageUri = intent.streamUri()
        val imageBytes = imageUri?.let { readImageBytes(it) }
        if (sharedText.isEmpty() && sharedUrl.isNullOrEmpty() && imageBytes == null) return
        val payload = mutableMapOf<String, Any?>(
            "sharedText" to sharedText.ifEmpty { null },
            "sharedUrl" to sharedUrl,
            "sourceHint" to if (
                sharedText.contains("strava", ignoreCase = true) ||
                sharedUrl?.contains("strava", ignoreCase = true) == true
            ) "STRAVA" else null,
            "imageBytes" to imageBytes,
            "imageMimeType" to imageUri?.let { contentResolver.getType(it) },
            "imageName" to null,
        )
        if (notifyDart && shareChannel != null) {
            shareChannel?.invokeMethod("onSharePayload", payload)
        } else {
            pendingSharePayload = payload
        }
    }

    @Suppress("DEPRECATION")
    private fun Intent.streamUri(): Uri? =
        getParcelableExtra(Intent.EXTRA_STREAM) as? Uri

    private fun readImageBytes(uri: Uri): ByteArray? = try {
        contentResolver.openInputStream(uri)?.use { input ->
            val output = ByteArrayOutputStream()
            val buffer = ByteArray(8192)
            var total = 0
            while (true) {
                val count = input.read(buffer)
                if (count < 0) break
                total += count
                if (total > MAX_SHARE_IMAGE_BYTES) return null
                output.write(buffer, 0, count)
            }
            output.toByteArray()
        }
    } catch (_: Exception) {
        null
    }

    companion object {
        private const val CHANNEL = "ora/session_store"
        private const val SHARE_CHANNEL = "ora/activity_share"
        private const val MAX_SHARE_IMAGE_BYTES = 5 * 1024 * 1024
    }
}

private class SecureSessionVault(context: Context) {
    private val preferences = context.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)

    fun write(key: String, plaintext: String) {
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, secretKey())
        val encrypted = cipher.doFinal(plaintext.toByteArray(Charsets.UTF_8))
        val payload = ByteArray(cipher.iv.size + encrypted.size)
        cipher.iv.copyInto(payload)
        encrypted.copyInto(payload, cipher.iv.size)
        preferences.edit().putString(key, Base64.encodeToString(payload, Base64.NO_WRAP)).apply()
    }

    fun read(key: String): String? {
        val encoded = preferences.getString(key, null) ?: return null
        return try {
            val payload = Base64.decode(encoded, Base64.NO_WRAP)
            if (payload.size <= IV_LENGTH_BYTES) throw IllegalStateException("Invalid ciphertext")
            val iv = payload.copyOfRange(0, IV_LENGTH_BYTES)
            val ciphertext = payload.copyOfRange(IV_LENGTH_BYTES, payload.size)
            val cipher = Cipher.getInstance(TRANSFORMATION)
            cipher.init(Cipher.DECRYPT_MODE, secretKey(), GCMParameterSpec(TAG_LENGTH_BITS, iv))
            String(cipher.doFinal(ciphertext), Charsets.UTF_8)
        } catch (_: Exception) {
            preferences.edit().remove(key).apply()
            null
        }
    }

    fun delete(key: String) {
        preferences.edit().remove(key).apply()
    }

    private fun secretKey(): SecretKey {
        val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (keyStore.getKey(KEY_ALIAS, null) as? SecretKey)?.let { return it }
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        generator.init(
            KeyGenParameterSpec.Builder(
                KEY_ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setRandomizedEncryptionRequired(true)
                .build()
        )
        return generator.generateKey()
    }

    companion object {
        private const val PREFERENCES_NAME = "ora_secure_session"
        private const val KEY_ALIAS = "ora.session.key.v1"
        private const val TRANSFORMATION = "AES/GCM/NoPadding"
        private const val IV_LENGTH_BYTES = 12
        private const val TAG_LENGTH_BITS = 128
    }
}
