import 'package:flutter/material.dart';

import '../../../../core/constants/app_categories.dart';
import '../../../../core/di/injector.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/formatters.dart';
import '../../../assets/domain/entities/account.dart';
import '../../../projects/domain/entities/project.dart';
import '../../domain/entities/transaction.dart';

/// 거래 직접 추가.
///
/// 자동으로 수집되지 않는 거래(현금, 중고거래, 누락분)를 입력한다.
class ManualEntryScreen extends StatefulWidget {
  const ManualEntryScreen({super.key});

  @override
  State<ManualEntryScreen> createState() => _ManualEntryScreenState();
}

class _ManualEntryScreenState extends State<ManualEntryScreen> {
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _brandController = TextEditingController();
  final TextEditingController _memoController = TextEditingController();

  DateTime _date = DateTime.now();
  TransactionDirection _direction = TransactionDirection.expense;
  String _category = CategoryTaxonomy.categories.first;
  late String _subcategory =
      CategoryTaxonomy.subcategoriesOf(_category).first;
  String? _account;

  /// 잔액에 반영할 계좌. 등록된 계좌를 골랐을 때만 값이 있다.
  /// (`현금` 처럼 계좌로 등록되지 않은 수단은 잔액에 반영하지 않는다)
  int? _accountId;
  int? _projectId;

