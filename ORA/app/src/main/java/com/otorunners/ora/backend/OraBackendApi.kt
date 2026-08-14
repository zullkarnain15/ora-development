package com.otorunners.ora.backend

import com.otorunners.ora.data.local.ActivityEntity
import com.otorunners.ora.data.GuildDirectoryResponse
import com.otorunners.ora.data.GuildMember
import com.otorunners.ora.data.GuildSummary
import com.otorunners.ora.data.GuildSummaryResponse
import com.otorunners.ora.data.CurrentUserRank
import com.otorunners.ora.data.LeaderboardEntry
import com.otorunners.ora.data.LeaderboardMetric
import com.otorunners.ora.data.LeaderboardResponse
import com.otorunners.ora.data.LeaderboardScope
import com.otorunners.ora.data.QuestMaster
import com.otorunners.ora.data.QuestClaimResult
import com.otorunners.ora.data.UserStats
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale
import org.json.JSONObject

const val ORA_BACKEND_URL =
    "https://script.google.com/macros/s/AKfycbyD2oOTr39col6dqHTd721TFNizut4-Gi9jSe5CLYaTwMqx1mlQT1jD-JK8fqHSVWsn/exec"

data class BackendParticipant(
    val nik: String,
    val nickname: String?,
    val divisionGuild: String,
    val active: Boolean
)

data class BackendLoginResult(
    val sessionToken: String,
    val expiresInSeconds: Long,
    val participant: BackendParticipant,
    val requiresNicknameActivation: Boolean
)

enum class SubmitActivityStatus { SAVED, DUPLICATE }

class BackendException(val code: String, message: String) : IOException(message)

interface OraBackendApi {
    fun login(nik: String, pin: String): BackendLoginResult
    fun activateNickname(sessionToken: String, nickname: String): BackendParticipant
    fun submitActivity(sessionToken: String, activity: ActivityEntity): SubmitActivityStatus
    fun getUserStats(sessionToken: String): UserStats
    fun getGuildSummary(sessionToken: String): GuildSummaryResponse =
        throw UnsupportedOperationException("Guild summary is not available")
    fun getGuildDirectory(sessionToken: String): GuildDirectoryResponse =
        throw UnsupportedOperationException("Guild directory is not available")
    fun getLeaderboard(
        sessionToken: String,
        scope: LeaderboardScope,
        metric: LeaderboardMetric
    ): LeaderboardResponse = throw UnsupportedOperationException("Leaderboard is not available")
    fun getQuests(): List<QuestMaster>
    fun getQuestProgress(sessionToken: String): List<QuestMaster> = getQuests()
    fun claimQuestReward(sessionToken: String, questId: String): QuestClaimResult =
        throw UnsupportedOperationException("Quest reward claim is not available")
}

