import 'package:flutter/material.dart';

import '../../../core/theme/ora_theme.dart';
import '../../../shared/widgets/ora_widgets.dart';
import '../application/feature_controller.dart';
import '../domain/feature_models.dart';
import 'formatters.dart';

class QuestScreen extends StatelessWidget {
  const QuestScreen({super.key, required this.controller});
  final FeatureController controller;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) => SafeArea(
      child: RefreshIndicator(
        onRefresh: () => controller.loadQuests(force: true),
        child: ListView(
          key: const Key('quest_list'),
          padding: const EdgeInsets.all(16),
          children: [
            const OraScreenTitle(
              title: 'QUEST BOARD',
              subtitle: 'ACTIVE MISSIONS FROM ORA MASTER',
              assetName: 'quest.png',
            ),
            const SizedBox(height: 16),
            if (controller.questPhase == LoadPhase.loading &&
                controller.quests.isEmpty)
              const OraStatusPanel(
                kind: OraPanelKind.loading,
                message: 'CONTACTING QUEST MASTER...',
              )
            else if (controller.questPhase == LoadPhase.error &&
                controller.quests.isEmpty)
              OraStatusPanel(
                kind: OraPanelKind.error,
                message:
                    controller.questError ?? 'QUESTS UNAVAILABLE - TRY AGAIN',
                onRetry: () => controller.loadQuests(force: true),
              )
            else if (controller.quests.isEmpty)
              const OraStatusPanel(
                kind: OraPanelKind.empty,
                message: 'THE QUEST BOARD IS CLEAR.',
              ),
            if (controller.questsAreFallback) ...[
              const _FallbackBanner(),
              const SizedBox(height: 8),
            ],
            for (final quest in controller.quests) ...[
              _QuestCard(
                quest: quest,
                isClaiming: controller.claimingQuestId == quest.questId,
                claimsLocked: controller.claimingQuestId != null,
                claimMessage: controller.claimMessage,
                showClaimMessage:
                    controller.claimMessageQuestId == quest.questId,
                onClaim: () => controller.claimQuest(quest.questId),
              ),
              const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    ),
  );
}

class _FallbackBanner extends StatelessWidget {
  const _FallbackBanner();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: OraColors.orange.withValues(alpha: 0.12),
      border: Border.all(color: OraColors.orange),
      borderRadius: BorderRadius.circular(4),
    ),
    child: const Row(
      children: [
        OraIcon('warning.png', size: 22),
        SizedBox(width: 10),
        Expanded(
          child: Text(
            'OFFLINE/FALLBACK DATA - PERSONAL PROGRESS IS NOT AVAILABLE',
          ),
        ),
      ],
    ),
  );
}

class _QuestCard extends StatelessWidget {
  const _QuestCard({
    required this.quest,
    required this.isClaiming,
    required this.claimsLocked,
    required this.claimMessage,
    required this.showClaimMessage,
    required this.onClaim,
  });
  final Quest quest;
  final bool isClaiming;
  final bool claimsLocked;
  final String? claimMessage;
  final bool showClaimMessage;
  final VoidCallback onClaim;

  @override
  Widget build(BuildContext context) {
    final state = quest.visualState;
    final accent = switch (state) {
      QuestVisualState.claimable => OraColors.orange,
      QuestVisualState.claimed => OraColors.teal,
      QuestVisualState.inProgress => OraColors.gold,
      _ => OraColors.creamMuted,
    };
    final badge = switch (state) {
      QuestVisualState.notStarted => 'NOT STARTED',
      QuestVisualState.inProgress => 'IN PROGRESS',
      QuestVisualState.claimable => 'QUEST COMPLETE!',
      QuestVisualState.claimed => 'CLAIMED ✓',
      QuestVisualState.unsupported => 'GUILD QUEST COMING SOON',
      QuestVisualState.noGuild => 'NO GUILD ASSIGNED',
      QuestVisualState.unknown => 'QUEST TYPE NOT READY',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
      decoration: BoxDecoration(
        color: state == QuestVisualState.notStarted
            ? OraColors.forest
            : OraColors.panel,
        border: Border.all(
          color: accent,
          width: state == QuestVisualState.claimable ? 2 : 1.2,
        ),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              OraIcon(
                quest.questType == 'GUILD_DISTANCE' ? 'guild.png' : 'quest.png',
                size: 21,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  quest.questName,
                  style: OraTextStyles.displaySmall.copyWith(color: accent),
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Row(
            children: [
              Expanded(
                child: Text(
                  badge,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: accent,
                  ),
                ),
              ),
              Text(
                '+${quest.rewardXp} XP',
                style: TextStyle(
                  fontSize: 11,
                  color: accent,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${quest.questType.replaceAll('_', ' ')}  •  ${quest.periodType.replaceAll('_', ' ')}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 5),
          OraStatLine(
            label: quest.progress == null ? 'TARGET' : 'PROGRESS',
            value: quest.progress == null
                ? '${compactNumber(quest.targetValue)} ${quest.unit}'.trim()
                : '${compactNumber(quest.progress!)} / ${compactNumber(quest.targetValue)} ${quest.unit}',
          ),
          if (quest.progress != null) ...[
            const SizedBox(height: 5),
            LinearProgressIndicator(
              value:
                  state == QuestVisualState.claimable ||
                      state == QuestVisualState.claimed
                  ? 1
                  : (quest.progressPercent! / 100).clamp(0.0, 1.0),
              minHeight: 6,
              color: accent,
              backgroundColor: OraColors.panelAlt,
            ),
          ],
          if (quest.canClaim) ...[
            const SizedBox(height: 8),
            FilledButton(
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
                minimumSize: const Size.fromHeight(38),
              ),
              onPressed: claimsLocked ? null : onClaim,
              child: isClaiming
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text('CLAIM +${quest.rewardXp} XP'),
            ),
          ],
          if (claimMessage != null && showClaimMessage) ...[
            const SizedBox(height: 8),
            Text(
              claimMessage!,
              style: const TextStyle(
                color: OraColors.gold,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
