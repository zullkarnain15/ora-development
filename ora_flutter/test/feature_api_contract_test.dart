import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ora_flutter/core/network/apps_script_client.dart';
import 'package:ora_flutter/features/activity/domain/final_activity.dart';
import 'package:ora_flutter/features/activity/domain/activity_sync.dart';
import 'package:ora_flutter/features/auth/data/auth_api.dart';
import 'package:ora_flutter/features/dashboard/data/ora_feature_api.dart';
import 'package:ora_flutter/features/dashboard/domain/feature_models.dart';

const _actions = {
  'health',
  'config',
  'levels',
  'quests',
  'login',
  'activateNickname',
  'updateNickname',
  'submitActivity',
  'getActivityHistory',
  'getUserStats',
  'getGuildSummary',
  'getGuildDirectory',
  'getLeaderboard',
  'getQuestProgress',
  'claimQuestReward',
  'submitAttendance',
};

class _ContractTransport implements ApiTransport {
  final List<Map<String, Object?>> requests = [];
  String? failAction;

  @override
  Future<TransportResponse> request(
    Uri endpoint, {
    required String method,
    String? body,
    required Duration connectTimeout,
    required Duration readTimeout,
  }) async {
    final request = method == 'GET'
        ? <String, Object?>{'action': endpoint.queryParameters['action']}
        : jsonDecode(body!) as Map<String, Object?>;
    requests.add(request);
    final action = request['action']! as String;
    if (action == failAction) {
      return TransportResponse(
        statusCode: 200,
        body: jsonEncode({
          'ok': false,
          'error': {'code': '${action}_ERROR', 'message': 'fixture'},
        }),
      );
    }
    return TransportResponse(statusCode: 200, body: _fixture(action));
  }

  String _fixture(String action) => switch (action) {
    'health' => '{"ok":true,"data":{"service":"ORA Backend","status":"UP","spreadsheet":"ORA_Master_Data"}}',
    'config' => '{"ok":true,"data":{"config":{"XP_PER_KM":10,"FEATURE":true}}}',
    'levels' => '{"ok":true,"data":{"levels":[{"level":1,"levelName":"ROOKIE","requiredTotalXp":0}]}}',
    'quests' => '{"ok":true,"data":{"quests":[{"questId":"Q1","questName":"FIRST RUN","questType":"RUN_COUNT","targetValue":1,"unit":"RUN","rewardXp":10,"periodType":"DAILY","startDate":"","endDate":""}]}}',
    'login' => '{"ok":true,"data":{"sessionToken":"fixture","expiresInSeconds":3600,"participant":{"nik":"1001","nickname":"RUNNER","divisionGuild":"OPS","status":"ACTIVE"},"requiresNicknameActivation":false}}',
    'activateNickname' => '{"ok":true,"data":{"participant":{"nik":"1001","nickname":"HERO","divisionGuild":"OPS","status":"ACTIVE"},"nicknameSaved":true,"alreadyActivated":false}}',
    'updateNickname' => '{"ok":true,"data":{"participant":{"nik":"1001","nickname":"NEWHERO","divisionGuild":"OPS","status":"ACTIVE"},"nicknameSaved":true,"unchanged":false}}',
    'submitActivity' => '{"ok":true,"data":{"status":"SAVED","activityId":"A1","message":"Activity saved"}}',
    'getActivityHistory' => '{"ok":true,"data":{"activities":[{"activityId":"A1","startTime":"2026-08-14T00:00:00.000Z","endTime":"2026-08-14T00:30:00.000Z","durationSec":1800,"distanceKm":5.5,"avgPace":"05:27","status":"COMPLETED","source":"ANDROID","syncedAt":"2026-08-14T00:31:00.000Z"}],"limit":50,"offset":0,"total":1,"hasMore":false}}',
    'getUserStats' => '{"ok":true,"stats":{"nik":"1001","nickname":"RUNNER","division":"OPS","totalActivities":2,"totalDistanceKm":5.5,"totalDurationSec":1800,"totalXP":55,"currentLevel":2,"currentLevelName":"SCOUT","nextLevelXP":100,"lastActivityId":"A1","lastActivityAt":"2026-08-14","updatedAt":null}}',
    'getGuildSummary' => '{"ok":true,"status":"ACTIVE","guild":{"guildId":"OPS","guildName":"OPS","displayName":"OPERATIONS","description":"FAST","memberCount":2,"activeMemberCount":2,"totalDistanceKm":10,"totalActivities":4,"totalXP":100,"currentLevel":2,"currentLevelName":"TEAM"},"members":[{"nik":"1001","nickname":"RUNNER","division":"OPS","totalDistanceKm":5.5,"totalActivities":2,"totalXP":55,"currentLevel":2,"currentLevelName":"SCOUT"}]}',
    'getGuildDirectory' => '{"ok":true,"guilds":[{"guildId":"OPS","guildName":"OPS","displayName":"OPERATIONS","description":"FAST","status":"ACTIVE","memberCount":2,"activeMemberCount":2,"totalDistanceKm":10,"totalActivities":4,"totalXP":100,"currentLevel":2,"currentLevelName":"TEAM"}]}',
    'getLeaderboard' => '{"ok":true,"scope":"GLOBAL","metric":"TOTAL_XP","status":"ACTIVE","leaderboard":[{"rank":1,"nik":"1001","nickname":"RUNNER","division":"OPS","totalXP":55,"totalDistanceKm":5.5,"totalActivities":2,"currentLevel":2,"currentLevelName":"SCOUT"}],"currentUserRank":{"rank":1,"metricValue":55}}',
    'getQuestProgress' => '{"ok":true,"quests":[{"questId":"Q1","name":"FIRST RUN","type":"RUN_COUNT","target":1,"unit":"RUN","rewardXp":10,"period":"DAILY","activeFrom":"","activeTo":"","progress":1,"progressPercent":100,"status":"ACTIVE","completed":true,"claimable":true,"claimed":false}]}',
    'claimQuestReward' => '{"ok":true,"data":{"status":"CLAIMED","claim":{"questId":"Q1","rewardXp":10,"status":"CLAIMED","claimId":"C1","claimedAt":"2026-08-14"}}}',
    'submitAttendance' => '{"ok":true,"data":{"status":"SUCCESS","eventId":"E1","eventName":"MORNING RUN","checkInAt":"2026-08-14T00:00:00.000Z","baseXP":20,"streakCount":3,"streakBonusXP":30,"totalXP":50,"currentXP":105,"currentLevel":2}}',
    _ => throw StateError('Missing fixture for $action'),
  };
}