  List<Account> _accounts = const <Account>[];
  List<Project> _projects = const <Project>[];
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadOptions();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _brandController.dispose();
    _memoController.dispose();
    super.dispose();
  }

  Future<void> _loadOptions() async {
    final List<Account> accounts = await Injector.instance.accounts.findAll();
    final List<Project> projects =
        await Injector.instance.projects.selectable();
    if (!mounted) return;
    setState(() {
      _accounts = accounts;
      _projects = projects;
    });
  }

  int? get _amount {
    final String digits = _amountController.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return null;
    return int.tryParse(digits);
  }

  bool get _canSave =>
      (_amount ?? 0) > 0 && _brandController.text.trim().isNotEmpty;

  Future<void> _pickDate() async {
    final DateTime now = DateTime.now();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
    );
    if (picked == null) return;
    // 시각은 유지하고 날짜만 바꾼다.
    setState(() {
      _date = DateTime(
        picked.year,
        picked.month,
        picked.day,
        _date.hour,
        _date.minute,
      );
    });
  }

  Future<void> _save() async {
    final int? amount = _amount;
    if (amount == null || amount <= 0) return;

    setState(() => _isSaving = true);
    try {
      await Injector.instance.addManualTransaction(
        date: _date,
        amount: amount,
        direction: _direction,
        category: _category,
        subcategory: _subcategory,
        brand: _brandController.text,
        account: _account,
        accountId: _accountId,
        memo: _memoController.text,
        projectId: _projectId,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on Object catch (e, stack) {
      AppLogger.e('직접 입력 저장 실패', e, stack);
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('저장하지 못했습니다: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final bool isIncome = _direction.isIncome;

    return Scaffold(
      appBar: AppBar(title: const Text('직접 추가')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: <Widget>[
          // ------------------------------------------------------ 지출/수입
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
              // 지출과 수입은 분류 체계가 다르다. 방향을 바꾸면 맞는 체계의
              // 첫 항목으로 초기화한다(없는 카테고리가 남아 있으면 안 된다).
              _category = CategoryTaxonomy.categoriesFor(
                isIncome: _direction.isIncome,
              ).first;
              _subcategory = CategoryTaxonomy.subcategoriesFor(
                _category,
                isIncome: _direction.isIncome,
              ).first;
            }),
          ),
          if (isIncome) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              '수입은 소비 통계에 포함되지 않습니다.',
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
            ),
          ],
          const SizedBox(height: 20),

          // ---------------------------------------------------------- 금액
          const _Label('금액'),
          const SizedBox(height: 6),
          TextField(
            controller: _amountController,
            keyboardType: TextInputType.number,
            autofocus: true,
            onChanged: (_) => setState(() {}),
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              suffixText: '원',
              hintText: '0',
              helperText: _amount == null ? null : Formatters.won(_amount!),
            ),
          ),
          const SizedBox(height: 20),

          // ---------------------------------------------------------- 날짜
          const _Label('날짜'),
          const SizedBox(height: 6),
          OutlinedButton.icon(
            onPressed: _pickDate,
            icon: const Icon(Icons.calendar_today_outlined, size: 18),
            label: Text(
              '${Formatters.yearMonthDay(_date)} '
              '(${Formatters.monthDay(_date)})',
            ),
          ),
          const SizedBox(height: 20),

          // ---------------------------------------------------------- 내용
          const _Label('내용'),
          const SizedBox(height: 6),
          TextField(
            controller: _brandController,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              isDense: true,
              hintText: isIncome ? '예: 급여, 용돈' : '예: 스타벅스, 중고거래',
            ),
          ),
          const SizedBox(height: 20),

          // ------------------------------------------------------ 카테고리
          const _Label('카테고리'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: CategoryTaxonomy.categoriesFor(isIncome: isIncome)
                .map((String category) {
              return ChoiceChip(
                label: Text(category),
                selected: category == _category,
                selectedColor:
                    CategoryColors.ofContext(context, category).withValues(alpha: 0.2),
                onSelected: (_) => setState(() {
                  _category = category;
                  _subcategory =
                      CategoryTaxonomy.subcategoriesFor(
                    category,
                    isIncome: isIncome,
                  ).first;
                }),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),

          const _Label('세부항목'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: CategoryTaxonomy.subcategoriesFor(
              _category,
              isIncome: isIncome,
            )
                .map((String sub) => ChoiceChip(
                      label: Text(sub),
                      selected: sub == _subcategory,
                      onSelected: (_) => setState(() => _subcategory = sub),
                    ))
                .toList(),
          ),
          const SizedBox(height: 20),

          // ---------------------------------------------------------- 계좌
          const _Label('계좌 · 수단'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              ChoiceChip(
                label: const Text('현금'),
                selected: _account == '현금',
                onSelected: (_) => setState(() {
                  final bool wasSelected = _account == '현금';
                  _account = wasSelected ? null : '현금';
                  // 등록된 계좌가 아니므로 잔액에는 반영하지 않는다.
                  _accountId = null;
                }),
              ),
              ..._accounts.map(
                (Account account) => ChoiceChip(
                  label: Text(account.name),
                  selected: _accountId == account.id,
                  onSelected: (_) => setState(() {
                    final bool wasSelected = _accountId == account.id;
                    _account = wasSelected ? null : account.name;
                    _accountId = wasSelected ? null : account.id;
                  }),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _accounts.isEmpty
                ? '자산 탭에서 계좌를 추가하면 여기에 나타나고, 잔액에 자동 반영됩니다.'
                : _accountId == null
                    ? '계좌를 고르면 그 계좌 잔액에 자동 반영됩니다.'
                    : '${_account!} 잔액이 '
                        '${isIncome ? '늘어납니다' : '줄어듭니다'}.',
            style: TextStyle(fontSize: 11, color: scheme.outline),
          ),
          const SizedBox(height: 20),

          // -------------------------------------------------------- 프로젝트
          if (_projects.isNotEmpty) ...<Widget>[
            const _Label('프로젝트 (선택)'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _projects
                  .map(
                    (Project p) => ChoiceChip(
                      label: Text(p.name),
                      selected: _projectId == p.id,
                      onSelected: (_) => setState(
                        () => _projectId = _projectId == p.id ? null : p.id,
                      ),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 20),
          ],

          // ---------------------------------------------------------- 메모
          const _Label('메모'),
          const SizedBox(height: 6),
          TextField(
            controller: _memoController,
            maxLines: 2,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
              hintText: '선택 사항',
            ),
          ),
          const SizedBox(height: 28),

          SizedBox(
            height: 48,
            child: FilledButton(
              onPressed: (_canSave && !_isSaving) ? _save : null,
              child: Text(_isSaving ? '저장 중...' : '저장'),
            ),
          ),
        ],
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
