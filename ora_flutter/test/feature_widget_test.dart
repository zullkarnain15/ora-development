import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ora_flutter/core/network/apps_script_client.dart';
import 'package:ora_flutter/core/theme/ora_theme.dart';
import 'package:ora_flutter/features/activity/data/activity_store.dart';
import 'package:ora_flutter/features/activity/domain/final_activity.dart';
import 'package:ora_flutter/features/auth/domain/auth_models.dart';
import 'package:ora_flutter/features/dashboard/application/feature_controller.dart';
import 'package:ora_flutter/features/dashboard/data/ora_feature_api.dart';
import 'package:ora_flutter/features/dashboard/domain/feature_models.dart';
import 'package:ora_flutter/features/dashboard/presentation/guild_screen.dart';
import 'package:ora_flutter/features/dashboard/presentation/home_screen.dart';
import 'package:ora_flutter/features/dashboard/presentation/quest_screen.dart';
import 'package:ora_flutter/features/dashboard/presentation/profile_screen.dart';
import 'package:ora_flutter/features/attendance/presentation/attendance_scanner_screen.dart';

class _NeverTransport implements ApiTransport {
  @override
  Future<TransportResponse> request(
    Uri endpoint, {
    required String method,
    String? body,
    required Duration connectTimeout,
    required Duration readTimeout,
  }) => throw UnimplementedError();
}

final _session = UserSession(
  sessionToken: 'fixture',
  nik: '1001',
  nickname: 'RUNNER',
  divisionGuild: 'OPS',
  status: 'ACTIVE',
  expiresAt: DateTime.utc(2030),
);

FeatureController _controller() => FeatureController(
  session: _session,
  api: AppsScriptFeatureApi(AppsScriptClient(transport: _NeverTransport())),
  activityStore: MemoryActivityStore(),
);

Widget _host(Widget child, {double scale = 1}) => MaterialApp(
  theme: buildOraTheme(),
  home: Builder(
    builder: (context) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(scale)),
      child: child,
    ),
  ),
);

