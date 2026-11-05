import 'package:flutter_test/flutter_test.dart';
import 'package:truthguard_ai/main.dart';

void main() {
  testWidgets('TruthGuard AI app loads', (WidgetTester tester) async {
    await tester.pumpWidget(const TruthGuardApp());

    expect(find.text('TruthGuard AI'), findsOneWidget);
    expect(find.text('Verify before you share'), findsOneWidget);
  });
}
