import 'package:flutter/material.dart';

import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';

import 'package:extera_next/pages/chat/trust_user_key_dialog.dart';
import 'package:extera_next/utils/emoji_kitchen.dart';
import 'package:extera_next/widgets/emoji_picker.dart';
import 'package:extera_next/widgets/matrix.dart';

class EmojiKitchenPicker extends StatefulWidget {
  final Room room;
  final Event? replyEvent;
  final String? threadRootEventId;
  final List<PickerEmoji> recentEmojis;
  final VoidCallback onSent;

  const EmojiKitchenPicker({
    super.key,
    required this.room,
    required this.onSent,
    this.replyEvent,
    this.threadRootEventId,
    this.recentEmojis = const [],
  });

  @override
  State<EmojiKitchenPicker> createState() => _EmojiKitchenPickerState();
}

class _EmojiKitchenPickerState extends State<EmojiKitchenPicker> {
  final _source = EmojiKitchenDataSource.instance;

  String? _selectedEmoji;
  String? _selectedCodepoint;
  List<EmojiKitchenCombination> _combinations = const [];
  EmojiKitchenCombination? _sending;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _warmUp();
  }

  Future<void> _warmUp() async {
    try {
      await _source.ensureLoaded();
    } catch (_) {
      // Loading is retried when the user actually selects an emoji. Avoid
      // replacing the normal picker with an error before it is needed.
    }
  }

  Future<void> _selectEmoji(String emoji) async {
    setState(() {
      _selectedEmoji = emoji;
      _selectedCodepoint = null;
      _combinations = const [];
      _loading = true;
      _error = null;
    });

    try {
      await _source.ensureLoaded();
      final codepoint = _source.supportedCodepointFor(emoji);
      if (codepoint == null) {
        throw const EmojiKitchenException(
          'This emoji is not supported by Emoji Kitchen yet.',
        );
      }
      final combinations = _source.combinationsFor(codepoint);
      if (!mounted) return;
      setState(() {
        _selectedCodepoint = codepoint;
        _combinations = combinations;
        _loading = false;
        if (combinations.isEmpty) {
          _error = 'No Emoji Kitchen combinations are available for this emoji.';
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _retry() async {
    final emoji = _selectedEmoji;
    if (emoji == null) return;

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _source.ensureLoaded(forceRefresh: true);
      if (!mounted) return;
      await _selectEmoji(emoji);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _send(EmojiKitchenCombination combination) async {
    if (_sending != null) return;

    final proceed = await showTrustUserInRoomDialog(context, widget.room);
    if (!proceed || !mounted) return;

    setState(() => _sending = combination);
    try {
      final response = await http
          .get(combination.imageUri)
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
        throw EmojiKitchenException(
          'Emoji Kitchen image returned HTTP ${response.statusCode}.',
        );
      }

      // Kitchen artwork is small, but cap unexpected responses so a broken CDN
      // or redirect can never turn a sticker tap into an unbounded upload.
      const maximumStickerBytes = 8 * 1024 * 1024;
      if (response.bodyBytes.length > maximumStickerBytes) {
        throw const EmojiKitchenException('Emoji Kitchen image is too large.');
      }

      final client = Matrix.of(context).client;
      final mxc = await client.uploadContent(
        response.bodyBytes,
        filename: combination.fileName,
        contentType: 'image/png',
      );
      if (!mounted) return;

      final selectedEmoji = _selectedEmoji ?? '';
      await widget.room.sendEvent(
        {
          'body': '$selectedEmoji + ${combination.partnerEmoji}',
          'info': {
            'mimetype': 'image/png',
            'size': response.bodyBytes.length,
          },
          'url': mxc.toString(),
        },
        type: EventTypes.Sticker,
        inReplyTo: widget.replyEvent,
        threadRootEventId: widget.threadRootEventId,
      );
      if (!mounted) return;
      widget.onSent();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text('Could not send Emoji Kitchen sticker: $error')),
      );
    } finally {
      if (mounted) setState(() => _sending = null);
    }
  }

  void _goBack() {
    setState(() {
      _selectedEmoji = null;
      _selectedCodepoint = null;
      _combinations = const [];
      _loading = false;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_selectedEmoji == null) {
      return Stack(
        children: [
          MatrixEmojiPicker(
            onEmojiSelected: (_, emoji) {
              if (emoji.type != PickerEmojiType.standard) return;
              final value = emoji.standardEmoji?.char;
              if (value != null) _selectEmoji(value);
            },
            onBackspacePressed: () {},
            recentEmojis: widget.recentEmojis
                .where((emoji) => emoji.type == PickerEmojiType.standard)
                .toList(growable: false),
          ),
          if (!_source.isLoaded)
            const Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: LinearProgressIndicator(minHeight: 2),
            ),
        ],
      );
    }

    return Column(
      children: [
        _KitchenHeader(
          emoji: _selectedEmoji!,
          count: _combinations.length,
          onBack: _goBack,
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
              ? _KitchenError(message: _error!, onRetry: _retry)
              : GridView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 112,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                  ),
                  itemCount: _combinations.length,
                  itemBuilder: (context, index) {
                    final combination = _combinations[index];
                    return _KitchenTile(
                      combination: combination,
                      sending: identical(_sending, combination),
                      disabled: _sending != null,
                      onTap: () => _send(combination),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _KitchenHeader extends StatelessWidget {
  final String emoji;
  final int count;
  final VoidCallback onBack;

  const _KitchenHeader({
    required this.emoji,
    required this.count,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      child: SafeArea(
        top: false,
        bottom: false,
        child: SizedBox(
          height: 48,
          child: Row(
            children: [
              IconButton(
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Choose another emoji',
              ),
              Text(emoji, style: const TextStyle(fontSize: 26)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  count == 0 ? 'Emoji Kitchen' : '$count combinations',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall,
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(right: 12),
                child: Icon(Icons.auto_awesome, size: 20),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _KitchenTile extends StatelessWidget {
  final EmojiKitchenCombination combination;
  final bool sending;
  final bool disabled;
  final VoidCallback onTap;

  const _KitchenTile({
    required this.combination,
    required this.sending,
    required this.disabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: disabled ? null : onTap,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Padding(
              padding: const EdgeInsets.all(8),
              child: Image.network(
                combination.imageUri.toString(),
                cacheWidth: 192,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.medium,
                errorBuilder: (context, error, stackTrace) => Center(
                  child: Text(
                    combination.partnerEmoji,
                    style: const TextStyle(fontSize: 34),
                  ),
                ),
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  return const Center(
                    child: SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  );
                },
              ),
            ),
            Positioned(
              right: 5,
              bottom: 3,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface.withValues(alpha: 0.86),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  child: Text(
                    combination.partnerEmoji,
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
              ),
            ),
            if (sending)
              ColoredBox(
                color: theme.colorScheme.surface.withValues(alpha: 0.72),
                child: const Center(child: CircularProgressIndicator()),
              ),
          ],
        ),
      ),
    );
  }
}

class _KitchenError extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _KitchenError({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.sentiment_dissatisfied_outlined, size: 36),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
