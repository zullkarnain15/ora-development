import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/network/apps_script_client.dart';
import '../../activity/application/activity_sync_service.dart';
import '../../activity/data/activity_store.dart';
import '../../activity/domain/final_activity.dart';
import '../../activity/domain/server_activity_summary.dart';
import '../../auth/domain/auth_models.dart';
import '../data/feature_cache_store.dart';
import '../data/ora_feature_api.dart';
import '../domain/feature_models.dart';

enum ImportedActivitySaveOutcome { duplicate, synced, pending }

typedef FeatureControllerFactory = FeatureController Function(
  UserSession session,
);

class FeatureController extends ChangeNotifier {
  FeatureController({
    required this.session,
    required this.api,
    required this.activityStore,
    FeatureCacheStore? cacheStore,
  }) : cacheStore = cacheStore ?? MemoryFeatureCacheStore(),
       syncService = ActivitySyncService(store: activityStore, api: api);

  UserSession session;
  final OraFeatureApi api;
  final ActivityStore activityStore;
  final FeatureCacheStore cacheStore;
  final ActivitySyncService syncService;

  LoadPhase statsPhase = LoadPhase.idle;
  UserStats? stats;
  String? statsError;

  LoadPhase questPhase = LoadPhase.idle;
  List<Quest> quests = const [];
  bool questsAreFallback = false;
  String? questError;
  String? claimingQuestId;
  String? claimMessage;
  String? claimMessageQuestId;
  Future<AttendanceResult>? _attendanceSubmission;

  LoadPhase guildPhase = LoadPhase.idle;
  GuildData? guildData;
  String? guildError;

  LoadPhase leaderboardPhase = LoadPhase.idle;
  LeaderboardData? leaderboardData;
  String? leaderboardError;
  LeaderboardScope leaderboardScope = LeaderboardScope.global;
  LeaderboardMetric leaderboardMetric = LeaderboardMetric.totalXp;

  LoadPhase activityPhase = LoadPhase.idle;
  List<FinalActivity> activities = const [];
  Set<String> localActivityIds = const {};
  FinalActivity? latestActivity;
  ActivityTotals activityTotals = ActivityTotals.zero;
  String? activityError;
  String? activityWarning;
  bool isSyncing = false;
  String? syncMessage;
  bool syncError = false;

  bool _disposed = false;
  Future<void>? _hydrateFuture;
  Future<void> _cacheWriteQueue = Future<void>.value();
  final Map<String, LeaderboardData> _cachedLeaderboards = {};
  bool _hasPersistentQuestData = false;

  void updateSession(UserSession value) {
    if (value.nik != session.nik) return;
    session = value;
    _safeNotify();
  }

  Future<void> loadHome({bool force = false}) async {
    await Future.wait([loadStats(force: force), loadActivities(force: force)]);
  }

  Future<void> loadStats({bool force = false}) async {
    await _ensureHydrated();
    if (_disposed || statsPhase == LoadPhase.loading) return;
    statsPhase = LoadPhase.loading;
    statsError = null;
    _safeNotify();
    try {
      final result = await api.userStats(session.sessionToken);
      if (result.nik.isNotEmpty && result.nik != session.nik) {
        throw const BackendFailure(
          BackendFailureKind.invalidResponse,
          'Stats owner does not match the active session.',
        );
      }
      stats = result;
      statsPhase = LoadPhase.ready;
      _scheduleCacheWrite();
    } on BackendFailure catch (error) {
      statsError = _featureMessage(error, 'RPG STATS UNAVAILABLE - TRY AGAIN');
      statsPhase =
          stats == null || error.kind == BackendFailureKind.invalidResponse
          ? LoadPhase.error
          : LoadPhase.ready;
    } on Object {
      statsError = 'RPG STATS UNAVAILABLE - TRY AGAIN';
      statsPhase = stats == null ? LoadPhase.error : LoadPhase.ready;
    }
    _safeNotify();
  }

