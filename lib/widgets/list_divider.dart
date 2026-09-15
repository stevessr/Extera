import 'package:material_ui/material_ui.dart';

class ListDivider extends StatelessWidget {
  final Color? color;

  const ListDivider({this.color, super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Divider(
      color: color ?? theme.scaffoldBackgroundColor,
      thickness: 2,
      height: 2,
    );
  }
}
