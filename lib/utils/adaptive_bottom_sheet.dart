import 'dart:math';

import 'package:flutter/material.dart';

import 'package:extera_next/config/app_config.dart';
import 'package:extera_next/config/themes.dart';

Future<T?> showAdaptiveBottomSheet<T>({
  required BuildContext context,
  required Widget Function(BuildContext) builder,
  bool isDismissible = true,
  bool isScrollControlled = true,
  bool useRootNavigator = false,
}) {
  if (FluffyThemes.isColumnMode(context)) {
    return showDialog<T>(
      context: context,
      useRootNavigator: useRootNavigator,
      barrierDismissible: isDismissible,
      useSafeArea: true,
      builder: (context) => Center(
        child: Container(
          margin: const EdgeInsets.all(16),
          constraints: const BoxConstraints(maxWidth: 480, maxHeight: 720),
          child: Material(
            elevation: Theme.of(context).dialogTheme.elevation ?? 4,
            shadowColor: Theme.of(context).dialogTheme.shadowColor,
            borderRadius: BorderRadius.circular(AppConfig.borderRadius),
            color: Theme.of(context).scaffoldBackgroundColor,
            clipBehavior: Clip.hardEdge,
            child: builder(context),
          ),
        ),
      ),
    );
  }

  return showModalBottomSheet<T>(
    context: context,
    builder: (context) => _BottomSheetTransitionContent(
      child: ClipRRect(
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(AppConfig.borderRadius / 2),
          topRight: Radius.circular(AppConfig.borderRadius / 2),
        ),
        clipBehavior: Clip.hardEdge,
        child: builder(context),
      ),
    ),
    useRootNavigator: useRootNavigator,
    isDismissible: isDismissible,
    isScrollControlled: isScrollControlled,
    constraints: BoxConstraints(
      maxHeight: min(MediaQuery.sizeOf(context).height - 32, 600),
      maxWidth: FluffyThemes.columnWidth * 1.25,
    ),
    backgroundColor: Colors.transparent,
    clipBehavior: Clip.hardEdge,
  );
}

/// Keeps heavy sheet contents (notably animated reactions and emoji grids)
/// from repainting on every frame while the route itself slides on or off
/// screen. The route can move the cached layer instead, while child tickers are
/// resumed as soon as the transition settles.
class _BottomSheetTransitionContent extends StatefulWidget {
  final Widget child;

  const _BottomSheetTransitionContent({required this.child});

  @override
  State<_BottomSheetTransitionContent> createState() =>
      _BottomSheetTransitionContentState();
}

class _BottomSheetTransitionContentState
    extends State<_BottomSheetTransitionContent> {
  Animation<double>? _routeAnimation;
  bool _routeIsAnimating = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final animation = ModalRoute.of(context)?.animation;
    if (identical(animation, _routeAnimation)) return;

    _routeAnimation?.removeStatusListener(_handleAnimationStatus);
    _routeAnimation = animation;
    _routeAnimation?.addStatusListener(_handleAnimationStatus);
    _routeIsAnimating = _isMoving(animation?.status);
  }

  static bool _isMoving(AnimationStatus? status) =>
      status == AnimationStatus.forward || status == AnimationStatus.reverse;

  void _handleAnimationStatus(AnimationStatus status) {
    final isAnimating = _isMoving(status);
    if (isAnimating == _routeIsAnimating || !mounted) return;
    setState(() => _routeIsAnimating = isAnimating);
  }

  @override
  void dispose() {
    _routeAnimation?.removeStatusListener(_handleAnimationStatus);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TickerMode(
    enabled: !_routeIsAnimating,
    child: RepaintBoundary(child: widget.child),
  );
}
