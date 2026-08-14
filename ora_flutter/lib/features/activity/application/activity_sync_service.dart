import '../../../core/network/apps_script_client.dart';
import '../../auth/domain/auth_models.dart';
import '../../dashboard/data/ora_feature_api.dart';
import '../data/activity_store.dart';
import '../domain/activity_sync.dart';

typedef SyncClock = DateTime Function();

class ActivitySyncResult {
  const ActivitySyncResult({
    this.attempted = 0,
    this.synced = 0,
    this.failed = 0,
    this.notEligible = 0,
    this.alreadyRunning = false,
  });

  final int attempted;
  final int synced;
  final int failed;
  final int notEligible;
  final bool alreadyRunning;
}

/// Uploads immutable queue payloads and only marks the local activity synced
/// after a terminal backend acknowledgement (SAVED or DUPLICATE).
class ActivitySyncService {
  ActivitySyncService({
    required this.store,
    required this.api,
    SyncClock? clock,
  }) : _clock = clock ?? DateTime.now;

  final ActivityStore store;
  final OraFeatureApi api;
  final SyncClock _clock;
  bool _running = false;

  Future<ActivitySyncResult> run(
    UserSession session, {
    bool force = false,
  }) async {
    if (_running) return const ActivitySyncResult(alreadyRunning: true);
    _running = true;
    var attempted = 0;
    var synced = 0;
    var failed = 0;
    var notEligible = 0;
    try {
      final nowMillis = _clock().millisecondsSinceEpoch;
      final entries = await store.dueSync(session.nik, nowMillis, force: force);
      for (final entry in entries) {
        if (entry.ownerNik != session.nik) continue;
        final ineligibilityReason = syncPayloadIneligibilityReason(
          entry.payload,
        );
        if (ineligibilityReason != null) {
          final marked = await store.markSyncNotEligible(
            entry.queueId,
            entry.activityId,
            session.nik,
            reason: ineligibilityReason,
            markedAtMillis: _clock().millisecondsSinceEpoch,
          );
          if (marked) notEligible++;
          continue;
        }
        final claimed = await store.beginSync(
          entry.queueId,
          session.nik,
          _clock().millisecondsSinceEpoch,
        );
        if (!claimed) continue;
        attempted++;
        try {
          final status = await api.submitActivity(
            session.sessionToken,
            entry.payload,
          );
          final acknowledged = await store.acknowledgeSync(
            entry.queueId,
            entry.activityId,
            session.nik,
            serverStatus: status,
            acknowledgedAtMillis: _clock().millisecondsSinceEpoch,
          );
          if (acknowledged) {
            synced++;
          } else {
            failed++;
            await _recordFailure(entry, 'LOCAL_ACK_REJECTED');
          }
        } on BackendFailure catch (error) {
          failed++;
          await _recordFailure(
            entry,
            error.code ?? error.kind.name.toUpperCase(),
          );
          if (error.invalidatesSession) rethrow;
        } on Object {
          failed++;
          await _recordFailure(entry, 'UNEXPECTED_ERROR');
        }
      }
      return ActivitySyncResult(
        attempted: attempted,
        synced: synced,
        failed: failed,
        notEligible: notEligible,
      );
    } finally {
      _running = false;
    }
  }

  Future<void> _recordFailure(SyncQueueEntry entry, String code) async {
    final now = _clock().millisecondsSinceEpoch;
    await store.failSync(
      entry.queueId,
      entry.ownerNik,
      nowMillis: now,
      nextAttemptAtMillis: now + syncBackoffMillis(entry.retryCount + 1),
      errorCode: code,
    );
  }
}
