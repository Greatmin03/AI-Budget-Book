import 'package:flutter/material.dart';

import '../../../../core/constants/app_categories.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/di/injector.dart';
import '../../../merchants/domain/services/brand_learning_policy.dart';
import '../../../assets/domain/entities/account.dart';
import '../../../projects/domain/entities/project.dart';
import '../../domain/entities/transaction.dart';

/// 편집 결과. `null` 로 닫히면 취소.
class TransactionEditResult {
  const TransactionEditResult({
    required this.category,
    required this.subcategory,
    required this.brand,
    this.memo,
    this.displayName,
    this.tag,
    this.applyToBrand = false,
    this.reclassifyPast = false,
    this.delete = false,
    this.openSettlements = false,
    this.openAssetTransfer = false,
    this.projectId,
    this.projectChanged = false,
    this.amount,
    this.paymentDatetime,
    this.direction,
    this.accountId,
    this.accountName,
    this.accountChanged = false,
  });

  const TransactionEditResult.deleted()
      : category = '',
        subcategory = '',
        brand = '',
        memo = null,
        displayName = null,
        tag = null,
        applyToBrand = false,
        reclassifyPast = false,
        delete = true,
        openSettlements = false,
        openAssetTransfer = false,
        projectId = null,
        projectChanged = false,
        amount = null,
        paymentDatetime = null,
        direction = null,
        accountId = null,
        accountName = null,
        accountChanged = false;

  final String category;
  final String subcategory;
  final String brand;
  final String? memo;

  /// 목록에 표시할 이름(원본 거래명은 그대로 보존된다).
  final String? displayName;

  /// 태그. 예: `친구 대신 결제`
  final String? tag;

  /// 같은 브랜드 전체에 적용(= 브랜드 규칙 학습).
  final bool applyToBrand;

  /// 과거 거래까지 소급 재분류.
  final bool reclassifyPast;

  final bool delete;

  /// 저장 후 정산 시트를 열지.
  final bool openSettlements;

  /// 저장 후 자산 이동 시트를 열지.
  final bool openAssetTransfer;

  /// 지정한 프로젝트. null 은 "프로젝트 없음" 을 뜻할 수 있으므로
  /// 실제 변경 여부는 [projectChanged] 로 판단한다.
  final int? projectId;
  final bool projectChanged;

  /// 고친 금액. null 이면 그대로 둔다. 항상 양수다(부호는 [direction] 이 정한다).
  final int? amount;

  /// 고친 결제 일시(날짜 + 시간).
  final DateTime? paymentDatetime;

  /// 지출/수입 전환.
  final TransactionDirection? direction;

  /// 잔액을 반영할 계좌. null 은 "계좌 없음" 을 뜻할 수 있으므로
  /// 실제 변경 여부는 [accountChanged] 로 판단한다.
  final int? accountId;
  final String? accountName;
  final bool accountChanged;
}

/// 거래 수정 시트.
///
/// 가맹점 결제라면 여기서의 수정이 곧 **학습**이다.
/// 하지만 이체/송금 거래는 거래명이 상대방 이름이므로 학습하지 않고
/// **이번 거래에만** 적용한다. 학습 스위치는 비활성화되고 이유가 표시된다.
class TransactionEditSheet extends StatefulWidget {
  const TransactionEditSheet({required this.transaction, super.key});

  final Transaction transaction;

  @override
  State<TransactionEditSheet> createState() => _TransactionEditSheetState();
}

class _TransactionEditSheetState extends State<TransactionEditSheet> {
  static const BrandLearningPolicy _policy = BrandLearningPolicy();

  late String _category;
  late String _subcategory;
  late final TextEditingController _brandController;
  late final TextEditingController _memoController;
  late final TextEditingController _displayNameController;
  late final TextEditingController _tagController;

  bool _applyToBrand = false;
  bool _reclassifyPast = false;
  bool _showRawNotification = false;

  List<Project> _projects = const <Project>[];
  int? _projectId;
  bool _projectChanged = false;

  late final TextEditingController _amountController;
  late DateTime _paymentDatetime;
  late TransactionDirection _direction;

  List<Account> _accounts = const <Account>[];
  int? _accountId;
  String? _accountName;
  bool _accountChanged = false;

