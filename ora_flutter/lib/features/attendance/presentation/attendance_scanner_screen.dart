import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/network/apps_script_client.dart';
import '../../../core/theme/ora_theme.dart';
import '../../mascot/awan_mascot.dart';
import '../../mascot/awan_mascot_state.dart';
import '../../../shared/widgets/ora_widgets.dart';
import '../data/attendance_camera_cleanup.dart';
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

class _AttendanceScannerScreenState extends State<AttendanceScannerScreen>
    with WidgetsBindingObserver {
  final _scanGate = AttendanceScanGate();
  late final bool _cameraSupported;
  MobileScannerController? _cameraController;
  _ScannerPhase _phase = _ScannerPhase.scanning;
  AttendanceResult? _result;
  String? _errorCode;
  bool _isClosing = false;
  bool _canPop = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
    WidgetsBinding.instance.removeObserver(this);
    final controller = _cameraController;
    if (controller != null) unawaited(_stopAndDisposeCamera(controller));
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
        unawaited(_stopCamera());
      case AppLifecycleState.resumed:
        if (_phase == _ScannerPhase.scanning && !_isClosing) {
          final controller = _cameraController;
          if (controller != null) unawaited(controller.start());
        }
    }
  }

  Future<void> _stopCamera() async {
    final controller = _cameraController;
    if (controller != null) {
      try {
        await controller.stop();
      } on Object {
        // The scanner error UI handles unavailable cameras; cleanup stays safe.
      }
    }
    releaseAttendanceBrowserCamera();
  }

  Future<void> _stopAndDisposeCamera(MobileScannerController controller) async {
    try {
      await controller.stop();
    } on Object {
      // Disposal below still releases any remaining platform resources.
    }
    releaseAttendanceBrowserCamera();
    try {
      await controller.dispose();
    } on Object {
      // The child scanner may have disposed the shared controller first.
    }
  }

  Future<void> _closeScanner() async {
    if (_isClosing) return;
    _isClosing = true;
    await _stopCamera();
    if (!mounted) return;
    setState(() => _canPop = true);
    Navigator.of(context).pop();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_phase != _ScannerPhase.scanning || capture.barcodes.isEmpty) return;
    final qrToken = capture.barcodes.first.rawValue?.trim() ?? '';
    if (!_scanGate.accept(qrToken)) return;
    // On web, stopping the decoder alone can leave the browser camera track
    // active. Release the complete stream as soon as the payload is accepted.
    unawaited(_stopCamera());
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
  Widget build(BuildContext context) => PopScope<void>(
    canPop: _canPop,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) unawaited(_closeScanner());
    },
    child: Scaffold(
      appBar: AppBar(
        title: const Text('ADVENTURE STAMP'),
        backgroundColor: OraColors.forest,
        leading: IconButton(
          key: const Key('attendance_scanner_close'),
          icon: const Icon(Icons.close),
          tooltip: 'Close scanner',
          onPressed: _closeScanner,
        ),
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
    ),
  );

  Widget _scannerBody(BuildContext context) {
    if (!_cameraSupported || _cameraController == null) {
      return _messageBody(
        context,
        icon: Icons.phonelink_erase_outlined,
        title: 'SCANNER NOT AVAILABLE',
        message:
            'QR ADVENTURE STAMP REQUIRES A COMPATIBLE CAMERA BROWSER OR APP.',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const OraScreenTitle(
          title: 'SCAN ADVENTURE STAMP QR',
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
        illustration: const AwanMascot(
          state: AwanMascotState.success,
          size: 90,
          loop: false,
          returnToIdle: false,
          semanticLabel: 'Awan merayakan pencapaian',
        ),
        title: 'STAMP CLAIMED!',
        message: result.eventName?.isNotEmpty == true
            ? result.eventName!
            : 'EVENT STAMP CONFIRMED.',
        details: [
          'BASE XP +${result.baseXp}',
          'STREAK ${result.streakCount}',
          'STREAK BONUS +${result.streakBonusXp}',
          'TOTAL +${result.totalXp} XP',
          'CURRENT XP ${result.currentXp}',
          'LEVEL ${result.currentLevel}',
        ],
        primaryLabel: 'DONE',
        onPrimary: _closeScanner,
      );

  Widget _alreadyCheckedInBody(BuildContext context) => _messageBody(
    context,
    icon: Icons.verified_outlined,
    title: 'ALREADY CHECKED IN',
    message: 'YOUR XP HAS NOT CHANGED.',
    primaryLabel: 'DONE',
    onPrimary: _closeScanner,
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
        'ADVENTURE STAMP IS NOT OPEN YET.',
      ),
      AttendanceStatus.eventClosed => (
        'EVENT CLOSED',
        'ADVENTURE STAMP FOR THIS EVENT HAS ENDED.',
      ),
      AttendanceStatus.attendanceDisabled => (
        'ADVENTURE STAMP UNAVAILABLE',
        'ATTENDANCE IS DISABLED.',
      ),
      AttendanceStatus.attendanceQrDisabled => (
        'ADVENTURE STAMP UNAVAILABLE',
        'QR ADVENTURE STAMP IS DISABLED.',
      ),
      AttendanceStatus.configurationError => (
        'ADVENTURE STAMP UNAVAILABLE',
        'EVENT CONFIGURATION NEEDS ADMIN REVIEW.',
      ),
      AttendanceStatus.unauthorized => (
        'SESSION EXPIRED',
        'PLEASE LOGIN AGAIN.',
      ),
      _ => ('ADVENTURE STAMP FAILED', 'PLEASE TRY AGAIN.'),
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
      onPrimary: canRetry ? _scanAgain : _closeScanner,
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
      title: 'ADVENTURE STAMP FAILED',
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
    Widget? illustration,
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
            illustration ?? Icon(icon, size: 44, color: OraColors.gold),
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
