// Keep the native/JS bridge unchanged; Dart2Wasm needs a DCO adapter.
export 'vodozemac_init_native.dart'
    if (dart.library.js_interop) 'vodozemac_init_web.dart';