void main() {
  testWidgets('Home loading content works with text scaling', (tester) async {
    final controller = _controller()
      ..statsPhase = LoadPhase.loading
      ..activityPhase = LoadPhase.loading;
    await tester.pumpWidget(
      _host(HomeScreen(controller: controller), scale: 1.5),
    );
    expect(find.text('LOADING ADVENTURER...'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Home exposes a tappable QR check-in card without a new tab', (
    tester,
  ) async {
    final controller = _controller()
      ..statsPhase = LoadPhase.ready
      ..activityPhase = LoadPhase.ready;
    await tester.pumpWidget(_host(HomeScreen(controller: controller)));

    expect(find.byKey(const Key('home_check_in')), findsOneWidget);
    expect(find.text('ADVENTURE STAMP'), findsOneWidget);
    expect(find.byIcon(Icons.qr_code_scanner), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('QR scanner degrades safely when camera is unsupported', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        AttendanceScannerScreen(
          controller: _controller(),
          cameraSupported: false,
        ),
      ),
    );

    expect(find.text('SCANNER NOT AVAILABLE'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Home last adventure can open unavailable local route', (
    tester,
  ) async {
    final controller = _controller()
      ..activityPhase = LoadPhase.ready
      ..latestActivity = _activity('A2', ActivitySyncStatus.synced);

    await tester.pumpWidget(_host(HomeScreen(controller: controller)));

    final button = find.byKey(const Key('home_view_last_route'));
    expect(button, findsOneWidget);
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();

    expect(find.text('ADVENTURE ROUTE'), findsOneWidget);
    expect(
      find.text('ROUTE DATA NOT AVAILABLE ON THIS DEVICE'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Quest error content remains retryable with text scaling', (
    tester,
  ) async {
    final controller = _controller()
      ..questPhase = LoadPhase.error
      ..questError = 'QUESTS UNAVAILABLE - TRY AGAIN';
    await tester.pumpWidget(
      _host(QuestScreen(controller: controller), scale: 1.8),
    );
    expect(find.text('QUESTS UNAVAILABLE - TRY AGAIN'), findsOneWidget);
    expect(find.text('TRY AGAIN'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Attendance COUNT quest renders on the existing quest card', (
    tester,
  ) async {
    final controller = _controller()
      ..questPhase = LoadPhase.ready
      ..quests = const [
        Quest(
          questId: 'AQ-COUNT',
          questName: 'JOIN THE PACK',
          questType: 'ATTENDANCE',
          targetValue: 3,
          unit: 'COUNT',
          rewardXp: 100,
          periodType: 'WEEKLY',
          startDate: '',
          endDate: '',
          progress: 2,
          progressPercent: 66.67,
          status: 'IN_PROGRESS',
        ),
      ];

    await tester.pumpWidget(_host(QuestScreen(controller: controller)));

    expect(find.text('JOIN THE PACK'), findsOneWidget);
    expect(find.text('2 / 3 ATTENDANCE'), findsOneWidget);
    expect(find.text('IN PROGRESS'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Guild empty state remains readable at 200 percent text', (
    tester,
  ) async {
    final controller = _controller()
      ..guildPhase = LoadPhase.ready
      ..guildData = const GuildData(
        status: 'UNASSIGNED',
        guild: null,
        members: [],
        directory: [],
      );
    await tester.pumpWidget(
      _host(GuildScreen(controller: controller), scale: 2),
    );
    expect(find.text('NO GUILD ASSIGNED'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Quest claimable state and Profile pending/synced activities render',
    (tester) async {
      final controller = _controller()
        ..questPhase = LoadPhase.ready
        ..quests = const [
          Quest(
            questId: 'Q1',
            questName: 'FIRST RUN',
            questType: 'RUN_COUNT',
            targetValue: 1,
            unit: 'RUN',
            rewardXp: 10,
            periodType: 'DAILY',
            startDate: '',
            endDate: '',
            progress: 1,
            progressPercent: 100,
            completed: true,
            claimable: true,
          ),
        ];
      await tester.pumpWidget(
        _host(QuestScreen(controller: controller), scale: 1.4),
      );
      expect(find.text('QUEST COMPLETE!'), findsOneWidget);
      expect(find.text('CLAIM +10 XP'), findsOneWidget);

      controller
        ..statsPhase = LoadPhase.ready
        ..stats = const UserStats(
          nik: '1001',
          nickname: 'RUNNER',
          division: 'OPS',
          totalActivities: 2,
          totalDistanceKm: 3,
          totalDurationSec: 120,
          totalXp: 30,
          currentLevel: 2,
          currentLevelName: 'SCOUT',
          nextLevelXp: 100,
          lastActivityId: 'A2',
          lastActivityAt: '',
          updatedAt: null,
        )
        ..activityPhase = LoadPhase.ready
        ..activities = [
          _activity('A2', ActivitySyncStatus.synced),
          _activity('A1', ActivitySyncStatus.pending),
        ];
      await tester.pumpWidget(
        _host(ProfileScreen(controller: controller, onSettings: () {})),
      );
      expect(find.text('SYNCED'), findsOneWidget);
      expect(find.text('PENDING'), findsOneWidget);
      expect(find.text('30 XP'), findsOneWidget);
      expect(find.text('SYNC ADVENTURES'), findsOneWidget);
      expect(find.byKey(const Key('sync_adventures')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Profile uses remove local data wording for synced local copy', (
    tester,
  ) async {
    final controller = _controller()
      ..activityPhase = LoadPhase.ready
      ..activities = [_activity('A2', ActivitySyncStatus.synced)]
      ..localActivityIds = {'A2'};

    await tester.pumpWidget(
      _host(ProfileScreen(controller: controller, onSettings: () {})),
    );

    final button = find.byKey(const Key('remove_local_data_A2'));
    expect(button, findsOneWidget);
    expect(find.text('REMOVE LOCAL DATA'), findsOneWidget);

    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();

    expect(find.text('REMOVE LOCAL DATA?'), findsOneWidget);
    expect(
      find.textContaining('summary will remain in your Adventure Log'),
      findsOneWidget,
    );
    expect(find.text('REMOVE'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Guild rank shows updating banner while refreshing old data', (
    tester,
  ) async {
    final controller = _controller()
      ..guildPhase = LoadPhase.ready
      ..guildData = GuildData(
        status: 'ACTIVE',
        guild: _guild('OPS', 'OUR GUILD'),
        members: const [],
        directory: const [],
      )
      ..leaderboardPhase = LoadPhase.loading
      ..leaderboardData = const LeaderboardData(
        scope: LeaderboardScope.global,
        metric: LeaderboardMetric.totalXp,
        status: 'ACTIVE',
        entries: [
          LeaderboardEntry(
            rank: 1,
            nik: '1001',
            nickname: 'RUNNER',
            division: 'OPS',
            totalXp: 100,
            totalDistanceKm: 10,
            totalActivities: 2,
            currentLevel: 2,
            currentLevelName: 'SCOUT',
          ),
        ],
        currentUserRank: CurrentUserRank(rank: 1, metricValue: 100),
      );

    await tester.pumpWidget(
      _host(Material(child: GuildScreen(controller: controller))),
    );
    await tester.tap(find.text('RANK'));
    await tester.pump();

    expect(find.byKey(const Key('leaderboard_refreshing')), findsOneWidget);
    expect(find.text('UPDATING RANKS...'), findsOneWidget);
    expect(find.byKey(const Key('your_rank_card')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('current guild is pinned first and your rank uses blue border', (
    tester,
  ) async {
    final current = _guild('OPS', 'OUR GUILD');
    final other = _guild('SALES', 'OTHER GUILD');
    final controller = _controller()
      ..guildPhase = LoadPhase.ready
      ..guildData = GuildData(
        status: 'ACTIVE',
        guild: current,
        members: [_member('2002', 'OTHER'), _member('1001', 'RUNNER')],
        directory: [other, current],
      )
      ..leaderboardPhase = LoadPhase.ready
      ..leaderboardData = const LeaderboardData(
        scope: LeaderboardScope.global,
        metric: LeaderboardMetric.totalXp,
        status: 'ACTIVE',
        entries: [
          LeaderboardEntry(
            rank: 1,
            nik: '1001',
            nickname: 'RUNNER',
            division: 'OPS',
            totalXp: 100,
            totalDistanceKm: 10,
            totalActivities: 2,
            currentLevel: 2,
            currentLevelName: 'SCOUT',
          ),
        ],
        currentUserRank: CurrentUserRank(rank: 1, metricValue: 100),
      );

    await tester.pumpWidget(
      _host(Material(child: GuildScreen(controller: controller))),
    );
    expect(find.byKey(const Key('your_member_card')), findsOneWidget);
    expect(
      tester.getTopLeft(find.byKey(const Key('your_member_card'))).dy,
      lessThan(tester.getTopLeft(find.text('OTHER')).dy),
    );
    final memberCard = tester.widget<Container>(
      find.byKey(const Key('your_member_card')),
    );
    final memberDecoration = memberCard.decoration! as BoxDecoration;
    expect(memberDecoration.color, OraColors.gold.withValues(alpha: 0.24));
    expect((memberDecoration.border! as Border).top.color, OraColors.rankBlue);

    await tester.tap(find.text('GUILDS'));
    await tester.pump();
    expect(find.text('YOUR GUILD'), findsOneWidget);
    expect(
      tester.getTopLeft(find.byKey(const Key('your_guild_card'))).dy,
      lessThan(tester.getTopLeft(find.text('OTHER GUILD')).dy),
    );
    final guildCard = tester.widget<Container>(
      find.byKey(const Key('your_guild_card')),
    );
    final guildDecoration = guildCard.decoration! as BoxDecoration;
    expect(guildDecoration.color, OraColors.gold.withValues(alpha: 0.24));
    expect((guildDecoration.border! as Border).top.color, OraColors.rankBlue);

    await tester.tap(find.text('RANK'));
    await tester.pump();
    final rankCard = tester.widget<Container>(
      find.byKey(const Key('your_rank_card')),
    );
    final decoration = rankCard.decoration! as BoxDecoration;
    expect((decoration.border! as Border).top.color, OraColors.rankBlue);
    final rankTexts = tester.widgetList<Text>(
      find.descendant(
        of: find.byKey(const Key('your_rank_card')),
        matching: find.byType(Text),
      ),
    );
    final rankValue = rankTexts.singleWhere(
      (text) => text.data?.startsWith('#1') == true,
    );
    expect(rankValue.style?.fontSize, 15);
    final rankBadges = tester
        .widgetList<Container>(
          find.descendant(
            of: find.byKey(const Key('your_rank_card')),
            matching: find.byType(Container),
          ),
        )
        .where((container) {
          final decoration = container.decoration;
          return decoration is BoxDecoration &&
              decoration.color == OraColors.gold.withValues(alpha: 0.92);
        });
    expect(rankBadges, isNotEmpty);
  });
}

GuildSummary _guild(String id, String name) => GuildSummary(
  guildId: id,
  guildName: name,
  memberCount: 5,
  activeMemberCount: 4,
  totalDistanceKm: 10,
  totalActivities: 3,
  totalXp: 100,
  currentLevel: 2,
  currentLevelName: 'TEAM',
  displayName: name,
  description: '',
);

GuildMember _member(String nik, String nickname) => GuildMember(
  nik: nik,
  nickname: nickname,
  division: 'OPS',
  totalDistanceKm: 10,
  totalActivities: 2,
  totalXp: 100,
  currentLevel: 2,
  currentLevelName: 'SCOUT',
);

FinalActivity _activity(String id, ActivitySyncStatus status) => FinalActivity(
  activityId: id,
  ownerNik: '1001',
  nicknameSnapshot: 'RUNNER',
  divisionGuildSnapshot: 'OPS',
  startDateTimeMillis: DateTime.now().millisecondsSinceEpoch,
  endDateTimeMillis: DateTime.now().millisecondsSinceEpoch + 60000,
  distanceMeters: 1000,
  activeDurationMillis: 60000,
  averagePaceSecondsPerKm: 300,
  createdAtMillis: DateTime.now().millisecondsSinceEpoch,
  syncStatus: status,
);
