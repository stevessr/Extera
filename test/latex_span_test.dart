import 'package:flutter_test/flutter_test.dart';
import 'package:latext/latext.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:extera_next/config/app_settings.dart';
import 'package:extera_next/pages/chat/events/html_message.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.init(loadWebConfigFile: false);
  });

  Future<void> pumpLatex(WidgetTester tester, String math) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LatexSpan(math: math, fontSize: 16, color: Colors.black),
        ),
      ),
    );
  }

  testWidgets('native LaTeX renders synchronously inside rich text', (
    tester,
  ) async {
    await pumpLatex(tester, r'x^2');

    expect(find.byType(LaTexT), findsOneWidget);
    expect(find.byType(FutureBuilder<void>), findsNothing);
    expect(find.text(r'x^2'), findsNothing);
  });

  testWidgets(r'LaTeX commands starting with \n are not treated as breaks', (
    tester,
  ) async {
    const math = r'\nabla \cdot \vec{E} = \frac{\rho}{\varepsilon_0}';
    await pumpLatex(tester, math);

    final renderer = tester.widget<LaTexT>(find.byType(LaTexT));
    expect(renderer.breakDelimiter, isNot(r'\n'));
    expect(renderer.laTeXCode.data, contains(math));
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(find.text(math), findsNothing);
  });

  testWidgets('multiline aligned equations stay one math expression', (
    tester,
  ) async {
    const math = r'''\begin{aligned}
f(x) &= \frac{1}{1 + e^{-x}} \\
f'(x) &= f(x)\left(1-f(x)\right)
\end{aligned}''';
    await pumpLatex(tester, math);

    final renderer = tester.widget<LaTexT>(find.byType(LaTexT));
    expect(renderer.laTeXCode.data, contains('\n'));
    expect(renderer.laTeXCode.data, contains(r'\\'));
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(find.text(math), findsNothing);
  });

  testWidgets('complex TeX does not depend on dollar delimiter recognition', (
    tester,
  ) async {
    const math =
        r'\left(\sum_{i=1}^{n}\frac{x_i^2}{\sqrt{1+x_i^2}}\right) + \text{cost }\$5';
    await pumpLatex(tester, math);

    final renderer = tester.widget<LaTexT>(find.byType(LaTexT));
    expect(renderer.delimiter, isNot(r'$'));
    expect(renderer.displayDelimiter, isNot(r'$$'));
    expect(renderer.laTeXCode.data, contains(r'\$5'));
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(find.text(math), findsNothing);
  });
}
