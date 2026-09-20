import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:ai_golf_coach/main.dart';
import 'package:ai_golf_coach/providers/swing_provider.dart';

void main() {
  testWidgets('앱 기본 화면이 렌더링된다', (WidgetTester tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => SwingProvider(),
        child: const AiGolfCoachApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('AI 온디바이스 골프 코치'), findsOneWidget);
    expect(find.textContaining('새 스윙 분석 시작'), findsAtLeastNWidgets(1));
  });
}
