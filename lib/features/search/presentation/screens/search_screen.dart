import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/di/injector.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/utils/date_range.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../presentation/widgets/period_selector.dart';
import '../../../statistics/domain/entities/analytics.dart';
import '../../../statistics/presentation/screens/brand_detail_screen.dart';

/// 브랜드명으로 소비 내역을 검색한다.
///
/// 기본 기간은 "올해" 다(요구사항 6의 "2026년 총 소비" 예시에 맞춘다).
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _queryController = TextEditingController();

  /// 입력마다 즉시 쿼리하지 않도록 잠깐 모아서 실행한다.
  Timer? _debounce;

  DateRange _range = DateRange.year();
  List<BrandSearchResult> _results = const <BrandSearchResult>[];
  bool _isSearching = false;
  bool _hasSearched = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _queryController.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    if (value.trim().isEmpty) {
      setState(() {
        _results = const <BrandSearchResult>[];
        _hasSearched = false;
      });
      return;
    }
    // 지우기 버튼이 곧바로 나타나도록 입력 즉시 한 번 갱신한다.
    setState(() {});
    _debounce = Timer(const Duration(milliseconds: 250), _search);
  }

  Future<void> _search() async {
    final String query = _queryController.text.trim();
    if (query.isEmpty) return;

    setState(() => _isSearching = true);
    try {
      final List<BrandSearchResult> results =
          await Injector.instance.analytics.searchBrands(query, _range);
      if (!mounted) return;
      setState(() {
        _results = results;
        _isSearching = false;
        _hasSearched = true;
      });
    } on Object catch (e, stack) {
      AppLogger.e('검색 실패', e, stack);
      if (!mounted) return;
      setState(() {
        _isSearching = false;
        _hasSearched = true;
      });
    }
  }

  void _changeRange(DateRange range) {
    if (range == _range) return;
    setState(() => _range = range);
    if (_queryController.text.trim().isNotEmpty) _search();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('검색'),
      ),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: TextField(
              controller: _queryController,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onChanged: _onQueryChanged,
              onSubmitted: (_) => _search(),
              decoration: InputDecoration(
                hintText: '브랜드명 검색 (예: 스타벅스)',
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                isDense: true,
                suffixIcon: _queryController.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _queryController.clear();
                          _onQueryChanged('');
                        },
                      ),
              ),
            ),
          ),
          PeriodSelector(
            range: _range,
            onChanged: _changeRange,
            showNavigation: false,
          ),
          Expanded(child: _buildResults(context)),
        ],
      ),
    );
  }

  Widget _buildResults(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    if (_isSearching && _results.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (!_hasSearched) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            '브랜드명을 입력하면\n총 소비 금액과 결제 횟수를 보여 줍니다.',
            textAlign: TextAlign.center,
            style: TextStyle(color: scheme.onSurfaceVariant, height: 1.5),
          ),
        ),
      );
    }

    if (_results.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            '"${_queryController.text.trim()}" 에 대한 결제 내역이 없습니다.\n'
            '기간을 넓혀 보세요.',
            textAlign: TextAlign.center,
            style: TextStyle(color: scheme.onSurfaceVariant, height: 1.5),
          ),
        ),
      );
    }

    return ListView.separated(
      itemCount: _results.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (BuildContext context, int index) {
        final BrandSearchResult item = _results[index];
        return ListTile(
          title: Text(
            item.brand,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const SizedBox(height: 2),
              Text(
                '${_range.label} · ${item.count}회 · '
                '평균 ${Formatters.won(item.averageAmount)}',
                style: const TextStyle(fontSize: 11),
              ),
              if (item.lastPaidAt != null)
                Text(
                  '최근 결제 ${Formatters.yearMonthDay(item.lastPaidAt!)}',
                  style: TextStyle(fontSize: 11, color: scheme.outline),
                ),
            ],
          ),
          trailing: Text(
            Formatters.signedWon(item.amount),
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          ),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => BrandDetailScreen(
                brand: item.brand,
                initialRange: _range,
              ),
            ),
          ),
        );
      },
    );
  }
}
