import 'package:flutter_test/flutter_test.dart';

import 'package:hermes_app/main.dart';

void main() {
  testWidgets('App 渲染出标题栏', (WidgetTester tester) async {
    await tester.pumpWidget(const HermesApp());
    expect(find.text('Hermes 控制台'), findsOneWidget);
  });
}
