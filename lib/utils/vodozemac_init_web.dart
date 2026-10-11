import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_vodozemac/flutter_vodozemac.dart' as vod;
import 'package:vodozemac/src/generated/frb_generated.dart' as generated;

/// Initialize vodozemac with a Wasm-compatible DartCObject decoder.
///
/// flutter_rust_bridge 2.13.0's web DCO codec expects Dart List<dynamic>,
/// while wasm-bindgen returns JavaScript arrays. dart2js can represent both
/// using JavaScript arrays, but dart2wasm keeps Dart and JS lists distinct.
/// Without converting the result, creating a Matrix Olm account throws a
/// runtime type check at DcoCodec.decodeObject.
Future<void> initVodozemac({required String wasmPath}) async {
  if (!kIsWasm) {
    await vod.init(wasmPath: wasmPath);
    return;
  }

  await generated.RustLib.init(
    handler: _WasmDcoHandler(),
    externalLibrary: await loadExternalLibrary(
      ExternalLibraryLoaderConfig(
        stem: 'vodozemac_bindings_dart',
        ioDirectory: './',
        webPrefix: wasmPath,
      ),
    ),
  );
}

class _WasmDcoHandler extends BaseHandler {
  @override
  S executeSync<S, E extends Object, WireSyncType>(
    SyncTask<S, E, WireSyncType> task,
  ) {
    // FRB's regular codec is correct for dart2js.
    if (!kIsWasm) return super.executeSync(task);

    final dynamic jsResult;
    try {
      // Do not impose WireSyncType (List<dynamic>) on a JSArray before
      // converting it. All vodozemac 0.8.1 bridge calls are synchronous DCO.
      jsResult = (task.callFfi as dynamic)();
    } catch (e, s) {
      if (e is FrbException) rethrow;
      throw PanicException('EXECUTE_SYNC_ABORT $e $s');
    }

    // JSAny.dartify recursively converts nested JS arrays to Dart lists.
    // FRB's web freeWireSyncRust2DartDco is a no-op; JS owns this result.
    return task.codec.decodeObject((jsResult as JSAny?)?.dartify());
  }
}
