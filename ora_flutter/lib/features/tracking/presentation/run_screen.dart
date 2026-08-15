import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/ora_theme.dart';
import '../../../shared/widgets/ora_widgets.dart';
import '../application/tracking_controller.dart';
import '../domain/tracking_models.dart';

class RunScreen extends StatelessWidget {
  const RunScreen({super.key, required this.controller});
  final TrackingController controller;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) => SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const OraScreenTitle(
            title: 'RUN ADVENTURE',
            subtitle: 'OFFLINE GPS TRACKING',
            assetName: 'run.png',
          ),
          const SizedBox(height: 16),
          if (kIsWeb) ...[
            const _WebTrackingNotice(),
            const SizedBox(height: 12),
          ],
          _StatusBanner(controller: controller),
          const SizedBox(height: 14),
          if (controller.status == TrackingStatus.recoverableSession)
            _RecoveryPanel(controller: controller)
          else ...[
            _MetricsPanel(controller: controller),
            const SizedBox(height: 16),
            _Actions(controller: controller),
          ],
        ],
      ),
    ),
  );
}

class _WebTrackingNotice extends StatelessWidget {
  const _WebTrackingNotice();

  @override
  Widget build(BuildContext context) => const OraCard(
    padding: EdgeInsets.all(12),
    child: Row(
      children: [
        OraIcon('warning.png', size: 22),
        SizedBox(width: 10),
        Expanded(
          child: Text(
            'FOR BEST TRACKING ACCURACY, KEEP ORA OPEN AND THE SCREEN AWAKE.',
          ),
        ),
      ],
    ),
  );
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.controller});
  final TrackingController controller;

  @override
  Widget build(BuildContext context) => OraCard(
    padding: const EdgeInsets.all(14),
    child: Column(
      children: [
        Row(
          children: [
            OraIcon(
              controller.isWarning ? 'warning.png' : 'location.png',
              size: 26,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    controller.status.name
                        .replaceAllMapped(
                          RegExp(r'([a-z])([A-Z])'),
                          (match) => '${match[1]} ${match[2]}',
                        )
                        .toUpperCase(),
                    style: OraTextStyles.displaySmall.copyWith(
                      color: controller.isWarning
                          ? OraColors.orange
                          : OraColors.gold,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(controller.message),
                ],
              ),
            ),
          ],
        ),
        if (controller.isBackgroundTracking) ...[
          const SizedBox(height: 10),
          const PixelBadge(text: 'BACKGROUND TRACKING ACTIVE'),
        ],
      ],
    ),
  );
}

class _MetricsPanel extends StatelessWidget {
  const _MetricsPanel({required this.controller});
  final TrackingController controller;

  @override
  Widget build(BuildContext context) => OraCard(
    child: Column(
      children: [
        _Metric(
          icon: 'distance.png',
          label: 'DISTANCE',
          value: formatTrackingDistance(controller.distanceMeters),
          large: true,
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: _Metric(
                icon: 'duration.png',
                label: 'ACTIVE DURATION',
                value: formatTrackingDuration(controller.activeDurationMillis),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _Metric(
                icon: 'pace.png',
                label: 'AVG PACE',
                value: formatTrackingPace(controller.averagePace),
              ),
            ),
          ],
        ),
        if (controller.status != TrackingStatus.idle) ...[
          const SizedBox(height: 12),
          OraStatLine(
            label: 'GPS QUALITY',
            value: controller.gpsQuality.name.toUpperCase(),
            assetName: 'location.png',
          ),
        ],
      ],
    ),
  );
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.icon,
    required this.label,
    required this.value,
    this.large = false,
  });
  final String icon;
  final String label;
  final String value;
  final bool large;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      OraIcon(icon, size: large ? 30 : 24),
      const SizedBox(height: 7),
      FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          value,
          style:
              (large ? OraTextStyles.displayLarge : OraTextStyles.displayMedium)
                  .copyWith(color: OraColors.gold),
        ),
      ),
      const SizedBox(height: 6),
      Text(label, textAlign: TextAlign.center),
    ],
  );
}

class _Actions extends StatelessWidget {
  const _Actions({required this.controller});
  final TrackingController controller;

