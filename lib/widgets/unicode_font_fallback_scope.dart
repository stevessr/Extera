import 'dart:async';

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'package:extera_next/utils/unicode_font_loader.dart';

/// Watches painted text and queues only newly visible code points for the
/// on-demand Unicode fallback loader.
class UnicodeFontFallbackScope extends StatefulWidget {
  const UnicodeFontFallbackScope({
    super.key,
    required this.enabled,
    required this.child,
    this.loader,
  });

  final bool enabled;
  final Widget child;
  final UnicodeFontLoader? loader;

  @override
  State<UnicodeFontFallbackScope> createState() =>
      _UnicodeFontFallbackScopeState();
}

class _UnicodeFontFallbackScopeState extends State<UnicodeFontFallbackScope> {
  static const _scanInterval = Duration(milliseconds: 120);

  final _anchorKey = GlobalKey();
  final _lastText = Expando<String>('unicode fallback visible text');
  Duration? _lastScanTimestamp;
  Timer? _delayedScan;

  UnicodeFontLoader get _loader => widget.loader ?? UnicodeFontLoader.instance;

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addPersistentFrameCallback(_handleFrame);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scanNow());
  }

  @override
  void didUpdateWidget(UnicodeFontFallbackScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled) {
      _delayedScan?.cancel();
      _delayedScan = null;
    } else if (!oldWidget.enabled || oldWidget.loader != widget.loader) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scanNow());
    }
  }

  void _handleFrame(Duration timestamp) {
    if (!mounted || !widget.enabled) return;
    final previous = _lastScanTimestamp;
    if (previous == null || timestamp - previous >= _scanInterval) {
      _lastScanTimestamp = timestamp;
      _delayedScan?.cancel();
      _delayedScan = null;
      _scanNow();
      return;
    }

    _delayedScan ??= Timer(_scanInterval - (timestamp - previous), () {
      _delayedScan = null;
      if (!mounted || !widget.enabled) return;
      _lastScanTimestamp = SchedulerBinding.instance.currentFrameTimeStamp;
      _scanNow();
    });
  }

  void _scanNow() {
    if (!mounted || !widget.enabled) return;
    final root = _anchorKey.currentContext?.findRenderObject();
    if (root is! RenderBox || !root.attached || !root.hasSize) return;

    final texts = <String>[];
    void visit(RenderObject object) {
      if (object is RenderOffstage && object.offstage) return;
      if (object is RenderOpacity && object.opacity == 0) return;

      InlineSpan? span;
      if (object is RenderParagraph) {
        span = object.text;
      } else if (object is RenderEditable && !object.obscureText) {
        span = object.text;
      }

      if (span != null && _isVisible(object, root)) {
        final text = span.toPlainText(
          includeSemanticsLabels: false,
          includePlaceholders: false,
        );
        if (text.isNotEmpty && _lastText[object] != text) {
          _lastText[object] = text;
          texts.add(text);
        }
      }

      object.visitChildren(visit);
    }

    root.visitChildren(visit);
    if (texts.isNotEmpty) {
      unawaited(_loader.ensureFontsForText(texts.join()));
    }
  }

  static bool _isVisible(RenderObject object, RenderBox root) {
    if (object is! RenderBox || !object.attached || !object.hasSize) {
      return false;
    }
    try {
      final transform = object.getTransformTo(root);
      final bounds = MatrixUtils.transformRect(transform, object.paintBounds);
      return bounds.overlaps(root.paintBounds);
    } catch (_) {
      // A render object can detach between traversal and transform lookup.
      return false;
    }
  }

  @override
  void dispose() {
    _delayedScan?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _UnicodeFontScanAnchor(key: _anchorKey, child: widget.child);
}

class _UnicodeFontScanAnchor extends SingleChildRenderObjectWidget {
  const _UnicodeFontScanAnchor({super.key, required super.child});

  @override
  RenderProxyBox createRenderObject(BuildContext context) => RenderProxyBox();
}