  Future<void> loadQuests({bool force = false}) async {
    await _ensureHydrated();
    if (_disposed || questPhase == LoadPhase.loading) return;
    questPhase = LoadPhase.loading;
    questError = null;
    _safeNotify();
    try {
      try {
        quests = await api.questProgress(session.sessionToken);
        questsAreFallback = false;
        _hasPersistentQuestData = true;
        _scheduleCacheWrite();
      } on BackendFailure catch (error) {
        if (error.invalidatesSession) rethrow;
        if (_hasPersistentQuestData) {
          questPhase = LoadPhase.ready;
          questError = _featureMessage(
            error,
            'QUEST REFRESH FAILED - SHOWING SAVED DATA',
          );
          _safeNotify();
          return;
        }
        quests = await api.quests();
        questsAreFallback = true;
      }
      questPhase = LoadPhase.ready;
    } on BackendFailure catch (error) {
      questError = _featureMessage(error, 'QUESTS UNAVAILABLE - TRY AGAIN');
      questPhase = _hasPersistentQuestData ? LoadPhase.ready : LoadPhase.error;
    } on Object {
      questError = 'QUESTS UNAVAILABLE - TRY AGAIN';
      questPhase = _hasPersistentQuestData ? LoadPhase.ready : LoadPhase.error;
    }
    _safeNotify();
  }

  Future<void> claimQuest(String questId) async {
    if (claimingQuestId != null) return;
    final matches = quests.where((quest) => quest.questId == questId);
    if (matches.isEmpty || !matches.first.canClaim) {
      claimMessage = 'QUEST REWARD IS NOT AVAILABLE';
      claimMessageQuestId = questId;
      _safeNotify();
      return;
    }
    claimingQuestId = questId;
    claimMessage = null;
    claimMessageQuestId = questId;
    _safeNotify();
    try {
      final result = await api.claimQuest(session.sessionToken, questId);
      quests = quests
          .map(
            (quest) => quest.questId == result.questId
                ? quest.withClaim(
                    claimId: result.claimId,
                    claimedAt: result.claimedAt,
                  )
                : quest,
          )
          .toList(growable: false);
      claimMessage = '+${result.rewardXp} XP CLAIMED';
      _hasPersistentQuestData = true;
      _scheduleCacheWrite();
      await loadStats(force: true);
    } on BackendFailure catch (error) {
      claimMessage = _featureMessage(error, 'CLAIM FAILED - TRY AGAIN');
    } on Object {
      claimMessage = 'CLAIM FAILED - TRY AGAIN';
    } finally {
      claimingQuestId = null;
      _safeNotify();
    }
  }

  bool get isSubmittingAttendance => _attendanceSubmission != null;

  Future<AttendanceResult> submitAttendance(String qrToken) async {
    final inFlight = _attendanceSubmission;
    if (inFlight != null) return inFlight;

    final submission = _submitAttendance(qrToken);
    _attendanceSubmission = submission;
    _safeNotify();
    try {
      return await submission;
    } finally {
      _attendanceSubmission = null;
      _safeNotify();
    }
  }

  Future<AttendanceResult> _submitAttendance(String qrToken) async {
    final result = await api.submitAttendance(session.sessionToken, qrToken);
    if (result.awarded) {
      await Future.wait([loadStats(force: true), loadQuests(force: true)]);
    }
    return result;
  }

  Future<void> loadGuild({bool force = false}) async {
    await _ensureHydrated();
    if (_disposed ||
        guildPhase == LoadPhase.loading ||
        leaderboardPhase == LoadPhase.loading) {
      return;
    }
    _applyCachedLeaderboardSelection();
    final requestedScope = leaderboardScope;
    final requestedMetric = leaderboardMetric;
    guildPhase = LoadPhase.loading;
    leaderboardPhase = LoadPhase.loading;
    guildError = null;
    leaderboardError = null;
    _safeNotify();
    try {
      final result = await api.guildData(
        session.sessionToken,
        requestedScope,
        requestedMetric,
      );
      final initialLeaderboard = result.leaderboard;
      if (initialLeaderboard == null) {
        throw const BackendFailure(
          BackendFailureKind.invalidResponse,
          'Guild leaderboard is missing.',
        );
      }
      guildData = result;
      _cachedLeaderboards[leaderboardCacheKey(
            requestedScope,
            requestedMetric,
          )] =
          initialLeaderboard;
      _applyCachedLeaderboardSelection();
      guildPhase = LoadPhase.ready;
      leaderboardPhase = leaderboardData == null
          ? LoadPhase.idle
          : LoadPhase.ready;
      _scheduleCacheWrite();
    } on BackendFailure catch (error) {
      guildError = _featureMessage(error, 'GUILD DATA UNAVAILABLE - TRY AGAIN');
      leaderboardError = _featureMessage(
        error,
        'LEADERBOARD UNAVAILABLE - TRY AGAIN',
      );
      guildPhase = guildData == null ? LoadPhase.error : LoadPhase.ready;
      leaderboardPhase = leaderboardData == null
          ? LoadPhase.error
          : LoadPhase.ready;
    } on Object {
      guildError = 'GUILD DATA UNAVAILABLE - TRY AGAIN';
      leaderboardError = 'LEADERBOARD UNAVAILABLE - TRY AGAIN';
      guildPhase = guildData == null ? LoadPhase.error : LoadPhase.ready;
      leaderboardPhase = leaderboardData == null
          ? LoadPhase.error
          : LoadPhase.ready;
    }
    _safeNotify();
    if (!_disposed &&
        (leaderboardScope != requestedScope ||
            leaderboardMetric != requestedMetric)) {
      leaderboardError = null;
      await loadLeaderboard(force: true);
    }
  }

