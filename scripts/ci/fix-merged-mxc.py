from pathlib import Path

path = Path('lib/widgets/mxc_image.dart')
text = path.read_text()
text = text.replace("import 'package:http/http.dart' show ClientException;\n", '')
old = '''  Future<void> _tryLoad(int generation, [int attempt = 0]) async {
    if (!mounted || generation != _loadGeneration || _imageData != null) {
      return;
    }
    try {
      await _load();
    } on IOException {
      await _retryAfterDelay(attempt);
    } on ClientException {
      // On the web, transport failures ("Failed to fetch") surface as
      // package:http's ClientException, which implements Exception but not
      // IOException. Same recoverable error class: retrying may succeed.
      await _retryAfterDelay(attempt);
    } catch (e, s) {
      // Deterministic failure (e.g. HTTP error status): retrying cannot
      // succeed. Keep the placeholder instead of crashing the app.
      Logs().e('Failed to load image', e, s);
    }
  }

  Future<void> _retryAfterDelay(int attempt) async {
    // Stop after a bounded number of retries: retrying forever burns network
    // and CPU for permanently unavailable media.
    if (attempt >= _maxLoadRetries || !mounted) return;
    await Future<void>.delayed(widget.retryDuration);
    if (mounted) await _tryLoad(attempt + 1);
  }
'''
new = '''  Future<void> _tryLoad(int generation, [int attempt = 0]) async {
    if (!mounted || generation != _loadGeneration || _imageData != null) {
      return;
    }
    try {
      await _load(generation);
      if (!mounted || generation != _loadGeneration || _imageData != null) {
        return;
      }

      // A completed request that produced no image bytes is terminal.
      setState(() => _loadFailed = true);
    } catch (error, stackTrace) {
      Logs().d(
        'Unable to load mxc image (attempt ${attempt + 1})',
        error,
        stackTrace,
      );
      if (attempt >= _maxLoadRetries ||
          !mounted ||
          generation != _loadGeneration) {
        if (mounted && generation == _loadGeneration && _imageData == null) {
          setState(() => _loadFailed = true);
        }
        return;
      }
      await Future<void>.delayed(widget.retryDuration);
      if (!mounted || generation != _loadGeneration) return;
      await _tryLoad(generation, attempt + 1);
    }
  }
'''
if old not in text:
    raise SystemExit('expected stale MXC retry block not found')
path.write_text(text.replace(old, new))
