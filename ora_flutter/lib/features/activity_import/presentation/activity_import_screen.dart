import 'package:flutter/material.dart';

import '../../../core/theme/ora_theme.dart';
import '../../../shared/widgets/ora_widgets.dart';
import '../application/activity_import_controller.dart';
import '../domain/activity_share_payload.dart';

class ActivityImportScreen extends StatefulWidget {
  const ActivityImportScreen({
    super.key,
    required this.controller,
    required this.onClose,
  });

  final ActivityImportController controller;
  final VoidCallback onClose;

  @override
  State<ActivityImportScreen> createState() => _ActivityImportScreenState();
}

class _ActivityImportScreenState extends State<ActivityImportScreen> {
  ActivityImportController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('SHARED ACTIVITY'),
      backgroundColor: OraColors.forest,
      automaticallyImplyLeading: false,
    ),
    body: SafeArea(child: _body(context)),
  );

  Widget _body(BuildContext context) {
    if (controller.phase == ActivityImportPhase.reading) {
      return const Center(
        child: OraStatusPanel(
          kind: OraPanelKind.loading,
          message: 'READING SHARED ACTIVITY...',
        ),
      );
    }
    if (controller.phase == ActivityImportPhase.error &&
        controller.draft == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: OraCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const OraIcon('warning.png', size: 42),
                const SizedBox(height: 14),
                Text(
                  controller.message ?? 'SHARED ACTIVITY FAILED',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _decline,
                  child: const Text('BACK TO ORA'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final draft = controller.draft;
    if (draft == null) return const SizedBox.shrink();
    final saved = controller.phase == ActivityImportPhase.saved;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const OraScreenTitle(
          title: 'SHARED ACTIVITY',
          subtitle: 'ACTIVITY PREVIEW',
          assetName: 'adventure.png',
        ),
        const SizedBox(height: 16),
        OraCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              OraStatLine(label: 'SOURCE', value: draft.source.label),
              const SizedBox(height: 12),
              OraStatLine(
                key: const Key('import_distance'),
                label: 'DISTANCE',
                value: _distanceText(draft.distanceMeters),
              ),
              const SizedBox(height: 12),
              OraStatLine(
                key: const Key('import_duration'),
                label: 'DURATION',
                value: _durationText(draft.durationSeconds),
              ),
              if (draft.derivedFromPace) ...[
                const SizedBox(height: 8),
                const OraStatLine(
                  label: 'DURATION SOURCE',
                  value: 'ESTIMATED FROM PACE',
                ),
              ],
              const SizedBox(height: 12),
              OraStatLine(
                key: const Key('import_pace'),
                label: 'PACE',
                value: _paceText(draft.calculatedPaceSecondsPerKm),
              ),
              if (draft.detectedPaceSecondsPerKm != null) ...[
                const SizedBox(height: 8),
                OraStatLine(
                  label: 'OCR PACE',
                  value: _paceText(draft.detectedPaceSecondsPerKm),
                ),
              ],
              const SizedBox(height: 18),
              OraStatLine(
                label: 'ACTIVITY DATE',
                value: _dateText(controller.selectedDate),
              ),
              const SizedBox(height: 12),
              OraStatLine(
                label: 'START TIME',
                value: _timeText(
                  controller.selectedHour,
                  controller.selectedMinute,
                ),
              ),
              if (draft.sourceRef case final sourceRef?) ...[
                const SizedBox(height: 12),
                OraStatLine(label: 'SOURCE REF', value: sourceRef),
              ],
            ],
          ),
        ),
        if (controller.message != null) ...[
          const SizedBox(height: 12),
          _ImportWarning(message: controller.message!, success: saved),
        ],
        const SizedBox(height: 16),
        if (saved)
          FilledButton(
            key: const Key('import_done'),
            onPressed: _done,
            child: const Text('DONE'),
          )
        else
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  key: const Key('import_decline'),
                  onPressed: controller.phase == ActivityImportPhase.saving
                      ? null
                      : _decline,
                  child: const Text('DECLINE'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  key: const Key('import_save'),
                  onPressed:
                      draft.canSave &&
                          controller.phase != ActivityImportPhase.saving
                      ? _save
                      : null,
                  child: Text(
                    controller.phase == ActivityImportPhase.saving
                        ? 'SAVING...'
                        : 'SAVE ACTIVITY',
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }

  Future<void> _save() async {
    final saved = await controller.save();
    if (saved || !mounted) return;
    final draft = controller.draft;
    if (draft?.possibleDuplicate != true ||
        draft?.possibleDuplicateConfirmed == true) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('POSSIBLE DUPLICATE'),
        content: const Text('POSSIBLE DUPLICATE – SAVE ANYWAY?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCEL'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('SAVE ANYWAY'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    controller.confirmPossibleDuplicate();
    await controller.save();
  }

  Future<void> _done() async {
    await controller.finish();
    if (mounted) widget.onClose();
  }

  Future<void> _decline() async {
    await controller.decline();
    if (mounted) widget.onClose();
  }
}

class _ImportWarning extends StatelessWidget {
  const _ImportWarning({required this.message, this.success = false});

  final String message;
  final bool success;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(11),
    decoration: BoxDecoration(
      color: (success ? OraColors.success : OraColors.orange).withValues(
        alpha: 0.12,
      ),
      border: Border.all(color: success ? OraColors.success : OraColors.orange),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(message, textAlign: TextAlign.center),
  );
}

String _distanceText(double? meters) =>
    meters == null ? '--.-- KM' : '${(meters / 1000).toStringAsFixed(2)} KM';

String _durationText(int? seconds) {
  if (seconds == null) return '--:--';
  final hours = seconds ~/ 3600;
  final minutes = (seconds % 3600) ~/ 60;
  final remainder = seconds % 60;
  return hours > 0
      ? '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${remainder.toString().padLeft(2, '0')}'
      : '${minutes.toString().padLeft(2, '0')}:${remainder.toString().padLeft(2, '0')}';
}

String _paceText(int? seconds) => seconds == null
    ? '--:-- /KM'
    : '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')} /KM';

String _dateText(DateTime? value) => value == null
    ? 'ACTIVITY DATE'
    : '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';

String _timeText(int? hour, int? minute) => hour == null || minute == null
    ? 'START TIME'
    : '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
