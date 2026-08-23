import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/network/apps_script_client.dart';
import '../../../core/theme/ora_theme.dart';
import '../../../shared/widgets/ora_widgets.dart';
import '../../dashboard/application/feature_controller.dart';
import '../../dashboard/domain/feature_models.dart';
import '../domain/attendance_scan_gate.dart';

enum _ScannerPhase { scanning, submitting, result, error }

class AttendanceScannerScreen extends StatefulWidget {
  const AttendanceScannerScreen({
    super.key,
    required this.controller,
    this.cameraSupported,
  });

  final FeatureController controller;

  /// Test-only override. Production supports mobile native and secure web.
  final bool? cameraSupported;

  @override
  State<AttendanceScannerScreen> createState() =>
      _AttendanceScannerScreenState();
}

class _AttendanceScannerScreenState extends State<AttendanceScannerScreen> {
  final _scanGate = AttendanceScanGate();
  late final bool _cameraSupported;
  MobileScannerController? _cameraController;
  _ScannerPhase _phase = _ScannerPhase.scanning;
  AttendanceResult? _result;
  String? _errorCode;

  @override
  void initState() {
    super.initState();
    _cameraSupported =
        widget.cameraSupported ??
        supportsAttendanceQrCamera(
          isWeb: kIsWeb,
          platform: defaultTargetPlatform,
        );
    if (_cameraSupported) {
      _cameraController = MobileScannerController(
        formats: const [BarcodeFormat.qrCode],
      );
    }
  }

