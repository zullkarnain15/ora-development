import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/ora_theme.dart';
import '../../../shared/widgets/ora_widgets.dart';
import '../data/activity_store.dart';
import '../domain/activity_sync.dart';
import '../domain/final_activity.dart';

abstract final class ActivityRouteProjector {
  static List<Offset> project(
    List<ActivityRoutePoint> points,
    Size size, {
    double padding = 24,
  }) {
    if (points.isEmpty || size.isEmpty) return const [];
    final sampled = _sample(points, 1200);
    if (sampled.length == 1) {
      return [Offset(size.width / 2, size.height / 2)];
    }
    final minLat = sampled.map((p) => p.latitude).reduce(math.min);
    final maxLat = sampled.map((p) => p.latitude).reduce(math.max);
    final minLon = sampled.map((p) => p.longitude).reduce(math.min);
    final maxLon = sampled.map((p) => p.longitude).reduce(math.max);
    final latRange = maxLat - minLat;
    final lonRange = maxLon - minLon;
    final width = math.max(0.0, size.width - padding * 2);
    final height = math.max(0.0, size.height - padding * 2);
    final scale = switch ((lonRange, latRange)) {
      (0, 0) => 0.0,
      (_, 0) => width / lonRange,
      (0, _) => height / latRange,
      _ => math.min(width / lonRange, height / latRange),
    };
    final contentWidth = lonRange * scale;
    final contentHeight = latRange * scale;
    final left = (size.width - contentWidth) / 2;
    final top = (size.height - contentHeight) / 2;
    return sampled
        .map(
          (point) => Offset(
            left + (point.longitude - minLon) * scale,
            top + (maxLat - point.latitude) * scale,
          ),
        )
        .toList(growable: false);
  }

  static List<ActivityRoutePoint> _sample(
    List<ActivityRoutePoint> points,
    int limit,
  ) {
    if (points.length <= limit) return List.unmodifiable(points);
    return List.generate(limit, (index) {
      final source = (index * (points.length - 1) / (limit - 1)).round();
      return points[source];
    }, growable: false);
  }
}

class ActivityRoutePainter extends CustomPainter {
  const ActivityRoutePainter(this.points);

  final List<ActivityRoutePoint> points;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = OraColors.forestDeep);
    final offsets = ActivityRouteProjector.project(points, size);
    if (offsets.isEmpty) return;
    if (offsets.length > 1) {
      final path = Path()..moveTo(offsets.first.dx, offsets.first.dy);
      for (final point in offsets.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = OraColors.gold
          ..strokeWidth = 4
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..style = PaintingStyle.stroke,
      );
    }
    canvas.drawCircle(offsets.first, 7, Paint()..color = OraColors.success);
    canvas.drawCircle(offsets.last, 7, Paint()..color = OraColors.orange);
  }

  @override
  bool shouldRepaint(ActivityRoutePainter oldDelegate) =>
      oldDelegate.points != points;
}

class ActivityRouteViewer extends StatelessWidget {
  const ActivityRouteViewer({
    super.key,
    required this.store,
    required this.activity,
    required this.ownerNik,
  });

  final ActivityStore store;
  final FinalActivity activity;
  final String ownerNik;

  @override
  Widget build(BuildContext context) => FutureBuilder<List<ActivityRoutePoint>>(
    future: store.acceptedRoute(activity.activityId, ownerNik),
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const SizedBox(
          height: 260,
          child: Center(child: CircularProgressIndicator()),
        );
      }
      final points = snapshot.data ?? const <ActivityRoutePoint>[];
      if (snapshot.hasError || points.isEmpty) {
        return const SizedBox(
          height: 180,
          child: Center(child: Text('ROUTE DATA NOT AVAILABLE ON THIS DEVICE')),
        );
      }
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            aspectRatio: 1.25,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: CustomPaint(
                key: const Key('activity_route_canvas'),
                painter: ActivityRoutePainter(points),
              ),
            ),
          ),
          const SizedBox(height: 10),
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.circle, size: 12, color: OraColors.success),
              Text(' START   '),
              Icon(Icons.circle, size: 12, color: OraColors.orange),
              Text(' FINISH'),
            ],
          ),
          const SizedBox(height: 12),
          OraStatLine(
            label: 'DISTANCE',
            value: '${(activity.distanceMeters / 1000).toStringAsFixed(2)} KM',
            assetName: 'distance.png',
          ),
          const SizedBox(height: 8),
          OraStatLine(
            label: 'AVG PACE',
            value: _formatAveragePace(activity.averagePaceSecondsPerKm),
            assetName: 'pace.png',
          ),
        ],
      );
    },
  );

  String _formatAveragePace(int? secondsPerKm) {
    if (secondsPerKm == null || secondsPerKm <= 0) return '-- /KM';
    final minutes = secondsPerKm ~/ 60;
    final seconds = secondsPerKm % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')} /KM';
  }
}