  Future<void> loadLeaderboard({bool force = false}) async {
    await _ensureHydrated();
    if (_disposed || leaderboardPhase == LoadPhase.loading) return;
    _applyCachedLeaderboardSelection();
    final requestedScope = leaderboardScope;
    final requestedMetric = leaderboardMetric;
    leaderboardPhase = LoadPhase.loading;
    leaderboardError = null;
    _safeNotify();
    try {
      final result = await api.leaderboard(
        session.sessionToken,
        requestedScope,
        requestedMetric,
      );
      _cachedLeaderboards[leaderboardCacheKey(
            requestedScope,
            requestedMetric,
          )] =
          result;
      _applyCachedLeaderboardSelection();
      leaderboardPhase = leaderboardData == null
          ? LoadPhase.idle
          : LoadPhase.ready;
      _scheduleCacheWrite();
    } on BackendFailure catch (error) {
      leaderboardError = _featureMessage(
        error,
        'LEADERBOARD UNAVAILABLE - TRY AGAIN',
      );
      leaderboardPhase = leaderboardData == null
          ? LoadPhase.error
          : LoadPhase.ready;
    } on Object {
      leaderboardError = 'LEADERBOARD UNAVAILABLE - TRY AGAIN';
      leaderboardPhase = leaderboardData == null
          ? LoadPhase.error
          : LoadPhase.ready;
    }
    _safeNotify();
    if (!_disposed &&
        (leaderboardScope != requestedScope ||
            leaderboardMetric != requestedMetric)) {
      leaderboardError = null;
      await loadLeaderboard(force: true);
    }
  }

  Future<void> selectLeaderboardScope(LeaderboardScope scope) async {
    if (scope == leaderboardScope) return;
    leaderboardScope = scope;
    _applyCachedLeaderboardSelection();
    leaderboardPhase = leaderboardData == null
        ? LoadPhase.idle
        : LoadPhase.ready;
    _safeNotify();
    await loadLeaderboard(force: true);
  }

  Future<void> selectLeaderboardMetric(LeaderboardMetric metric) async {
    if (metric == leaderboardMetric) return;
    leaderboardMetric = metric;
    _applyCachedLeaderboardSelection();
    leaderboardPhase = leaderboardData == null
        ? LoadPhase.idle
        : LoadPhase.ready;
    _safeNotify();
    await loadLeaderboard(force: true);
  }

  Future<void> loadActivities({bool force = false}) async {
    await _ensureHydrated();
    if (_disposed || activityPhase == LoadPhase.loading) return;
    activityPhase = LoadPhase.loading;
    activityError = null;
    activityWarning = null;
    _safeNotify();
    try {
      final ownerNik = session.nik;
      final cached = activities;
      final values = await Future.wait<Object?>([
        activityStore.newestFirst(ownerNik),
        activityStore.totals(ownerNik),
      ]);
      final local = values[0]! as List<FinalActivity>;
      final localIds = local.map((activity) => activity.activityId).toSet();
      List<ServerActivitySummary> backend = const [];
      var backendLoaded = false;
      try {
        backend = await api.activityHistory(session.sessionToken);
        backendLoaded = true;
      } on BackendFailure catch (error) {
        activityWarning = error.invalidatesSession
            ? 'SESSION EXPIRED - LOGIN AGAIN'
            : cached.isEmpty
            ? 'SERVER HISTORY UNAVAILABLE - SHOWING DEVICE LOG'
            : 'SERVER HISTORY UNAVAILABLE - SHOWING SAVED LOG';
      } on Object {
        activityWarning = cached.isEmpty
            ? 'SERVER HISTORY UNAVAILABLE - SHOWING DEVICE LOG'
            : 'SERVER HISTORY UNAVAILABLE - SHOWING SAVED LOG';
      }
      if (session.nik != ownerNik) return;
      activities = backendLoaded
          ? mergeActivityHistory(
              ownerNik: ownerNik,
              local: local,
              backend: backend,
            )
          : _mergeCachedActivities(ownerNik, cached, local);
      localActivityIds = Set.unmodifiable(localIds);
      latestActivity = activities.isEmpty ? null : activities.first;
      activityTotals = values[1]! as ActivityTotals;
      activityPhase = LoadPhase.ready;
      _scheduleCacheWrite();
    } on Object {
      activityError = 'ADVENTURE LOG UNAVAILABLE';
      activityPhase = activities.isEmpty ? LoadPhase.error : LoadPhase.ready;
    }
    _safeNotify();
  }