  @override
  Widget build(BuildContext context) => switch (controller.status) {
    TrackingStatus.idle || TrackingStatus.error => FilledButton.icon(
      key: const Key('run_prepare_gps'),
      onPressed: controller.prepareGps,
      icon: const OraIcon('location.png', size: 25),
      label: const Text('PREPARE GPS'),
    ),
    TrackingStatus.preparingGps =>
      controller.gpsSearchTimedOut
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'GPS SIGNAL IS STILL WEAK',
                  textAlign: TextAlign.center,
                  style: OraTextStyles.displaySmall.copyWith(
                    color: OraColors.orange,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Duration can start now. Distance will wait for a good GPS fix.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  key: const Key('run_start_anyway'),
                  onPressed: controller.canStartAnyway
                      ? controller.startAnyway
                      : null,
                  icon: const OraIcon('run.png', size: 22),
                  label: const Text('START ANYWAY'),
                ),
                const SizedBox(height: 7),
                OutlinedButton(
                  key: const Key('run_cancel_gps'),
                  onPressed: controller.cancelGpsPreparation,
                  child: const Text('CANCEL RUN'),
                ),
              ],
            )
          : Column(
              children: [
                const CircularProgressIndicator(color: OraColors.gold),
                const SizedBox(height: 10),
                Text(
                  'SEARCHING FOR GPS  00:${controller.gpsSearchRemainingSeconds.toString().padLeft(2, '0')}',
                ),
              ],
            ),
    TrackingStatus.gpsReady => FilledButton.icon(
      key: const Key('run_start'),
      onPressed: controller.start,
      icon: const OraIcon('run.png', size: 25),
      label: const Text('START ADVENTURE'),
    ),
    TrackingStatus.startRequested || TrackingStatus.finalizing => const Center(
      child: CircularProgressIndicator(color: OraColors.gold),
    ),
    TrackingStatus.acquiringGps ||
    TrackingStatus.running ||
    TrackingStatus.reacquiring => Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            key: const Key('run_pause'),
            onPressed: controller.pause,
            icon: const OraIcon('pause.png', size: 22),
            label: const Text('PAUSE'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: FilledButton.icon(
            key: const Key('run_finish'),
            onPressed: controller.finish,
            icon: const OraIcon('finish.png', size: 22),
            label: const Text('FINISH'),
          ),
        ),
      ],
    ),
    TrackingStatus.paused => Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            key: const Key('run_resume'),
            onPressed: controller.resume,
            icon: const OraIcon('resume.png', size: 22),
            label: const Text('RESUME'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton.icon(
            key: const Key('run_finish'),
            onPressed: controller.finish,
            icon: const OraIcon('finish.png', size: 22),
            label: const Text('FINISH'),
          ),
        ),
      ],
    ),
    TrackingStatus.finished => FilledButton.icon(
      key: const Key('run_done'),
      onPressed: controller.done,
      icon: const OraIcon('success.png', size: 24),
      label: const Text('DONE'),
    ),
    TrackingStatus.recoverableSession => const SizedBox.shrink(),
  };
}

class _RecoveryPanel extends StatelessWidget {
  const _RecoveryPanel({required this.controller});
  final TrackingController controller;

  @override
  Widget build(BuildContext context) => OraCard(
    child: Column(
      children: [
        const OraIcon('warning.png', size: 42),
        const SizedBox(height: 12),
        Text(
          'RECOVER ADVENTURE',
          style: OraTextStyles.displayMedium.copyWith(color: OraColors.gold),
        ),
        const SizedBox(height: 10),
        Text(
          '${formatTrackingDistance(controller.distanceMeters)} • '
          '${formatTrackingDuration(controller.activeDurationMillis)} ACTIVE',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          key: const Key('recovery_resume'),
          onPressed: controller.resumeRecovered,
          icon: const OraIcon('resume.png', size: 22),
          label: const Text('RESUME ADVENTURE'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          key: const Key('recovery_save'),
          onPressed: controller.endRecoveredAndSave,
          icon: const OraIcon('finish.png', size: 22),
          label: const Text('END & SAVE'),
        ),
        TextButton(
          key: const Key('recovery_discard'),
          onPressed: () => _confirmDiscard(context),
          child: const Text('DISCARD'),
        ),
      ],
    ),
  );

  Future<void> _confirmDiscard(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('DISCARD ADVENTURE?'),
        content: const Text(
          'This unfinished run and its GPS points will be removed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCEL'),
          ),
          FilledButton(
            key: const Key('recovery_discard_confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('DISCARD'),
          ),
        ],
      ),
    );
    if (confirmed == true) await controller.discardRecovered();
  }
}
