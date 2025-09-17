package com.example.zarq_messenger

import android.util.Log
import com.google.firebase.auth.FirebaseAuth
import kotlinx.coroutines.tasks.await
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import java.util.concurrent.TimeUnit
import org.json.JSONArray


object MessageApi {
    private val client: OkHttpClient = OkHttpClient.Builder()
        .callTimeout(15, TimeUnit.SECONDS)
        .build()

    suspend fun updateMessageStatus(
        messageId: Int,
        recipientDeviceId: Int? = null,
        markDelivered: Boolean = false,
        markRead: Boolean = false,
        serverBaseUrl: String = "http://192.168.29.81:8080"
    ) {
        val user = FirebaseAuth.getInstance().currentUser ?: throw IllegalStateException("Not signed in")
        val idToken = user.getIdToken(true).await().token ?: throw IllegalStateException("No id token")

        // Build request JSON
        val json = JSONObject().apply {
            put("message_id", messageId)
            if (recipientDeviceId != null) put("recipient_device_id", recipientDeviceId)
            if (markDelivered) put("delivered", true)
            if (markRead) put("read", true)
        }

        val mediaType = "application/json; charset=utf-8".toMediaType()
        val body = json.toString().toRequestBody(mediaType)

        val req = Request.Builder()
            .url("$serverBaseUrl/v1/messages/status")
            .addHeader("Authorization", "Bearer $idToken")
            .addHeader("Content-Type", "application/json")
            .post(body)
            .build()

        client.newCall(req).execute().use { resp ->
            if (!resp.isSuccessful) {
                val err = resp.body?.string()
                Log.e("MessageApi", "updateMessageStatus failed: ${resp.code} - $err")
                throw Exception("updateMessageStatus failed: ${resp.code}")
            }
            val respBody = resp.body?.string()
            Log.i("MessageApi", "updateMessageStatus success: $respBody")
        }
    }

    suspend fun fetchMessages(
        conversationId: Int,
        sinceId: Int = 0,
        limit: Int = 100,
        serverBaseUrl: String = "http://192.168.29.81:8080"
    ): List<FetchedMessage> {
        val user = FirebaseAuth.getInstance().currentUser ?: throw IllegalStateException("Not signed in")
        val idToken = user.getIdToken(true).await().token ?: throw IllegalStateException("No id token")

        // Build URL with query params
        val url = "$serverBaseUrl/v1/messages/sync?conversation_id=$conversationId&since_id=$sinceId&limit=$limit"

        val req = Request.Builder()
            .url(url)
            .addHeader("Authorization", "Bearer $idToken")
            .addHeader("Content-Type", "application/json")
            .get()
            .build()

        client.newCall(req).execute().use { resp ->
            if (!resp.isSuccessful) {
                val err = resp.body?.string()
                throw Exception("fetchMessages failed: ${resp.code} - $err")
            }
            val bodyStr = resp.body?.string() ?: return emptyList()
            val root = JSONObject(bodyStr)
            val msgs = mutableListOf<FetchedMessage>()
            val arr: JSONArray = root.optJSONArray("messages") ?: JSONArray()

            for (i in 0 until arr.length()) {
                val o = arr.getJSONObject(i)
                val id = o.getInt("id")
                val conv = o.getInt("conversation_id")
                val senderUid = o.getString("sender_uid")
                val senderDeviceId = o.optInt("sender_device_id", 1)
                val contentB64 = o.getString("content_b64")
                val createdAt = o.getString("created_at")

                val statusesJson = o.optJSONArray("statuses") ?: JSONArray()
                val statuses = mutableListOf<MessageStatus>()
                for (j in 0 until statusesJson.length()) {
                    val s = statusesJson.getJSONObject(j)
                    val rid = s.getInt("recipient_device_id")
                    val deliveredAt = if (s.has("delivered_at") && !s.isNull("delivered_at")) s.getString("delivered_at") else null
                    val readAt = if (s.has("read_at") && !s.isNull("read_at")) s.getString("read_at") else null
                    statuses.add(MessageStatus(rid, deliveredAt, readAt))
                }

                msgs.add(FetchedMessage(id, conv, senderUid, senderDeviceId, contentB64, createdAt, statuses))
            }
            return msgs
        }
    }
}

data class MessageStatus(
    val recipientDeviceId: Int,
    val deliveredAt: String?, // RFC3339 string or null
    val readAt: String?       // RFC3339 string or null
)

data class FetchedMessage(
    val id: Int,
    val conversationId: Int,
    val senderUid: String,
    val senderDeviceId: Int,
    val contentB64: String,
    val createdAt: String,
    val statuses: List<MessageStatus>
)