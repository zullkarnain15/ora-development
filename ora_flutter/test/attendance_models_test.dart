import 'package:flutter_test/flutter_test.dart';
import 'package:ora_flutter/features/dashboard/domain/feature_models.dart';

void main() {
  test('attendance result uses backend reward and progression values', () {
    final result = AttendanceResult.fromJson({
      'status': 'SUCCESS',
      'eventId': 'E-1',
      'eventName': 'SUNRISE RUN',
      'checkInAt': '2026-08-20T00:00:00.000Z',
      'baseXP': 20,
      'streakCount': 3,
      'streakBonusXP': 30,
      'totalXP': 50,
      'currentXP': 150,
      'currentLevel': 2,
    });

    expect(result.status, AttendanceStatus.success);
    expect(result.eventName, 'SUNRISE RUN');
    expect(result.baseXp, 20);
    expect(result.streakBonusXp, 30);
    expect(result.totalXp, 50);
    expect(result.currentXp, 150);
    expect(result.currentLevel, 2);
  });

  test('attendance response status mapping covers QR and event outcomes', () {
    expect(
      attendanceStatusFromApi('ALREADY_CHECKED_IN'),
      AttendanceStatus.alreadyCheckedIn,
    );
    expect(attendanceStatusFromApi('INVALID_QR'), AttendanceStatus.invalidQr);
    expect(
      attendanceStatusFromApi('EVENT_INACTIVE'),
      AttendanceStatus.eventInactive,
    );
    expect(
      attendanceStatusFromApi('EVENT_NOT_STARTED'),
      AttendanceStatus.eventNotStarted,
    );
    expect(
      attendanceStatusFromApi('EVENT_CLOSED'),
      AttendanceStatus.eventClosed,
    );
    expect(
      attendanceStatusFromApi('ATTENDANCE_DISABLED'),
      AttendanceStatus.attendanceDisabled,
    );
    expect(
      attendanceStatusFromApi('ATTENDANCE_QR_DISABLED'),
      AttendanceStatus.attendanceQrDisabled,
    );
    expect(
      attendanceStatusFromApi('CONFIG_ERROR'),
      AttendanceStatus.configurationError,
    );
    expect(
      attendanceStatusFromApi('UNAUTHORIZED'),
      AttendanceStatus.unauthorized,
    );
  });

  test('attendance quest uses the existing quest response shape', () {
    final quest = Quest.fromJson({
      'questId': 'AQ-COUNT',
      'name': 'JOIN THE PACK',
      'type': 'ATTENDANCE',
      'target': 3,
      'unit': 'COUNT',
      'rewardXp': 100,
      'period': 'WEEKLY',
      'activeFrom': '2026-08-10',
      'activeTo': '2026-08-16',
      'progress': 2,
      'progressPercent': 66.67,
      'status': 'IN_PROGRESS',
      'completed': false,
      'claimable': false,
      'claimed': false,
    }, progressResponse: true);

    expect(quest.questType, 'ATTENDANCE');
    expect(quest.progressUnit, 'ATTENDANCE');
    expect(quest.progress, 2);
    expect(quest.visualState, QuestVisualState.inProgress);
  });
}
