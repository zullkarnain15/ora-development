import 'package:flutter/material.dart';

import 'awan_mascot.dart';
import 'awan_mascot_controller.dart';
import 'awan_mascot_state.dart';

/// A responsive, non-intrusive placement wrapper for the Awan mascot.
class AwanMascotSlot extends StatelessWidget {
  const AwanMascotSlot({
    super.key,
    this.controller,
    this.state = AwanMascotState.idle,
    this.minSize = 56,
    this.maxSize = 84,
    this.hiddenBelow = 280,
    this.alignment = Alignment.centerRight,
    this.semanticLabel = 'Awan',
  });

  final AwanMascotController? controller;
  final AwanMascotState state;
  final double minSize;
  final double maxSize;
  final double hiddenBelow;
  final AlignmentGeometry alignment;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    if (screenWidth < hiddenBelow) return const SizedBox.shrink();
    final size = (screenWidth * 0.22).clamp(minSize, maxSize).toDouble();
    return Align(
      alignment: alignment,
      child: AwanMascot(
        controller: controller,
        state: state,
        size: size,
        semanticLabel: semanticLabel,
      ),
    );
  }
}
