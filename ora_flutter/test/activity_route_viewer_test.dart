import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ora_flutter/features/activity/domain/activity_sync.dart';
import 'package:ora_flutter/features/activity/presentation/activity_route_viewer.dart';

ActivityRoutePoint _point(double lat, double lon, int sequence) =>
    ActivityRoutePoint(latitude: lat, longitude: lon, sequence: sequence);

void main() {
  const size = Size(300, 200);

  test(
    'route projection handles empty, one, duplicate and straight routes',
    () {
      expect(ActivityRouteProjector.project(const [], size), isEmpty);
      expect(
        ActivityRouteProjector.project([_point(1, 1, 1)], size).single,
        const Offset(150, 100),
      );
      final duplicate = ActivityRouteProjector.project([
        _point(1, 1, 1),
        _point(1, 1, 2),
      ], size);
      expect(
        duplicate.every((point) => point == const Offset(150, 100)),
        isTrue,
      );
      final vertical = ActivityRouteProjector.project([
        _point(1, 1, 1),
        _point(2, 1, 2),
      ], size);
      expect(vertical.first.dx, vertical.last.dx);
      expect(vertical.first.dy, isNot(vertical.last.dy));
      final horizontal = ActivityRouteProjector.project([
        _point(1, 1, 1),
        _point(1, 2, 2),
      ], size);
      expect(horizontal.first.dy, horizontal.last.dy);
      expect(horizontal.first.dx, isNot(horizontal.last.dx));
    },
  );

  test('large route is bounded and source points remain unchanged', () {
    final source = List.generate(
      5000,
      (index) => _point(index / 1000, index / 2000, index),
    );
    final before = List<ActivityRoutePoint>.of(source);
    final projected = ActivityRouteProjector.project(source, size);
    expect(projected, hasLength(1200));
    expect(source, orderedEquals(before));
    expect(projected.every((p) => p.dx >= 0 && p.dx <= size.width), isTrue);
    expect(projected.every((p) => p.dy >= 0 && p.dy <= size.height), isTrue);
  });

  testWidgets('route painter renders without exception', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CustomPaint(
          size: size,
          painter: ActivityRoutePainter([
            _point(-6.2, 106.8, 1),
            _point(-6.21, 106.81, 2),
          ]),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });
}