  Future<void> syncPending({bool manual = true}) async {
    if (isSyncing) return;
    isSyncing = true;
    syncError = false;
    syncMessage = null;
    _safeNotify();
    try {
      final result = await syncService.run(session, force: manual);
      if (result.alreadyRunning) return;
      if (result.attempted == 0) {
        if (result.notEligible > 0) {
          syncMessage =
              '${result.notEligible} ADVENTURE${result.notEligible == 1 ? '' : 'S'} NOT ELIGIBLE';
        } else if (manual) {
          syncMessage = 'NO PENDING ADVENTURES';
        }
      } else if (result.failed == 0) {
        syncMessage =
            '${result.synced} ADVENTURE${result.synced == 1 ? '' : 'S'} SYNCED';
      } else {
        syncError = true;
        syncMessage =
            '${result.failed} ADVENTURE${result.failed == 1 ? '' : 'S'} STILL PENDING';
      }
      if (result.synced > 0 || result.notEligible > 0) {
        await Future.wait([
          loadActivities(force: true),
          loadStats(force: true),
          loadQuests(force: true),
        ]);
      }
    } on BackendFailure catch (error) {
      syncError = true;
      syncMessage = _featureMessage(error, 'SYNC FAILED - TRY AGAIN');
    } on Object {
      syncError = true;
      syncMessage = 'SYNC FAILED - TRY AGAIN';
    } finally {
      isSyncing = false;
      _safeNotify();
    }
  }

  Future<bool> saveImportedActivity(FinalActivity activity) async {
    final outcome = await saveAndSyncImportedActivity(activity);
    return outcome != ImportedActivitySaveOutcome.duplicate;
  }

  Future<ImportedActivitySaveOutcome> saveAndSyncImportedActivity(
    FinalActivity activity,
  ) async {
    if (activity.ownerNik != session.nik) {
      return ImportedActivitySaveOutcome.duplicate;
    }
    final inserted = await activityStore.insert(activity);
    if (!inserted) return ImportedActivitySaveOutcome.duplicate;
    await syncPending(manual: false);
    await Future.wait([
      loadActivities(force: true),
      loadStats(force: true),
      loadQuests(force: true),
    ]);
    FinalActivity? stored;
    for (final item in await activityStore.newestFirst(session.nik)) {
      if (item.activityId == activity.activityId) {
        stored = item;
        break;
      }
    }
    return stored?.syncStatus == ActivitySyncStatus.synced
        ? ImportedActivitySaveOutcome.synced
        : ImportedActivitySaveOutcome.pending;
  }

  Future<bool> deleteNotEligibleActivity(String activityId) async {
    final deleted = await activityStore.deleteNotEligible(
      activityId,
      session.nik,
    );
    if (deleted) await loadActivities(force: true);
    return deleted;
  }

  Future<bool> removeLocalActivityData(String activityId) async {
    final removed = await activityStore.removeLocalData(
      activityId,
      session.nik,
    );
    if (removed) await loadActivities(force: true);
    return removed;
  }

  bool get isStatsRefreshing =>
      statsPhase == LoadPhase.loading && stats != null;
  bool get isQuestRefreshing =>
      questPhase == LoadPhase.loading && _hasPersistentQuestData;
  bool get isGuildRefreshing =>
      guildPhase == LoadPhase.loading && guildData != null;
  bool get isLeaderboardRefreshing =>
      leaderboardPhase == LoadPhase.loading && leaderboardData != null;
  bool get isActivityRefreshing =>
      activityPhase == LoadPhase.loading && activities.isNotEmpty;

