import 'package:flutter/material.dart';

import '../../core/theme/ora_theme.dart';

class OraIcon extends StatelessWidget {
  const OraIcon(
    this.assetName, {
    super.key,
    this.size = 28,
    this.semanticLabel,
  });
  final String assetName;
  final double size;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) => Image.asset(
    'assets/images/$assetName',
    width: size,
    height: size,
    fit: BoxFit.contain,
    semanticLabel: semanticLabel,
    excludeFromSemantics: semanticLabel == null,
    filterQuality: FilterQuality.medium,
  );
}

class OraCard extends StatelessWidget {
  const OraCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.gradient,
    this.borderColor,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Gradient? gradient;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: gradient == null ? OraColors.panel : null,
      gradient: gradient,
      borderRadius: BorderRadius.circular(5),
      border: Border.all(color: borderColor ?? OraColors.outline, width: 1.5),
    ),
    child: child,
  );
}

class OraScreenTitle extends StatelessWidget {
  const OraScreenTitle({
    super.key,
    required this.title,
    this.subtitle,
    this.assetName,
  });
  final String title;
  final String? subtitle;
  final String? assetName;

  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (assetName != null) ...[
          OraIcon(assetName!, size: 38),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: OraTextStyles.displayMedium.copyWith(
                  color: OraColors.gold,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 6),
                Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
              ],
            ],
          ),
        ),
      ],
    ),
  );
}

class PixelBadge extends StatelessWidget {
  const PixelBadge({super.key, required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: OraColors.panelAlt,
      borderRadius: BorderRadius.circular(3),
      border: Border.all(color: OraColors.gold),
    ),
    child: FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: OraTextStyles.displaySmall,
      ),
    ),
  );
}

class OraStatLine extends StatelessWidget {
  const OraStatLine({
    super.key,
    required this.label,
    required this.value,
    this.assetName,
    this.valueStyle,
    this.valuePadding,
    this.valueDecoration,
  });
  final String label;
  final String value;
  final String? assetName;
  final TextStyle? valueStyle;
  final EdgeInsetsGeometry? valuePadding;
  final Decoration? valueDecoration;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      if (assetName != null) ...[
        OraIcon(assetName!, size: 24),
        const SizedBox(width: 10),
      ],
      Expanded(
        child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
      ),
      Container(
        padding: valuePadding,
        decoration: valueDecoration,
        child: Text(
          value,
          style:
              valueStyle ??
              OraTextStyles.displaySmall.copyWith(color: OraColors.gold),
        ),
      ),
    ],
  );
}

enum OraPanelKind { loading, error, empty }

class OraStatusPanel extends StatelessWidget {
  const OraStatusPanel({
    super.key,
    required this.kind,
    required this.message,
    this.onRetry,
  });
  final OraPanelKind kind;
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final icon = switch (kind) {
      OraPanelKind.loading => 'adventure.png',
      OraPanelKind.error => 'warning.png',
      OraPanelKind.empty => 'quest.png',
    };
    return OraCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (kind == OraPanelKind.loading)
            const CircularProgressIndicator(color: OraColors.gold)
          else if (kind == OraPanelKind.empty)
            Image.asset(
              'assets/mascot/awan/navy_awan_static.png',
              width: 74,
              height: 74,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.none,
            )
          else
            OraIcon(icon, size: 34),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          if (onRetry != null) ...[
            const SizedBox(height: 10),
            TextButton(onPressed: onRetry, child: const Text('TRY AGAIN')),
          ],
        ],
      ),
    );
  }
}
