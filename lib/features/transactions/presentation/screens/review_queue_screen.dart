import 'package:flutter/material.dart';

import '../../../../core/constants/app_categories.dart';
import '../../../../core/di/injector.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/utils/formatters.dart';
import '../../domain/entities/transaction.dart';
import '../../domain/usecases/apply_user_correction.dart';
import '../widgets/classify_sheet.dart';

/// "분류 필요" 거래를 하나씩 처리하는 화면.
///
/// 요구사항 9의 흐름을 담당한다.
/// 등록되지 않은 브랜드는 사용자가 **한 번만** 카테고리를 고르고,
/// 그 선택이 브랜드 DB 에 저장되어 이후 같은 브랜드는 자동 분류된다.
class ReviewQueueScreen extends StatefulWidget {
  const ReviewQueueScreen({super.key});

  @override
  State<ReviewQueueScreen> createState() => _ReviewQueueScreenState();
}

class _ReviewQueueScreenState extends State<ReviewQueueScreen> {
  List<Transaction> _items = const <Transaction>[];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final List<Transaction> items =
          await Injector.instance.transactions.findNeedingReview();
      if (!mounted) return;
      setState(() {
        _items = items;
        _isLoading = false;
      });
    } on Object catch (e, stack) {
      AppLogger.e('분류 대기 목록 조회 실패', e, stack);
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  Future<void> _classify(Transaction transaction) async {
    final ClassifyResult? result = await showModalBottomSheet<ClassifyResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => ClassifySheet(transaction: transaction),
    );
    if (result == null) return;

    final CorrectionResult outcome = await Injector.instance.applyUserCorrection(
      transaction: transaction,
      category: result.category,
      subcategory: result.subcategory,
      brand: result.brand,
      tag: result.tag,
      // 시트에서 학습을 끄거나 정책이 막았다면 이번 거래에만 적용된다.
      applyToBrand: result.learnBrand,
      reclassifyPastTransactions: result.applyToPast,
    );

    if (!mounted) return;

    final int before = _items.length;
    await _load();
    if (!mounted) return;

    final int resolved = before - _items.length;
    final String message;
    if (!outcome.learned) {
      message = '이번 거래만 ${result.category}/${result.subcategory} 로 '
          '분류했습니다.'
          '${outcome.blockedReason == null ? '' : ' ${outcome.blockedReason}'}';
    } else if (resolved > 1) {
      message = '"${result.brand}" 를 ${result.category}/${result.subcategory} 로 '
          '학습했습니다. 같은 브랜드 $resolved건이 함께 정리되었습니다.';
    } else {
      message = '"${result.brand}" 를 ${result.category}/${result.subcategory} 로 '
          '학습했습니다. 다음부터 자동 분류됩니다.';
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('분류가 필요한 거래'),
        actions: <Widget>[
          if (_items.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Text(
                  '${_items.length}건',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? _buildEmpty(context)
              : ListView.separated(
                  padding: const EdgeInsets.only(bottom: 24),
                  itemCount: _items.length + 1,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (BuildContext context, int index) {
                    if (index == 0) return _buildHeader(context);
                    return _ReviewTile(
                      transaction: _items[index - 1],
                      onTap: () => _classify(_items[index - 1]),
                    );
                  },
                ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      color: scheme.surfaceContainerLow,
      child: Text(
        '처음 보는 브랜드입니다. 카테고리를 한 번만 골라 주면\n'
        '같은 브랜드의 다음 결제는 자동으로 분류됩니다.',
        style: TextStyle(fontSize: 12, height: 1.5, color: scheme.onSurfaceVariant),
      ),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(Icons.check_circle_outline, size: 48, color: scheme.primary),
            const SizedBox(height: 16),
            const Text(
              '분류가 필요한 거래가 없습니다.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _ReviewTile extends StatelessWidget {
  const _ReviewTile({required this.transaction, required this.onTap});

  final Transaction transaction;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final CategoryPair suggestion = CategoryTaxonomy.coerce(
      transaction.category,
      transaction.subcategory,
    );
    final bool hasSuggestion = suggestion.subcategory != '미분류';

    return ListTile(
      onTap: onTap,
      title: Text(
        transaction.displayName,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SizedBox(height: 2),
          Text(
            '${Formatters.monthDay(transaction.paymentDatetime)} '
            '${Formatters.time(transaction.paymentDatetime)}',
            style: const TextStyle(fontSize: 11),
          ),
          if (hasSuggestion) ...<Widget>[
            const SizedBox(height: 4),
            Row(
              children: <Widget>[
                Icon(Icons.lightbulb_outline, size: 12, color: scheme.tertiary),
                const SizedBox(width: 3),
                Text(
                  '추천: ${suggestion.category} · ${suggestion.subcategory}',
                  style: TextStyle(fontSize: 11, color: scheme.tertiary),
                ),
              ],
            ),
          ],
        ],
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          Text(
            Formatters.signedWon(transaction.amount),
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          ),
          const SizedBox(height: 2),
          Text(
            '분류하기',
            style: TextStyle(fontSize: 10, color: scheme.primary),
          ),
        ],
      ),
    );
  }
}
