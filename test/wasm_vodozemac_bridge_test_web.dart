import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:extera_next/utils/vodozemac_init_web.dart'
    show decodeWasmDcoValue;

void main() {
  test(
    'Dart2Wasm decodes JS arrays and integer tags in vodozemac DCO results',
    () {
      final codec = DcoCodec<int, Exception>(
        decodeSuccessData: (raw) => (raw as List<dynamic>).single as int,
        decodeErrorData: null,
      );
      final jsResult = <JSAny?>[
        0.toJS,
        <JSAny?>[42.toJS].toJS,
      ].toJS;

      expect(codec.decodeObject(decodeWasmDcoValue(jsResult)), 42);
    },
    skip: !kIsWasm,
  );
}
