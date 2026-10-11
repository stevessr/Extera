import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vodozemac/vodozemac.dart' as vod;

import 'package:extera_next/utils/vodozemac_init.dart';

void main() {
  test(
    'Dart2Wasm can create and use a vodozemac Olm account',
    () async {
      await initVodozemac(wasmPath: './assets/assets/vodozemac/');

      // Account construction exercises the failing synchronous DCO return.
      final account = vod.Account();
      expect(account.maxNumberOfOneTimeKeys, greaterThan(0));
      final keys = account.identityKeys;
      expect(keys.curve25519.toBase64(), isNotEmpty);
      expect(keys.ed25519.toBase64(), isNotEmpty);
    },
    skip: !kIsWasm,
  );
}
