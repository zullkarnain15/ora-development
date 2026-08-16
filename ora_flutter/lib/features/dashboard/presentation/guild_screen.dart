import 'package:flutter/material.dart';

import '../../../core/theme/ora_theme.dart';
import '../../../shared/widgets/ora_widgets.dart';
import '../application/feature_controller.dart';
import '../domain/feature_models.dart';
import 'formatters.dart';

enum GuildView { members, leaderboard, directory }

class GuildScreen extends StatefulWidget {
  const GuildScreen({super.key, required this.controller});
  final FeatureController controller;

  @override
  State<GuildScreen> createState() => _GuildScreenState();
}

class _GuildScreenState extends State<GuildScreen> {
  GuildView view = GuildView.members;

  Future<void> _refresh() => Future.wait([
    widget.controller.loadGuild(force: true),
    widget.controller.loadLeaderboard(force: true),
  ]);

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) => SafeArea(
      child: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const OraScreenTitle(
              title: 'GUILD HALL',
              subtitle: 'RUNNERS, RANKS, AND GUILD DIRECTORY',
              assetName: 'guild.png',
            ),
            const SizedBox(height: 14),
            SegmentedButton<GuildView>(
              segments: const [
                ButtonSegment(value: GuildView.members, label: Text('MEMBERS')),
                ButtonSegment(
                  value: GuildView.leaderboard,
                  label: Text('RANK'),
                ),
                ButtonSegment(
                  value: GuildView.directory,
                  label: Text('GUILDS'),
                ),
              ],
              selected: {view},
              onSelectionChanged: (value) => setState(() => view = value.first),
              showSelectedIcon: false,
            ),
            const SizedBox(height: 16),
            switch (view) {
              GuildView.members => _members(),
              GuildView.leaderboard => _leaderboard(),
              GuildView.directory => _directory(),
            },
          ],
        ),
      ),
    ),
  );

  Widget _members() {
    final controller = widget.controller;
    if (controller.guildPhase == LoadPhase.loading &&
        controller.guildData == null) {
      return const OraStatusPanel(
        kind: OraPanelKind.loading,
        message: 'ASSEMBLING GUILD...',
      );
    }
    if (controller.guildPhase == LoadPhase.error &&
        controller.guildData == null) {
      return OraStatusPanel(
        kind: OraPanelKind.error,
        message: controller.guildError ?? 'GUILD DATA UNAVAILABLE',
        onRetry: () => controller.loadGuild(force: true),
      );
    }
    final data = controller.guildData;
    if (data == null || data.status == 'UNASSIGNED') {
      return const OraStatusPanel(
        kind: OraPanelKind.empty,
        message: 'NO GUILD ASSIGNED',
      );
    }
    if (data.status == 'GUILD_INACTIVE') {
      return const OraStatusPanel(
        kind: OraPanelKind.error,
        message: 'THIS GUILD IS INACTIVE',
      );
    }
    final guild = data.guild;
    final currentNik = widget.controller.session.nik;
    final orderedMembers = <GuildMember>[
      ...data.members.where((member) => member.nik == currentNik),
      ...data.members.where((member) => member.nik != currentNik),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (guild != null)
          OraCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  guild.resolvedName,
                  style: OraTextStyles.displayMedium.copyWith(
                    color: OraColors.gold,
                  ),
                ),
                if (guild.description.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(guild.description),
                ],
                const SizedBox(height: 14),
                OraStatLine(
                  label: 'LEVEL ${guild.currentLevel}',
                  value: guild.currentLevelName,
                  assetName: 'level.png',
                ),
                const SizedBox(height: 10),
                OraStatLine(
                  label: 'TOTAL XP',
                  value: '${guild.totalXp} XP',
                  assetName: 'xp.png',
                ),
                const SizedBox(height: 10),
                OraStatLine(
                  label: 'MEMBERS',
                  value: '${guild.activeMemberCount}/${guild.memberCount}',
                  assetName: 'you.png',
                ),
                const SizedBox(height: 10),
                OraStatLine(
                  label: 'DISTANCE',
                  value: formatBackendDistance(guild.totalDistanceKm),
                  assetName: 'distance.png',
                ),
              ],
            ),
          ),
        const SizedBox(height: 14),
        if (data.members.isEmpty)
          const OraStatusPanel(
            kind: OraPanelKind.empty,
            message: 'NO ACTIVE GUILD MEMBERS',
          )
        else
          for (final member in orderedMembers) ...[
            Container(
              key: member.nik == currentNik
                  ? const Key('your_member_card')
                  : null,
              padding: const EdgeInsets.all(12),
              decoration: member.nik == currentNik
                  ? _highlightDecoration()
                  : _standardGuildCardDecoration(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          member.nickname.isEmpty
                              ? member.nik
                              : member.nickname,
                          style: OraTextStyles.displaySmall.copyWith(
                            color: OraColors.gold,
                          ),
                        ),
                      ),
                      if (member.nik == currentNik)
                        const PixelBadge(text: 'YOU'),
                    ],
                  ),
                  const SizedBox(height: 9),
                  OraStatLine(
                    label: 'LEVEL ${member.currentLevel}',
                    value: member.currentLevelName,
                  ),
                  const SizedBox(height: 7),
                  OraStatLine(label: 'XP', value: '${member.totalXp}'),
                  const SizedBox(height: 7),
                  OraStatLine(
                    label: 'RUNS',
                    value: '${member.totalActivities}',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
      ],
    );
  }

  Widget _leaderboard() {
    final controller = widget.controller;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final scope in LeaderboardScope.values)
              ChoiceChip(
                label: Text(scope.apiValue),
                selected: controller.leaderboardScope == scope,
                onSelected: (_) => controller.selectLeaderboardScope(scope),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final metric in LeaderboardMetric.values)
              ChoiceChip(
                label: Text(metric.label),
                selected: controller.leaderboardMetric == metric,
                onSelected: (_) => controller.selectLeaderboardMetric(metric),
              ),
          ],
        ),
        const SizedBox(height: 14),
        if (controller.leaderboardPhase == LoadPhase.loading &&
            controller.leaderboardData != null) ...[
          const _LeaderboardLoadingBanner(),
          const SizedBox(height: 12),
        ],
        if (controller.leaderboardPhase == LoadPhase.loading &&
            controller.leaderboardData == null)
          const OraStatusPanel(
            kind: OraPanelKind.loading,
            message: 'CALCULATING RANKS...',
          )
        else if (controller.leaderboardPhase == LoadPhase.error)
          OraStatusPanel(
            kind: OraPanelKind.error,
            message: controller.leaderboardError ?? 'LEADERBOARD UNAVAILABLE',
            onRetry: () => controller.loadLeaderboard(force: true),
          )
        else if (controller.leaderboardData?.status == 'NO_GUILD')
          const OraStatusPanel(
            kind: OraPanelKind.empty,
            message: 'NO GUILD RANK AVAILABLE',
          )
        else if (controller.leaderboardData == null ||
            controller.leaderboardData!.entries.isEmpty)
          const OraStatusPanel(
            kind: OraPanelKind.empty,
            message: 'NO RUNNERS ON THIS BOARD',
          )
        else ...[
          if (controller.leaderboardData!.currentUserRank case final rank?) ...[
            Container(
              key: const Key('your_rank_card'),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: OraColors.rankBlue.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(5),
                border: Border.all(color: OraColors.rankBlue, width: 2),
              ),
              child: OraStatLine(
                label: 'YOUR RANK',
                value: '#${rank.rank} • ${compactNumber(rank.metricValue)}',
                assetName: 'trophy.png',
                valueStyle: OraTextStyles.displayLarge.copyWith(
                  color: OraColors.forestDeep,
                  fontSize: 24,
                ),
                valuePadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 9,
                ),
                valueDecoration: BoxDecoration(
                  color: OraColors.gold.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: OraColors.cream, width: 1.5),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          for (final entry in controller.leaderboardData!.entries) ...[
            OraCard(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  SizedBox(
                    width: 44,
                    child: Text(
                      '#${entry.rank}',
                      style: OraTextStyles.displaySmall.copyWith(
                        color: OraColors.gold,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.nickname.isEmpty ? entry.nik : entry.nickname,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          '${entry.division} • LV ${entry.currentLevel}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: OraColors.creamMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    _metricValue(entry),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ],
      ],
    );
  }

  String _metricValue(LeaderboardEntry entry) =>
      switch (widget.controller.leaderboardMetric) {
        LeaderboardMetric.totalXp => '${entry.totalXp} XP',
        LeaderboardMetric.totalDistance => formatBackendDistance(
          entry.totalDistanceKm,
        ),
        LeaderboardMetric.totalActivities => '${entry.totalActivities} RUNS',
      };

  BoxDecoration _highlightDecoration() => BoxDecoration(
    color: OraColors.gold.withValues(alpha: 0.24),
    borderRadius: BorderRadius.circular(5),
    border: Border.all(color: OraColors.rankBlue, width: 2),
  );

  BoxDecoration _standardGuildCardDecoration() => BoxDecoration(
    color: OraColors.panel,
    borderRadius: BorderRadius.circular(5),
    border: Border.all(color: OraColors.outline),
  );

  Widget _directory() {
    final controller = widget.controller;
    if (controller.guildPhase == LoadPhase.loading &&
        controller.guildData == null) {
      return const OraStatusPanel(
        kind: OraPanelKind.loading,
        message: 'LOADING GUILD DIRECTORY...',
      );
    }
    final guilds = controller.guildData?.directory ?? const <GuildSummary>[];
    if (guilds.isEmpty) {
      return const OraStatusPanel(
        kind: OraPanelKind.empty,
        message: 'NO GUILDS IN DIRECTORY',
      );
    }
    final current = controller.guildData?.guild?.guildId.toLowerCase();
    final orderedGuilds = <GuildSummary>[
      ...guilds.where((guild) => guild.guildId.toLowerCase() == current),
      ...guilds.where((guild) => guild.guildId.toLowerCase() != current),
    ];
    return Column(
      children: [
        for (final guild in orderedGuilds) ...[
          Builder(
            builder: (context) {
              final isCurrent = guild.guildId.toLowerCase() == current;
              return Container(
                key: isCurrent ? const Key('your_guild_card') : null,
                padding: const EdgeInsets.all(14),
                decoration: isCurrent
                    ? _highlightDecoration()
                    : _standardGuildCardDecoration(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            guild.resolvedName,
                            style: OraTextStyles.displaySmall.copyWith(
                              color: OraColors.gold,
                            ),
                          ),
                        ),
                        if (isCurrent) const PixelBadge(text: 'YOUR GUILD'),
                      ],
                    ),
                    if (guild.description.isNotEmpty) ...[
                      const SizedBox(height: 7),
                      Text(guild.description),
                    ],
                    const SizedBox(height: 9),
                    OraStatLine(
                      label: 'MEMBERS',
                      value: '${guild.activeMemberCount} ACTIVE',
                    ),
                    const SizedBox(height: 7),
                    OraStatLine(
                      label: 'TOTAL XP',
                      value: '${guild.totalXp} XP',
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _LeaderboardLoadingBanner extends StatelessWidget {
  const _LeaderboardLoadingBanner();

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('leaderboard_refreshing'),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: OraColors.panelAlt,
      borderRadius: BorderRadius.circular(5),
      border: Border.all(color: OraColors.gold.withValues(alpha: 0.55)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const LinearProgressIndicator(
          minHeight: 5,
          color: OraColors.gold,
          backgroundColor: OraColors.outline,
        ),
        const SizedBox(height: 8),
        Text(
          'UPDATING RANKS...',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: OraColors.creamMuted),
        ),
      ],
    ),
  );
}
