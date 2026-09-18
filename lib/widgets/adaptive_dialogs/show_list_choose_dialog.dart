import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:material_ui/material_ui.dart';

import 'package:extera_next/generated/l10n/l10n.dart';
import 'package:extera_next/utils/url_launcher.dart';
import 'package:extera_next/widgets/adaptive_dialogs/dialog_text_field.dart';

Future<List<String>?> showListChooseDialog({
  required BuildContext context,
  required String title,
  String? message,
  String? okLabel,
  String? cancelLabel,
  bool useRootNavigator = false,
  String? hintText,
  List<String>? initialItems,
  bool isDestructive = false,
  String? Function(String input)? validator,
}) {
  return showAdaptiveDialog<List<String>>(
    context: context,
    useRootNavigator: useRootNavigator,
    builder: (context) {
      return _ListChooseDialog(
        title: title,
        message: message,
        okLabel: okLabel,
        cancelLabel: cancelLabel,
        hintText: hintText,
        initialItems: initialItems,
        isDestructive: isDestructive,
        validator: validator,
      );
    },
  );
}

class _ListChooseDialog extends StatefulWidget {
  final String title;
  final String? message;
  final String? okLabel;
  final String? cancelLabel;
  final String? hintText;
  final List<String>? initialItems;
  final bool isDestructive;
  final String? Function(String input)? validator;

  const _ListChooseDialog({
    required this.title,
    this.message,
    this.okLabel,
    this.cancelLabel,
    this.hintText,
    this.initialItems,
    this.isDestructive = false,
    this.validator,
  });

  @override
  State<_ListChooseDialog> createState() => _ListChooseDialogState();
}

class _ListChooseDialogState extends State<_ListChooseDialog> {
  late final List<String> _items;
  final _controller = TextEditingController();
  String? _error;

  @override
  void initState() {
    super.initState();
    _items = List.from(widget.initialItems ?? []);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _addItem() {
    final input = _controller.text;
    if (input.isEmpty) return;

    final errorText = widget.validator?.call(input);
    if (errorText != null) {
      setState(() {
        _error = errorText;
      });
      return;
    }

    setState(() {
      _error = null;
      _items.add(input);
      _controller.clear();
    });
  }

  void _removeItem(int index) {
    setState(() {
      _items.removeAt(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 512),
      child: AlertDialog.adaptive(
        title: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 256),
          child: Text(widget.title),
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 256),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.message != null) ...[
                SelectableLinkify(
                  text: widget.message!,
                  textScaleFactor: MediaQuery.textScalerOf(context).scale(1),
                  linkStyle: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    decorationColor: Theme.of(context).colorScheme.primary,
                  ),
                  options: const LinkifyOptions(humanize: false),
                  onOpen: (url) => UrlLauncher(context, url.url).launchUrl(),
                ),
                const SizedBox(height: 16),
              ],
              if (_items.isNotEmpty) ...[
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (int i = 0; i < _items.length; i++)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(_items[i]),
                            trailing: IconButton(
                              icon: const Icon(Icons.remove_circle_outline),
                              color: Theme.of(context).colorScheme.error,
                              onPressed: () => _removeItem(i),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: DialogTextField(
                      hintText: widget.hintText,
                      errorText: _error,
                      controller: _controller,
                      onSubmitted: (_) => _addItem(),
                      textInputAction: TextInputAction.done,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.only(top: 4.0),
                    child: IconButton(
                      icon: const Icon(Icons.add_circle_outline),
                      color: Theme.of(context).colorScheme.primary,
                      onPressed: _addItem,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(null),
            style: OutlinedButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24.0),
              ),
            ),
            child: Text(widget.cancelLabel ?? L10n.of(context).cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop<List<String>>(_items),
            autofocus: true,
            style: widget.isDestructive
                ? FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.error,
                    foregroundColor: Theme.of(context).colorScheme.onError,
                  )
                : null,
            child: Text(widget.okLabel ?? L10n.of(context).ok),
          ),
        ],
      ),
    );
  }
}
