import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/ora_theme.dart';
import '../../../shared/widgets/ora_widgets.dart';
import '../application/activity_import_controller.dart';
import '../domain/activity_import_models.dart';
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
  final _distance = TextEditingController();
  final _duration = TextEditingController();
  final _sharedText = TextEditingController();
  ActivityImportDraft? _hydratedDraft;

  ActivityImportController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    controller.addListener(_onControllerChanged);
    _onControllerChanged();
  }

  @override
  void dispose() {
    controller.removeListener(_onControllerChanged);
    _distance.dispose();
    _duration.dispose();
    _sharedText.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    final draft = controller.draft;
    if (draft != null && _hydratedDraft == null) {
      _hydratedDraft = draft;
      _distance.text = draft.distanceMeters == null
          ? ''
          : (draft.distanceMeters! / 1000).toStringAsFixed(2);
      _duration.text = _durationText(draft.durationSeconds);
      _sharedText.text = draft.payload.sharedText ?? '';
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('IMPORT ACTIVITY'),
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
          message: 'READING ACTIVITY...',
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
                  controller.message ?? 'IMPORT FAILED',
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
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const OraScreenTitle(
          title: 'ORA IMPORT',
          subtitle: 'REVIEW BEFORE SAVING',
          assetName: 'adventure.png',
        ),
        const SizedBox(height: 16),
        OraCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              OraStatLine(label: 'SOURCE', value: draft.source.label),
              const SizedBox(height: 12),
              TextField(
                key: const Key('import_distance'),
                controller: _distance,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'DISTANCE (KM)',
                  helperText: 'REQUIRED',
                ),
                onChanged: controller.updateDistanceKm,
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('import_duration'),
                controller: _duration,
                keyboardType: TextInputType.datetime,
                decoration: const InputDecoration(
                  labelText: 'DURATION',
                  hintText: '58:06 OR 01:02:03',
                  helperText: 'MM:SS OR HH:MM:SS',
                ),
                onChanged: controller.updateDuration,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const Key('import_date'),
                      onPressed: () => _pickDate(draft),
                      icon: const Icon(Icons.calendar_today_outlined),
                      label: Text(_dateText(controller.selectedDate)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const Key('import_time'),
                      onPressed: () => _pickTime(draft),
                      icon: const Icon(Icons.schedule),
                      label: Text(
                        _timeText(
                          controller.selectedHour,
                          controller.selectedMinute,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              OraStatLine(
                label: 'CALCULATED PACE',
                value: _paceText(draft.calculatedPaceSecondsPerKm),
              ),
              if (draft.detectedPaceSecondsPerKm != null) ...[
                const SizedBox(height: 8),
                OraStatLine(
                  label: 'PACE CHECK',
                  value: draft.paceStatus == ActivityImportPaceStatus.verified
                      ? 'VERIFIED'
                      : 'REVIEW REQUIRED',
                ),
              ],
              if (draft.possibleDuplicate) ...[
                const SizedBox(height: 12),
                const _ImportWarning(
                  message: 'POSSIBLE DUPLICATE - REVIEW BEFORE SAVING',
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        OraCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const OraScreenTitle(
                title: 'SHARED DATA',
                assetName: 'resume.png',
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('import_shared_text'),
                controller: _sharedText,
                minLines: 3,
                maxLines: 7,
                decoration: const InputDecoration(
                  labelText: 'TEXT FROM SHARE',
                  hintText: 'PASTE STRAVA TEXT HERE',
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                key: const Key('import_reparse'),
                onPressed: () => controller.replaceSharedText(_sharedText.text),
                icon: const Icon(Icons.auto_fix_high),
                label: const Text('PARSE TEXT'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                key: const Key('import_screenshot'),
                onPressed: _pickScreenshot,
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: Text(
                  draft.payload.images.isEmpty
                      ? 'SELECT SCREENSHOT'
                      : 'SCREENSHOT SELECTED',
                ),
              ),
              if (draft.payload.sharedUrl case final url?) ...[
                const SizedBox(height: 10),
                Text(
                  url,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
        if (controller.message != null) ...[
          const SizedBox(height: 12),
          _ImportWarning(message: controller.message!),
        ],
        const SizedBox(height: 16),
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

  Future<void> _pickScreenshot() async {
    final result = await FilePicker.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: true,
    );
    final file = result == null || result.files.isEmpty
        ? null
        : result.files.single;
    final bytes = file?.bytes;
    if (file == null || bytes == null) return;
    if (bytes.lengthInBytes > 5 * 1024 * 1024) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('SCREENSHOT MUST BE 5 MB OR SMALLER')),
      );
      return;
    }
    await controller.addImage(
      ActivityShareImage(
        bytes: bytes,
        mimeType: _imageMimeType(file.extension),
        name: file.name,
      ),
    );
  }

  Future<void> _pickDate(ActivityImportDraft draft) async {
    final now = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: now,
      initialDate: controller.selectedDate ?? draft.startDateTime ?? now,
    );
    if (selected != null) controller.updateDate(selected);
  }

  Future<void> _pickTime(ActivityImportDraft draft) async {
    final currentHour = controller.selectedHour ?? draft.startDateTime?.hour;
    final currentMinute =
        controller.selectedMinute ?? draft.startDateTime?.minute;
    final selected = await showTimePicker(
      context: context,
      initialTime: currentHour == null || currentMinute == null
          ? TimeOfDay.now()
          : TimeOfDay(hour: currentHour, minute: currentMinute),
    );
    if (selected != null) controller.updateTime(selected.hour, selected.minute);
  }

  Future<void> _save() async {
    if (await controller.save() && mounted) widget.onClose();
  }

  Future<void> _decline() async {
    await controller.decline();
    if (mounted) widget.onClose();
  }
}

class _ImportWarning extends StatelessWidget {
  const _ImportWarning({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(11),
    decoration: BoxDecoration(
      color: OraColors.orange.withValues(alpha: 0.12),
      border: Border.all(color: OraColors.orange),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(message, textAlign: TextAlign.center),
  );
}

String _durationText(int? seconds) {
  if (seconds == null) return '';
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
    ? 'SELECT DATE'
    : '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';

String _timeText(int? hour, int? minute) => hour == null || minute == null
    ? 'START TIME'
    : '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

String _imageMimeType(String? extension) => switch (extension?.toLowerCase()) {
  'png' => 'image/png',
  'webp' => 'image/webp',
  'heic' || 'heif' => 'image/heic',
  _ => 'image/jpeg',
};
