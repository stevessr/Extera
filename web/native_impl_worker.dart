// Entry point for the matrix dart SDK native implementations web worker.
//
// The SDK ships the worker side of NativeImplementationsWebWorker
// (image shrinking and metadata calculation). This file instantiates it;
// it is compiled to plain JS with `dart compile js` so the same script
// serves both the dart2js bundle and the dart2wasm bundle:
//
//   dart compile js --minify -O4 \
//     -o web/native_impl_worker.dart.js web/native_impl_worker.dart
//
// The compiled output is gitignored; scripts/prepare-web.sh builds it for
// local runs and .github/actions/build-web-app/action.yml for CI.
import 'package:matrix/matrix.dart';

Future<void> main() => startWebWorker();