  Future<void> _ensureHydrated() => _hydrateFuture ??= _hydrateFromCache();

  Future<void> _hydrateFromCache() async {
    final ownerNik = session.nik;
    final snapshot = await cacheStore.read(ownerNik);
    if (_disposed || session.nik != ownerNik || snapshot == null) return;
    final cachedStats = snapshot.stats;
    if (cachedStats != null &&
        (cachedStats.nik.isEmpty || cachedStats.nik == ownerNik)) {
      stats = cachedStats;
      statsPhase = LoadPhase.ready;
    }
    if (snapshot.quests case final values?) {
      quests = List.unmodifiable(values);
      questsAreFallback = false;
      _hasPersistentQuestData = true;
      questPhase = LoadPhase.ready;
    }
    if (snapshot.guildData case final value?) {
      guildData = value;
      guildPhase = LoadPhase.ready;
    }
    _cachedLeaderboards
      ..clear()
      ..addAll(snapshot.leaderboards);
    final guildLeaderboard = guildData?.leaderboard;
    if (guildLeaderboard != null) {
      _cachedLeaderboards.putIfAbsent(
        leaderboardCacheKey(guildLeaderboard.scope, guildLeaderboard.metric),
        () => guildLeaderboard,
      );
    }
    _applyCachedLeaderboardSelection();
    if (leaderboardData != null) leaderboardPhase = LoadPhase.ready;
    if (snapshot.activities case final values?) {
      activities = List.unmodifiable(
        values.where((value) => value.ownerNik == ownerNik),
      );
      latestActivity = activities.isEmpty ? null : activities.first;
      activityPhase = LoadPhase.ready;
    }
    _safeNotify();
  }

  void _applyCachedLeaderboardSelection() {
    leaderboardData =
        _cachedLeaderboards[leaderboardCacheKey(
          leaderboardScope,
          leaderboardMetric,
        )];
  }

  void _scheduleCacheWrite() {
    if (_disposed) return;
    final ownerNik = session.nik;
    final snapshot = FeatureCacheSnapshot(
      ownerNik: ownerNik,
      savedAtMillis: DateTime.now().millisecondsSinceEpoch,
      stats: stats?.nik == ownerNik ? stats : null,
      quests: _hasPersistentQuestData && !questsAreFallback
          ? List.unmodifiable(quests)
          : null,
      guildData: guildData,
      leaderboards: Map.unmodifiable(_cachedLeaderboards),
      activities: List.unmodifiable(activities),
    );
    _cacheWriteQueue = _cacheWriteQueue
        .then((_) async {
          if (snapshot.ownerNik == ownerNik) await cacheStore.write(snapshot);
        })
        .catchError((Object _) {
          // Persistent cache is optional; live backend state remains usable.
        });
  }

  @visibleForTesting
  Future<void> settleCacheWrites() => _cacheWriteQueue;

  List<FinalActivity> _mergeCachedActivities(
    String ownerNik,
    List<FinalActivity> cached,
    List<FinalActivity> local,
  ) {
    final merged = <String, FinalActivity>{
      for (final item in cached.where((value) => value.ownerNik == ownerNik))
        item.activityId: item,
    };
    for (final item in local.where((value) => value.ownerNik == ownerNik)) {
      merged[item.activityId] =
          merged[item.activityId]?.syncStatus == ActivitySyncStatus.synced
          ? item.withSyncStatus(ActivitySyncStatus.synced)
          : item;
    }
    final result = merged.values.toList(growable: false);
    result.sort((a, b) {
      final aTime = a.endDateTimeMillis > 0
          ? a.endDateTimeMillis
          : a.startDateTimeMillis;
      final bTime = b.endDateTimeMillis > 0
          ? b.endDateTimeMillis
          : b.startDateTimeMillis;
      final byTime = bTime.compareTo(aTime);
      if (byTime != 0) return byTime;
      final byCreated = b.createdAtMillis.compareTo(a.createdAtMillis);
      return byCreated != 0 ? byCreated : b.activityId.compareTo(a.activityId);
    });
    return result;
  }

  String _featureMessage(BackendFailure error, String fallback) {
    return error.invalidatesSession
        ? 'SESSION EXPIRED - LOGIN AGAIN'
        : fallback;
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
