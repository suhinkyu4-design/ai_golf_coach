import 'package:flutter_test/flutter_test.dart';
import 'package:ai_golf_coach/main.dart';

void main() {
  testWidgets('앱 기본 화면이 렌더링된다', (WidgetTester tester) async {
    await tester.pumpWidget(const AiGolfCoachApp());
    await tester.pumpAndSettle();

    expect(find.text('GOLF / COACH'), findsOneWidget);
    expect(find.textContaining('새 스윙 기록'), findsOneWidget);
  });
}
