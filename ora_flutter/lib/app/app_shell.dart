import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme/ora_theme.dart';
import '../core/network/network_reachability_monitor.dart';
import '../features/auth/application/auth_controller.dart';
import '../features/auth/domain/auth_models.dart';
import '../features/auth/domain/auth_validation.dart';
import '../features/activity_import/activity_import_config.dart';
import '../features/activity_import/application/activity_import_controller.dart';
import '../features/activity_import/application/activity_import_inbox.dart';
import '../features/activity_import/data/activity_import_bridge_api.dart';
import '../features/activity_import/presentation/activity_import_screen.dart';
import '../core/network/apps_script_client.dart';
import '../features/dashboard/application/feature_controller.dart';
import '../features/dashboard/presentation/guild_screen.dart';
import '../features/dashboard/presentation/home_screen.dart';
import '../features/dashboard/presentation/profile_screen.dart';
import '../features/dashboard/presentation/quest_screen.dart';
import '../features/tracking/application/tracking_controller.dart';
import '../features/tracking/domain/tracking_models.dart';
import '../features/tracking/presentation/run_screen.dart';
import '../shared/widgets/ora_widgets.dart';

enum OraDestination { home, quest, run, guild, you }

extension on OraDestination {
  String get label => switch (this) {
    OraDestination.home => 'Home',
    OraDestination.quest => 'Quest',
    OraDestination.run => 'RUN',
    OraDestination.guild => 'Guild',
    OraDestination.you => 'You',
  };
  String get icon => switch (this) {
    OraDestination.home => 'home.png',
    OraDestination.quest => 'quest.png',
    OraDestination.run => 'run.png',
    OraDestination.guild => 'guild.png',
    OraDestination.you => 'you.png',
  };
}

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.session,
    required this.authController,
    required this.featureControllerFactory,
    this.importInbox,
    this.importBridgeApi,
  });
  final UserSession session;
  final AuthController authController;
  final FeatureControllerFactory featureControllerFactory;
  final ActivityImportInbox? importInbox;
  final ActivityImportBridgeApi? importBridgeApi;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  OraDestination destination = OraDestination.home;
  bool showSettings = false;
  bool showImport = false;
  late FeatureController featureController;
  late TrackingController trackingController;
  DateTime? _lastBackPressedAt;
  late final NetworkReachabilityMonitor _reachabilityMonitor;
  late final ActivityImportInbox _importInbox;
  late final ActivityImportBridgeApi _importBridgeApi;
  late final bool _ownsImportInbox;
  ActivityImportController? _importController;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    featureController = widget.featureControllerFactory(widget.session);
    _ownsImportInbox = widget.importInbox == null;
    _importInbox = widget.importInbox ?? ActivityImportInbox();
    _importBridgeApi =
        widget.importBridgeApi ??
        AppsScriptActivityImportBridgeApi(AppsScriptClient());
    _importInbox.addListener(_onImportInboxChanged);
    if (_ownsImportInbox) unawaited(_importInbox.initialize());
    _reachabilityMonitor = NetworkReachabilityMonitor(
      onRestored: () => featureController.syncPending(manual: false),
    )..start();
    trackingController = _createTrackingController();
    unawaited(featureController.loadHome());
    unawaited(featureController.syncPending(manual: false));
    unawaited(trackingController.initialize());
    _onImportInboxChanged();
  }

  @override
  void didUpdateWidget(covariant AppShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session.nik != widget.session.nik) {
      featureController.dispose();
      trackingController.dispose();
      featureController = widget.featureControllerFactory(widget.session);
      trackingController = _createTrackingController();
      final launch = _importInbox.current;
      if (launch != null) _openImport(launch);
      unawaited(featureController.loadHome());
      unawaited(featureController.syncPending(manual: false));
      unawaited(trackingController.initialize());
    } else if (oldWidget.session.sessionToken != widget.session.sessionToken ||
        oldWidget.session.nickname != widget.session.nickname ||
        oldWidget.session.divisionGuild != widget.session.divisionGuild) {
      featureController.updateSession(widget.session);
      trackingController.updateUser(widget.session);
      unawaited(featureController.loadHome(force: true));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _reachabilityMonitor.stop();
    _importInbox.removeListener(_onImportInboxChanged);
    if (_ownsImportInbox) _importInbox.dispose();
    _importController?.dispose();
    featureController.dispose();
    trackingController.dispose();
    super.dispose();
  }

  void _onImportInboxChanged() {
    final launch = _importInbox.current;
    if (launch == null || showImport || !_importAvailable) return;
    _openImport(launch);
  }

  bool get _importAvailable =>
      ActivityImportConfig.enabled &&
      (!kIsWeb || ActivityImportConfig.webEnabled);

  void _openImport(ActivityImportLaunch launch) {
    _importController?.dispose();
    final controller = ActivityImportController(
      launch: launch,
      inbox: _importInbox,
      bridgeApi: _importBridgeApi,
      featureController: featureController,
    );
    _importController = controller;
    if (mounted) setState(() => showImport = true);
    unawaited(controller.initialize());
  }

  void _closeImport() {
    if (!mounted) return;
    setState(() => showImport = false);
    _importController?.dispose();
    _importController = null;
  }

  TrackingController _createTrackingController() => TrackingController(
    user: widget.session,
    store: featureController.activityStore,
    onActivitySaved: () {
      unawaited(featureController.loadActivities(force: true));
      unawaited(featureController.loadStats(force: true));
      unawaited(featureController.syncPending(manual: false));
    },
  );

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _reachabilityMonitor.start();
      unawaited(featureController.syncPending(manual: false));
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _reachabilityMonitor.stop();
    }
  }

  Future<void> _requestLogout() async {
    if (!trackingController.hasActiveSession) {
      if (mounted) setState(() => showSettings = false);
      await widget.authController.logout();
      return;
    }
    final shouldFinish = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ACTIVE ADVENTURE'),
        content: const Text(
          'Your run belongs to this account. Finish and save it before logging out.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('KEEP RUNNING'),
          ),
          FilledButton(
            key: const Key('finish_and_logout'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('FINISH & LOGOUT'),
          ),
        ],
      ),
    );
    if (shouldFinish != true) return;
    if (trackingController.status == TrackingStatus.recoverableSession) {
      await trackingController.endRecoveredAndSave();
    } else {
      await trackingController.finish();
    }
    if (trackingController.status != TrackingStatus.finished) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ADVENTURE COULD NOT BE SAVED')),
      );
      return;
    }
    if (mounted) setState(() => showSettings = false);
    await widget.authController.logout();
  }

  void _selectDestination(int index) {
    final selected = OraDestination.values[index];
    _lastBackPressedAt = null;
    trackingController.setRunVisible(selected == OraDestination.run);
    setState(() => destination = selected);
    switch (selected) {
      case OraDestination.home:
        unawaited(featureController.loadHome());
      case OraDestination.quest:
        unawaited(featureController.loadQuests());
      case OraDestination.run:
        break;
      case OraDestination.guild:
        unawaited(featureController.loadGuild());
        unawaited(featureController.loadLeaderboard());
      case OraDestination.you:
        unawaited(featureController.loadHome());
    }
  }

  void _handleBack() {
    if (showImport) {
      final controller = _importController;
      if (controller?.phase == ActivityImportPhase.saved) {
        unawaited(controller?.finish());
      } else {
        unawaited(controller?.decline());
      }
      _closeImport();
      return;
    }
    if (showSettings) {
      _lastBackPressedAt = null;
      setState(() => showSettings = false);
      return;
    }
    if (destination != OraDestination.home) {
      _lastBackPressedAt = null;
      trackingController.setRunVisible(false);
      setState(() => destination = OraDestination.home);
      unawaited(featureController.loadHome());
      return;
    }
    final now = DateTime.now();
    if (_lastBackPressedAt == null ||
        now.difference(_lastBackPressedAt!) > const Duration(seconds: 2)) {
      _lastBackPressedAt = now;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 2),
            content: Text(
              trackingController.hasActiveSession
                  ? 'PRESS BACK AGAIN TO EXIT • TRACKING CONTINUES'
                  : 'PRESS BACK AGAIN TO EXIT',
            ),
          ),
        );
      return;
    }
    SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final screens = <Widget>[
      HomeScreen(controller: featureController),
      QuestScreen(controller: featureController),
      RunScreen(controller: trackingController),
      GuildScreen(controller: featureController),
      ProfileScreen(
        controller: featureController,
        onSettings: () => setState(() => showSettings = true),
      ),
    ];
    final shell = Scaffold(
      body: IndexedStack(index: destination.index, children: screens),
      bottomNavigationBar: NavigationBar(
        backgroundColor: OraColors.forest,
        indicatorColor: OraColors.panelAlt,
        selectedIndex: destination.index,
        onDestinationSelected: _selectDestination,
        destinations: OraDestination.values.map((item) {
          final isRun = item == OraDestination.run;
          return NavigationDestination(
            key: Key('nav_${item.name}'),
            icon: OraIcon(item.icon, size: isRun ? 36 : 27),
            selectedIcon: Container(
              padding: EdgeInsets.all(isRun ? 7 : 4),
              decoration: BoxDecoration(
                color: isRun
                    ? OraColors.gold.withValues(alpha: 0.18)
                    : OraColors.panelAlt,
                borderRadius: BorderRadius.circular(isRun ? 18 : 7),
                border: isRun ? Border.all(color: OraColors.gold) : null,
              ),
              child: OraIcon(item.icon, size: isRun ? 38 : 27),
            ),
            label: item.label,
          );
        }).toList(),
      ),
    );
    return PopScope<Object?>(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _handleBack();
      },
      child: Navigator(
        pages: [
          MaterialPage<void>(key: const ValueKey('ora_shell'), child: shell),
          if (showSettings)
            MaterialPage<void>(
              key: const ValueKey('ora_settings'),
              name: '/settings',
              child: SettingsScreen(
                session: widget.session,
                authController: widget.authController,
                onLogout: _requestLogout,
              ),
            ),
          if (showImport && _importController != null)
            MaterialPage<void>(
              key: const ValueKey('ora_import'),
              name: '/import',
              child: ActivityImportScreen(
                controller: _importController!,
                onClose: _closeImport,
              ),
            ),
        ],
        onDidRemovePage: (page) {
          if (page.key == const ValueKey('ora_settings') && showSettings) {
            setState(() => showSettings = false);
          } else if (page.key == const ValueKey('ora_import') && showImport) {
            _closeImport();
          }
        },
      ),
    );
  }
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    required this.session,
    required this.authController,
    required this.onLogout,
  });
  final UserSession session;
  final AuthController authController;
  final Future<void> Function() onLogout;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('SETTINGS'),
      backgroundColor: OraColors.forest,
    ),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const OraScreenTitle(
            title: 'SETTINGS',
            subtitle: 'ORA - OTO RUNNERS ADVENTURE',
            assetName: 'settings.png',
          ),
          const SizedBox(height: 18),
          _settingsCard('ACCOUNT', 'you.png', [
            Row(
              children: [
                const Expanded(child: Text('NICKNAME')),
                Text(
                  session.nickname,
                  style: OraTextStyles.displaySmall.copyWith(
                    color: OraColors.gold,
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  key: const Key('edit_nickname'),
                  onPressed: () => _editNickname(context),
                  tooltip: 'Edit nickname',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.edit, color: OraColors.gold),
                ),
              ],
            ),
            OraStatLine(
              label: 'DIVISION / GUILD',
              value: session.divisionGuild,
            ),
            OraStatLine(label: 'ACCOUNT STATUS', value: session.status),
          ]),
          const SizedBox(height: 14),
          FilledButton.icon(
            key: const Key('logout_button'),
            onPressed: onLogout,
            icon: const Icon(Icons.logout),
            label: const Text('LOGOUT'),
          ),
          const SizedBox(height: 14),
          _settingsCard('RUN SETTINGS', 'location.png', const [
            OraStatLine(
              label: 'LOCATION / GPS',
              value: 'REQUIRED WHILE RUNNING',
            ),
            OraStatLine(label: 'TRACKING', value: 'OFFLINE + RECOVERY'),
          ]),
          const SizedBox(height: 14),
          _settingsCard('DATA & SAFETY', 'lock.png', const [
            OraStatLine(label: 'SESSION', value: 'SECURE ON THIS DEVICE'),
            OraStatLine(label: 'ACTIVITY LOG', value: 'OWNER ISOLATED'),
            OraStatLine(label: 'BACKEND', value: 'ORA LIVE DATA'),
          ]),
          const SizedBox(height: 14),
          _settingsCard('ABOUT', 'adventure.png', const [
            OraStatLine(label: 'ORA', value: 'OTO RUNNERS ADVENTURE'),
            OraStatLine(label: 'PROGRAM', value: 'RUN PLAYING GAME'),
            OraStatLine(label: 'VERSION', value: '1.0.0'),
          ]),
        ],
      ),
    ),
  );

  Widget _settingsCard(String title, String icon, List<Widget> values) =>
      OraCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OraScreenTitle(title: title, assetName: icon),
            const SizedBox(height: 14),
            for (var index = 0; index < values.length; index++) ...[
              values[index],
              if (index != values.length - 1) const SizedBox(height: 11),
            ],
          ],
        ),
      );

  Future<void> _editNickname(BuildContext context) async {
    final input = TextEditingController(text: session.nickname);
    var saving = false;
    String? error;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('EDIT NICKNAME'),
          content: TextField(
            key: const Key('nickname_edit_input'),
            controller: input,
            enabled: !saving,
            autofocus: true,
            maxLength: 8,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              labelText: 'NICKNAME',
              errorText: error,
              helperText: 'UP TO 8 LETTERS OR NUMBERS',
            ),
            onSubmitted: saving
                ? null
                : (_) => _saveNickname(
                    dialogContext,
                    input,
                    setDialogState,
                    (value) => error = value,
                    (value) => saving = value,
                  ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(dialogContext),
              child: const Text('CANCEL'),
            ),
            FilledButton(
              key: const Key('nickname_edit_save'),
              onPressed: saving
                  ? null
                  : () => _saveNickname(
                      dialogContext,
                      input,
                      setDialogState,
                      (value) => error = value,
                      (value) => saving = value,
                    ),
              child: saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('SAVE'),
            ),
          ],
        ),
      ),
    );
    input.dispose();
  }

  Future<void> _saveNickname(
    BuildContext dialogContext,
    TextEditingController input,
    StateSetter setDialogState,
    ValueChanged<String?> setError,
    ValueChanged<bool> setSaving,
  ) async {
    final validation = nicknameValidationError(input.text);
    if (validation != null) {
      setDialogState(() => setError(validation));
      return;
    }
    if (canonicalNickname(input.text) == session.nickname.toUpperCase()) {
      Navigator.pop(dialogContext);
      return;
    }
    setDialogState(() {
      setError(null);
      setSaving(true);
    });
    final saved = await authController.updateNickname(input.text);
    if (!dialogContext.mounted) return;
    if (saved) {
      Navigator.pop(dialogContext);
    } else {
      setDialogState(() {
        setSaving(false);
        setError(authController.nicknameUpdateError ?? 'UPDATE FAILED');
      });
    }
  }
}
