import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ora_flutter/core/network/apps_script_client.dart';
import 'package:ora_flutter/features/activity/data/activity_store.dart';
import 'package:ora_flutter/features/activity/domain/final_activity.dart';
import 'package:ora_flutter/features/activity/domain/activity_sync.dart';
import 'package:ora_flutter/features/activity/domain/server_activity_summary.dart';
import 'package:ora_flutter/features/auth/domain/auth_models.dart';
import 'package:ora_flutter/features/dashboard/application/feature_controller.dart';
import 'package:ora_flutter/features/dashboard/data/ora_feature_api.dart';
import 'package:ora_flutter/features/dashboard/domain/feature_models.dart';

class _FakeFeatureApi implements OraFeatureApi {
  UserStats stats = const UserStats(
    nik: '1001',
    nickname: 'RUNNER',
    division: 'OPS',
    totalActivities: 0,
    totalDistanceKm: 0,
    totalDurationSec: 0,
    totalXp: 0,
    currentLevel: 1,
    currentLevelName: 'ROOKIE',
    nextLevelXp: 100,
    lastActivityId: '',
    lastActivityAt: '',
    updatedAt: null,
  );
  List<Quest> publicQuests = const [];
  List<Quest> progressQuests = const [];
  BackendFailure? progressFailure;
  GuildData guild = const GuildData(
    status: 'UNASSIGNED',
    guild: null,
    members: [],
    directory: [],
  );
  LeaderboardData board = const LeaderboardData(
    scope: LeaderboardScope.global,
    metric: LeaderboardMetric.totalXp,
    status: 'ACTIVE',
    entries: [],
    currentUserRank: null,
  );
  QuestClaim claim = const QuestClaim(
    questId: 'Q1',
    rewardXp: 10,
    status: 'CLAIMED',
    claimId: 'C1',
  );
  Completer<QuestClaim>? claimCompleter;
  int claimCalls = 0;
  int statsCalls = 0;
  LeaderboardScope? requestedScope;
  LeaderboardMetric? requestedMetric;
  int submitCalls = 0;
  String submitStatus = 'SAVED';
  BackendFailure? submitFailure;
  Completer<String>? submitCompleter;
  final submittedPayloads = <ActivityUploadPayload>[];
  List<ServerActivitySummary> backendActivities = const [];
  BackendFailure? activityHistoryFailure;

  @override
  Future<Map<String, Object?>> health() async => const {};
  @override
  Future<Map<String, Object?>> config() async => const {};
  @override
  Future<List<OraLevel>> levels() async => const [];
  @override
  Future<List<Quest>> quests() async => publicQuests;
  @override
  Future<UserStats> userStats(String sessionToken) async {
    statsCalls++;
    return stats;
  }

  @override
  Future<GuildData> guildData(String sessionToken) async => guild;
  @override
  Future<LeaderboardData> leaderboard(
    String sessionToken,
    LeaderboardScope scope,
    LeaderboardMetric metric,
  ) async {
    requestedScope = scope;
    requestedMetric = metric;
    return board;
  }

  @override
  Future<List<Quest>> questProgress(String sessionToken) async {
    if (progressFailure case final error?) throw error;
    return progressQuests;
  }

  @override
  Future<QuestClaim> claimQuest(String sessionToken, String questId) async {
    claimCalls++;
    return claimCompleter == null ? claim : claimCompleter!.future;
  }

  @override
  Future<String> submitActivity(
    String sessionToken,
    ActivityUploadPayload payload,
  ) async {
    submitCalls++;
    submittedPayloads.add(payload);
    if (submitFailure case final error?) throw error;
    return submitCompleter?.future ?? submitStatus;
  }

  @override
  Future<List<ServerActivitySummary>> activityHistory(
    String sessionToken, {
    int limit = 50,
    int offset = 0,
  }) async {
    if (activityHistoryFailure case final error?) throw error;
    return backendActivities;
  }
}

final _session = UserSession(
  sessionToken: 'fixture',
  nik: '1001',
  nickname: 'RUNNER',
  divisionGuild: 'OPS',
  status: 'ACTIVE',
  expiresAt: DateTime.utc(2030),
);

Quest _quest({
  bool completed = false,
  bool claimed = false,
  bool? claimable,
  String? status,
  String? blocked,
  double progress = 0,
}) => Quest(
  questId: 'Q1',
  questName: 'FIRST RUN',
  questType: 'RUN_COUNT',
  targetValue: 1,
  unit: 'RUN',
  rewardXp: 10,
  periodType: 'DAILY',
  startDate: '',
  endDate: '',
  progress: progress,
  progressPercent: progress * 100,
  completed: completed,
  claimed: claimed,
  claimable: claimable,
  status: status,
  claimBlockedReason: blocked,
);

