import 'package:flutter/material.dart';

import '../../../core/theme/ora_theme.dart';
import '../../mascot/awan_mascot_slot.dart';
import '../../mascot/awan_mascot_state.dart';
import '../../../shared/widgets/ora_widgets.dart';
import '../../activity/domain/final_activity.dart';
import '../../activity/presentation/activity_route_viewer.dart';
import '../application/feature_controller.dart';
import '../domain/feature_models.dart';
import 'formatters.dart';

enum _AdventureLogFilter { all, synced, pending, notEligible }

enum _AdventureDateFilter {
  today,
  last7Days,
  last30Days,
  thisMonth,
  allTime,
  custom,
}

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    required this.controller,
    required this.onSettings,
  });
  final FeatureController controller;
  final VoidCallback onSettings;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  _AdventureLogFilter _activityFilter = _AdventureLogFilter.all;
  _AdventureDateFilter _dateFilter = _AdventureDateFilter.last7Days;
  DateTimeRange? _customDateRange;

  FeatureController get controller => widget.controller;
  VoidCallback get onSettings => widget.onSettings;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) => SafeArea(
      child: RefreshIndicator(
        onRefresh: () => Future.wait([
          controller.loadStats(force: true),
          controller.loadActivities(force: true),
        ]),
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Expanded(
                  child: OraScreenTitle(
                    title: 'ADVENTURER PROFILE',
                    assetName: 'you.png',
                  ),
                ),
                const AwanMascotSlot(
                  state: AwanMascotState.cheer,
                  minSize: 34,
                  maxSize: 39,
                ),
                IconButton(
                  key: const Key('open_settings'),
                  onPressed: onSettings,
                  tooltip: 'Settings',
                  icon: const OraIcon('settings.png', size: 30),
                ),
              ],
            ),
            const SizedBox(height: 18),
            _status(context),
            const SizedBox(height: 14),
            _totals(),
            const SizedBox(height: 14),
            _log(context),
          ],
        ),
      ),
    ),
  );

  Widget _status(BuildContext context) {
    final stats = controller.stats;
    return OraCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const OraScreenTitle(title: 'STATUS', assetName: 'level.png'),
          const SizedBox(height: 14),
          Text(
            stats?.nickname.isNotEmpty == true
                ? stats!.nickname
                : controller.session.nickname,
            style: OraTextStyles.displayMedium.copyWith(color: OraColors.gold),
          ),
          const SizedBox(height: 12),
          if (controller.statsPhase == LoadPhase.loading && stats == null)
            const Center(child: CircularProgressIndicator())
          else if (stats != null) ...[
            OraStatLine(
              label: 'LEVEL ${stats.currentLevel}',
              value: stats.currentLevelName.isEmpty
                  ? 'ADVENTURER'
                  : stats.currentLevelName,
              assetName: 'level.png',
            ),
            const SizedBox(height: 10),
            OraStatLine(
              label: 'GUILD',
              value: stats.division.isEmpty
                  ? controller.session.divisionGuild
                  : stats.division,
              assetName: 'guild.png',
            ),
            const SizedBox(height: 10),
            OraStatLine(
              label: 'TOTAL XP',
              value: '${stats.totalXp} XP',
              assetName: 'xp.png',
            ),
          ],
          if (controller.statsError != null) ...[
            const SizedBox(height: 10),
            Text(
              controller.statsError!,
              style: const TextStyle(color: OraColors.orange),
            ),
          ],
        ],
      ),
    );
  }

  Widget _totals() {
    final stats = controller.stats;
    return OraCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const OraScreenTitle(title: 'RPG STATS', assetName: 'trophy.png'),
          const SizedBox(height: 14),
          OraStatLine(
            label: 'TOTAL DISTANCE',
            value: stats == null
                ? '-- KM'
                : formatBackendDistance(stats.totalDistanceKm),
            assetName: 'distance.png',
          ),
          const SizedBox(height: 10),
          OraStatLine(
            label: 'ADVENTURES',
            value: stats?.totalActivities.toString() ?? '--',
            assetName: 'adventure.png',
          ),
          const SizedBox(height: 10),
          OraStatLine(
            label: 'TOTAL TIME',
            value: stats == null
                ? '--:--'
                : formatDurationMillis((stats.totalDurationSec * 1000).round()),
            assetName: 'duration.png',
          ),
          const SizedBox(height: 12),
          const Divider(color: OraColors.outline),
          OraStatLine(
            label: 'LOCAL LOG',
            value: '${controller.activityTotals.activityCount}',
          ),
        ],
      ),
    );
  }

  Widget _log(BuildContext context) => OraCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const OraScreenTitle(
          title: 'ADVENTURE LOG',
          assetName: 'adventure.png',
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          key: const Key('sync_adventures'),
          onPressed: controller.isSyncing ? null : controller.syncPending,
          style: FilledButton.styleFrom(
            backgroundColor: OraColors.gold,
            foregroundColor: OraColors.forestDeep,
            disabledBackgroundColor: OraColors.gold.withValues(alpha: 0.45),
            minimumSize: const Size.fromHeight(48),
            side: const BorderSide(color: OraColors.cream, width: 1.2),
          ),
          icon: controller.isSyncing
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const OraIcon('resume.png', size: 20),
          label: Text(controller.isSyncing ? 'SYNCING...' : 'SYNC ADVENTURES'),
        ),
        if (controller.syncMessage != null) ...[
          const SizedBox(height: 8),
          Text(
            controller.syncMessage!,
            style: TextStyle(
              color: controller.syncError
                  ? OraColors.orange
                  : OraColors.success,
            ),
          ),
        ],
        const SizedBox(height: 14),
        if (controller.activityPhase == LoadPhase.loading &&
            controller.activities.isEmpty)
          const Center(child: CircularProgressIndicator())
        else if (controller.activityError != null)
          Text(
            controller.activityError!,
            style: const TextStyle(color: OraColors.orange),
          )
        else if (controller.activities.isEmpty)
          const Text('NO ADVENTURE YET', textAlign: TextAlign.center)
        else ...[
          Material(
            color: Colors.transparent,
            child: DropdownButtonFormField<_AdventureDateFilter>(
              key: const Key('adventure_date_filter'),
              initialValue: _dateFilter,
              decoration: const InputDecoration(
                labelText: 'DATE RANGE',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: const [
                DropdownMenuItem(
                  value: _AdventureDateFilter.today,
                  child: Text('TODAY'),
                ),
                DropdownMenuItem(
                  value: _AdventureDateFilter.last7Days,
                  child: Text('LAST 7 DAYS'),
                ),
                DropdownMenuItem(
                  value: _AdventureDateFilter.last30Days,
                  child: Text('LAST 30 DAYS'),
                ),
                DropdownMenuItem(
                  value: _AdventureDateFilter.thisMonth,
                  child: Text('THIS MONTH'),
                ),
                DropdownMenuItem(
                  value: _AdventureDateFilter.allTime,
                  child: Text('ALL TIME'),
                ),
                DropdownMenuItem(
                  value: _AdventureDateFilter.custom,
                  child: Text('CUSTOM DATE RANGE'),
                ),
              ],
              onChanged: _selectDateFilter,
            ),
          ),
          const SizedBox(height: 12),
          Material(
            color: Colors.transparent,
            child: DropdownButtonFormField<_AdventureLogFilter>(
              key: const Key('adventure_log_filter'),
              initialValue: _activityFilter,
              decoration: const InputDecoration(
                labelText: 'FILTER ADVENTURES',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: const [
                DropdownMenuItem(
                  value: _AdventureLogFilter.all,
                  child: Text('ALL ADVENTURES'),
                ),
                DropdownMenuItem(
                  value: _AdventureLogFilter.synced,
                  child: Text('SYNCED'),
                ),
                DropdownMenuItem(
                  value: _AdventureLogFilter.pending,
                  child: Text('PENDING SYNC'),
                ),
                DropdownMenuItem(
                  value: _AdventureLogFilter.notEligible,
                  child: Text('NOT ELIGIBLE'),
                ),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _activityFilter = value);
              },
            ),
          ),
          const SizedBox(height: 12),
          if (_filteredActivities.isEmpty)
            const Text(
              'NO ADVENTURES MATCH THIS FILTER',
              textAlign: TextAlign.center,
            ),
          for (final activity in _filteredActivities) ...[
            _ActivityTile(
              activity,
              onViewRoute: () => _showRoute(context, activity),
              onDelete: activity.syncStatus == ActivitySyncStatus.notEligible
                  ? () => _deleteNotEligible(context, activity)
                  : activity.syncStatus == ActivitySyncStatus.synced &&
                        controller.localActivityIds.contains(
                          activity.activityId,
                        )
                  ? () => _removeLocalData(context, activity)
                  : null,
              deleteKey: activity.syncStatus == ActivitySyncStatus.synced
                  ? Key('remove_local_data_${activity.activityId}')
                  : Key('delete_not_eligible_${activity.activityId}'),
              deleteLabel: activity.syncStatus == ActivitySyncStatus.synced
                  ? 'REMOVE LOCAL DATA'
                  : 'DELETE LOCAL LOG',
            ),
            const SizedBox(height: 10),
          ],
        ],
        if (controller.activityWarning != null) ...[
          const SizedBox(height: 8),
          Text(
            controller.activityWarning!,
            style: const TextStyle(color: OraColors.orange, fontSize: 11),
          ),
        ],
      ],
    ),
  );

  List<FinalActivity> get _filteredActivities => controller.activities
      .where((activity) => _matchesStatus(activity) && _matchesDate(activity))
      .toList(growable: false);

  bool _matchesStatus(FinalActivity activity) => switch (_activityFilter) {
    _AdventureLogFilter.all => true,
    _AdventureLogFilter.synced =>
      activity.syncStatus == ActivitySyncStatus.synced,
    _AdventureLogFilter.pending =>
      activity.syncStatus == ActivitySyncStatus.pending ||
          activity.syncStatus == ActivitySyncStatus.localOnly,
    _AdventureLogFilter.notEligible =>
      activity.syncStatus == ActivitySyncStatus.notEligible,
  };

  bool _matchesDate(FinalActivity activity) {
    final date = DateTime.fromMillisecondsSinceEpoch(
      activity.startDateTimeMillis,
    );
    final range = _dateRange;
    return range == null ||
        (!date.isBefore(range.start) && date.isBefore(range.end));
  }

  DateTimeRange? get _dateRange {
    final today = DateUtils.dateOnly(DateTime.now());
    switch (_dateFilter) {
      case _AdventureDateFilter.today:
        return DateTimeRange(
          start: today,
          end: today.add(const Duration(days: 1)),
        );
      case _AdventureDateFilter.last7Days:
        return DateTimeRange(
          start: today.subtract(const Duration(days: 6)),
          end: today.add(const Duration(days: 1)),
        );
      case _AdventureDateFilter.last30Days:
        return DateTimeRange(
          start: today.subtract(const Duration(days: 29)),
          end: today.add(const Duration(days: 1)),
        );
      case _AdventureDateFilter.thisMonth:
        return DateTimeRange(
          start: DateTime(today.year, today.month),
          end: DateTime(today.year, today.month + 1),
        );
      case _AdventureDateFilter.custom:
        if (_customDateRange case final range?) {
          return DateTimeRange(
            start: DateUtils.dateOnly(range.start),
            end: DateUtils.dateOnly(range.end).add(const Duration(days: 1)),
          );
        }
      case _AdventureDateFilter.allTime:
        return null;
    }
    return null;
  }

  Future<void> _selectDateFilter(_AdventureDateFilter? filter) async {
    if (filter == null) return;
    if (filter != _AdventureDateFilter.custom) {
      setState(() => _dateFilter = filter);
      return;
    }
    final today = DateUtils.dateOnly(DateTime.now());
    final selected = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: today,
      initialDateRange: _customDateRange,
    );
    if (!mounted || selected == null) return;
    setState(() {
      _dateFilter = _AdventureDateFilter.custom;
      _customDateRange = selected;
    });
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

  Future<void> _deleteNotEligible(
    BuildContext context,
    FinalActivity activity,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('DELETE LOCAL ADVENTURE?'),
        content: const Text(
          'This adventure has no eligible GPS distance or active duration. Its local route and recovery evidence will also be deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCEL'),
          ),
          FilledButton(
            key: const Key('confirm_delete_not_eligible'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('DELETE'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    bool deleted;
    try {
      deleted = await controller.deleteNotEligibleActivity(activity.activityId);
    } on Object {
      deleted = false;
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          deleted ? 'LOCAL ADVENTURE DELETED' : 'ADVENTURE WAS NOT DELETED',
        ),
      ),
    );
  }

  Future<void> _removeLocalData(
    BuildContext context,
    FinalActivity activity,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('REMOVE LOCAL DATA?'),
        content: const Text(
          'The activity summary will remain in your Adventure Log because it is already synced. Local route data on this device will be removed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCEL'),
          ),
          FilledButton(
            key: const Key('confirm_remove_local_data'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('REMOVE'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    bool removed;
    try {
      removed = await controller.removeLocalActivityData(activity.activityId);
    } on Object {
      removed = false;
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          removed ? 'LOCAL DATA REMOVED' : 'LOCAL DATA WAS NOT REMOVED',
        ),
      ),
    );
  }
}