class AppsScriptBackendApi(
    private val endpointUrl: String = ORA_BACKEND_URL,
    private val connectTimeoutMillis: Int = 15_000,
    private val readTimeoutMillis: Int = 20_000
) : OraBackendApi {
    override fun login(nik: String, pin: String): BackendLoginResult {
        val data = post(
            JSONObject()
                .put("action", "login")
                .put("nik", nik)
                .put("pin", pin)
        )
        return BackendLoginResult(
            sessionToken = data.getString("sessionToken"),
            expiresInSeconds = data.getLong("expiresInSeconds"),
            participant = data.getJSONObject("participant").toParticipant(),
            requiresNicknameActivation = data.optBoolean("requiresNicknameActivation", false)
        )
    }

    override fun activateNickname(sessionToken: String, nickname: String): BackendParticipant {
        val data = post(
            JSONObject()
                .put("action", "activateNickname")
                .put("sessionToken", sessionToken)
                .put("nickname", nickname)
        )
        return data.getJSONObject("participant").toParticipant()
    }

    override fun submitActivity(
        sessionToken: String,
        activity: ActivityEntity
    ): SubmitActivityStatus {
        val payload = JSONObject()
            .put("action", "submitActivity")
            .put("sessionToken", sessionToken)
            .put("activity", activity.toBackendJson())
        return when (post(payload).getString("status")) {
            "SAVED" -> SubmitActivityStatus.SAVED
            "DUPLICATE" -> SubmitActivityStatus.DUPLICATE
            else -> throw BackendException("INVALID_RESPONSE", "Status sinkronisasi tidak dikenali.")
        }
    }

    override fun getUserStats(sessionToken: String): UserStats {
        val data = post(
            JSONObject()
                .put("action", "getUserStats")
                .put("sessionToken", sessionToken)
        )
        return data.getJSONObject("stats").toUserStats()
    }

    override fun getGuildSummary(sessionToken: String): GuildSummaryResponse {
        return post(
            JSONObject()
                .put("action", "getGuildSummary")
                .put("sessionToken", sessionToken)
        ).toGuildSummaryResponse()
    }

    override fun getGuildDirectory(sessionToken: String): GuildDirectoryResponse {
        return post(
            JSONObject()
                .put("action", "getGuildDirectory")
                .put("sessionToken", sessionToken)
        ).toGuildDirectoryResponse()
    }

    override fun getLeaderboard(
        sessionToken: String,
        scope: LeaderboardScope,
        metric: LeaderboardMetric
    ): LeaderboardResponse {
        return post(
            JSONObject()
                .put("action", "getLeaderboard")
                .put("sessionToken", sessionToken)
                .put("scope", scope.apiValue)
                .put("metric", metric.apiValue)
        ).toLeaderboardResponse(scope, metric)
    }

    override fun getQuests(): List<QuestMaster> {
        val quests = post(JSONObject().put("action", "quests")).getJSONArray("quests")
        return buildList {
            for (index in 0 until quests.length()) {
                add(quests.getJSONObject(index).toQuestMaster())
            }
        }
    }

    override fun getQuestProgress(sessionToken: String): List<QuestMaster> {
        val quests = post(
            JSONObject()
                .put("action", "getQuestProgress")
                .put("sessionToken", sessionToken)
        ).getJSONArray("quests")
        return buildList {
            for (index in 0 until quests.length()) {
                add(quests.getJSONObject(index).toQuestProgress())
            }
        }
    }

    override fun claimQuestReward(sessionToken: String, questId: String): QuestClaimResult {
        val claim = post(
            JSONObject()
                .put("action", "claimQuestReward")
                .put("sessionToken", sessionToken)
                .put("questId", questId)
        ).getJSONObject("claim")
        return QuestClaimResult(
            questId = claim.getString("questId"),
            rewardXp = claim.optInt("rewardXp", 0),
            status = claim.optString("status"),
            claimId = claim.optString("claimId").ifBlank { null },
            claimedAt = claim.optString("claimedAt")
                .takeIf { it.isNotBlank() && it != "null" }
        )
    }

    private fun post(payload: JSONObject): JSONObject {
        val connection = (URL(endpointUrl).openConnection() as HttpURLConnection).apply {
            requestMethod = "POST"
            doOutput = true
            instanceFollowRedirects = true
            connectTimeout = connectTimeoutMillis
            readTimeout = readTimeoutMillis
            setRequestProperty("Content-Type", "application/json; charset=utf-8")
            setRequestProperty("Accept", "application/json")
        }

        return try {
            connection.outputStream.bufferedWriter(Charsets.UTF_8).use { it.write(payload.toString()) }
            val responseCode = connection.responseCode
            val stream = if (responseCode in 200..299) connection.inputStream else connection.errorStream
            val body = stream?.bufferedReader(Charsets.UTF_8)?.use { it.readText() }.orEmpty()
            if (body.isBlank()) throw BackendException("EMPTY_RESPONSE", "Backend tidak memberi respons.")

            val response = try {
                JSONObject(body)
            } catch (_: Exception) {
                throw BackendException("INVALID_RESPONSE", "Respons backend tidak valid.")
            }
            if (!response.optBoolean("ok", false)) {
                val error = response.optJSONObject("error")
                throw BackendException(
                    error?.optString("code", "BACKEND_ERROR") ?: "BACKEND_ERROR",
                    error?.optString("message", "Backend ORA menolak request.")
                        ?: "Backend ORA menolak request."
                )
            }
            response.optJSONObject("data") ?: response
        } finally {
            connection.disconnect()
        }
    }
}