  @override
  void initState() {
    super.initState();
    final CategoryPair pair = CategoryTaxonomy.coerceFor(
      widget.transaction.category,
      widget.transaction.subcategory,
      isIncome: widget.transaction.isIncome,
    );
    _category = pair.category;
    _subcategory = pair.subcategory;
    _brandController = TextEditingController(text: widget.transaction.brand);
    _memoController =
        TextEditingController(text: widget.transaction.memo ?? '');
    _displayNameController =
        TextEditingController(text: widget.transaction.userDisplayName ?? '');
    _tagController = TextEditingController(text: widget.transaction.tag ?? '');

    // 학습이 안전한 경우에만 기본으로 켠다.
    _applyToBrand = _decision.defaultsOn;
    _projectId = widget.transaction.projectId;

    // 금액은 항상 양수로 편집한다. 부호는 지출/수입 선택이 정한다.
    // (취소 거래는 음수로 저장되므로 절대값을 보여 준다)
    _amountController = TextEditingController(
      text: widget.transaction.amount.abs().toString(),
    );
    _paymentDatetime = widget.transaction.paymentDatetime;
    _direction = widget.transaction.direction;
    _accountId = widget.transaction.accountId;
    _accountName = widget.transaction.account;

    _loadOptions();
  }

  Future<void> _loadOptions() async {
    final List<Project> projects =
        await Injector.instance.projects.selectable();
    final List<Account> accounts = await Injector.instance.accounts.findAll();
    if (!mounted) return;
    setState(() {
      _projects = projects;
      _accounts = accounts;
    });
  }

  /// 입력된 금액. 숫자가 아니면 null.
  int? get _editedAmount {
    final String digits =
        _amountController.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return null;
    final int? value = int.tryParse(digits);
    return (value == null || value <= 0) ? null : value;
  }

  bool get _amountIsValid => _editedAmount != null;

