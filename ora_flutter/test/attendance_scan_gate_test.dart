import 'package:flutter_test/flutter_test.dart';
import 'package:ora_flutter/features/attendance/domain/attendance_scan_gate.dart';

void main() {
  test('scan gate accepts only the first non-empty QR until reset', () {
    final gate = AttendanceScanGate();

    expect(gate.accept(''), isFalse);
    expect(gate.accept(' QR-ONE '), isTrue);
    expect(gate.accept('QR-ONE'), isFalse);
    expect(gate.accept('QR-TWO'), isFalse);

    gate.reset();
    expect(gate.accept('QR-TWO'), isTrue);
  });
}
