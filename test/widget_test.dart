import 'package:flutter_test/flutter_test.dart';

import 'package:cctt/main.dart';

void main() {
  test('CcttApp exposes the application root widget', () {
    const app = CcttApp();

    expect(app, isA<CcttApp>());
  });
}