  Future<void> _pickDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _paymentDatetime,
      firstDate: DateTime(_paymentDatetime.year - 5),
      // 미래 거래도 있을 수 있으므로 오늘로 제한하지 않는다(예: 예약 결제).
      lastDate: DateTime(DateTime.now().year + 1, 12, 31),
    );
    if (picked == null) return;
    setState(() {
      _paymentDatetime = DateTime(
        picked.year,
        picked.month,
        picked.day,
        _paymentDatetime.hour,
        _paymentDatetime.minute,
      );
    });
  }

  Future<void> _pickTime() async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_paymentDatetime),
    );
    if (picked == null) return;
    setState(() {
      _paymentDatetime = DateTime(
        _paymentDatetime.year,
        _paymentDatetime.month,
        _paymentDatetime.day,
        picked.hour,
        picked.minute,
      );
    });
  }

  /// 현재 입력된 브랜드명 기준으로 학습 가능 여부를 다시 판단한다.
  BrandLearningDecision get _decision => _policy.evaluate(
        method: widget.transaction.method,
        brand: _brandController.text.trim().isEmpty
            ? widget.transaction.brand
            : _brandController.text.trim(),
        merchantRaw: widget.transaction.merchantRaw,
      );

  @override
  void dispose() {
    _brandController.dispose();
    _amountController.dispose();
    _memoController.dispose();
    _displayNameController.dispose();
    _tagController.dispose();
    super.dispose();
  }

  String? _trimmedOrNull(TextEditingController controller) {
    final String value = controller.text.trim();
    return value.isEmpty ? null : value;
  }

  void _submit({
    bool openSettlements = false,
    bool openAssetTransfer = false,
  }) {
    final BrandLearningDecision decision = _decision;
    Navigator.of(context).pop(
      TransactionEditResult(
        openSettlements: openSettlements,
        openAssetTransfer: openAssetTransfer,
        category: _category,
        subcategory: _subcategory,
        brand: _brandController.text.trim(),
        memo: _trimmedOrNull(_memoController),
        displayName: _trimmedOrNull(_displayNameController),
        tag: _trimmedOrNull(_tagController),
        projectId: _projectId,
        projectChanged: _projectChanged,
        amount: _editedAmount,
        paymentDatetime: _paymentDatetime,
        direction: _direction,
        accountId: _accountId,
        accountName: _accountName,
        accountChanged: _accountChanged,
        // 정책이 막았다면 무조건 false 로 보낸다(유즈케이스에서도 한 번 더 막힌다).
        applyToBrand: decision.isBlocked ? false : _applyToBrand,
        reclassifyPast: decision.isBlocked ? false : _reclassifyPast,
      ),
    );
  }

  Future<void> _confirmDelete() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('거래를 삭제할까요?'),
        content: const Text('삭제한 거래는 되돌릴 수 없습니다.'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    Navigator.of(context).pop(const TransactionEditResult.deleted());
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Transaction tx = widget.transaction;
    final BrandLearningDecision decision = _decision;

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: scheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ------------------------------------------------------- 요약
            Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Flexible(
                            child: Text(
                              tx.displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          _TypeChip(label: tx.method.label),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${Formatters.monthDay(tx.paymentDatetime)} '
                        '${Formatters.time(tx.paymentDatetime)}'
                        '${tx.cardName == null ? '' : '  ·  ${tx.cardName}'}',
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  Formatters.signedWon(tx.amount),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // ------------------------------------------------- 금액 / 지출·수입
            const _Label('금액'),
            const SizedBox(height: 6),
            Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: _amountController,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      isDense: true,
                      border: const OutlineInputBorder(),
                      suffixText: '원',
                      errorText: _amountIsValid ? null : '0보다 큰 금액',
                      helperText: tx.hasSettlements
                          ? '정산 ${Formatters.won(tx.settledAmount)}은 그대로 유지됩니다.'
                          : null,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SegmentedButton<TransactionDirection>(
              segments: const <ButtonSegment<TransactionDirection>>[
                ButtonSegment<TransactionDirection>(
                  value: TransactionDirection.expense,
                  label: Text('지출'),
                  icon: Icon(Icons.remove),
                ),
                ButtonSegment<TransactionDirection>(
                  value: TransactionDirection.income,
                  label: Text('수입'),
                  icon: Icon(Icons.add),
                ),
              ],
              selected: <TransactionDirection>{_direction},
              onSelectionChanged: (Set<TransactionDirection> value) =>
                  setState(() {
                _direction = value.first;
                // 방향이 바뀌면 분류 체계도 바뀐다.
                final CategoryPair fixed = CategoryTaxonomy.coerceFor(
                  _category,
                  _subcategory,
                  isIncome: _direction.isIncome,
                );
                _category = fixed.category;
                _subcategory = fixed.subcategory;
              }),
            ),
            const SizedBox(height: 20),

            // --------------------------------------------------- 날짜 / 시간
            const _Label('날짜 · 시간'),
            const SizedBox(height: 6),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickDate,
                    icon: const Icon(Icons.calendar_today_outlined, size: 16),
                    label: Text(Formatters.monthDay(_paymentDatetime)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickTime,
                    icon: const Icon(Icons.schedule_outlined, size: 16),
                    label: Text(Formatters.time(_paymentDatetime)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // ---------------------------------------------------------- 계좌
            const _Label('계좌 (잔액 반영)'),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                ChoiceChip(
                  label: const Text('반영 안 함'),
                  selected: _accountId == null,
                  onSelected: (_) => setState(() {
                    _accountId = null;
                    _accountName = null;
                    _accountChanged = true;
                  }),
                ),
                ..._accounts.map(
                  (Account account) => ChoiceChip(
                    label: Text(account.name),
                    selected: _accountId == account.id,
                    onSelected: (_) => setState(() {
                      _accountId = account.id;
                      _accountName = account.name;
                      _accountChanged = true;
                    }),
                  ),
                ),
              ],
            ),
            if (_accounts.isEmpty) ...<Widget>[
              const SizedBox(height: 6),
              Text(
                '자산 탭에서 계좌를 추가하면 여기에 나타납니다.',
                style: TextStyle(fontSize: 11, color: scheme.outline),
              ),
            ],
            const SizedBox(height: 20),

            // ------------------------------------------------------- 브랜드
            _Label(tx.isTransfer ? '브랜드 (이번 거래만)' : '브랜드'),
            const SizedBox(height: 6),
            TextField(
              controller: _brandController,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                isDense: true,
                border: const OutlineInputBorder(),
                hintText: tx.isTransfer ? '예: 메가커피' : '예: 메가커피',
                helperText: tx.isTransfer
                    ? '이체 거래의 브랜드는 이번 건에만 적용됩니다.'
                    : null,
                helperMaxLines: 2,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '원본 거래명: ${tx.merchantRaw}',
              style: TextStyle(fontSize: 11, color: scheme.outline),
            ),
            const SizedBox(height: 20),

            // --------------------------------------------------- 표시 이름
            const _Label('표시 이름'),
            const SizedBox(height: 6),
            TextField(
              controller: _displayNameController,
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
                hintText: '예: 친구 대신 결제',
                helperText: '목록에 보일 이름입니다. 원본 거래명은 그대로 보존됩니다.',
                helperMaxLines: 2,
              ),
            ),
            const SizedBox(height: 20),

            // ---------------------------------------------------- 카테고리
            const _Label('카테고리'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: CategoryTaxonomy.categoriesFor(
                isIncome: _direction.isIncome,
              ).map((String category) {
                final bool selected = category == _category;
                return ChoiceChip(
                  label: Text(category),
                  selected: selected,
                  selectedColor: CategoryColors.ofContext(context, category)
                      .withValues(alpha: 0.2),
                  onSelected: (_) {
                    setState(() {
                      _category = category;
                      // 카테고리가 바뀌면 서브카테고리도 유효한 값으로 맞춘다.
                      _subcategory =
                          CategoryTaxonomy.subcategoriesFor(
                        category,
                        isIncome: _direction.isIncome,
                      ).first;
                    });
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 20),

            const _Label('세부 항목'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: CategoryTaxonomy.subcategoriesFor(
                _category,
                isIncome: _direction.isIncome,
              )
                  .map((String sub) => ChoiceChip(
                        label: Text(sub),
                        selected: sub == _subcategory,
                        onSelected: (_) => setState(() => _subcategory = sub),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 20),

            // ------------------------------------------------------ 프로젝트
            if (_projects.isNotEmpty) ...<Widget>[
              const _Label('프로젝트'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _projects
                    .map(
                      (Project p) => ChoiceChip(
                        label: Text(p.name),
                        selected: _projectId == p.id,
                        onSelected: (_) => setState(() {
                          _projectId = _projectId == p.id ? null : p.id;
                          _projectChanged = true;
                        }),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 20),
            ],

            // -------------------------------------------------------- 태그
            const _Label('태그'),
            const SizedBox(height: 6),
            TextField(
              controller: _tagController,
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
                hintText: '예: 회비, 여행 경비',
              ),
            ),
            const SizedBox(height: 20),

            // -------------------------------------------------------- 메모
            const _Label('메모'),
            const SizedBox(height: 6),
            TextField(
              controller: _memoController,
              maxLines: 2,
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
                hintText: '선택 사항',
              ),
            ),
            const SizedBox(height: 16),

            // -------------------------------------------------------- 정산
            _SettlementSummary(
              transaction: tx,
              onTap: () => _submit(openSettlements: true),
            ),
            const SizedBox(height: 10),

            // ---------------------------------------------------- 자산 이동
            _AssetTransferRow(
              transaction: tx,
              onTap: () => _submit(openAssetTransfer: true),
            ),
            const SizedBox(height: 16),

            // -------------------------------------------------------- 학습
            _LearningSection(
              decision: decision,
              applyToBrand: _applyToBrand,
              reclassifyPast: _reclassifyPast,
              onApplyToBrandChanged: (bool value) => setState(() {
                _applyToBrand = value;
                if (!value) _reclassifyPast = false;
              }),
              onReclassifyPastChanged: (bool value) =>
                  setState(() => _reclassifyPast = value),
            ),
            const SizedBox(height: 8),

            // ---------------------------------------------------- 원본 알림
            TextButton.icon(
              onPressed: () => setState(
                () => _showRawNotification = !_showRawNotification,
              ),
              icon: Icon(
                _showRawNotification ? Icons.expand_less : Icons.expand_more,
                size: 18,
              ),
              label: const Text('원본 알림 보기'),
            ),
            if (_showRawNotification)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  tx.rawNotification,
                  style: const TextStyle(fontSize: 12, height: 1.4),
                ),
              ),
            const SizedBox(height: 20),

            Row(
              children: <Widget>[
                IconButton(
                  onPressed: _confirmDelete,
                  icon: const Icon(Icons.delete_outline),
                  color: scheme.error,
                  tooltip: '삭제',
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: _submit,
                    child: Text(
                      decision.isBlocked || !_applyToBrand
                          ? '이번 거래만 저장'
                          : '저장하고 학습',
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 학습 스위치 영역.
///
/// 정책이 금지한 경우 스위치를 비활성화하고 이유를 명확히 보여 준다.
/// 비활성화만 하고 이유를 숨기면 사용자는 앱이 고장난 줄 안다.
class _LearningSection extends StatelessWidget {
  const _LearningSection({
    required this.decision,
    required this.applyToBrand,
    required this.reclassifyPast,
    required this.onApplyToBrandChanged,
    required this.onReclassifyPastChanged,
  });

  final BrandLearningDecision decision;
  final bool applyToBrand;
  final bool reclassifyPast;
  final ValueChanged<bool> onApplyToBrandChanged;
  final ValueChanged<bool> onReclassifyPastChanged;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    if (decision.isBlocked) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: <Widget>[
            Icon(Icons.lock_outline, size: 18, color: scheme.onSurfaceVariant),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    decision.reason ?? '자동 학습할 수 없는 거래입니다.',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (decision.detail != null) ...<Widget>[
                    const SizedBox(height: 3),
                    Text(
                      decision.detail!,
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.4,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const SizedBox(height: 3),
                  Text(
                    '이번 거래에만 적용됩니다.',
                    style: TextStyle(fontSize: 11, color: scheme.primary),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: <Widget>[
        if (decision.isDiscouraged)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: scheme.tertiaryContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: <Widget>[
                Icon(
                  Icons.warning_amber_outlined,
                  size: 15,
                  color: scheme.onTertiaryContainer,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${decision.reason ?? ''} ${decision.detail ?? ''}'.trim(),
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.4,
                      color: scheme.onTertiaryContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),
        SwitchListTile(
          value: applyToBrand,
          onChanged: onApplyToBrandChanged,
          contentPadding: EdgeInsets.zero,
          title: const Text('이 변경을 앞으로도 자동 적용'),
          subtitle: const Text(
            '같은 브랜드의 다른 지점도 자동으로 이 분류가 적용됩니다.',
            style: TextStyle(fontSize: 12),
          ),
        ),
        SwitchListTile(
          value: reclassifyPast,
          onChanged: applyToBrand ? onReclassifyPastChanged : null,
          contentPadding: EdgeInsets.zero,
          title: const Text('과거 거래에도 소급 적용'),
          subtitle: const Text(
            '이미 기록된 같은 브랜드 거래의 분류도 함께 바꿉니다.',
            style: TextStyle(fontSize: 12),
          ),
        ),
      ],
    );
  }
}

/// 정산(더치페이) 요약 + 관리 화면 진입.
///
/// 금액 자체는 여기서 고칠 수 없다. 30,000원 결제를 10,000원으로 바꾸는 대신
/// "20,000원을 돌려받았다" 를 기록하는 것이 이 앱의 방식이다.
class _SettlementSummary extends StatelessWidget {
  const _SettlementSummary({required this.transaction, required this.onTap});

  final Transaction transaction;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final bool has = transaction.hasSettlements;

    return Material(
      color: has ? scheme.tertiaryContainer : scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: <Widget>[
              Icon(
                Icons.group_outlined,
                size: 18,
                color: has ? scheme.onTertiaryContainer : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      has ? '정산 · 실제 부담 ${Formatters.signedWon(transaction.netAmount)}' : '더치페이 정산',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: has ? scheme.onTertiaryContainer : null,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      has
                          ? '${Formatters.won(transaction.settledAmount)} 돌려받음'
                          : '나눠 낸 금액이 있으면 여기에 기록하세요. '
                              '결제 금액은 그대로 유지됩니다.',
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.3,
                        color: has
                            ? scheme.onTertiaryContainer
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: has ? scheme.onTertiaryContainer : scheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 자산 이동 표시 진입.
class _AssetTransferRow extends StatelessWidget {
  const _AssetTransferRow({required this.transaction, required this.onTap});

  final Transaction transaction;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final bool marked = transaction.isAssetTransfer;

    return Material(
      color: marked ? scheme.secondaryContainer : scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: <Widget>[
              Icon(
                Icons.savings_outlined,
                size: 18,
                color: marked
                    ? scheme.onSecondaryContainer
                    : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      marked ? '자산 이동 (소비 통계 제외)' : '자산 이동으로 표시',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: marked ? scheme.onSecondaryContainer : null,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      marked
                          ? '이 거래는 소비가 아니라 계좌 이동으로 집계됩니다.'
                          : '적금 납입처럼 소비가 아닌 이동이면 여기서 표시하세요.',
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.3,
                        color: marked
                            ? scheme.onSecondaryContainer
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: marked
                    ? scheme.onSecondaryContainer
                    : scheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TypeChip extends StatelessWidget {
  const _TypeChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}