class _StaticTransport implements ApiTransport {
  _StaticTransport(this.response);
  final Map<String, Object?> response;

  @override
  Future<TransportResponse> request(
    Uri endpoint, {
    required String method,
    String? body,
    required Duration connectTimeout,
    required Duration readTimeout,
  }) async => TransportResponse(statusCode: 200, body: jsonEncode(response));
}

void main() {
  test('all 16 action contracts parse successful fixtures with exact payload names', () async {
    final transport = _ContractTransport();
    final client = AppsScriptClient(transport: transport);
    final auth = AppsScriptAuthApi(client);
    final api = AppsScriptFeatureApi(client);

    expect((await api.health())['status'], 'UP');
    expect((await api.config())['XP_PER_KM'], 10);
    expect((await api.levels()).single.levelName, 'ROOKIE');
    expect((await api.quests()).single.questId, 'Q1');
    expect((await auth.login('1001', '1234')).participant.nickname, 'RUNNER');
    expect((await auth.activateNickname('fixture', 'HERO')).nickname, 'HERO');
    expect(
      (await auth.updateNickname('fixture', 'NEWHERO')).nickname,
      'NEWHERO',
    );
    final activity = FinalActivity(
      activityId: 'A1',
      ownerNik: '1001',
      nicknameSnapshot: 'RUNNER',
      divisionGuildSnapshot: 'OPS',
      startDateTimeMillis: 1,
      endDateTimeMillis: 2001,
      distanceMeters: 10,
      activeDurationMillis: 2000,
      averagePaceSecondsPerKm: 200,
      createdAtMillis: 2001,
    );
    expect(
      await api.submitActivity(
        'fixture',
        ActivityPayloadMapper.mapV1(
          activity,
          deviceTime: DateTime.fromMillisecondsSinceEpoch(2001),
        ),
      ),
      'SAVED',
    );
    final history = await api.activityHistory('fixture');
    expect(history.single.activityId, 'A1');
    expect(history.single.distanceKm, 5.5);
    expect(history.single.averagePaceSecondsPerKm, 327);
    expect((await api.userStats('fixture')).totalXp, 55);
    expect((await api.guildData('fixture')).guild?.resolvedName, 'OPERATIONS');
    expect(
      (await api.leaderboard(
        'fixture',
        LeaderboardScope.global,
        LeaderboardMetric.totalXp,
      )).entries.single.rank,
      1,
    );
    expect(
      (await api.questProgress('fixture')).single.visualState,
      QuestVisualState.claimable,
    );
    expect((await api.claimQuest('fixture', 'Q1')).claimId, 'C1');
    final attendance = await api.submitAttendance('fixture', 'QR-TOKEN');
    expect(attendance.status, AttendanceStatus.success);
    expect(attendance.totalXp, 50);

    expect(transport.requests.map((item) => item['action']).toSet(), _actions);
    final login = transport.requests.singleWhere(
      (item) => item['action'] == 'login',
    );
    expect(login, {'action': 'login', 'nik': '1001', 'pin': '1234'});
    final activation = transport.requests.singleWhere(
      (item) => item['action'] == 'activateNickname',
    );
    expect(activation, {
      'action': 'activateNickname',
      'sessionToken': 'fixture',
      'nickname': 'HERO',
    });
    final nicknameUpdate = transport.requests.singleWhere(
      (item) => item['action'] == 'updateNickname',
    );
    expect(nicknameUpdate, {
      'action': 'updateNickname',
      'sessionToken': 'fixture',
      'nickname': 'NEWHERO',
    });
    final leaderboard = transport.requests.singleWhere(
      (item) => item['action'] == 'getLeaderboard',
    );
    expect(leaderboard['scope'], 'GLOBAL');
    expect(leaderboard['metric'], 'TOTAL_XP');
    final activityHistory = transport.requests.singleWhere(
      (item) => item['action'] == 'getActivityHistory',
    );
    expect(activityHistory, {
      'action': 'getActivityHistory',
      'sessionToken': 'fixture',
      'limit': 50,
      'offset': 0,
    });
    final attendanceRequest = transport.requests.singleWhere(
      (item) => item['action'] == 'submitAttendance',
    );
    expect(attendanceRequest, {
      'action': 'submitAttendance',
      'sessionToken': 'fixture',
      'qrToken': 'QR-TOKEN',
    });
  });

  test('all 16 actions preserve backend error codes', () async {
    for (final action in _actions) {
      final transport = _ContractTransport()..failAction = action;
      final client = AppsScriptClient(transport: transport);
      final call = action == 'health'
          ? client.get(action)
          : client.call(action);
      await expectLater(
        call,
        throwsA(
          isA<BackendFailure>().having(
            (error) => error.code,
            'code',
            '${action}_ERROR',
          ),
        ),
        reason: action,
      );
    }
  });

  test('leaderboard preserves backend tie order, top 50, and current rank outside list', () async {
    final entries = List.generate(
      50,
      (index) => {
        'rank': index + 1,
        'nik': (1000 + index).toString(),
        'nickname': index == 0
            ? 'ALPHA'
            : index == 1
            ? 'BRAVO'
            : 'RUNNER$index',
        'division': 'OPS',
        'totalXP': index < 2 ? 500 : 500 - index,
        'totalDistanceKm': 1,
        'totalActivities': 1,
        'currentLevel': 1,
        'currentLevelName': 'ROOKIE',
      },
    );
    final api = AppsScriptFeatureApi(
      AppsScriptClient(
        transport: _StaticTransport({
          'ok': true,
          'scope': 'GLOBAL',
          'metric': 'TOTAL_XP',
          'status': 'ACTIVE',
          'leaderboard': entries,
          'currentUserRank': {'rank': 51, 'metricValue': 1},
        }),
      ),
    );
    final result = await api.leaderboard(
      'fixture',
      LeaderboardScope.global,
      LeaderboardMetric.totalXp,
    );
    expect(result.entries, hasLength(50));
    expect(result.entries.take(2).map((entry) => entry.nickname), [
      'ALPHA',
      'BRAVO',
    ]);
    expect(result.currentUserRank?.rank, 51);
  });

  test(
    'missing numeric user stats fields use backend-compatible zero defaults',
    () {
      final stats = UserStats.fromJson({'nik': '1001'});
      expect(stats.totalActivities, 0);
      expect(stats.totalDistanceKm, 0);
      expect(stats.totalDurationSec, 0);
      expect(stats.totalXp, 0);
      expect(stats.nextLevelXp, isNull);
    },
  );
}