FeatureController _controller(_FakeFeatureApi api) => FeatureController(
  session: _session,
  api: api,
  activityStore: MemoryActivityStore(),
);

FinalActivity _localActivity(
  String id, {
  required int start,
  ActivitySyncStatus syncStatus = ActivitySyncStatus.pending,
}) => FinalActivity(
  activityId: id,
  ownerNik: _session.nik,
  nicknameSnapshot: 'LOCAL RUNNER',
  divisionGuildSnapshot: 'LOCAL OPS',
  startDateTimeMillis: start,
  endDateTimeMillis: start + 1000,
  distanceMeters: 1200,
  activeDurationMillis: 360000,
  averagePaceSecondsPerKm: 300,
  createdAtMillis: start + 1000,
  syncStatus: syncStatus,
);

ServerActivitySummary _backendActivity(String id, {required int start}) =>
    ServerActivitySummary(
      activityId: id,
      startTime: DateTime.fromMillisecondsSinceEpoch(start, isUtc: true),
      endTime: DateTime.fromMillisecondsSinceEpoch(start + 1000, isUtc: true),
      durationSec: 360,
      distanceKm: 1.2,
      averagePaceSecondsPerKm: 300,
      status: 'COMPLETED',
      source: 'ANDROID',
      syncedAt: DateTime.fromMillisecondsSinceEpoch(start + 2000, isUtc: true),
    );

