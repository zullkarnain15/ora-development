import 'package:flutter/material.dart';

import '../../../core/theme/ora_theme.dart';
import '../../../core/platform/pwa_install_controller.dart';
import '../../../core/platform/pwa_install_platform.dart';
import '../../mascot/awan_home_greeting.dart';
import '../../../shared/widgets/ora_widgets.dart';
import '../../activity/domain/final_activity.dart';
import '../../activity/presentation/activity_route_viewer.dart';
import '../../attendance/presentation/attendance_scanner_screen.dart';
import '../application/feature_controller.dart';
import '../domain/feature_models.dart';
import 'formatters.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.controller,
    this.pwaInstallController,
  });
  final FeatureController controller;
  final PwaInstallController? pwaInstallController;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) => SafeArea(
      child: RefreshIndicator(
        onRefresh: () => controller.loadHome(force: true),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (pwaInstallController case final installController?)
                _PwaInstallBanner(controller: installController),
              const OraScreenTitle(
                title: 'ORA',
                subtitle: 'OTO RUNNERS ADVENTURE',
                assetName: 'oto_runners.PNG',
              ),
              if (controller.isStatsRefreshing ||
                  controller.isActivityRefreshing ||
                  (controller.stats != null && controller.statsError != null) ||
                  (controller.activities.isNotEmpty &&
                      controller.activityWarning != null)) ...[
                const SizedBox(height: 10),
                OraRefreshStatus(
                  key: const Key('home_refresh_status'),
                  refreshing:
                      controller.isStatsRefreshing ||
                      controller.isActivityRefreshing,
                  warning: controller.statsError ?? controller.activityWarning,
                ),
              ],
              const SizedBox(height: 24),
              Text('WELCOME,', style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 6),
              Text(
                controller.session.nickname,
                style: OraTextStyles.displayLarge.copyWith(
                  color: OraColors.gold,
                ),
              ),
              const SizedBox(height: 8),
              const AwanHomeGreeting(),
              const SizedBox(height: 20),
              _adventureStampCard(context),
              const SizedBox(height: 16),
              _adventurerCard(context),
              const SizedBox(height: 16),
              _latestCard(context),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _adventurerCard(BuildContext context) {
    if (controller.statsPhase == LoadPhase.loading &&
        controller.stats == null) {
      return const OraStatusPanel(
        kind: OraPanelKind.loading,
        message: 'LOADING ADVENTURER...',
      );
    }
    if (controller.statsPhase == LoadPhase.error && controller.stats == null) {
      return OraStatusPanel(
        kind: OraPanelKind.error,
        message: controller.statsError ?? 'RPG STATS UNAVAILABLE',
        onRetry: () => controller.loadStats(force: true),
      );
    }
    final stats = controller.stats;
    return OraCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const OraScreenTitle(
            title: 'ADVENTURER CARD',
            assetName: 'level.png',
          ),
          const SizedBox(height: 16),
          OraStatLine(
            label: 'LEVEL ${stats?.currentLevel ?? '--'}',
            value: stats?.currentLevelName.isNotEmpty == true
                ? stats!.currentLevelName
                : 'ADVENTURER',
            assetName: 'level.png',
          ),
          const SizedBox(height: 12),
          OraStatLine(
            label: 'TOTAL XP',
            value: stats == null ? '--' : '${stats.totalXp} XP',
            assetName: 'xp.png',
          ),
          const SizedBox(height: 12),
          OraStatLine(
            label: 'ADVENTURES',
            value: stats?.totalActivities.toString() ?? '--',
            assetName: 'adventure.png',
          ),
          const SizedBox(height: 12),
          OraStatLine(
            label: 'DISTANCE',
            value: stats == null
                ? '--'
                : formatBackendDistance(stats.totalDistanceKm),
            assetName: 'distance.png',
          ),
          const SizedBox(height: 14),
          _xpProgress(stats),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: controller.isSyncing ? null : controller.syncPending,
            icon: controller.isSyncing
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const OraIcon('resume.png', size: 20),
            label: Text(
              controller.isSyncing ? 'SYNCING...' : 'SYNC ADVENTURES',
            ),
          ),
          if (controller.syncMessage != null) ...[
            const SizedBox(height: 8),
            Text(
              controller.syncMessage!,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: controller.syncError
                    ? OraColors.orange
                    : OraColors.success,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _xpProgress(UserStats? stats) {
    final next = stats?.nextLevelXp;
    final progress = next == null || next <= 0
        ? 1.0
        : (stats!.totalXp / next).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LinearProgressIndicator(
          value: stats == null ? 0 : progress,
          minHeight: 9,
          color: OraColors.gold,
          backgroundColor: OraColors.panelAlt,
          borderRadius: BorderRadius.circular(2),
        ),
        const SizedBox(height: 6),
        Text(
          next == null ? 'MAX LEVEL' : '${stats?.totalXp ?? 0} / $next XP',
          textAlign: TextAlign.end,
          style: const TextStyle(fontSize: 12, color: OraColors.creamMuted),
        ),
      ],
    );
  }

  Widget _adventureStampCard(BuildContext context) => OraCard(
    padding: EdgeInsets.zero,
    gradient: const LinearGradient(
      colors: [OraColors.forestLight, OraColors.panelAlt],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    borderColor: OraColors.orange,
    child: Semantics(
      button: true,
      label: 'Adventure Stamp with event QR',
      child: GestureDetector(
        key: const Key('home_check_in'),
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => AttendanceScannerScreen(controller: controller),
          ),
        ),
        child: const Padding(
          padding: EdgeInsets.all(18),
          child: Row(
            children: [
              _AdventureStampIcon(),
              SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('ADVENTURE STAMP', style: OraTextStyles.displayMedium),
                    SizedBox(height: 8),
                    Text('SCAN EVENT QR • CLAIM YOUR XP'),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios, size: 18, color: OraColors.gold),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _latestCard(BuildContext context) {
    if (controller.activityPhase == LoadPhase.loading &&
        controller.latestActivity == null) {
      return const OraStatusPanel(
        kind: OraPanelKind.loading,
        message: 'LOADING ADVENTURE LOG...',
      );
    }
    final activity = controller.latestActivity;
    return OraCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const OraScreenTitle(
            title: 'LAST ADVENTURE',
            assetName: 'adventure.png',
          ),
          const SizedBox(height: 16),
          if (activity == null)
            const Text('NO ADVENTURE YET', textAlign: TextAlign.center)
          else ...[
            Text(
              formatActivityDate(activity.startDateTimeMillis),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            OraStatLine(
              label: 'DISTANCE',
              value: formatDistanceMeters(activity.distanceMeters),
              assetName: 'distance.png',
            ),
            const SizedBox(height: 10),
            OraStatLine(
              label: 'DURATION',
              value: formatDurationMillis(activity.activeDurationMillis),
              assetName: 'duration.png',
            ),
            const SizedBox(height: 10),
            OraStatLine(
              label: 'PACE',
              value: formatPace(activity.averagePaceSecondsPerKm),
              assetName: 'pace.png',
            ),
            if (activity.syncStatus == ActivitySyncStatus.notEligible) ...[
              const SizedBox(height: 10),
              const OraStatLine(
                label: 'SYNC',
                value: 'NOT ELIGIBLE — LOCAL ONLY',
                assetName: 'warning.png',
              ),
            ],
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const Key('home_view_last_route'),
              onPressed: () => _showRoute(context, activity),
              icon: const Icon(Icons.route),
              label: const Text('VIEW ROUTE'),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _showRoute(BuildContext context, FinalActivity activity) =>
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('ADVENTURE ROUTE'),
          content: SizedBox(
            width: 460,
            child: ActivityRouteViewer(
              store: controller.activityStore,
              activity: activity,
              ownerNik: controller.session.nik,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('CLOSE'),
            ),
          ],
        ),
      );
}

class _PwaInstallBanner extends StatelessWidget {
  const _PwaInstallBanner({required this.controller});

  final PwaInstallController controller;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final state = controller.state;
      if (state == PwaInstallState.hidden) return const SizedBox.shrink();
      final description = switch (state) {
        PwaInstallState.install =>
          'Install untuk akses ORA lebih cepat dari layar utama.',
        PwaInstallState.openInChrome =>
          'Buka halaman ini di Chrome untuk menginstal ORA.',
        PwaInstallState.iosInstructions =>
          'Buka di Safari → Share → Add to Home Screen',
        PwaInstallState.hidden => '',
      };
      final actionLabel = switch (state) {
        PwaInstallState.install => 'INSTALL ORA',
        PwaInstallState.openInChrome => 'BUKA DI CHROME',
        PwaInstallState.iosInstructions => 'LIHAT PANDUAN',
        PwaInstallState.hidden => '',
      };
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: OraCard(
          key: const Key('home_install_ora_banner'),
          padding: const EdgeInsets.all(14),
          borderColor: OraColors.gold,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Icon(Icons.install_mobile, color: OraColors.gold, size: 30),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'INSTALL ORA',
                      style: OraTextStyles.displaySmall,
                    ),
                    const SizedBox(height: 5),
                    Text(
                      description,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton(
                key: const Key('home_install_ora_action'),
                onPressed: () => _handleAction(context, state),
                child: Text(actionLabel),
              ),
            ],
          ),
        ),
      );
    },
  );

  Future<void> _handleAction(
    BuildContext context,
    PwaInstallState state,
  ) async {
    if (state == PwaInstallState.install) {
      await controller.promptInstall();
      return;
    }
    final title = state == PwaInstallState.openInChrome
        ? 'BUKA DI CHROME'
        : 'INSTALL ORA';
    final guide = state == PwaInstallState.openInChrome
        ? 'Buka menu browser, pilih Open in Chrome, lalu tekan INSTALL ORA. '
              'ORA tidak akan memindahkan halaman secara otomatis.'
        : 'Buka halaman ORA di Safari, tekan Share, lalu pilih Add to Home Screen.';
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(guide),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}

class _AdventureStampIcon extends StatelessWidget {
  const _AdventureStampIcon();

  @override
  Widget build(BuildContext context) => Container(
    width: 48,
    height: 48,
    decoration: BoxDecoration(
      color: OraColors.orange,
      borderRadius: BorderRadius.circular(4),
      border: Border.all(color: OraColors.gold, width: 2),
    ),
    child: const Icon(Icons.qr_code_scanner, color: OraColors.forestDeep),
  );
}
