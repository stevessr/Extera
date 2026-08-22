import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

Future<void>? _loading;

bool get _isLoaded => web.window.hasProperty('Imaging'.toJS).toDart;

Future<void> ensureNativeImagingLoaded() async {
  if (_isLoaded) return;

  final loading = _loading;
  if (loading != null) return loading;

  final future = _load();
  _loading = future;
  try {
    await future;
  } catch (_) {
    // Permit a later operation to retry after a transient network failure.
    _loading = null;
    rethrow;
  }
}

Future<void> _load() async {
  final script = web.HTMLScriptElement()
    ..src = 'Imaging.js'
    ..async = true;

  final loaded = script.onLoad.first.then<void>((_) {});
  final failed = script.onError.first.then<void>(
    (_) => throw StateError('Unable to load Imaging.js'),
  );

  web.document.head!.append(script);
  await Future.any([loaded, failed]);

  if (!_isLoaded) {
    throw StateError('Imaging.js loaded without exposing window.Imaging');
  }
}
