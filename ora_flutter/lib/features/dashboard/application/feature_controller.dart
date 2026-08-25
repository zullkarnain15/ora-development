import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/network/apps_script_client.dart';
import '../../activity/application/activity_sync_service.dart';
import '../../activity/data/activity_store.dart';
import '../../activity/domain/final_activity.dart';
import '../../activity/domain/server_activity_summary.dart';
import '../../auth/domain/auth_models.dart';
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
  }) : syncService = ActivitySyncService(store: activityStore, api: api);

  UserSession session;
  final OraFeatureApi api;
  final ActivityStore activityStore;
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

  void updateSession(UserSession value) {
    if (value.nik != session.nik) return;
    session = value;
    _safeNotify();
  }

  Future<void> loadHome({bool force = false}) async {
    await Future.wait([loadStats(force: force), loadActivities(force: force)]);
  }

  Future<void> loadStats({bool force = false}) async {
    if (statsPhase == LoadPhase.loading ||
        (!force && statsPhase == LoadPhase.ready)) {
      return;
    }
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
    } on BackendFailure catch (error) {
      statsPhase = LoadPhase.error;
      statsError = _featureMessage(error, 'RPG STATS UNAVAILABLE - TRY AGAIN');
    } on Object {
      statsPhase = LoadPhase.error;
      statsError = 'RPG STATS UNAVAILABLE - TRY AGAIN';
    }
    _safeNotify();
  }

  Future<void> loadQuests({bool force = false}) async {
    if (questPhase == LoadPhase.loading ||
        (!force && questPhase == LoadPhase.ready)) {
      return;
    }
    questPhase = LoadPhase.loading;
    questError = null;
    _safeNotify();
    try {
      try {
        quests = await api.questProgress(session.sessionToken);
        questsAreFallback = false;
      } on BackendFailure catch (error) {
        if (error.invalidatesSession) rethrow;
        quests = await api.quests();
        questsAreFallback = true;
      }
      questPhase = LoadPhase.ready;
    } on BackendFailure catch (error) {
      questPhase = LoadPhase.error;
      questError = _featureMessage(error, 'QUESTS UNAVAILABLE - TRY AGAIN');
    } on Object {
      questPhase = LoadPhase.error;
      questError = 'QUESTS UNAVAILABLE - TRY AGAIN';
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
    if (guildPhase == LoadPhase.loading ||
        (!force && guildPhase == LoadPhase.ready)) {
      return;
    }
    guildPhase = LoadPhase.loading;
    guildError = null;
    _safeNotify();
    try {
      guildData = await api.guildData(session.sessionToken);
      guildPhase = LoadPhase.ready;
    } on BackendFailure catch (error) {
      guildPhase = LoadPhase.error;
      guildError = _featureMessage(error, 'GUILD DATA UNAVAILABLE - TRY AGAIN');
    } on Object {
      guildPhase = LoadPhase.error;
      guildError = 'GUILD DATA UNAVAILABLE - TRY AGAIN';
    }
    _safeNotify();
  }

  Future<void> loadLeaderboard({bool force = false}) async {
    if (leaderboardPhase == LoadPhase.loading ||
        (!force && leaderboardPhase == LoadPhase.ready)) {
      return;
    }
    leaderboardPhase = LoadPhase.loading;
    leaderboardError = null;
    _safeNotify();
    try {
      leaderboardData = await api.leaderboard(
        session.sessionToken,
        leaderboardScope,
        leaderboardMetric,
      );
      leaderboardPhase = LoadPhase.ready;
    } on BackendFailure catch (error) {
      leaderboardPhase = LoadPhase.error;
      leaderboardError = _featureMessage(
        error,
        'LEADERBOARD UNAVAILABLE - TRY AGAIN',
      );
    } on Object {
      leaderboardPhase = LoadPhase.error;
      leaderboardError = 'LEADERBOARD UNAVAILABLE - TRY AGAIN';
    }
    _safeNotify();
  }

  Future<void> selectLeaderboardScope(LeaderboardScope scope) async {
    if (scope == leaderboardScope) return;
    leaderboardScope = scope;
    leaderboardPhase = LoadPhase.idle;
    await loadLeaderboard(force: true);
  }

  Future<void> selectLeaderboardMetric(LeaderboardMetric metric) async {
    if (metric == leaderboardMetric) return;
    leaderboardMetric = metric;
    leaderboardPhase = LoadPhase.idle;
    await loadLeaderboard(force: true);
  }

  Future<void> loadActivities({bool force = false}) async {
    if (activityPhase == LoadPhase.loading ||
        (!force && activityPhase == LoadPhase.ready)) {
      return;
    }
    activityPhase = LoadPhase.loading;
    activityError = null;
    activityWarning = null;
    _safeNotify();
    try {
      final ownerNik = session.nik;
      final values = await Future.wait<Object?>([
        activityStore.newestFirst(ownerNik),
        activityStore.totals(ownerNik),
      ]);
      final local = values[0]! as List<FinalActivity>;
      final localIds = local.map((activity) => activity.activityId).toSet();
      List<ServerActivitySummary> backend = const [];
      try {
        backend = await api.activityHistory(session.sessionToken);
      } on BackendFailure catch (error) {
        activityWarning = error.invalidatesSession
            ? 'SESSION EXPIRED - LOGIN AGAIN'
            : 'SERVER HISTORY UNAVAILABLE - SHOWING DEVICE LOG';
      } on Object {
        activityWarning = 'SERVER HISTORY UNAVAILABLE - SHOWING DEVICE LOG';
      }
      if (session.nik != ownerNik) return;
      activities = mergeActivityHistory(
        ownerNik: ownerNik,
        local: local,
        backend: backend,
      );
      localActivityIds = Set.unmodifiable(localIds);
      latestActivity = activities.isEmpty ? null : activities.first;
      activityTotals = values[1]! as ActivityTotals;
      activityPhase = LoadPhase.ready;
    } on Object {
      activityPhase = LoadPhase.error;
      activityError = 'ADVENTURE LOG UNAVAILABLE';
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
