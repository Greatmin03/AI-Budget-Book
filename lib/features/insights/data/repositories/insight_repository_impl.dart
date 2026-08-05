import 'package:sqflite/sqflite.dart';

import '../../../../core/database/db_schema.dart';
import '../../../../core/utils/date_range.dart';
import '../../domain/entities/insight_facts.dart';
import '../../domain/repositories/insight_repository.dart';

/// 사실 계산 레이어.
///
/// 모든 숫자를 SQL 로 뽑아 [InsightFacts] 로 만든다.
/// LLM 은 여기 값을 문장으로 바꾸기만 하므로, 숫자가 틀릴 여지가 없다.
class InsightRepositoryImpl implements InsightRepository {
  InsightRepositoryImpl(this._db);

  final Database _db;

  static const String _from = 'FROM ${DbSchema.tableTransactions} t';
  static const String _net = DbSchema.netAmountExpr;

  /// 소비 기준(자산 이동·수입 제외) + 기간.
  static const String _where =
      't.${DbSchema.tPaymentDatetime} >= ? '
      'AND t.${DbSchema.tPaymentDatetime} < ? '
      'AND ${DbSchema.spendingOnly}';

  @override
  Future<InsightFacts> facts(
    DateRange range, {
    int weekdayLookbackWeeks = 8,
  }) async {
    final DateRange previous = range.previous();

    final int total = await _sum(range);
    final int previousTotal = await _sum(previous);
    final int count = await _count(range);

    final List<ItemFact> categories = await _itemFacts(
      range: range,
      previous: previous,
      nameColumn: DbSchema.tCategory,
    );
    final List<ItemFact> subcategories = await _itemFacts(
      range: range,
      previous: previous,
      nameColumn: DbSchema.tSubcategory,
      parentColumn: DbSchema.tCategory,
    );
    final List<ItemFact> brands = await _itemFacts(
      range: range,
      previous: previous,
      nameColumn: DbSchema.tBrand,
      parentColumn: DbSchema.tSubcategory,
    );

    final List<WeekdayPattern> patterns =
        await _weekdayPatterns(weeks: weekdayLookbackWeeks);

    return InsightFacts(
      range: range,
      total: total,
      previousTotal: previousTotal,
      transactionCount: count,
      dailyAverage:
          range.elapsedDays == 0 ? 0 : (total / range.elapsedDays).round(),
      categories: categories,
      subcategories: subcategories,
      brands: brands,
      weekdayPatterns: patterns,
    );
  }

  Future<int> _sum(DateRange range) async {
    final List<Map<String, Object?>> rows = await _db.rawQuery(
      'SELECT COALESCE(SUM($_net), 0) AS v $_from WHERE $_where',
      _args(range),
    );
    return _int(rows.isEmpty ? null : rows.first['v']);
  }

  Future<int> _count(DateRange range) async {
    final List<Map<String, Object?>> rows = await _db.rawQuery(
      'SELECT COUNT(*) AS v $_from WHERE $_where',
      _args(range),
    );
    return _int(rows.isEmpty ? null : rows.first['v']);
  }

  /// 항목별 현재/이전 기간을 각각 집계해 합친다.
  ///
  /// 한 쿼리로 합치는 것보다 두 번 집계하고 Dart 에서 맞추는 편이
  /// 읽기 쉽고, "이전 기간에 없던 새 항목" 도 자연히 잡힌다.
  Future<List<ItemFact>> _itemFacts({
    required DateRange range,
    required DateRange previous,
    required String nameColumn,
    String? parentColumn,
  }) async {
    final Map<String, _Agg> current = await _aggregate(
      range: range,
      nameColumn: nameColumn,
      parentColumn: parentColumn,
    );
    final Map<String, _Agg> before = await _aggregate(
      range: previous,
      nameColumn: nameColumn,
      parentColumn: parentColumn,
    );

    final List<ItemFact> facts = <ItemFact>[];
    current.forEach((String name, _Agg agg) {
      final _Agg? prev = before[name];
      facts.add(
        ItemFact(
          name: name,
          parent: agg.parent,
          amount: agg.amount,
          count: agg.count,
          previousAmount: prev?.amount ?? 0,
          previousCount: prev?.count ?? 0,
        ),
      );
    });

    facts.sort((ItemFact a, ItemFact b) => b.amount.compareTo(a.amount));
    return facts;
  }

