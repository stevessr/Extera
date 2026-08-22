import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('web startup does not wait for optional page assets', () {
    final index = File('web/index.html').readAsStringSync();
    final bootstrap = File('web/flutter_bootstrap.js').readAsStringSync();

    expect(index, contains('<script src="flutter_bootstrap.js" async>'));
    expect(index, isNot(contains('window.addEventListener')));
    expect(index, isNot(contains('src="flutter.js"')));
    expect(index, isNot(contains('src="Imaging.js"')));

    expect(bootstrap, contains('{{flutter_js}}'));
    expect(bootstrap, contains('{{flutter_build_config}}'));
    expect(bootstrap, contains('onEntrypointLoaded'));
  });
}
