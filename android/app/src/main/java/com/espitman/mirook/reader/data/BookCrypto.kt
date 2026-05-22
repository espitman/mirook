package com.espitman.mirook.reader.data

import android.util.Base64
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import java.security.spec.KeySpec
import javax.crypto.Cipher
import javax.crypto.SecretKey
import javax.crypto.SecretKeyFactory
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.PBEKeySpec
import javax.crypto.spec.SecretKeySpec

@Serializable
data class BookEncryptionMetadata(
    val iterations: Int,
    @Serializable(with = ByteArrayBase64Serializer::class)
    val salt: ByteArray,
    @Serializable(with = ByteArrayBase64Serializer::class)
    val passwordCheck: ByteArray
)

class BookCrypto(private val json: Json) {
    fun parseMetadata(data: ByteArray): BookEncryptionMetadata =
        json.decodeFromString(BookEncryptionMetadata.serializer(), data.decodeToString())

    fun deriveKey(password: String, salt: ByteArray, iterations: Int): SecretKey {
        val factory = SecretKeyFactory.getInstance("PBKDF2WithHmacSHA256")
        val spec: KeySpec = PBEKeySpec(password.toCharArray(), salt, iterations, 256)
        return SecretKeySpec(factory.generateSecret(spec).encoded, "AES")
    }

    fun checkPassword(metadata: BookEncryptionMetadata, password: String): SecretKey {
        val key = deriveKey(password, metadata.salt, metadata.iterations)
        val check = decrypt(metadata.passwordCheck, key).decodeToString()
        if (check != PASSWORD_CHECK_TEXT) {
            throw MirookBookError.InvalidPassword
        }
        return key
    }

    fun decrypt(combined: ByteArray, key: SecretKey): ByteArray {
        if (combined.size < 13) throw MirookBookError.CryptoFailure
        val nonce = combined.copyOfRange(0, 12)
        val cipherTextAndTag = combined.copyOfRange(12, combined.size)
        return try {
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(128, nonce))
            cipher.doFinal(cipherTextAndTag)
        } catch (_: Exception) {
            throw MirookBookError.InvalidPassword
        }
    }

    companion object {
        const val PASSWORD_CHECK_TEXT = "mirook-password-check-v1"
    }
}

object ByteArrayBase64Serializer : kotlinx.serialization.KSerializer<ByteArray> {
    override val descriptor = kotlinx.serialization.descriptors.PrimitiveSerialDescriptor(
        "ByteArrayBase64",
        kotlinx.serialization.descriptors.PrimitiveKind.STRING
    )

    override fun deserialize(decoder: kotlinx.serialization.encoding.Decoder): ByteArray =
        Base64.decode(decoder.decodeString(), Base64.DEFAULT)

    override fun serialize(encoder: kotlinx.serialization.encoding.Encoder, value: ByteArray) {
        encoder.encodeString(Base64.encodeToString(value, Base64.NO_WRAP))
    }
}
