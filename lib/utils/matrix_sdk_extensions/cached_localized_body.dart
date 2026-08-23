import 'dart:async';

import 'package:matrix/matrix.dart';

import 'package:extera_next/utils/matrix_sdk_extensions/matrix_locals.dart';

/// Memoization for the localized-body and sender-lookup paths that run on
/// every rebuild of hot widgets (chat list rows, reply previews).
///
/// Cache lifetime is tied to the [Event] instance via [Expando]: the SDK
/// replaces event objects whenever their content changes (edits, redactions,
/// sync updates), so instance identity is an exact invalidation signal and
/// nothing can go stale beyond a content change. Entries are garbage
/// collected with their event, so no size bound is needed.
final Expando<Map<String, String>> _fallbackBodyCache = Expando(
  'calcLocalizedBodyFallbackCache',
);

final Expando<Map<String, Future<String>>> _asyncBodyCache = Expando(
  'calcLocalizedBodyCache',
);

final Expando<Map<String, Future<User?>>> _senderUserCache = Expando(
  'fetchSenderUserCache',
);

String _localeTag(MatrixLocalizations i18n) =>
    i18n is MatrixLocals ? i18n.localeName : '';

String _flagKey(
  MatrixLocalizations i18n, {
  required bool withSenderNamePrefix,
  required bool hideReply,
  required bool hideEdit,
  required bool plaintextBody,
  required bool removeMarkdown,
}) =>
    '${_localeTag(i18n)}|$withSenderNamePrefix$hideReply$hideEdit'
    '$plaintextBody$removeMarkdown';

extension CachedLocalizedBody on Event {
  /// [calcLocalizedBodyFallback] memoized per event instance, locale and
  /// flag combination.
  String calcLocalizedBodyFallbackCached(
    MatrixLocalizations i18n, {
    bool withSenderNamePrefix = false,
    bool hideReply = false,
    bool hideEdit = false,
    bool plaintextBody = false,
    bool removeMarkdown = false,
  }) {
    final key = _flagKey(
      i18n,
      withSenderNamePrefix: withSenderNamePrefix,
      hideReply: hideReply,
      hideEdit: hideEdit,
      plaintextBody: plaintextBody,
      removeMarkdown: removeMarkdown,
    );
    final cache = _fallbackBodyCache[this] ??= {};
    return cache[key] ??= calcLocalizedBodyFallback(
      i18n,
      withSenderNamePrefix: withSenderNamePrefix,
      hideReply: hideReply,
      hideEdit: hideEdit,
      plaintextBody: plaintextBody,
      removeMarkdown: removeMarkdown,
    );
  }

  /// [calcLocalizedBody] memoized per event instance. Returning the same
  /// [Future] for repeated calls lets `FutureBuilder`s skip re-awaiting the
  /// (potentially profile-fetching) work on every rebuild.
  Future<String> calcLocalizedBodyCached(
    MatrixLocalizations i18n, {
    bool withSenderNamePrefix = false,
    bool hideReply = false,
    bool hideEdit = false,
    bool plaintextBody = false,
    bool removeMarkdown = false,
  }) {
    final key = _flagKey(
      i18n,
      withSenderNamePrefix: withSenderNamePrefix,
      hideReply: hideReply,
      hideEdit: hideEdit,
      plaintextBody: plaintextBody,
      removeMarkdown: removeMarkdown,
    );
    final cache = _asyncBodyCache[this] ??= {};
    return cache[key] ??= _memoFuture(
      _asyncBodyCache,
      this,
      key,
      () => calcLocalizedBody(
        i18n,
        withSenderNamePrefix: withSenderNamePrefix,
        hideReply: hideReply,
        hideEdit: hideEdit,
        plaintextBody: plaintextBody,
        removeMarkdown: removeMarkdown,
      ),
    );
  }

  /// [fetchSenderUser] memoized per event instance so reply previews do not
  /// re-run the member/profile lookup on every rebuild.
  Future<User?> fetchSenderUserCached() {
    const key = 'sender';
    final cache = _senderUserCache[this] ??= {};
    return cache[key] ??= _memoFuture(
      _senderUserCache,
      this,
      key,
      fetchSenderUser,
    );
  }
}

/// Registers [create]'s future under [key], evicting it again on failure so
/// transient errors are retried on the next rebuild instead of being cached
/// forever. The eviction is guarded: a newer replacement entry survives.
Future<T> _memoFuture<T>(
  Expando<Map<String, Future<T>>> store,
  Event instance,
  String key,
  Future<T> Function() create,
) {
  final future = create();
  unawaited(
    future.then(
      (_) {},
      onError: (Object _) {
        final cache = store[instance];
        if (identical(cache?[key], future)) cache?.remove(key);
      },
    ),
  );
  return future;
}