  @override
  void dispose() {
    final controller = _cameraController;
    if (controller != null) unawaited(controller.dispose());
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_phase != _ScannerPhase.scanning || capture.barcodes.isEmpty) return;
    final qrToken = capture.barcodes.first.rawValue?.trim() ?? '';
    if (!_scanGate.accept(qrToken)) return;
    final camera = _cameraController;
    if (camera != null) unawaited(camera.stop());
    setState(() => _phase = _ScannerPhase.submitting);
    unawaited(_submit(qrToken));
  }

  Future<void> _submit(String qrToken) async {
    try {
      final result = await widget.controller.submitAttendance(qrToken);
      if (!mounted) return;
      setState(() {
        _result = result;
        _phase = _ScannerPhase.result;
      });
    } on BackendFailure catch (error) {
      if (!mounted) return;
      setState(() {
        _errorCode = error.code;
        _phase = _ScannerPhase.error;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _errorCode = null;
        _phase = _ScannerPhase.error;
      });
    }
  }

  void _scanAgain() {
    _scanGate.reset();
    setState(() {
      _result = null;
      _errorCode = null;
      _phase = _ScannerPhase.scanning;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final controller = _cameraController;
      if (mounted && controller != null) unawaited(controller.start());
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('CHECK-IN'),
      backgroundColor: OraColors.forest,
    ),
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: switch (_phase) {
          _ScannerPhase.scanning => _scannerBody(context),
          _ScannerPhase.submitting => _submittingBody(),
          _ScannerPhase.result => _resultBody(context, _result!),
          _ScannerPhase.error => _errorBody(context, _errorCode),
        },
      ),
    ),
  );

  Widget _scannerBody(BuildContext context) {
    if (!_cameraSupported || _cameraController == null) {
      return _messageBody(
        context,
        icon: Icons.phonelink_erase_outlined,
        title: 'SCANNER NOT AVAILABLE',
        message: 'QR CHECK-IN REQUIRES A COMPATIBLE CAMERA BROWSER OR APP.',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const OraScreenTitle(
          title: 'SCAN CHECK-IN QR',
          subtitle: 'POINT YOUR CAMERA AT THE EVENT QR',
        ),
        const SizedBox(height: 20),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: MobileScanner(
              controller: _cameraController,
              onDetect: _onDetect,
              errorBuilder: (context, error) =>
                  _cameraErrorBody(context, error.errorCode),
              overlayBuilder: (context, constraints) => Center(
                child: Container(
                  width: constraints.maxWidth * .72,
                  height: constraints.maxWidth * .72,
                  decoration: BoxDecoration(
                    border: Border.all(color: OraColors.gold, width: 3),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'SCAN THE QR PROVIDED BY THE EVENT ORGANIZER.',
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _submittingBody() => const Center(
    child: OraStatusPanel(
      kind: OraPanelKind.loading,
      message: 'CHECKING IN...',
    ),
  );

  Widget _resultBody(BuildContext context, AttendanceResult result) {
    return switch (result.status) {
      AttendanceStatus.success => _successBody(context, result),
      AttendanceStatus.alreadyCheckedIn => _alreadyCheckedInBody(context),
      _ => _attendanceIssueBody(context, result.status),
    };
  }

  Widget _successBody(BuildContext context, AttendanceResult result) =>
      _messageBody(
        context,
        icon: Icons.emoji_events_outlined,
        title: 'CHECK-IN SUCCESS!',
        message: result.eventName?.isNotEmpty == true
            ? result.eventName!
            : 'EVENT CHECK-IN CONFIRMED.',
        details: [
          'BASE XP +${result.baseXp}',
          'STREAK ${result.streakCount}',
          'STREAK BONUS +${result.streakBonusXp}',
          'TOTAL +${result.totalXp} XP',
          'CURRENT XP ${result.currentXp}',
          'LEVEL ${result.currentLevel}',
        ],
        primaryLabel: 'DONE',
        onPrimary: () => Navigator.of(context).pop(),
      );

  Widget _alreadyCheckedInBody(BuildContext context) => _messageBody(
    context,
    icon: Icons.verified_outlined,
    title: 'ALREADY CHECKED IN',
    message: 'YOUR XP HAS NOT CHANGED.',
    primaryLabel: 'DONE',
    onPrimary: () => Navigator.of(context).pop(),
  );

  Widget _attendanceIssueBody(BuildContext context, AttendanceStatus status) {
    final copy = switch (status) {
      AttendanceStatus.invalidQr => ('INVALID QR', 'THIS QR IS NOT VALID.'),
      AttendanceStatus.eventInactive => (
        'EVENT INACTIVE',
        'THIS EVENT IS NOT ACTIVE.',
      ),
      AttendanceStatus.eventNotStarted => (
        'EVENT NOT STARTED',
        'CHECK-IN IS NOT OPEN YET.',
      ),
      AttendanceStatus.eventClosed => (
        'EVENT CLOSED',
        'CHECK-IN FOR THIS EVENT HAS ENDED.',
      ),
      AttendanceStatus.attendanceDisabled => (
        'CHECK-IN UNAVAILABLE',
        'ATTENDANCE IS DISABLED.',
      ),
      AttendanceStatus.attendanceQrDisabled => (
        'CHECK-IN UNAVAILABLE',
        'QR CHECK-IN IS DISABLED.',
      ),
      AttendanceStatus.configurationError => (
        'CHECK-IN UNAVAILABLE',
        'EVENT CONFIGURATION NEEDS ADMIN REVIEW.',
      ),
      AttendanceStatus.unauthorized => (
        'SESSION EXPIRED',
        'PLEASE LOGIN AGAIN.',
      ),
      _ => ('CHECK-IN FAILED', 'PLEASE TRY AGAIN.'),
    };
    final canRetry =
        status != AttendanceStatus.attendanceDisabled &&
        status != AttendanceStatus.attendanceQrDisabled &&
        status != AttendanceStatus.configurationError &&
        status != AttendanceStatus.unauthorized;
    return _messageBody(
      context,
      icon: Icons.warning_amber_rounded,
      title: copy.$1,
      message: copy.$2,
      primaryLabel: canRetry ? 'SCAN AGAIN' : 'DONE',
      onPrimary: canRetry ? _scanAgain : () => Navigator.of(context).pop(),
    );
  }

  Widget _errorBody(BuildContext context, String? code) {
    final status = attendanceStatusFromApi(code ?? '');
    if (status != AttendanceStatus.unknown) {
      return _attendanceIssueBody(context, status);
    }
    return _messageBody(
      context,
      icon: Icons.cloud_off_outlined,
      title: 'CHECK-IN FAILED',
      message: 'PLEASE CHECK YOUR CONNECTION AND SCAN AGAIN.',
      primaryLabel: 'SCAN AGAIN',
      onPrimary: _scanAgain,
    );
  }

  Widget _cameraErrorBody(BuildContext context, MobileScannerErrorCode code) =>
      _messageBody(
        context,
        icon: code == MobileScannerErrorCode.permissionDenied
            ? Icons.no_photography_outlined
            : Icons.videocam_off_outlined,
        title: code == MobileScannerErrorCode.permissionDenied
            ? 'CAMERA ACCESS NEEDED'
            : 'CAMERA UNAVAILABLE',
        message: code == MobileScannerErrorCode.permissionDenied
            ? 'ALLOW CAMERA ACCESS IN DEVICE SETTINGS, THEN TRY AGAIN.'
            : 'THIS DEVICE CANNOT OPEN THE QR CAMERA.',
        primaryLabel: 'TRY AGAIN',
        onPrimary: _scanAgain,
      );

  Widget _messageBody(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String message,
    List<String> details = const [],
    String? primaryLabel,
    VoidCallback? onPrimary,
  }) => Center(
    child: SingleChildScrollView(
      child: OraCard(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(icon, size: 44, color: OraColors.gold),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: OraTextStyles.displayMedium.copyWith(
                color: OraColors.gold,
              ),
            ),
            const SizedBox(height: 14),
            Text(message, textAlign: TextAlign.center),
            for (final detail in details) ...[
              const SizedBox(height: 8),
              Text(
                detail,
                textAlign: TextAlign.center,
                style: OraTextStyles.displaySmall.copyWith(
                  color: OraColors.creamMuted,
                ),
              ),
            ],
            if (primaryLabel != null && onPrimary != null) ...[
              const SizedBox(height: 20),
              FilledButton(onPressed: onPrimary, child: Text(primaryLabel)),
            ],
          ],
        ),
      ),
    ),
  );
}
