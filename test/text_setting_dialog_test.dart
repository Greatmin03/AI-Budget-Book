import 'package:budget_book/features/settings/presentation/widgets/text_setting_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 설정 값 입력 다이얼로그.
///
/// 실기기에서 Ollama 주소 / 카카오 API 키를 입력하면 아래 크래시가 났다.
///
/// ```
/// Failed assertion: '_dependents.isEmpty': is not true
/// ```
///
/// 원인은 `showDialog(...).whenComplete(controller.dispose)` 였다.
/// `showDialog` 의 Future 는 라우트가 pop 되는 즉시 완료되지만 다이얼로그
/// 위젯 트리는 퇴장 애니메이션 동안 아직 mount 되어 있다. 그 시점에 컨트롤러를
/// dispose 하면 살아 있는 `TextField` 가 죽은 컨트롤러를 참조하고,
/// teardown 순서가 깨져 `InheritedElement` 가 dependent 를 남긴 채
/// deactivate 된다.
///
/// **핵심은 `pumpAndSettle` 로 퇴장 애니메이션을 끝까지 돌리는 것**이다.
/// pop 직후만 확인하면 이 버그를 놓친다.
void main() {
  /// 다이얼로그를 열고 값을 반환받는 최소 화면.
  Future<String?> openAndAct(
    WidgetTester tester,
    Future<void> Function(WidgetTester tester) act,
  ) async {
    String? result;
    bool returned = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (BuildContext context) => TextButton(
              onPressed: () async {
                result = await showTextSettingDialog(
                  context: context,
                  title: '카카오 REST API 키',
                  initialValue: 'old-value',
                  helperText: '두 줄짜리\n도움말',
                );
                returned = true;
              },
              child: const Text('열기'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();

    await act(tester);

    // 퇴장 애니메이션이 완전히 끝날 때까지 돌린다. 여기서 크래시가 났다.
    await tester.pumpAndSettle();
    expect(returned, isTrue, reason: '다이얼로그가 값을 반환해야 한다');
    return result;
  }

  testWidgets('저장을 누르면 입력값을 반환하고 크래시하지 않는다',
      (WidgetTester tester) async {
    final String? value = await openAndAct(tester, (WidgetTester tester) async {
      await tester.enterText(find.byType(TextField), 'new-api-key');
      await tester.tap(find.text('저장'));
    });

    expect(tester.takeException(), isNull);
    expect(value, 'new-api-key');
  });

  testWidgets('취소를 누르면 null 을 반환하고 크래시하지 않는다',
      (WidgetTester tester) async {
    final String? value = await openAndAct(tester, (WidgetTester tester) async {
      await tester.enterText(find.byType(TextField), '버려질 입력');
      await tester.tap(find.text('취소'));
    });

    expect(tester.takeException(), isNull);
    expect(value, isNull);
  });

  testWidgets('키보드 확인(onSubmitted)으로도 저장된다',
      (WidgetTester tester) async {
    final String? value = await openAndAct(tester, (WidgetTester tester) async {
      await tester.enterText(find.byType(TextField), 'submitted-key');
      await tester.testTextInput.receiveAction(TextInputAction.done);
    });

    expect(tester.takeException(), isNull);
    expect(value, 'submitted-key');
  });

  testWidgets('초기값이 그대로 채워진다', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (BuildContext context) => TextButton(
              onPressed: () => showTextSettingDialog(
                context: context,
                title: 'Ollama 주소',
                initialValue: 'http://10.0.2.2:11434',
              ),
              child: const Text('열기'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();

    expect(find.text('http://10.0.2.2:11434'), findsOneWidget);
    expect(find.text('Ollama 주소'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('연달아 열고 닫아도 컨트롤러가 어긋나지 않는다',
      (WidgetTester tester) async {
    // 설정 화면에서 주소 -> 모델 -> 키를 연속으로 고치는 상황.
    for (int i = 0; i < 3; i++) {
      final String? value =
          await openAndAct(tester, (WidgetTester tester) async {
        await tester.enterText(find.byType(TextField), 'value-$i');
        await tester.tap(find.text('저장'));
      });
      expect(tester.takeException(), isNull);
      expect(value, 'value-$i');
    }
  });
}
