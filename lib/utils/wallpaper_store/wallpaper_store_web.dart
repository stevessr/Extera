import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

const String _databaseName = 'extera_wallpaper';
const String _storeName = 'wallpaper';

/// Key of the global wallpaper. Kept as it was before per room wallpapers
/// existed so that already stored images are not orphaned.
const String _globalEntryKey = 'chat_wallpaper';

String _entryKey(String storageKey) =>
    storageKey.isEmpty ? _globalEntryKey : 'room:$storageKey';
const int _databaseVersion = 1;

Future<T> _await<T extends JSAny?>(web.IDBRequest request) {
  final completer = Completer<T>();
  request.onsuccess = ((web.Event _) {
    completer.complete(request.result as T);
  }).toJS;
  request.onerror = ((web.Event _) {
    completer.completeError(
      StateError('IndexedDB request failed: ${request.error?.message}'),
    );
  }).toJS;
  return completer.future;
}

Future<web.IDBDatabase> _openDatabase() {
  final completer = Completer<web.IDBDatabase>();
  final request = web.window.indexedDB.open(_databaseName, _databaseVersion);

  request.onupgradeneeded = ((web.Event _) {
    final db = request.result as web.IDBDatabase;
    if (!db.objectStoreNames.contains(_storeName)) {
      db.createObjectStore(_storeName);
    }
  }).toJS;
  request.onsuccess = ((web.Event _) {
    completer.complete(request.result as web.IDBDatabase);
  }).toJS;
  request.onerror = ((web.Event _) {
    completer.completeError(
      StateError('Unable to open IndexedDB: ${request.error?.message}'),
    );
  }).toJS;

  return completer.future;
}

/// Runs [action] inside a transaction and waits for the transaction to be
/// committed, so that the caller can rely on the data actually being stored.
Future<void> _write(void Function(web.IDBObjectStore store) action) async {
  final db = await _openDatabase();
  try {
    final transaction = db.transaction(_storeName.toJS, 'readwrite');
    final completer = Completer<void>();
    transaction.oncomplete = ((web.Event _) => completer.complete()).toJS;
    transaction.onerror = ((web.Event _) {
      completer.completeError(
        StateError(
          'IndexedDB transaction failed: ${transaction.error?.message}',
        ),
      );
    }).toJS;
    transaction.onabort = ((web.Event _) {
      completer.completeError(StateError('IndexedDB transaction aborted'));
    }).toJS;

    action(transaction.objectStore(_storeName));
    await completer.future;
  } finally {
    db.close();
  }
}

/// Persists the chat wallpaper bytes in IndexedDB.
///
/// The settings store is backed by local storage on web, which is both tiny
/// and synchronous, so the image itself lives here and the setting only keeps
/// a marker.
Future<void> saveWallpaperBytes(String storageKey, Uint8List bytes) =>
    _write((store) => store.put(bytes.toJS, _entryKey(storageKey).toJS));

/// Reads the wallpaper bytes persisted by [saveWallpaperBytes].
Future<Uint8List?> loadWallpaperBytes(String storageKey) async {
  final db = await _openDatabase();
  try {
    final transaction = db.transaction(_storeName.toJS, 'readonly');
    final result = await _await<JSAny?>(
      transaction.objectStore(_storeName).get(_entryKey(storageKey).toJS),
    );
    if (result == null) return null;
    if (result.isA<JSUint8Array>()) return (result as JSUint8Array).toDart;
    if (result.isA<JSArrayBuffer>()) {
      return (result as JSArrayBuffer).toDart.asUint8List();
    }
    return null;
  } finally {
    db.close();
  }
}

/// Removes the persisted wallpaper bytes.
Future<void> deleteWallpaperBytes(String storageKey) =>
    _write((store) => store.delete(_entryKey(storageKey).toJS));
