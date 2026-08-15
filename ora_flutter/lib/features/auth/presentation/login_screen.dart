import 'package:flutter/material.dart';

import '../../../core/theme/ora_theme.dart';
import '../../../shared/widgets/ora_widgets.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    required this.errorMessage,
    required this.isLoading,
    required this.onClearError,
    required this.onLogin,
  });

  final String? errorMessage;
  final bool isLoading;
  final VoidCallback onClearError;
  final Future<void> Function(String nik, String pin) onLogin;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _nikController = TextEditingController();
  final _pinController = TextEditingController();
  final _pinFocus = FocusNode();

  @override
  void dispose() {
    _nikController.dispose();
    _pinController.dispose();
    _pinFocus.dispose();
    super.dispose();
  }

  void _submit() {
    if (!widget.isLoading) {
      widget.onLogin(_nikController.text, _pinController.text);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final horizontalPadding = constraints.maxWidth < 400 ? 16.0 : 24.0;
          return SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: horizontalPadding,
              vertical: 30,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: constraints.maxHeight - 60,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: AutofillGroup(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const OraIcon(
                          'run.png',
                          size: 68,
                          semanticLabel: 'OTO Runners Adventure',
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'ORA',
                          style: OraTextStyles.displayLarge.copyWith(
                            color: OraColors.gold,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'OTO RUNNERS ADVENTURE',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(color: OraColors.creamMuted),
                        ),
                        const SizedBox(height: 14),
                        const PixelBadge(text: 'RPG - RUN PLAYING GAME'),
                        const SizedBox(height: 26),
                        OraCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  const OraIcon('lock.png', size: 26),
                                  const SizedBox(width: 8),
                                  Text(
                                    'ENTER ORA',
                                    style: OraTextStyles.displayMedium.copyWith(
                                      color: OraColors.gold,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              TextField(
                                key: const Key('login_nik'),
                                controller: _nikController,
                                enabled: !widget.isLoading,
                                maxLength: 24,
                                decoration: const InputDecoration(
                                  labelText: 'NIK',
                                  counterText: '',
                                ),
                                keyboardType: TextInputType.number,
                                textInputAction: TextInputAction.next,
                                autofillHints: const [AutofillHints.username],
                                onChanged: (_) => widget.onClearError(),
                                onSubmitted: (_) => _pinFocus.requestFocus(),
                              ),
                              const SizedBox(height: 14),
                              TextField(
                                key: const Key('login_pin'),
                                controller: _pinController,
                                focusNode: _pinFocus,
                                enabled: !widget.isLoading,
                                maxLength: 8,
                                obscureText: true,
                                decoration: const InputDecoration(
                                  labelText: 'PIN',
                                  counterText: '',
                                ),
                                keyboardType: TextInputType.number,
                                textInputAction: TextInputAction.done,
                                autofillHints: const [AutofillHints.password],
                                onChanged: (_) => widget.onClearError(),
                                onSubmitted: (_) => _submit(),
                              ),
                              if (widget.errorMessage != null) ...[
                                const SizedBox(height: 12),
                                _AuthError(widget.errorMessage!),
                              ],
                              const SizedBox(height: 16),
                              SizedBox(
                                height: 60,
                                child: FilledButton(
                                  key: const Key('login_submit'),
                                  onPressed: widget.isLoading ? null : _submit,
                                  style: FilledButton.styleFrom(
                                    backgroundColor: OraColors.gold,
                                    foregroundColor: OraColors.forestDeep,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                  ),
                                  child: widget.isLoading
                                      ? const Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            SizedBox.square(
                                              dimension: 24,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 3,
                                              ),
                                            ),
                                            SizedBox(width: 10),
                                            Text('CONNECTING...'),
                                          ],
                                        )
                                      : const Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            OraIcon('run.png', size: 28),
                                            SizedBox(width: 10),
                                            Text('ENTER ADVENTURE'),
                                          ],
                                        ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    ),
  );
}

class _AuthError extends StatelessWidget {
  const _AuthError(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const OraIcon('warning.png', size: 22),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: OraColors.orange,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );
}
