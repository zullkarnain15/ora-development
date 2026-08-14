import 'package:flutter/material.dart';

import '../../../core/theme/ora_theme.dart';
import '../../../shared/widgets/ora_widgets.dart';
import '../domain/auth_validation.dart';

class ActivationScreen extends StatefulWidget {
  const ActivationScreen({
    super.key,
    required this.divisionGuild,
    required this.errorMessage,
    required this.isLoading,
    required this.onClearError,
    required this.onActivate,
  });

  final String divisionGuild;
  final String? errorMessage;
  final bool isLoading;
  final VoidCallback onClearError;
  final Future<void> Function(String nickname) onActivate;

  @override
  State<ActivationScreen> createState() => _ActivationScreenState();
}

class _ActivationScreenState extends State<ActivationScreen> {
  final _nicknameController = TextEditingController();

  @override
  void dispose() {
    _nicknameController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!widget.isLoading) widget.onActivate(_nicknameController.text);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 30),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: constraints.maxHeight - 60,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const OraIcon(
                        'you.png',
                        size: 64,
                        semanticLabel: 'Create your adventurer',
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'CREATE YOUR ADVENTURER',
                        textAlign: TextAlign.center,
                        style: OraTextStyles.displayLarge.copyWith(
                          color: OraColors.gold,
                        ),
                      ),
                      const SizedBox(height: 24),
                      OraCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: OraColors.panelAlt,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: OraColors.outline),
                              ),
                              child: Row(
                                children: [
                                  const OraIcon('guild.png', size: 30),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'GUILD',
                                          style: OraTextStyles.displaySmall
                                              .copyWith(
                                                color: OraColors.creamMuted,
                                              ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          widget.divisionGuild,
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleMedium,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            TextField(
                              key: const Key('activation_nickname'),
                              controller: _nicknameController,
                              enabled: !widget.isLoading,
                              maxLength: maxNicknameLength + 4,
                              textCapitalization: TextCapitalization.characters,
                              textInputAction: TextInputAction.done,
                              decoration: const InputDecoration(
                                labelText: 'Nickname',
                                helperText:
                                    'Up to 8 characters, letters and numbers',
                                counterText: '',
                              ),
                              onChanged: (_) => widget.onClearError(),
                              onSubmitted: (_) => _submit(),
                            ),
                            if (widget.errorMessage != null) ...[
                              const SizedBox(height: 12),
                              Semantics(
                                liveRegion: true,
                                child: Text(
                                  widget.errorMessage!,
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: OraColors.orange,
                                        fontWeight: FontWeight.w600,
                                      ),
                                ),
                              ),
                            ],
                            const SizedBox(height: 16),
                            SizedBox(
                              height: 60,
                              child: FilledButton(
                                key: const Key('activation_submit'),
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
                                          Text('ACTIVATING...'),
                                        ],
                                      )
                                    : const Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          OraIcon('success.png', size: 28),
                                          SizedBox(width: 10),
                                          Text('ACTIVATE ADVENTURER'),
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
          );
        },
      ),
    ),
  );
}