class _ActivityTile extends StatelessWidget {
  const _ActivityTile(
    this.activity, {
    required this.onViewRoute,
    this.onDelete,
    this.deleteKey,
    this.deleteLabel,
  });
  final FinalActivity activity;
  final VoidCallback onViewRoute;
  final VoidCallback? onDelete;
  final Key? deleteKey;
  final String? deleteLabel;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: OraColors.panelAlt,
      border: Border.all(color: OraColors.outline),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          formatActivityDate(activity.startDateTimeMillis),
          style: OraTextStyles.displaySmall.copyWith(color: OraColors.gold),
        ),
        const SizedBox(height: 10),
        OraStatLine(
          label: 'DISTANCE',
          value: formatDistanceMeters(activity.distanceMeters),
        ),
        const SizedBox(height: 7),
        OraStatLine(
          label: 'DURATION',
          value: formatDurationMillis(activity.activeDurationMillis),
        ),
        const SizedBox(height: 7),
        OraStatLine(
          label: 'PACE',
          value: formatPace(activity.averagePaceSecondsPerKm),
        ),
        const SizedBox(height: 7),
        OraStatLine(
          label: 'SYNC',
          value: switch (activity.syncStatus) {
            ActivitySyncStatus.synced => 'SYNCED',
            ActivitySyncStatus.notEligible => 'NOT ELIGIBLE',
            _ => 'PENDING',
          },
          assetName: activity.syncStatus == ActivitySyncStatus.synced
              ? 'success.png'
              : 'warning.png',
        ),
        if (activity.syncStatus == ActivitySyncStatus.notEligible) ...[
          const SizedBox(height: 8),
          const Text(
            'NO GPS DISTANCE OR ACTIVE DURATION — KEPT ON THIS DEVICE ONLY',
            style: TextStyle(color: OraColors.orange, fontSize: 11),
          ),
        ],
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: onViewRoute,
          icon: const Icon(Icons.route),
          label: const Text('VIEW ROUTE'),
        ),
        if (onDelete != null) ...[
          const SizedBox(height: 6),
          TextButton.icon(
            key: deleteKey,
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline),
            label: Text(deleteLabel ?? 'DELETE LOCAL LOG'),
          ),
        ],
      ],
    ),
  );
}
