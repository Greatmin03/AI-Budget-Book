import 'dart:convert';

import 'package:budget_book/core/database/db_schema.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' hide Transaction;

/// 옛 버전의 스키마를 만든다. 이관(migration) 테스트용.
///
/// 기기에는 이미 사용자의 거래가 쌓여 있다. 이관이 깨지면 그것이 사라지므로,
/// **옛 DB 를 실제로 만들어 놓고 열어 보는** 것 말고는 확인할 방법이 없다.
///
/// 옛 CREATE 문을 테스트에 복사해 두는 방법은 쓰지 않는다. 진짜 스키마가
/// 바뀌어도 복사본은 그대로라 테스트만 조용히 낡는다. 대신 현재
/// [DbSchema.createStatements] 에서 **그 버전 이후에 추가된 것만** 덜어낸다.
/// 새 이관을 만들 때 [_addedIn] 한 줄만 적으면 모든 이관 테스트가 따라온다.
class LegacySchema {
  const LegacySchema._();

  /// 각 버전이 새로 추가한 것.
  ///
  /// 테이블은 이름만, 컬럼은 `테이블.컬럼` 으로 적는다.
  static const Map<int, List<String>> _addedIn = <int, List<String>>{
    10: <String>[DbSchema.tableCardAccountLinks],
    11: <String>['${DbSchema.tableDeposits}.${DbSchema.dpTransactionId}'],
    // v12 는 데이터만 고친다. 스키마에 추가된 것이 없다.
    13: <String>[DbSchema.tableUnmappedPlaceCategories],
    14: <String>[
      '${DbSchema.tableAssetTransfers}.${DbSchema.atToAccountId}',
    ],
    // v15 는 데이터만 고친다.
    16: <String>[
      '${DbSchema.tableTransactions}.${DbSchema.tAccountNumber}',
      '${DbSchema.tableTransactions}.${DbSchema.tBalanceAfter}',
      '${DbSchema.tableTransactions}.${DbSchema.tMergedSources}',
    ],
  };

  /// [version] 시점의 스키마를 [db] 에 만든다.
  static Future<void> createAt(Database db, int version) async {
    final List<String> droppedTables = <String>[];
    final List<(String table, String column)> droppedColumns =
        <(String, String)>[];

    _addedIn.forEach((int addedAt, List<String> items) {
      if (addedAt <= version) return;
      for (final String item in items) {
        final int dot = item.indexOf('.');
        if (dot < 0) {
          droppedTables.add(item);
        } else {
          droppedColumns.add((item.substring(0, dot), item.substring(dot + 1)));
        }
      }
    });

    for (final String statement in DbSchema.createStatements) {
      if (droppedTables.any((String t) => _targets(statement, t))) continue;

      String sql = statement;
      for (final (String table, String column) in droppedColumns) {
        if (_targets(sql, table)) sql = _withoutColumn(sql, column);
      }
      await db.execute(sql);
    }
  }

  /// [statement] 가 [table] 을 만들거나 그 위에 인덱스를 거는가.
  ///
  /// 인덱스도 함께 걸러야 한다. 테이블 없이 인덱스만 만들면 실패한다.
  static bool _targets(String statement, String table) =>
      statement.contains('TABLE $table') ||
      statement.contains('TABLE IF NOT EXISTS $table') ||
      statement.contains('ON $table(');

  /// [column] 을 정의하는 줄을 뺀다.
  ///
  /// 정의가 다음 줄까지 이어지는 경우(`REFERENCES ...`)도 함께 버린다.
  static String _withoutColumn(String statement, String column) {
    final List<String> kept = <String>[];
    bool justDropped = false;

    for (final String line in const LineSplitter().convert(statement)) {
      if (RegExp('\\b$column\\s').hasMatch(line)) {
        justDropped = true;
        continue;
      }
      if (justDropped) {
        justDropped = false;
        if (line.trimLeft().startsWith('REFERENCES')) continue;
      }
      kept.add(line);
    }
    return kept.join('\n');
  }

  /// [db] 를 [from] 에서 현재 버전까지 이관한다.
  static Future<void> upgrade(Database db, int from, int to) async {
    for (int v = from + 1; v <= to; v++) {
      for (final String statement
          in DbSchema.migrations[v] ?? const <String>[]) {
        await db.execute(statement);
      }
    }
  }
}
