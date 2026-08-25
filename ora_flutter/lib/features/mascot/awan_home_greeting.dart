import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/theme/ora_theme.dart';
import 'awan_mascot_slot.dart';
import 'awan_mascot_state.dart';

class AwanHomeGreeting extends StatefulWidget {
  const AwanHomeGreeting({super.key});

  @override
  State<AwanHomeGreeting> createState() => _AwanHomeGreetingState();
}

class _AwanHomeGreetingState extends State<AwanHomeGreeting> {
  static const _messages = [
    'HALO, SAYA AWAN,\nSANG MASKOT!',
    'SELAMAT DATANG DI\nOTO RUNNERS ADVENTURE!',
  ];

  Timer? _timer;
  var _messageIndex = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (mounted) {
        setState(() => _messageIndex = (_messageIndex + 1) % _messages.length);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < 340;
      final bubble = _AwanBubble(message: _messages[_messageIndex]);
      const mascot = AwanMascotSlot(
        state: AwanMascotState.cheer,
        minSize: 40,
        maxSize: 50,
      );
      if (compact) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [bubble, const SizedBox(height: 2), mascot],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(child: bubble),
          mascot,
        ],
      );
    },
  );
}

class _AwanBubble extends StatelessWidget {
  const _AwanBubble({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: const _RpgBubblePainter(),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 230),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 18, 22),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.96, end: 1).animate(animation),
              child: child,
            ),
          ),
          child: Text(
            message,
            key: ValueKey(message),
            style: const TextStyle(
              fontFamily: 'PressStart2P',
              fontSize: 7,
              height: 1.6,
              color: OraColors.forestDeep,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    ),
  );
}

class _RpgBubblePainter extends CustomPainter {
  const _RpgBubblePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final right = size.width - 2;
    final bottom = size.height - 13;
    final path = Path()
      ..moveTo(10, 1)
      ..lineTo(right - 10, 1)
      ..lineTo(right - 10, 4)
      ..lineTo(right - 4, 4)
      ..lineTo(right - 4, 10)
      ..lineTo(right, 10)
      ..lineTo(right, bottom - 10)
      ..lineTo(right - 4, bottom - 10)
      ..lineTo(right - 4, bottom - 4)
      ..lineTo(right - 10, bottom - 4)
      ..lineTo(right - 28, bottom - 4)
      ..lineTo(right - 28, bottom + 5)
      ..lineTo(right - 16, bottom + 5)
      ..lineTo(right - 16, bottom + 11)
      ..lineTo(right - 34, bottom + 11)
      ..lineTo(right - 34, bottom + 5)
      ..lineTo(right - 40, bottom + 5)
      ..lineTo(right - 40, bottom - 4)
      ..lineTo(10, bottom - 4)
      ..lineTo(10, bottom)
      ..lineTo(4, bottom)
      ..lineTo(4, bottom - 6)
      ..lineTo(1, bottom - 6)
      ..lineTo(1, 10)
      ..lineTo(4, 10)
      ..lineTo(4, 4)
      ..lineTo(10, 4)
      ..close();

    final shadowPaint = Paint()
      ..color = OraColors.forestDeep
      ..isAntiAlias = false;
    final fillPaint = Paint()
      ..color = OraColors.cream
      ..isAntiAlias = false;
    canvas.drawPath(path.shift(const Offset(3, 3)), shadowPaint);
    canvas.drawPath(path, fillPaint);
    final borderPaint = Paint()
      ..color = OraColors.forestDeep
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeJoin = StrokeJoin.miter
      ..isAntiAlias = false;
    canvas.drawPath(path, borderPaint);
  }

  @override
  bool shouldRepaint(covariant _RpgBubblePainter oldDelegate) => false;
}
