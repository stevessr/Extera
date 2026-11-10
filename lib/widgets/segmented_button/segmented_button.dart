import 'package:material_ui/material_ui.dart';

import 'package:extera_next/config/themes.dart';

class ExpressiveButtonSegment<T> {
  const ExpressiveButtonSegment({required this.value, this.label, this.icon});

  final T value;
  final Widget? label;
  final Widget? icon;
}

class ExpressiveSegmentedButton<T> extends StatelessWidget {
  const ExpressiveSegmentedButton({
    super.key,
    required this.segments,
    required this.selected,
    required this.onSelectionChanged,
    this.showSelectedIcon = false,
    this.expanded = false,
  });

  final List<ExpressiveButtonSegment<T>> segments;
  final T selected;
  final ValueChanged<T> onSelectionChanged;
  final bool showSelectedIcon;

  /// Stretch the segments to fill the available width, scrolling
  /// horizontally instead when the segments do not fit.
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    if (!expanded) {
      return _buildSegmentsRow(stretched: false);
    }
    final textDirection = Directionality.of(context);
    final labelStyle = Theme.of(context).textTheme.labelLarge;
    final textScaler = MediaQuery.textScalerOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final intrinsicWidth = _measureSegmentsWidth(
          textDirection,
          labelStyle,
          textScaler,
        );
        // An unbounded width would break the stretched Row, scroll instead.
        final fits = maxWidth.isFinite && intrinsicWidth <= maxWidth;
        if (fits) {
          return _buildSegmentsRow(stretched: true);
        }
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: _buildSegmentsRow(stretched: false),
        );
      },
    );
  }

  Widget _buildSegmentsRow({required bool stretched}) {
    final segmentCount = segments.length;
    return Row(
      mainAxisSize: stretched ? MainAxisSize.max : MainAxisSize.min,
      children: [
        for (var i = 0; i < segmentCount; i++) ...[
          if (i > 0) const SizedBox(width: 2),
          if (stretched)
            Expanded(child: _buildSegment(i))
          else
            _buildSegment(i),
        ],
      ],
    );
  }

  Widget _buildSegment(int i) => _ExpressiveSegment<T>(
    label: segments[i].label,
    icon: segments[i].icon,
    selected: segments[i].value == selected,
    isFirst: i == 0,
    isLast: i == segments.length - 1,
    showSelectedIcon: showSelectedIcon,
    onTap: () => onSelectionChanged(segments[i].value),
  );

  double _measureSegmentsWidth(
    TextDirection textDirection,
    TextStyle? labelStyle,
    TextScaler textScaler,
  ) {
    var totalWidth = 0.0;
    for (var i = 0; i < segments.length; i++) {
      if (i > 0) totalWidth += 2;
      totalWidth += _measureSegmentWidth(
        segments[i],
        segments[i].value == selected,
        textDirection,
        labelStyle,
        textScaler,
      );
    }
    return totalWidth;
  }

  double _measureSegmentWidth(
    ExpressiveButtonSegment<T> segment,
    bool isSelected,
    TextDirection textDirection,
    TextStyle? labelStyle,
    TextScaler textScaler,
  ) {
    final label = segment.label;
    // Non-text labels cannot be measured, fall back to the scroll mode.
    if (label != null && label is! Text) return double.infinity;

    final text = label is Text ? label.data : null;
    if (label != null && text == null) return double.infinity;

    final labelWidth = text == null
        ? 0.0
        : (TextPainter(
            text: TextSpan(text: text, style: labelStyle),
            textDirection: textDirection,
            textScaler: textScaler,
            maxLines: 1,
          )..layout()).width;

    final hasLeading = (showSelectedIcon && isSelected) || segment.icon != null;
    if (hasLeading) {
      if (label != null) {
        return 12 + 18 + 8 + labelWidth + 16;
      }
      return 16 + 18 + 16;
    }
    if (label != null) return 16 + labelWidth + 16;
    return 32;
  }
}

class _ExpressiveSegment<T> extends StatelessWidget {
  const _ExpressiveSegment({
    required this.label,
    required this.icon,
    required this.selected,
    required this.isFirst,
    required this.isLast,
    required this.showSelectedIcon,
    required this.onTap,
  });

  final Widget? label;
  final Widget? icon;
  final bool selected;
  final bool isFirst;
  final bool isLast;
  final bool showSelectedIcon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    const fullRadius = Radius.circular(20);
    const innerRadius = Radius.circular(12);

    final BorderRadius borderRadius;
    if (selected || (isFirst && isLast)) {
      borderRadius = const BorderRadius.all(fullRadius);
    } else if (isFirst) {
      borderRadius = const BorderRadius.only(
        topLeft: fullRadius,
        bottomLeft: fullRadius,
        topRight: innerRadius,
        bottomRight: innerRadius,
      );
    } else if (isLast) {
      borderRadius = const BorderRadius.only(
        topLeft: innerRadius,
        bottomLeft: innerRadius,
        topRight: fullRadius,
        bottomRight: fullRadius,
      );
    } else {
      borderRadius = const BorderRadius.all(innerRadius);
    }

    final background = selected
        ? colorScheme.secondaryContainer
        : colorScheme.surfaceContainerHighest;
    final foreground = selected
        ? colorScheme.onSecondaryContainer
        : colorScheme.onSurface;

    final Widget? leading;
    if (showSelectedIcon && selected) {
      leading = Icon(Icons.check, size: 18, color: foreground);
    } else if (icon != null) {
      leading = IconTheme.merge(
        data: IconThemeData(size: 18, color: foreground),
        child: icon!,
      );
    } else {
      leading = null;
    }

    final padding = (leading != null && label != null)
        ? const EdgeInsetsDirectional.fromSTEB(12, 8, 16, 8)
        : const EdgeInsets.symmetric(horizontal: 16, vertical: 8);

    return AnimatedContainer(
      duration: FluffyThemes.animationDuration,
      curve: FluffyThemes.animationCurve,
      constraints: const BoxConstraints(minHeight: 40),
      decoration: BoxDecoration(color: background, borderRadius: borderRadius),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: borderRadius,
          onTap: onTap,
          child: Padding(
            padding: padding,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ?leading,
                if (leading != null && label != null) const SizedBox(width: 8),
                if (label != null)
                  DefaultTextStyle(
                    style: theme.textTheme.labelLarge!.copyWith(
                      color: foreground,
                    ),
                    child: label!,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
