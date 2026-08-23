import '../../../core/network/apps_script_client.dart';
import '../../activity/domain/activity_sync.dart';
import '../../activity/domain/server_activity_summary.dart';
import '../domain/feature_models.dart';

abstract interface class OraFeatureApi {
  Future<Map<String, Object?>> health();
  Future<Map<String, Object?>> config();
  Future<List<OraLevel>> levels();
  Future<List<Quest>> quests();
  Future<UserStats> userStats(String sessionToken);
  Future<GuildData> guildData(String sessionToken);
  Future<LeaderboardData> leaderboard(
    String sessionToken,
    LeaderboardScope scope,
    LeaderboardMetric metric,
  );
  Future<List<Quest>> questProgress(String sessionToken);
  Future<QuestClaim> claimQuest(String sessionToken, String questId);
  Future<AttendanceResult> submitAttendance(
    String sessionToken,
    String qrToken,
  );
  Future<String> submitActivity(
    String sessionToken,
    ActivityUploadPayload payload,
  );
  Future<List<ServerActivitySummary>> activityHistory(
    String sessionToken, {
    int limit = 50,
    int offset = 0,
  });
}

class AppsScriptFeatureApi implements OraFeatureApi {
  const AppsScriptFeatureApi(this.client);
  final AppsScriptClient client;

  @override
  Future<Map<String, Object?>> health() => client.get('health');

  @override
  Future<Map<String, Object?>> config() async {
    final data = await client.call('config');
    return data.object('config') ?? const {};
  }

  @override
  Future<List<OraLevel>> levels() async {
    final data = await client.call('levels');
    return _parse(
      () =>
          data.objects('levels').map(OraLevel.fromJson).toList(growable: false),
    );
  }

  @override
  Future<List<Quest>> quests() async {
    final data = await client.call('quests');
    return _parse(
      () => data
          .objects('quests')
          .map((item) => Quest.fromJson(item))
          .toList(growable: false),
    );
  }

  @override
  Future<UserStats> userStats(String sessionToken) async {
    final data = await client.call('getUserStats', {
      'sessionToken': sessionToken,
    });
    final stats = data.object('stats');
    if (stats == null) return _invalid('User stats are missing.');
    return _parse(() => UserStats.fromJson(stats));
  }

  @override
  Future<GuildData> guildData(String sessionToken) async {
    final summary = await client.call('getGuildSummary', {
      'sessionToken': sessionToken,
    });
    final directory = await client.call('getGuildDirectory', {
      'sessionToken': sessionToken,
    });
    return _parse(() {
      final guildJson = summary.object('guild');
      return GuildData(
        status: summary.string(
          'status',
          fallback: guildJson == null ? 'UNASSIGNED' : 'ACTIVE',
        ),
        guild: guildJson == null ? null : GuildSummary.fromJson(guildJson),
        members: summary
            .objects('members')
            .map(GuildMember.fromJson)
            .toList(growable: false),
        directory: directory
            .objects('guilds')
            .map(GuildSummary.fromJson)
            .toList(growable: false),
      );
    });
  }

  @override
  Future<LeaderboardData> leaderboard(
    String sessionToken,
    LeaderboardScope scope,
    LeaderboardMetric metric,
  ) async {
    final data = await client.call('getLeaderboard', {
      'sessionToken': sessionToken,
      'scope': scope.apiValue,
      'metric': metric.apiValue,
    });
    return _parse(() {
      final responseScope = data.string('scope') == 'GUILD'
          ? LeaderboardScope.guild
          : LeaderboardScope.global;
      final responseMetric = switch (data.string('metric')) {
        'TOTAL_DISTANCE' => LeaderboardMetric.totalDistance,
        'TOTAL_ACTIVITIES' => LeaderboardMetric.totalActivities,
        'TOTAL_XP' => LeaderboardMetric.totalXp,
        _ => metric,
      };
      final rankJson = data.object('currentUserRank');
      return LeaderboardData(
        scope: data.string('scope').isEmpty ? scope : responseScope,
        metric: responseMetric,
        status: data.string('status', fallback: 'ACTIVE'),
        entries: data
            .objects('leaderboard')
            .asMap()
            .entries
            .map((entry) => LeaderboardEntry.fromJson(entry.value, entry.key))
            .toList(growable: false),
        currentUserRank: rankJson == null
            ? null
            : CurrentUserRank(
                rank: rankJson.integer('rank'),
                metricValue: rankJson.decimal('metricValue'),
              ),
      );
    });
  }

  @override
  Future<List<Quest>> questProgress(String sessionToken) async {
    final data = await client.call('getQuestProgress', {
      'sessionToken': sessionToken,
    });
    return _parse(
      () => data
          .objects('quests')
          .map((item) => Quest.fromJson(item, progressResponse: true))
          .toList(growable: false),
    );
  }

  @override
  Future<QuestClaim> claimQuest(String sessionToken, String questId) async {
    final data = await client.call('claimQuestReward', {
      'sessionToken': sessionToken,
      'questId': questId,
    });
    final claim = data.object('claim');
    if (claim == null) return _invalid('Quest claim is missing.');
    return _parse(() => QuestClaim.fromJson(claim));
  }

  @override
  Future<AttendanceResult> submitAttendance(
    String sessionToken,
    String qrToken,
  ) async {
    final data = await client.call('submitAttendance', {
      'sessionToken': sessionToken,
      'qrToken': qrToken,
    });
    final result = _parse(() => AttendanceResult.fromJson(data));
    if (result.status == AttendanceStatus.unknown) {
      return _invalid('Attendance status is invalid.');
    }
    return result;
  }

  @override
  Future<String> submitActivity(
    String sessionToken,
    ActivityUploadPayload payload,
  ) async {
    final data = await client.call('submitActivity', {
      'sessionToken': sessionToken,
      'activity': payload.fields,
    });
    final status = data.string('status');
    if (status != 'SAVED' && status != 'DUPLICATE') {
      return _invalid('Activity status is invalid.');
    }
    return status;
  }

  @override
  Future<List<ServerActivitySummary>> activityHistory(
    String sessionToken, {
    int limit = 50,
    int offset = 0,
  }) async {
    final data = await client.call('getActivityHistory', {
      'sessionToken': sessionToken,
      'limit': limit,
      'offset': offset,
    });
    return _parse(
      () => data
          .objects('activities')
          .map(ServerActivitySummary.fromJson)
          .toList(growable: false),
    );
  }

  T _parse<T>(T Function() parser) {
    try {
      return parser();
    } on BackendFailure {
      rethrow;
    } on Object {
      return _invalid('Backend response fields are invalid.');
    }
  }

  Never _invalid(String message) =>
      throw BackendFailure(BackendFailureKind.invalidResponse, message);
}
