import 'package:flutter_test/flutter_test.dart';
import 'package:svara/services/systemconfig.dart';

void main() {
  test('detects a newer semantic version', () {
    expect(isUpdateAvailable('1.0.0', '1', '1.0.1', '1'), isTrue);
  });

  test('does not flag the same version as an update', () {
    expect(isUpdateAvailable('1.0.1', '2', '1.0.1', '2'), isFalse);
  });
}
