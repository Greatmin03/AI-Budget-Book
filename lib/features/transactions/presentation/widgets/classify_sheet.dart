import 'package:flutter/material.dart';

import '../../../../core/constants/app_categories.dart';
import '../../../../core/di/injector.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/formatters.dart';
import '../../../classification/domain/entities/brand_metadata.dart';
import '../../../merchants/domain/services/brand_learning_policy.dart';
import '../../domain/entities/transaction.dart';

/// 분류 결과.
class ClassifyResult {
  const ClassifyResult({
    required this.brand,
    required this.category,
    required this.subcategory,
    this.tag,
    this.learnBrand = true,
    this.applyToPast = true,
  });

  final String brand;
  final String category;
  final String subcategory;

  /// 태그(주로 이체 거래의 목적을 남기는 데 쓴다).
  final String? tag;

  /// 이 브랜드를 앞으로도 자동 적용할지.
  ///
  /// 이체/송금 거래에서는 항상 false 다.
  final bool learnBrand;

  /// 이미 기록된 같은 브랜드 거래도 함께 정리할지.
  final bool applyToPast;
}

/// 처음 보는 브랜드의 카테고리를 고르는 시트.
///
/// 수정용 [TransactionEditSheet] 와 달리 목적이 하나뿐이다: **분류 확정**.
/// 그래서 메모/삭제 같은 요소를 두지 않고 카테고리 선택에만 집중한다.
class ClassifySheet extends StatefulWidget {
  const ClassifySheet({required this.transaction, super.key});

  final Transaction transaction;

  @override
  State<ClassifySheet> createState() => _ClassifySheetState();
}

class _ClassifySheetState extends State<ClassifySheet> {
  static const BrandLearningPolicy _policy = BrandLearningPolicy();

  late String _category;
  late String _subcategory;
  late final TextEditingController _brandController;
  late final TextEditingController _tagController;
  bool _learnBrand = true;
  bool _applyToPast = true;

  /// 규칙 기반 추천이 있었는지(있으면 미리 선택해 둔다).
  late final bool _hadSuggestion;

  bool _isLooking = false;

  /// 업종 조회 결과 한 줄. 무엇을 근거로 채웠는지 보여 준다.
  String? _lookupMessage;

  @override
  void initState() {
    super.initState();
    final CategoryPair pair = CategoryTaxonomy.coerce(
      widget.transaction.category,
      widget.transaction.subcategory,
    );
    _hadSuggestion = pair.subcategory != '미분류';
    _category = pair.category;
    _subcategory = pair.subcategory;
    _brandController = TextEditingController(text: widget.transaction.brand);
    _tagController = TextEditingController(text: widget.transaction.tag ?? '');
    _learnBrand = _decision.defaultsOn;
  }