  Future<Map<String, _Agg>> _aggregate({
    required DateRange range,
    required String nameColumn,
    String? parentColumn,
  }) async {
    final String parentSelect =
        parentColumn == null ? "'' AS parent" : 't.$parentColumn AS parent';

    final List<Map<String, Object?>> rows = await _db.rawQuery(
      'SELECT t.$nameColumn AS name, $parentSelect, '
      'SUM($_net) AS amount, COUNT(*) AS cnt '
      '$_from WHERE $_where '
      'GROUP BY t.$nameColumn '
      'ORDER BY amount DESC',
      _args(range),
    );

    return <String, _Agg>{
      for (final Map<String, Object?> row in rows)
        ((row['name'] as String?) ?? ''): _Agg(
          amount: _int(row['amount']),
          count: _int(row['cnt']),
          parent: (row['parent'] as String?)?.isEmpty ?? true
              ? null
              : row['parent'] as String,
        ),
    };
  }

  /// 요일별 패턴.
  ///
  /// 타임존 때문에 SQLite 의 strftime 에 맡기지 않고 원시 시각을 받아
  /// Dart 에서 요일을 계산한다.
  Future<List<WeekdayPattern>> _weekdayPatterns({required int weeks}) async {
    final DateTime now = DateTime.now();
    final DateTime from = now.subtract(Duration(days: weeks * 7));
    final DateRange lookback = DateRange.custom(from, now);

    final List<Map<String, Object?>> rows = await _db.rawQuery(
      'SELECT t.${DbSchema.tPaymentDatetime} AS ts, '
      't.${DbSchema.tSubcategory} AS sub, $_net AS amount '
      '$_from WHERE $_where',
      _args(lookback),
    );

    // (요일, 세부항목) -> 합계/횟수/발생한 주
    final Map<String, _WeekdayAgg> buckets = <String, _WeekdayAgg>{};

    for (final Map<String, Object?> row in rows) {
      final int ts = _int(row['ts']);
      if (ts == 0) continue;
      final DateTime at = DateTime.fromMillisecondsSinceEpoch(ts);
      final String sub = (row['sub'] as String?) ?? '';
      if (sub.isEmpty) continue;

      final String key = '${at.weekday}|$sub';
      final _WeekdayAgg agg =
          buckets.putIfAbsent(key, () => _WeekdayAgg(at.weekday, sub));
      agg.amount += _int(row['amount']);
      agg.count += 1;
      // 몇 번째 주에 발생했는지 기록해 "매주" 여부를 판단한다.
      agg.weeks.add(_weekIndex(at, from));
    }

    final List<WeekdayPattern> patterns = buckets.values
        .where((_WeekdayAgg agg) => agg.count >= 3)
        .map(
          (_WeekdayAgg agg) => WeekdayPattern(
            weekday: agg.weekday,
            subcategory: agg.subcategory,
            averageAmount: (agg.amount / agg.count).round(),
            occurrences: agg.weeks.length,
            weeksObserved: weeks,
          ),
        )
        .toList();

    // 금액이 큰 패턴 먼저.
    patterns.sort(
      (WeekdayPattern a, WeekdayPattern b) =>
          b.averageAmount.compareTo(a.averageAmount),
    );
    return patterns;
  }

  static int _weekIndex(DateTime at, DateTime from) =>
      at.difference(from).inDays ~/ 7;

  static List<Object?> _args(DateRange range) =>
      <Object?>[range.startMillis, range.endExclusiveMillis];

  static int _int(Object? value) {
    if (value is int) return value;
    if (value is num) return value.round();
    return 0;
  }
}

class _Agg {
  const _Agg({required this.amount, required this.count, this.parent});

  final int amount;
  final int count;
  final String? parent;
}

class _WeekdayAgg {
  _WeekdayAgg(this.weekday, this.subcategory);

  final int weekday;
  final String subcategory;
  int amount = 0;
  int count = 0;

  /// 발생한 주 번호 집합(중복 제거).
  final Set<int> weeks = <int>{};
}