void main() {
  test('backend-only activity appears when local store is empty', () async {
    final api = _FakeFeatureApi()
      ..backendActivities = [_backendActivity('SERVER-1', start: 1000)];
    final controller = _controller(api);

    await controller.loadActivities();

    expect(controller.activities.single.activityId, 'SERVER-1');
    expect(controller.latestActivity?.activityId, 'SERVER-1');
    expect(controller.activities.single.syncStatus, ActivitySyncStatus.synced);
  });

  test('local-only pending activity remains visible', () async {
    final api = _FakeFeatureApi();
    final store = MemoryActivityStore();
    await store.insert(_localActivity('LOCAL-1', start: 1000));
    final controller = FeatureController(
      session: _session,
      api: api,
      activityStore: store,
    );

    await controller.loadActivities();

    expect(controller.activities.single.activityId, 'LOCAL-1');
    expect(controller.activities.single.syncStatus, ActivitySyncStatus.pending);
  });

  test(
    'matching backend and local ActivityId is shown once with local data',
    () async {
      final api = _FakeFeatureApi()
        ..backendActivities = [_backendActivity('SAME', start: 1000)];
      final store = MemoryActivityStore();
      await store.insert(_localActivity('SAME', start: 1000));
      final controller = FeatureController(
        session: _session,
        api: api,
        activityStore: store,
      );

      await controller.loadActivities();

      expect(controller.activities, hasLength(1));
      expect(controller.activities.single.nicknameSnapshot, 'LOCAL RUNNER');
      expect(
        controller.activities.single.syncStatus,
        ActivitySyncStatus.synced,
      );
    },
  );

  test(
    'remove synced local data falls back to backend summary without resync',
    () async {
      final api = _FakeFeatureApi()
        ..backendActivities = [_backendActivity('SAME', start: 1000)];
      final store = MemoryActivityStore();
      await store.insert(_localActivity('SAME', start: 1000));
      final controller = FeatureController(
        session: _session,
        api: api,
        activityStore: store,
      );

      await controller.loadActivities();
      expect(controller.activities, hasLength(1));
      expect(controller.localActivityIds, contains('SAME'));
      expect(controller.activities.single.nicknameSnapshot, 'LOCAL RUNNER');

      expect(await controller.removeLocalActivityData('SAME'), isTrue);

      expect(controller.activities, hasLength(1));
      final summary = controller.activities.single;
      expect(summary.activityId, 'SAME');
      expect(summary.syncStatus, ActivitySyncStatus.synced);
      expect(summary.nicknameSnapshot, isNull);
      expect(summary.distanceMeters, 1200);
      expect(summary.activeDurationMillis, 360000);
      expect(summary.averagePaceSecondsPerKm, 300);
      expect(controller.localActivityIds, isNot(contains('SAME')));
      expect(await store.newestFirst(_session.nik), isEmpty);
      expect(await store.dueSync(_session.nik, 999999, force: true), isEmpty);
      expect(api.submitCalls, 0);
    },
  );

  test('newer local pending activity becomes Last Adventure', () async {
    final api = _FakeFeatureApi()
      ..backendActivities = [_backendActivity('SERVER-OLD', start: 1000)];
    final store = MemoryActivityStore();
    await store.insert(_localActivity('LOCAL-NEW', start: 5000));
    final controller = FeatureController(
      session: _session,
      api: api,
      activityStore: store,
    );

    await controller.loadActivities();

    expect(controller.latestActivity?.activityId, 'LOCAL-NEW');
  });

  test('newer backend activity becomes Last Adventure', () async {
    final api = _FakeFeatureApi()
      ..backendActivities = [_backendActivity('SERVER-NEW', start: 5000)];
    final store = MemoryActivityStore();
    await store.insert(_localActivity('LOCAL-OLD', start: 1000));
    final controller = FeatureController(
      session: _session,
      api: api,
      activityStore: store,
    );

    await controller.loadActivities();

    expect(controller.latestActivity?.activityId, 'SERVER-NEW');
  });

  test('backend-only summary preserves distance duration and pace', () async {
    final api = _FakeFeatureApi()
      ..backendActivities = [_backendActivity('SUMMARY', start: 1000)];
    final controller = _controller(api);

    await controller.loadActivities();

    final activity = controller.activities.single;
    expect(activity.distanceMeters, 1200);
    expect(activity.activeDurationMillis, 360000);
    expect(activity.averagePaceSecondsPerKm, 300);
  });

  test('backend unavailable falls back to local activities', () async {
    final api = _FakeFeatureApi()
      ..activityHistoryFailure = const BackendFailure(
        BackendFailureKind.connection,
        'offline',
      );
    final store = MemoryActivityStore();
    await store.insert(_localActivity('OFFLINE', start: 1000));
    final controller = FeatureController(
      session: _session,
      api: api,
      activityStore: store,
    );

    await controller.loadActivities();

    expect(controller.activityPhase, LoadPhase.ready);
    expect(controller.activities.single.activityId, 'OFFLINE');
    expect(controller.activityWarning, contains('DEVICE LOG'));
  });

  test(
    'durable sync retries the identical payload and ACKs duplicate',
    () async {
      final api = _FakeFeatureApi();
      final store = MemoryActivityStore();
      final controller = FeatureController(
        session: _session,
        api: api,
        activityStore: store,
      );
      await store.insert(
        FinalActivity(
          activityId: 'SYNC-1',
          ownerNik: _session.nik,
          nicknameSnapshot: _session.nickname,
          divisionGuildSnapshot: _session.divisionGuild,
          startDateTimeMillis: 1000,
          endDateTimeMillis: 3000,
          distanceMeters: 20,
          activeDurationMillis: 2000,
          averagePaceSecondsPerKm: 100,
          createdAtMillis: 3000,
        ),
      );
      api.submitFailure = const BackendFailure(
        BackendFailureKind.connection,
        'offline',
      );
      await controller.syncService.run(_session, force: true);
      final firstPayload = api.submittedPayloads.single.encode();
      expect(await store.pending(_session.nik), hasLength(1));

      api.submitFailure = null;
      api.submitStatus = 'DUPLICATE';
      final result = await controller.syncService.run(_session, force: true);
      expect(result.synced, 1);
      expect(api.submittedPayloads.last.encode(), firstPayload);
      expect(await store.pending(_session.nik), isEmpty);
      controller.dispose();
    },
  );

  test('sync service is single-flight', () async {
    final api = _FakeFeatureApi()..submitCompleter = Completer<String>();
    final store = MemoryActivityStore();
    final controller = FeatureController(
      session: _session,
      api: api,
      activityStore: store,
    );
    await store.insert(
      FinalActivity(
        activityId: 'SYNC-2',
        ownerNik: _session.nik,
        nicknameSnapshot: 'RUNNER',
        divisionGuildSnapshot: 'OPS',
        startDateTimeMillis: 1,
        endDateTimeMillis: 2,
        distanceMeters: 1,
        activeDurationMillis: 1,
        averagePaceSecondsPerKm: null,
        createdAtMillis: 2,
      ),
    );
    final first = controller.syncService.run(_session, force: true);
    await Future<void>.delayed(Duration.zero);
    final second = await controller.syncService.run(_session, force: true);
    expect(second.alreadyRunning, isTrue);
    expect(api.submitCalls, 1);
    api.submitCompleter!.complete('SAVED');
    expect((await first).synced, 1);
    controller.dispose();
  });

  test(
    'user stats defaults stay zero and owner mismatch is rejected',
    () async {
      final api = _FakeFeatureApi();
      final controller = _controller(api);
      await controller.loadStats();
      expect(controller.stats?.totalXp, 0);
      expect(controller.statsPhase, LoadPhase.ready);

      api.stats = UserStats(
        nik: 'OTHER',
        nickname: '',
        division: '',
        totalActivities: 0,
        totalDistanceKm: 0,
        totalDurationSec: 0,
        totalXp: 0,
        currentLevel: 0,
        currentLevelName: '',
        nextLevelXp: null,
        lastActivityId: '',
        lastActivityAt: '',
        updatedAt: null,
      );
      await controller.loadStats(force: true);
      expect(controller.statsPhase, LoadPhase.error);
      expect(controller.statsError, isNotNull);
    },
  );

  test('quest progress failure falls back visibly to public master', () async {
    final api = _FakeFeatureApi()
      ..progressFailure = const BackendFailure(
        BackendFailureKind.connection,
        'offline',
      )
      ..publicQuests = [_quest()];
    final controller = _controller(api);
    await controller.loadQuests();
    expect(controller.questPhase, LoadPhase.ready);
    expect(controller.questsAreFallback, isTrue);
    expect(controller.quests.single.visualState, QuestVisualState.notStarted);
  });

  test('quest visual and guild reward blocking states match contract', () {
    expect(_quest(progress: .5).visualState, QuestVisualState.inProgress);
    expect(
      _quest(completed: true, claimable: true).visualState,
      QuestVisualState.claimable,
    );
    expect(_quest(claimed: true).visualState, QuestVisualState.claimed);
    expect(_quest(status: 'NO_GUILD').visualState, QuestVisualState.noGuild);
    expect(
      _quest(status: 'UNKNOWN_TYPE').visualState,
      QuestVisualState.unknown,
    );
    expect(
      _quest(status: 'UNSUPPORTED_GROUP_SCOPE').visualState,
      QuestVisualState.unsupported,
    );
    expect(
      _quest(completed: true, blocked: 'GUILD_REWARD_NOT_READY').canClaim,
      isFalse,
    );
  });

  test('claim is single-flight, marks claimed, and refreshes stats', () async {
    final completer = Completer<QuestClaim>();
    final api = _FakeFeatureApi()
      ..progressQuests = [_quest(completed: true, claimable: true)]
      ..claimCompleter = completer;
    final controller = _controller(api);
    await controller.loadQuests();
    final first = controller.claimQuest('Q1');
    final second = controller.claimQuest('Q1');
    expect(api.claimCalls, 1);
    completer.complete(api.claim);
    await Future.wait([first, second]);
    expect(controller.quests.single.claimed, isTrue);
    expect(api.statsCalls, 1);
    expect(controller.claimMessage, '+10 XP CLAIMED');
  });

  test('blocked claim never reaches backend', () async {
    final api = _FakeFeatureApi()
      ..progressQuests = [_quest(status: 'NO_GUILD')];
    final controller = _controller(api);
    await controller.loadQuests();
    await controller.claimQuest('Q1');
    expect(api.claimCalls, 0);
    expect(controller.claimMessage, 'QUEST REWARD IS NOT AVAILABLE');
  });

  test(
    'guild unassigned, inactive, and legacy metadata are preserved',
    () async {
      final api = _FakeFeatureApi();
      final controller = _controller(api);
      await controller.loadGuild();
      expect(controller.guildData?.status, 'UNASSIGNED');

      api.guild = GuildData(
        status: 'GUILD_INACTIVE',
        guild: const GuildSummary(
          guildId: 'LEGACY',
          guildName: 'LEGACY',
          memberCount: 0,
          activeMemberCount: 0,
          totalDistanceKm: 0,
          totalActivities: 0,
          totalXp: 0,
          currentLevel: 1,
          currentLevelName: '',
          displayName: '',
          description: '',
        ),
        members: const [],
        directory: const [],
      );
      await controller.loadGuild(force: true);
      expect(controller.guildData?.status, 'GUILD_INACTIVE');
      expect(controller.guildData?.guild?.resolvedName, 'LEGACY');
    },
  );

  test(
    'leaderboard forwards scope and metric and preserves empty NO_GUILD',
    () async {
      final api = _FakeFeatureApi()
        ..board = const LeaderboardData(
          scope: LeaderboardScope.guild,
          metric: LeaderboardMetric.totalDistance,
          status: 'NO_GUILD',
          entries: [],
          currentUserRank: null,
        );
      final controller = _controller(api);
      await controller.selectLeaderboardScope(LeaderboardScope.guild);
      await controller.selectLeaderboardMetric(LeaderboardMetric.totalDistance);
      expect(api.requestedScope, LeaderboardScope.guild);
      expect(api.requestedMetric, LeaderboardMetric.totalDistance);
      expect(controller.leaderboardData?.entries, isEmpty);
      expect(controller.leaderboardData?.currentUserRank, isNull);
    },
  );
}