  /// 현재 입력된 브랜드명 기준 학습 가능 여부.
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
    _tagController.dispose();
    super.dispose();
  }

  /// 카카오 장소 API 로 업종을 **다시** 조회한다.
  ///
  /// 수집 시점에만 조회하면, 그때 실패한 거래는 영영 미분류로 남는다.
  /// (이체로 잘못 판정돼 조회 자체가 막혔던 거래가 실제로 그랬다)
  ///
  /// 결과는 **바로 저장하지 않고 화면에만 채운다.** 자동 분류가 틀릴 수도
  /// 있으므로 사용자가 보고 확정한다.
  Future<void> _lookupIndustry() async {
    final String brand = _brandController.text.trim().isEmpty
        ? widget.transaction.brand
        : _brandController.text.trim();

    setState(() {
      _isLooking = true;
      _lookupMessage = null;
    });

    try {
      final BrandMetadata? found =
          await Injector.instance.lookupBrandIndustry(brand);
      if (!mounted) return;

      if (found == null || !found.isUsable) {
        setState(() => _lookupMessage = '업종을 찾지 못했습니다. 직접 골라 주세요.');
        return;
      }

      setState(() {
        _category = found.category!;
        _subcategory = found.subcategory!;
        _lookupMessage = '${found.industry ?? '업종'} → '
            '${found.category}/${found.subcategory}';
      });
    } on Object catch (e, stack) {
      AppLogger.e('업종 재조회 실패', e, stack);
      if (!mounted) return;
      setState(() => _lookupMessage = '조회하지 못했습니다. ($e)');
    } finally {
      if (mounted) setState(() => _isLooking = false);
    }
  }

  bool get _canSubmit =>
      _brandController.text.trim().isNotEmpty && _subcategory != '미분류';

  void _submit() {
    final BrandLearningDecision decision = _decision;
    final String tag = _tagController.text.trim();
    Navigator.of(context).pop(
      ClassifyResult(
        brand: _brandController.text.trim(),
        category: _category,
        subcategory: _subcategory,
        tag: tag.isEmpty ? null : tag,
        learnBrand: decision.isBlocked ? false : _learnBrand,
        applyToPast: decision.isBlocked ? false : _applyToPast,
      ),
    );
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
            const SizedBox(height: 18),

            Row(
              children: <Widget>[
                Flexible(
                  child: Text(
                    tx.merchantRaw,
                    maxLines: 2,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    tx.method.label,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${Formatters.signedWon(tx.amount)} · '
              '${Formatters.monthDay(tx.paymentDatetime)} '
              '${Formatters.time(tx.paymentDatetime)}'
              '${tx.cardName == null ? '' : ' · ${tx.cardName}'}',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 20),

            // ------------------------------------------------------- 브랜드명
            Text(
              '브랜드명',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _brandController,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
                helperText: '지점명을 뗀 대표 이름으로 두면 지점이 달라도 같은 브랜드로 묶입니다.',
                helperMaxLines: 2,
              ),
            ),
            const SizedBox(height: 20),

            if (_hadSuggestion) ...<Widget>[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: scheme.tertiaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: <Widget>[
                    Icon(
                      Icons.lightbulb_outline,
                      size: 15,
                      color: scheme.onTertiaryContainer,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '가맹점 이름으로 추측한 분류를 미리 선택해 두었습니다. '
                        '맞다면 그대로 저장하세요.',
                        style: TextStyle(
                          fontSize: 11,
                          color: scheme.onTertiaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
            ],

            // ------------------------------------------------- 업종 재조회
            //
            // 수집 시점에만 조회하면 그때 실패한 거래는 영영 미분류로 남는다.
            // 여기서 다시 부를 수 있어야 한다.
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isLooking ? null : _lookupIndustry,
                    icon: _isLooking
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.travel_explore_outlined, size: 18),
                    label: const Text('업종 다시 조회'),
                  ),
                ),
              ],
            ),
            if (_lookupMessage != null) ...<Widget>[
              const SizedBox(height: 6),
              Text(
                _lookupMessage!,
                style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
              ),
            ],
            const SizedBox(height: 16),

            // ----------------------------------------------------- 카테고리
            Text(
              '카테고리',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: CategoryTaxonomy.categories.map((String category) {
                return ChoiceChip(
                  label: Text(category),
                  selected: category == _category,
                  selectedColor:
                      CategoryColors.ofContext(context, category)
                          .withValues(alpha: 0.2),
                  onSelected: (_) => setState(() {
                    _category = category;
                    _subcategory =
                        CategoryTaxonomy.subcategoriesOf(category).first;
                  }),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),

            Text(
              '세부 항목',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: CategoryTaxonomy.subcategoriesOf(_category)
                  .map((String sub) => ChoiceChip(
                        label: Text(sub),
                        selected: sub == _subcategory,
                        onSelected: (_) => setState(() => _subcategory = sub),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 16),

            // -------------------------------------------------------- 태그
            Text(
              '태그 (선택)',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _tagController,
              decoration: InputDecoration(
                isDense: true,
                border: const OutlineInputBorder(),
                hintText: tx.isTransfer ? '예: 친구 대신 결제, 회비' : '예: 여행 경비',
                helperText: tx.isTransfer
                    ? '이체는 목적이 매번 달라지므로 태그로 남겨 두면 나중에 찾기 쉽습니다.'
                    : null,
                helperMaxLines: 2,
              ),
            ),
            const SizedBox(height: 16),

            // -------------------------------------------------------- 학습
            if (decision.isBlocked)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: <Widget>[
                    Icon(
                      Icons.lock_outline,
                      size: 18,
                      color: scheme.onSurfaceVariant,
                    ),
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
                        ],
                      ),
                    ),
                  ],
                ),
              )
            else ...<Widget>[
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
                          '${decision.reason ?? ''} ${decision.detail ?? ''}'
                              .trim(),
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
                value: _learnBrand,
                onChanged: (bool value) => setState(() {
                  _learnBrand = value;
                  if (!value) _applyToPast = false;
                }),
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  '이 변경을 앞으로도 자동 적용',
                  style: TextStyle(fontSize: 14),
                ),
                subtitle: const Text(
                  '같은 브랜드의 다음 결제는 묻지 않고 자동 분류됩니다.',
                  style: TextStyle(fontSize: 11),
                ),
              ),
              SwitchListTile(
                value: _applyToPast,
                onChanged: _learnBrand
                    ? (bool value) => setState(() => _applyToPast = value)
                    : null,
                contentPadding: EdgeInsets.zero,
                title: const Text('과거 거래에도 적용', style: TextStyle(fontSize: 14)),
                subtitle: const Text(
                  '이미 기록된 같은 브랜드 거래도 이 분류로 정리합니다.',
                  style: TextStyle(fontSize: 11),
                ),
              ),
            ],
            const SizedBox(height: 12),

            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _canSubmit ? _submit : null,
                child: const Text('이 분류로 저장'),
              ),
            ),
            const SizedBox(height: 6),
            Center(
              child: Text(
                decision.isBlocked || !_learnBrand
                    ? '이번 거래에만 적용됩니다.'
                    : '다음부터 이 브랜드는 자동으로 분류됩니다.',
                style: TextStyle(fontSize: 11, color: scheme.outline),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
