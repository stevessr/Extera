import 'package:flutter_vodozemac/flutter_vodozemac.dart' as vod;

/// Initialize the encryption backend with the package's standard loader.
Future<void> initVodozemac({required String wasmPath}) =>
    vod.init(wasmPath: wasmPath);
