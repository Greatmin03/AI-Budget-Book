import 'package:flutter/material.dart';

/// 앱 테마와 카테고리 색상.
///
/// 의도적으로 서브 테마를 최소한만 지정한다.
/// (`CardTheme`, `AppBarTheme` 등은 Flutter 버전에 따라 타입이 바뀌어 왔다.
///  버전 간 호환을 위해 위젯 단위 스타일링을 선호한다.)
class AppTheme {
  const AppTheme._();

  static const Color _seed = Color(0xFF2E6BE6);

  static ThemeData light() => _base(Brightness.light);

  static ThemeData dark() => _base(Brightness.dark);

  static ThemeData _base(Brightness brightness) {
    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: brightness,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// 카드 스타일을 한 곳에서 관리한다.
  static BoxDecoration cardDecoration(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return BoxDecoration(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: scheme.outlineVariant, width: 1),
    );
  }
}

/// 수입 / 지출 / 자산이동 의미색.
///
/// 카테고리 색과 **역할이 다르다.** 카테고리는 "무엇에 썼나"(identity)이고
/// 이쪽은 "들어왔나 나갔나"(polarity)다. 그래서 파랑↔빨강 양극 쌍을 쓴다.
/// 한국 금융 앱 관례(입금 파랑 / 출금 빨강)와도 일치한다.
///
/// 검증기 결과(각 모드의 카드 배경 기준):
///  - 라이트 `#f4f3fa`: CVD 최악 ΔE 21.6(protan), 일반시야 32.3, 대비 3:1 이상
///  - 다크   `#1a1b21`: CVD 최악 ΔE 19.2(protan), 일반시야 29.0, 대비 3:1 이상
///
/// 값이 `교통`/`교육` 카테고리 색과 같은 것은 의도적이다. 두 팔레트는 같은
/// 차트에 동시에 나오지 않으며, 이쪽은 **항상 `수입`/`지출` 글자와 부호를
/// 함께 표시**하므로 색만으로 구분하지 않는다.
class FlowColors {
  const FlowColors._();

  static const Color _incomeLight = Color(0xFF2A78D6);
  static const Color _incomeDark = Color(0xFF3987E5);
  static const Color _expenseLight = Color(0xFFE34948);
  static const Color _expenseDark = Color(0xFFE66767);

  /// 자산 이동은 "사라진 돈" 이 아니므로 양극 중 어느 쪽도 아니다.
  /// 중립색을 쓴다(`기타` 와 같은 예약 중립색).
  static const Color _assetLight = Color(0xFF9AA0A6);
  static const Color _assetDark = Color(0xFF8B8B84);

  static Color income(BuildContext context) =>
      _isDark(context) ? _incomeDark : _incomeLight;

  static Color expense(BuildContext context) =>
      _isDark(context) ? _expenseDark : _expenseLight;

  static Color assetTransfer(BuildContext context) =>
      _isDark(context) ? _assetDark : _assetLight;

  /// 순증가 표시색. 늘었으면 수입색, 줄었으면 지출색.
  static Color net(BuildContext context, int amount) =>
      amount >= 0 ? income(context) : expense(context);

  static bool _isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;
}

/// 카테고리별 고정 색상.
///
/// 차트와 목록에서 같은 카테고리가 항상 같은 색으로 보여야 하므로
/// 이름 -> 색을 고정한다. **순위(금액 크기)가 아니라 항목에 색이 붙는다.**
/// 필터를 걸어 항목 수가 줄어도 남은 항목의 색은 바뀌지 않는다.
///
/// 라이트/다크는 자동 반전이 아니라 각각 별도로 선택된 값이다.
///
/// 이 팔레트는 색각 이상(protanopia/deuteranopia/tritanopia) 분리도와
/// 명도/채도 하한을 검증기로 통과한 조합이다(인접쌍 기준).
///  - 라이트: 최악 인접쌍 CVD ΔE 9.2, 일반시야 ΔE 19.6
///  - 다크  : 최악 인접쌍 CVD ΔE 9.4, 일반시야 ΔE 19.3
///
/// 순서를 바꾸거나 색을 추가하면 인접쌍 분리도가 깨질 수 있으므로,
/// 수정 시에는 반드시 검증을 다시 수행한다.
///
/// 라이트 모드에서 생활/주거·통신/의료·건강 3색은 배경 대비 3:1 미만이다.
/// 따라서 차트는 **항상 이름 라벨(범례/목록)을 함께 제공해야 한다**.
/// 색만으로 정보를 전달하지 않는다.
class CategoryColors {
  const CategoryColors._();

  /// '기타'(Other)에 쓰는 예약 중립색. 다른 카테고리에 재사용하지 않는다.
  static const Color _otherLight = Color(0xFF9AA0A6);
  static const Color _otherDark = Color(0xFF8B8B84);

  static const Map<String, Color> _light = <String, Color>{
    '식비': Color(0xFFEB6834),
    '생활': Color(0xFF1BAF7A),
    '교통': Color(0xFF2A78D6),
    '주거/통신': Color(0xFFEDA100),
    '의료/건강': Color(0xFFE87BA4),
    '문화/여가': Color(0xFF008300),
    '쇼핑': Color(0xFF4A3AA7),
    '교육': Color(0xFFE34948),
    '금융': Color(0xFF0E8FA0),
    '기타': _otherLight,
  };

  static const Map<String, Color> _dark = <String, Color>{
    '식비': Color(0xFFD95926),
    '생활': Color(0xFF199E70),
    '교통': Color(0xFF3987E5),
    '주거/통신': Color(0xFFC98500),
    '의료/건강': Color(0xFFD55181),
    '문화/여가': Color(0xFF008300),
    '쇼핑': Color(0xFF9085E9),
    '교육': Color(0xFFE66767),
    '금융': Color(0xFF1795A8),
    '기타': _otherDark,
  };

  static Color of(String category, Brightness brightness) {
    final bool isDark = brightness == Brightness.dark;
    final Map<String, Color> map = isDark ? _dark : _light;
    return map[category] ?? (isDark ? _otherDark : _otherLight);
  }

  /// 위젯에서 쓰는 단축형.
  static Color ofContext(BuildContext context, String category) =>
      of(category, Theme.of(context).brightness);

  /// 서브카테고리는 상위 카테고리 색의 명도만 달리해서 쓴다.
  ///
  /// 같은 카테고리 안의 계열임을 보이기 위한 것이므로, 서브카테고리끼리는
  /// 색만으로 구분하지 않는다(항상 이름 라벨을 함께 노출한다).
  static Color forSubcategory(
    String? parentCategory,
    int index,
    Brightness brightness,
  ) {
    final HSLColor hsl =
        HSLColor.fromColor(of(parentCategory ?? '기타', brightness));
    // clamp 의 정적 반환형이 num 이므로 명시적으로 double 로 만든다.
    final double lightness =
        (hsl.lightness + (index % 4) * 0.08).clamp(0.28, 0.74).toDouble();
    return hsl.withLightness(lightness).toColor();
  }
}
