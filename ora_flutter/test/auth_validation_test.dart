import 'package:flutter_test/flutter_test.dart';
import 'package:ora_flutter/features/auth/domain/auth_validation.dart';

void main() {
  group('PIN validation', () {
    test('empty', () => expect(pinValidationError(''), 'Enter your PIN.'));
    test(
      'short',
      () => expect(pinValidationError('123'), 'PIN must be exactly 4 digits.'),
    );
    test(
      'long',
      () =>
          expect(pinValidationError('12345'), 'PIN must be exactly 4 digits.'),
    );
    test(
      'non-numeric',
      () =>
          expect(pinValidationError('12A4'), 'PIN must contain numbers only.'),
    );
    test('valid', () => expect(pinValidationError('0123'), isNull));
  });

  group('nickname validation', () {
    test(
      'empty',
      () => expect(nicknameValidationError(''), 'Enter a nickname.'),
    );
    test(
      'whitespace',
      () => expect(nicknameValidationError('   '), 'Enter a nickname.'),
    );
    test(
      'eight characters',
      () => expect(nicknameValidationError('ABCD1234'), isNull),
    );
    test(
      'nine characters',
      () => expect(
        nicknameValidationError('ABCDE1234'),
        'Nickname can have up to 8 characters.',
      ),
    );
    test(
      'alphanumeric only',
      () => expect(
        nicknameValidationError('ORA_RUN'),
        'Use letters and numbers only.',
      ),
    );
    test(
      'canonical uppercase',
      () => expect(canonicalNickname('  Ora123  '), 'ORA123'),
    );
  });
}