private fun JSONObject.toQuestMaster(): QuestMaster {
    return QuestMaster(
        questId = getString("questId"),
        questName = getString("questName"),
        questType = getString("questType"),
        targetValue = getDouble("targetValue"),
        unit = optString("unit"),
        rewardXp = getInt("rewardXp"),
        periodType = optString("periodType"),
        startDate = optString("startDate"),
        endDate = optString("endDate")
    )
}

internal fun JSONObject.toGuildSummaryResponse(): GuildSummaryResponse {
    val guildObject = optJSONObject("guild")
    val memberArray = optJSONArray("members")
    val members = buildList {
        if (memberArray != null) {
            for (index in 0 until memberArray.length()) {
                add(memberArray.getJSONObject(index).toGuildMember())
            }
        }
    }
    return GuildSummaryResponse(
        status = optString("status").ifBlank {
            if (guildObject == null) "UNASSIGNED" else "ACTIVE"
        },
        guild = guildObject?.let { guild ->
            GuildSummary(
                guildId = guild.optString("guildId"),
                guildName = guild.optString("guildName"),
                memberCount = guild.optInt("memberCount", 0),
                activeMemberCount = guild.optInt("activeMemberCount", 0),
                totalDistanceKm = guild.optDouble("totalDistanceKm", 0.0),
                totalActivities = guild.optInt("totalActivities", 0),
                totalXp = guild.optInt("totalXP", 0),
                currentLevel = guild.optInt("currentLevel", 1),
                currentLevelName = guild.optString("currentLevelName"),
                displayName = guild.optString("displayName"),
                description = guild.optString("description")
            )
        },
        members = members
    )
}

internal fun JSONObject.toGuildDirectoryResponse(): GuildDirectoryResponse {
    val guildArray = optJSONArray("guilds")
    val guilds = buildList {
        if (guildArray != null) {
            for (index in 0 until guildArray.length()) {
                val guild = guildArray.getJSONObject(index)
                add(
                    GuildSummary(
                        guildId = guild.optString("guildId"),
                        guildName = guild.optString("guildName"),
                        memberCount = guild.optInt("memberCount", 0),
                        activeMemberCount = guild.optInt("activeMemberCount", 0),
                        totalDistanceKm = guild.optDouble("totalDistanceKm", 0.0),
                        totalActivities = guild.optInt("totalActivities", 0),
                        totalXp = guild.optInt("totalXP", 0),
                        currentLevel = guild.optInt("currentLevel", 1),
                        currentLevelName = guild.optString("currentLevelName"),
                        displayName = guild.optString("displayName"),
                        description = guild.optString("description")
                    )
                )
            }
        }
    }
    return GuildDirectoryResponse(guilds = guilds)
}

private fun JSONObject.toGuildMember(): GuildMember {
    return GuildMember(
        nik = optString("nik"),
        nickname = optString("nickname"),
        division = optString("division"),
        totalDistanceKm = optDouble("totalDistanceKm", 0.0),
        totalActivities = optInt("totalActivities", 0),
        totalXp = optInt("totalXP", 0),
        currentLevel = optInt("currentLevel", 1),
        currentLevelName = optString("currentLevelName")
    )
}

internal fun JSONObject.toLeaderboardResponse(
    requestedScope: LeaderboardScope,
    requestedMetric: LeaderboardMetric
): LeaderboardResponse {
    val entriesJson = optJSONArray("leaderboard")
    val entries = buildList {
        if (entriesJson != null) {
            for (index in 0 until entriesJson.length()) {
                val entry = entriesJson.getJSONObject(index)
                add(
                    LeaderboardEntry(
                        rank = entry.optInt("rank", index + 1),
                        nik = entry.optString("nik"),
                        nickname = entry.optString("nickname"),
                        division = entry.optString("division"),
                        totalXp = entry.optInt("totalXP", 0),
                        totalDistanceKm = entry.optDouble("totalDistanceKm", 0.0),
                        totalActivities = entry.optInt("totalActivities", 0),
                        currentLevel = entry.optInt("currentLevel", 1),
                        currentLevelName = entry.optString("currentLevelName")
                    )
                )
            }
        }
    }
    val currentRankJson = optJSONObject("currentUserRank")
    val responseMetric = optString("metric")
        .takeIf { it.isNotBlank() }
        ?.let { value -> LeaderboardMetric.entries.find { it.apiValue == value } }
        ?: requestedMetric
    val responseScope = optString("scope")
        .takeIf { it.isNotBlank() }
        ?.let { value -> LeaderboardScope.entries.find { it.apiValue == value } }
        ?: requestedScope
    return LeaderboardResponse(
        scope = responseScope,
        status = optString("status", "ACTIVE"),
        metric = responseMetric,
        leaderboard = entries,
        currentUserRank = currentRankJson?.let {
            CurrentUserRank(
                rank = it.optInt("rank", 0),
                metricValue = it.optDouble("metricValue", 0.0)
            )
        }
    )
}

