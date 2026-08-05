import 'package:flutter/material.dart';

/// 값 하나를 입력받는 공통 다이얼로그.
///
/// 취소하면 `null` 을 반환한다.
Future<String?> showTextSettingDialog({
  required BuildContext context,
  required String title,
  required String initialValue,
  String? helperText,
  TextInputType? keyboardType,
}) {
  return showDialog<String>(
    context: context,
    builder: (BuildContext context) => _TextSettingDialog(
      title: title,
      initialValue: initialValue,
      helperText: helperText,
      keyboardType: keyboardType,
    ),
  );
}

/// 입력 컨트롤러를 **위젯이 직접 소유**하는 다이얼로그.
///
/// ## 왜 StatefulWidget 인가
/// 이전에는 함수 안에서 컨트롤러를 만들고
/// `showDialog(...).whenComplete(controller.dispose)` 로 정리했다.
/// 이 방식은 실제 기기에서 다음 크래시를 냈다.
///
/// ```
/// Failed assertion: '_dependents.isEmpty': is not true
/// ```
///
/// `showDialog` 의 Future 는 라우트가 pop 되는 **즉시** 완료되지만, 다이얼로그
/// 위젯 트리는 퇴장 애니메이션이 끝날 때까지 아직 살아 있다. 그 시점에
/// 컨트롤러를 dispose 하면 아직 mount 되어 있는 `TextField`(내부 `EditableText`)가
/// 이미 죽은 컨트롤러를 참조하게 되고, teardown 순서가 깨져
/// `InheritedElement` 가 dependent 를 남긴 채 deactivate 된다.
///
/// `State.dispose()` 는 **위젯이 실제로 unmount 될 때** 호출되므로 순서가 항상
/// 맞다. 컨트롤러의 수명은 그것을 쓰는 위젯의 수명과 같아야 한다.
class _TextSettingDialog extends StatefulWidget {
  const _TextSettingDialog({
    required this.title,
    required this.initialValue,
    this.helperText,
    this.keyboardType,
  });

  final String title;
  final String initialValue;
  final String? helperText;
  final TextInputType? keyboardType;

  @override
  State<_TextSettingDialog> createState() => _TextSettingDialogState();
}

class _TextSettingDialogState extends State<_TextSettingDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialValue);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(_controller.text);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: widget.keyboardType,
        decoration: InputDecoration(
          helperText: widget.helperText,
          helperMaxLines: 3,
          border: const OutlineInputBorder(),
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('취소'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('저장'),
        ),
      ],
    );
  }
}
