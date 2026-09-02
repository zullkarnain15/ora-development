import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ora_flutter/core/network/apps_script_client.dart';
import 'package:ora_flutter/features/activity/data/activity_store.dart';
import 'package:ora_flutter/features/activity/domain/final_activity.dart';
import 'package:ora_flutter/features/activity/domain/activity_sync.dart';
import 'package:ora_flutter/features/activity/domain/server_activity_summary.dart';
import 'package:ora_flutter/features/auth/domain/auth_models.dart';
import 'package:ora_flutter/features/dashboard/application/feature_controller.dart';
import 'package:ora_flutter/features/dashboard/data/feature_cache_store.dart';
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
  Completer<UserStats>? statsCompleter;
  List<Quest> publicQuests = const [];
  List<Quest> progressQuests = const [];
  Completer<List<Quest>>? progressCompleter;
  BackendFailure? progressFailure;
  int progressCalls = 0;
  GuildData guild = const GuildData(
    status: 'UNASSIGNED',
    guild: null,
    members: [],
    directory: [],
  );
  Completer<GuildData>? guildCompleter;
  LeaderboardData board = const LeaderboardData(
    scope: LeaderboardScope.global,
    metric: LeaderboardMetric.totalXp,
    status: 'ACTIVE',
    entries: [],
    currentUserRank: null,
  );
  Completer<LeaderboardData>? leaderboardCompleter;
  QuestClaim claim = const QuestClaim(
    questId: 'Q1',
    rewardXp: 10,
    status: 'CLAIMED',
    claimId: 'C1',
  );
  Completer<QuestClaim>? claimCompleter;
  int claimCalls = 0;
  AttendanceResult attendance = const AttendanceResult(
    status: AttendanceStatus.success,
    rawStatus: 'SUCCESS',
    baseXp: 20,
    streakCount: 1,
    streakBonusXp: 0,
    totalXp: 20,
    currentXp: 20,
    currentLevel: 1,
  );
  Completer<AttendanceResult>? attendanceCompleter;
  BackendFailure? attendanceFailure;
  int attendanceCalls = 0;
  int statsCalls = 0;
  int guildCalls = 0;
  int leaderboardCalls = 0;
  LeaderboardScope? requestedScope;
  LeaderboardMetric? requestedMetric;
  int submitCalls = 0;
  String submitStatus = 'SAVED';
  BackendFailure? submitFailure;
  Completer<String>? submitCompleter;
  final submittedPayloads = <ActivityUploadPayload>[];
  List<ServerActivitySummary> backendActivities = const [];
  Completer<List<ServerActivitySummary>>? activityHistoryCompleter;
  int activityHistoryCalls = 0;
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
    return statsCompleter?.future ?? stats;
  }

  @override
  Future<GuildData> guildData(
    String sessionToken,
    LeaderboardScope scope,
    LeaderboardMetric metric,
  ) async {
    guildCalls++;
    requestedScope = scope;
    requestedMetric = metric;
    if (guildCompleter case final completer?) return completer.future;
    return GuildData(
      status: guild.status,
      guild: guild.guild,
      members: guild.members,
      directory: guild.directory,
      leaderboard: board,
    );
  }

  @override
  Future<LeaderboardData> leaderboard(
    String sessionToken,
    LeaderboardScope scope,
    LeaderboardMetric metric,
  ) async {
    leaderboardCalls++;
    requestedScope = scope;
    requestedMetric = metric;
    return leaderboardCompleter?.future ?? board;
  }

  @override
  Future<List<Quest>> questProgress(String sessionToken) async {
    progressCalls++;
    if (progressFailure case final error?) throw error;
    return progressCompleter?.future ?? progressQuests;
  }

  @override
  Future<QuestClaim> claimQuest(String sessionToken, String questId) async {
    claimCalls++;
    return claimCompleter == null ? claim : claimCompleter!.future;
  }

  @override
  Future<AttendanceResult> submitAttendance(
    String sessionToken,
    String qrToken,
  ) async {
    attendanceCalls++;
    if (attendanceFailure case final error?) throw error;
    return attendanceCompleter?.future ?? attendance;
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
    activityHistoryCalls++;
    if (activityHistoryFailure case final error?) throw error;
    return activityHistoryCompleter?.future ?? backendActivities;
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

FeatureController _controller(
  _FakeFeatureApi api, {
  FeatureCacheStore? cacheStore,
  UserSession? session,
}) => FeatureController(
  session: session ?? _session,
  api: api,
  activityStore: MemoryActivityStore(),
  cacheStore: cacheStore,
);

UserStats _stats(int totalXp, {String nik = '1001'}) => UserStats(
  nik: nik,
  nickname: 'RUNNER',
  division: 'OPS',
  totalActivities: totalXp ~/ 10,
  totalDistanceKm: totalXp / 10,
  totalDurationSec: totalXp.toDouble(),
  totalXp: totalXp,
  currentLevel: 1,
  currentLevelName: 'ROOKIE',
  nextLevelXp: 100,
  lastActivityId: '',
  lastActivityAt: '',
  updatedAt: null,
);

LeaderboardData _board(int rank) => LeaderboardData(
  scope: LeaderboardScope.global,
  metric: LeaderboardMetric.totalXp,
  status: 'ACTIVE',
  entries: [
    LeaderboardEntry(
      rank: rank,
      nik: _session.nik,
      nickname: 'RUNNER',
      division: 'OPS',
      totalXp: 100,
      totalDistanceKm: 10,
      totalActivities: 2,
      currentLevel: 1,
      currentLevelName: 'ROOKIE',
    ),
  ],
  currentUserRank: CurrentUserRank(rank: rank, metricValue: 100),
);

GuildData _guild(String name, LeaderboardData board) => GuildData(
  status: 'ACTIVE',
  guild: GuildSummary(
    guildId: 'OPS',
    guildName: name,
    memberCount: 1,
    activeMemberCount: 1,
    totalDistanceKm: 10,
    totalActivities: 2,
    totalXp: 100,
    currentLevel: 1,
    currentLevelName: 'ROOKIE',
    displayName: name,
    description: '',
  ),
  members: const [],
  directory: const [],
  leaderboard: board,
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

Future<void> _waitFor(bool Function() condition) async {
  for (var attempt = 0; attempt < 20 && !condition(); attempt++) {
    await Future<void>.delayed(Duration.zero);
  }
  expect(condition(), isTrue);
}

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

  test(
    'imported activity uses the existing local queue and sync flow',
    () async {
      final api = _FakeFeatureApi();
      final store = MemoryActivityStore();
      final controller = FeatureController(
        session: _session,
        api: api,
        activityStore: store,
      );
      final activity = _localActivity(
        'import_strava_fixture',
        start: DateTime(2026, 8, 25, 6).millisecondsSinceEpoch,
      );

      expect(await controller.saveImportedActivity(activity), isTrue);

      expect(controller.activities.single.activityId, activity.activityId);
      expect(api.submitCalls, 1);
      expect(api.submittedPayloads.single.fields['source'], 'STRAVA');
      expect(await store.pending(_session.nik), isEmpty);
      controller.dispose();
    },
  );

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
    expect(api.progressCalls, 1);
    expect(controller.claimMessage, '+10 XP CLAIMED');
  });

  test('attendance submission is single-flight and refreshes server data only on success', () async {
    final completer = Completer<AttendanceResult>();
    final api = _FakeFeatureApi()..attendanceCompleter = completer;
    final controller = _controller(api);

    final first = controller.submitAttendance('QR-1');
    final second = controller.submitAttendance('QR-1');
    expect(api.attendanceCalls, 1);
    completer.complete(api.attendance);

    final results = await Future.wait([first, second]);
    expect(
      results.map((result) => result.status),
      everyElement(AttendanceStatus.success),
    );
    expect(api.statsCalls, 1);

    api.attendance = const AttendanceResult(
      status: AttendanceStatus.alreadyCheckedIn,
      rawStatus: 'ALREADY_CHECKED_IN',
      baseXp: 0,
      streakCount: 0,
      streakBonusXp: 0,
      totalXp: 0,
      currentXp: 20,
      currentLevel: 1,
    );
    api.attendanceCompleter = null;
    await controller.submitAttendance('QR-1');
    expect(api.attendanceCalls, 2);
    expect(api.statsCalls, 1);
    expect(api.progressCalls, 1);
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
      expect(controller.leaderboardPhase, LoadPhase.ready);
      expect(api.guildCalls, 1);
      expect(api.leaderboardCalls, 0);

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

  test(
    'cached Home and activity history render before refresh completes',
    () async {
      final cache = MemoryFeatureCacheStore();
      await cache.write(
        FeatureCacheSnapshot(
          ownerNik: _session.nik,
          savedAtMillis: 1,
          stats: _stats(20),
          activities: [
            _localActivity(
              'CACHED-RUN',
              start: 1000,
              syncStatus: ActivitySyncStatus.synced,
            ),
          ],
        ),
      );
      final api = _FakeFeatureApi()
        ..statsCompleter = Completer<UserStats>()
        ..activityHistoryCompleter = Completer<List<ServerActivitySummary>>();
      final controller = _controller(api, cacheStore: cache);

      final refresh = controller.loadHome();
      await _waitFor(
        () => api.statsCalls == 1 && api.activityHistoryCalls == 1,
      );

      expect(controller.stats?.totalXp, 20);
      expect(controller.latestActivity?.activityId, 'CACHED-RUN');
      expect(controller.isStatsRefreshing, isTrue);
      expect(controller.isActivityRefreshing, isTrue);

      api.statsCompleter!.complete(_stats(80));
      api.activityHistoryCompleter!.complete([
        _backendActivity('FRESH-RUN', start: 5000),
      ]);
      await refresh;
      expect(controller.stats?.totalXp, 80);
      expect(controller.latestActivity?.activityId, 'FRESH-RUN');
    },
  );

  test(
    'cached Quest renders first and valid backend replaces persistence',
    () async {
      final cache = MemoryFeatureCacheStore();
      await cache.write(
        FeatureCacheSnapshot(
          ownerNik: _session.nik,
          savedAtMillis: 1,
          quests: [_quest(progress: .2)],
        ),
      );
      final api = _FakeFeatureApi()
        ..progressCompleter = Completer<List<Quest>>();
      final controller = _controller(api, cacheStore: cache);

      final refresh = controller.loadQuests();
      await _waitFor(() => api.progressCalls == 1);
      expect(controller.quests.single.progress, .2);
      expect(controller.isQuestRefreshing, isTrue);

      api.progressCompleter!.complete([_quest(progress: .8)]);
      await refresh;
      await controller.settleCacheWrites();
      expect(controller.quests.single.progress, .8);
      expect((await cache.read(_session.nik))?.quests?.single.progress, .8);
    },
  );

  test(
    'cached Guild and Leaderboard render before backend completes',
    () async {
      final cache = MemoryFeatureCacheStore();
      final cachedBoard = _board(4);
      await cache.write(
        FeatureCacheSnapshot(
          ownerNik: _session.nik,
          savedAtMillis: 1,
          guildData: _guild('CACHED GUILD', cachedBoard),
          leaderboards: {
            leaderboardCacheKey(
              LeaderboardScope.global,
              LeaderboardMetric.totalXp,
            ): cachedBoard,
          },
        ),
      );
      final api = _FakeFeatureApi()..guildCompleter = Completer<GuildData>();
      final controller = _controller(api, cacheStore: cache);

      final refresh = controller.loadGuild();
      await _waitFor(() => api.guildCalls == 1);
      expect(controller.guildData?.guild?.resolvedName, 'CACHED GUILD');
      expect(controller.leaderboardData?.currentUserRank?.rank, 4);
      expect(controller.isGuildRefreshing, isTrue);
      expect(controller.isLeaderboardRefreshing, isTrue);

      final freshBoard = _board(1);
      api.guildCompleter!.complete(_guild('FRESH GUILD', freshBoard));
      await refresh;
      expect(controller.guildData?.guild?.resolvedName, 'FRESH GUILD');
      expect(controller.leaderboardData?.currentUserRank?.rank, 1);
    },
  );

  test('backend failure keeps cached data with non-blocking warning', () async {
    final cache = MemoryFeatureCacheStore();
    await cache.write(
      FeatureCacheSnapshot(
        ownerNik: _session.nik,
        savedAtMillis: 1,
        quests: [_quest(progress: .6)],
      ),
    );
    final api = _FakeFeatureApi()
      ..progressFailure = const BackendFailure(
        BackendFailureKind.connection,
        'offline',
      );
    final controller = _controller(api, cacheStore: cache);

    await controller.loadQuests();

    expect(controller.questPhase, LoadPhase.ready);
    expect(controller.quests.single.progress, .6);
    expect(controller.questsAreFallback, isFalse);
    expect(controller.questError, contains('SAVED DATA'));
  });

  test('owner-scoped cache does not leak after account switch', () async {
    final cache = MemoryFeatureCacheStore();
    await cache.write(
      FeatureCacheSnapshot(
        ownerNik: _session.nik,
        savedAtMillis: 1,
        quests: [_quest(progress: .9)],
      ),
    );
    final otherSession = UserSession(
      sessionToken: 'other-session',
      nik: '2002',
      nickname: 'OTHER',
      divisionGuild: 'SALES',
      status: 'ACTIVE',
      expiresAt: DateTime.utc(2030),
    );
    final api = _FakeFeatureApi()..progressCompleter = Completer<List<Quest>>();
    final controller = _controller(
      api,
      cacheStore: cache,
      session: otherSession,
    );

    final refresh = controller.loadQuests();
    await _waitFor(() => api.progressCalls == 1);
    expect(controller.quests, isEmpty);
    expect(
      featureCacheKeyForOwner(_session.nik),
      isNot(featureCacheKeyForOwner(otherSession.nik)),
    );
    api.progressCompleter!.complete(const []);
    await refresh;
  });

  test('force refresh always calls backend', () async {
    final api = _FakeFeatureApi()..progressQuests = [_quest(progress: .1)];
    final controller = _controller(api);

    await controller.loadQuests();
    await controller.loadQuests(force: true);

    expect(api.progressCalls, 2);
  });
}
