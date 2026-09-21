import 'package:material_ui/material_ui.dart';

import 'package:extera_next/config/app_config.dart';
import 'package:extera_next/config/themes.dart';
import 'package:extera_next/generated/l10n/l10n.dart';

enum _RoleChoice { admin, moderator, member, muted, custom }

Future<int?> showPermissionChooser(
  BuildContext context, {
  int currentLevel = 0,
  int maxLevel = 100,
}) async {
  return await showAdaptiveDialog<int>(
    context: context,
    builder: (context) =>
        _RoleChooserDialog(currentLevel: currentLevel, maxLevel: maxLevel),
  );
}

class _RoleChooserDialog extends StatefulWidget {
  final int currentLevel;
  final int maxLevel;

  const _RoleChooserDialog({
    required this.currentLevel,
    required this.maxLevel,
  });

  @override
  State<_RoleChooserDialog> createState() => _RoleChooserDialogState();
}

class _RoleChooserDialogState extends State<_RoleChooserDialog> {
  late _RoleChoice _selected;
  late final TextEditingController _customController;
  String? _customError;

  @override
  void initState() {
    super.initState();
    _customController = TextEditingController(
      text: widget.currentLevel.toString(),
    );
    _selected = _initialChoice(widget.currentLevel);
  }

  @override
  void dispose() {
    _customController.dispose();
    super.dispose();
  }

  _RoleChoice _initialChoice(int level) {
    if (level >= 100) return .admin;
    if (level == 50) return .moderator;
    if (level == 0) return .member;
    if (level < 0) return .muted;
    return .custom;
  }

  bool _isChoiceEnabled(_RoleChoice choice) {
    switch (choice) {
      case .admin:
        return widget.maxLevel >= 100;
      case .moderator:
        return widget.maxLevel >= 50;
      case .member:
      case .muted:
      case .custom:
        return true;
    }
  }

  void _onApply() {
    switch (_selected) {
      case .admin:
        Navigator.of(context).pop<int>(100);
        return;
      case .moderator:
        Navigator.of(context).pop<int>(50);
        return;
      case .member:
        Navigator.of(context).pop<int>(0);
        return;
      case .muted:
        Navigator.of(context).pop<int>(-1);
        return;
      case .custom:
        final parsed = int.tryParse(_customController.text.trim());
        if (parsed == null) {
          setState(() {
            _customError = L10n.of(context).powerLevelMustBeANumber;
          });
          return;
        }
        if (parsed > widget.maxLevel) {
          setState(() {
            _customError = L10n.of(
              context,
            ).cannotExceedPowerLevel(widget.maxLevel);
          });
          return;
        }
        Navigator.of(context).pop<int>(parsed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppConfig.borderRadius),
      ),
      title: Text(L10n.of(context).setPermissionsLevel),
      contentPadding: const .symmetric(vertical: 8),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: RadioGroup<_RoleChoice>(
          groupValue: _selected,
          onChanged: (v) {
            if (v != null) setState(() => _selected = v);
          },
          child: Column(
            mainAxisSize: .min,
            crossAxisAlignment: .stretch,
            children: [
              _buildRadio(
                context,
                choice: .admin,
                label: L10n.of(context).admin,
                subtitle: '100',
                onSelected: (v) {
                  setState(() => _selected = v);
                },
              ),
              _buildRadio(
                context,
                choice: .moderator,
                label: L10n.of(context).moderator,
                subtitle: '50',
                onSelected: (v) {
                  setState(() => _selected = v);
                },
              ),
              _buildRadio(
                context,
                choice: .member,
                label: L10n.of(context).member,
                subtitle: '0',
                onSelected: (v) {
                  setState(() => _selected = v);
                },
              ),
              _buildRadio(
                context,
                choice: .muted,
                label: L10n.of(context).powerLevelReadOnly,
                subtitle: '-1',
                onSelected: (v) {
                  setState(() => _selected = v);
                },
              ),
              _buildRadio(
                context,
                choice: .custom,
                label: L10n.of(context).custom,
                onSelected: (v) {
                  setState(() => _selected = v);
                },
              ),
              AnimatedSize(
                duration: FluffyThemes.animationDuration,
                alignment: Alignment.topCenter,
                curve: FluffyThemes.animationCurve,
                child: _selected == .custom
                    ? Padding(
                        padding: const .symmetric(horizontal: 24),
                        child: TextField(
                          controller: _customController,
                          autofocus: true,
                          keyboardType: .numberWithOptions(
                            signed: true,
                            decimal: false,
                          ),
                          decoration: InputDecoration(
                            isDense: true,
                            labelText: L10n.of(context).powerLevel,
                            helperText: L10n.of(
                              context,
                            ).maxPowerLevel(widget.maxLevel),
                            errorText: _customError,
                          ),
                          onChanged: (_) {
                            if (_customError != null) {
                              setState(() => _customError = null);
                            }
                          },
                          onSubmitted: (_) => _onApply(),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(L10n.of(context).cancel),
        ),
        FilledButton(onPressed: _onApply, child: Text(L10n.of(context).apply)),
      ],
      backgroundColor: theme.colorScheme.surfaceContainerHigh,
      surfaceTintColor: Colors.transparent,
    );
  }

  Widget _buildRadio(
    BuildContext context, {
    required _RoleChoice choice,
    required String label,
    void Function(_RoleChoice choice)? onSelected,
    String? subtitle,
  }) {
    final enabled = _isChoiceEnabled(choice);
    final selected = _selected == choice;

    return ListTile(
      selected: selected,
      onTap: () {
        onSelected?.call(choice);
      },
      leading: Radio<_RoleChoice>(value: choice, enabled: enabled),
      trailing: subtitle != null ? Text(subtitle) : null,
      title: Text(label),
    );
  }
}