private fun JSONObject.toQuestProgress(): QuestMaster {
    return QuestMaster(
        questId = getString("questId"),
        questName = optString("name", optString("questName")),
        questType = optString("type", optString("questType")),
        targetValue = optDouble("target", optDouble("targetValue", 0.0)),
        unit = optString("unit"),
        rewardXp = optInt("rewardXp", 0),
        periodType = optString("period", optString("periodType")),
        startDate = optString("activeFrom", optString("startDate"))
            .takeUnless { it == "null" }
            .orEmpty(),
        endDate = optString("activeTo", optString("endDate"))
            .takeUnless { it == "null" }
            .orEmpty(),
        progress = optDouble("progress", 0.0),
        progressPercent = optDouble("progressPercent", 0.0).coerceIn(0.0, 100.0),
        status = optString("status").ifBlank { null },
        completed = optBoolean("completed", false),
        claimable = if (has("claimable") && !isNull("claimable")) {
            optBoolean("claimable", false)
        } else {
            null
        },
        claimBlockedReason = optString("claimBlockedReason")
            .takeIf { it.isNotBlank() && it != "null" },
        claimed = optBoolean("claimed", false),
        claimId = optString("claimId").ifBlank { null },
        claimedAt = optString("claimedAt")
            .takeIf { it.isNotBlank() && it != "null" }
    )
}

private fun JSONObject.toParticipant(): BackendParticipant {
    return BackendParticipant(
        nik = getString("nik"),
        nickname = optString("nickname").takeIf { it.isNotBlank() && it != "null" },
        divisionGuild = getString("divisionGuild"),
        active = optString("status").equals("ACTIVE", ignoreCase = true)
    )
}

private fun JSONObject.toUserStats(): UserStats {
    return UserStats(
        nik = getString("nik"),
        nickname = optString("nickname"),
        division = optString("division"),
        totalActivities = optInt("totalActivities", 0),
        totalDistanceKm = optDouble("totalDistanceKm", 0.0),
        totalDurationSec = optDouble("totalDurationSec", 0.0),
        totalXp = optInt("totalXP", 0),
        currentLevel = optInt("currentLevel", 0),
        currentLevelName = optString("currentLevelName"),
        nextLevelXp = if (has("nextLevelXP") && !isNull("nextLevelXP")) {
            getInt("nextLevelXP")
        } else {
            null
        },
        lastActivityId = optString("lastActivityId"),
        lastActivityAt = optString("lastActivityAt"),
        updatedAt = optString("updatedAt").takeIf { it.isNotBlank() && it != "null" }
    )
}

private fun ActivityEntity.toBackendJson(): JSONObject {
    return JSONObject()
        .put("activityId", activityId)
        .put("startTime", startDateTimeMillis.toIsoOffset())
        .put("endTime", endDateTimeMillis.toIsoOffset())
        .put("durationSec", activeDurationMillis / 1_000.0)
        .put("distanceKm", distanceMeters / 1_000.0)
        .put("avgPace", averagePaceSecondsPerKm.toPaceText())
        .put("deviceTime", System.currentTimeMillis().toIsoOffset())
}

private fun Long.toIsoOffset(): String {
    return DateTimeFormatter.ISO_OFFSET_DATE_TIME.format(
        Instant.ofEpochMilli(this).atZone(ZoneId.systemDefault())
    )
}

private fun Int?.toPaceText(): String {
    if (this == null || this <= 0) return ""
    return String.format(Locale.US, "%02d:%02d", this / 60, this % 60)
}
