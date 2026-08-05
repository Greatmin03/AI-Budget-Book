import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../logging/app_logger.dart';
import 'db_schema.dart';
import 'seed/brand_seed.dart';

/// SQLite 연결 관리자.
///
/// 앱 전체에서 단 하나의 [Database] 핸들을 공유한다.
/// 스키마 생성/마이그레이션과 최초 시드 데이터 주입을 담당한다.
class AppDatabase {
  AppDatabase._();

  static final AppDatabase instance = AppDatabase._();

  Database? _db;

  /// 열려 있는 DB 핸들. [open] 이 먼저 호출되어 있어야 한다.
  Database get db {
    final Database? current = _db;
    if (current == null) {
      throw StateError('AppDatabase.open() 이 호출되지 않았습니다.');
    }
    return current;
  }

  bool get isOpen => _db != null;

  Future<Database> open() async {
    if (_db != null) return _db!;

    final String dbPath = p.join(
      await getDatabasesPath(),
      DbSchema.databaseName,
    );

    _db = await openDatabase(
      dbPath,
      version: DbSchema.databaseVersion,
      onConfigure: (Database db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (Database db, int version) async {
        AppLogger.i('DB 생성 (v$version)');
        final Batch batch = db.batch();
        for (final String statement in DbSchema.createStatements) {
          batch.execute(statement);
        }
        await batch.commit(noResult: true);
        await _seedBrandRules(db);
      },
      onUpgrade: (Database db, int from, int to) async {
        AppLogger.i('DB 마이그레이션 v$from -> v$to');

        // 버전 번호 순서대로, 아직 적용되지 않은 것만 실행한다.
        final List<int> versions = DbSchema.migrations.keys.toList()..sort();
        for (final int version in versions) {
          if (from >= version) continue;
          for (final String statement in DbSchema.migrations[version]!) {
            await db.execute(statement);
          }
          AppLogger.i('마이그레이션 v$version 적용 완료');
        }
      },
      onOpen: (Database db) async {
        // 시드가 비어 있으면(수동 삭제 등) 다시 채운다.
        final int count = Sqflite.firstIntValue(
              await db.rawQuery(
                'SELECT COUNT(*) FROM ${DbSchema.tableBrandRules}',
              ),
            ) ??
            0;
        if (count == 0) {
          await _seedBrandRules(db);
        }
      },
    );

    return _db!;
  }

  /// 브랜드 규칙 시드 주입. 이미 있는 pattern 은 건너뛴다(사용자 수정 보호).
  Future<void> _seedBrandRules(Database db) async {
    final Batch batch = db.batch();
    for (final BrandSeedEntry entry in BrandSeed.entries) {
      batch.insert(
        DbSchema.tableBrandRules,
        entry.toRow(),
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
    await batch.commit(noResult: true);
    AppLogger.i('브랜드 시드 ${BrandSeed.entries.length}건 주입 완료');
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  /// 개발용: 모든 거래를 삭제한다(가맹점 학습 데이터는 유지).
  Future<void> clearTransactions() async {
    await db.delete(DbSchema.tableTransactions);
  }

  /// 개발용: 학습된 가맹점을 모두 삭제한다(시드 규칙은 유지).
  Future<void> clearLearnedMerchants() async {
    await db.delete(DbSchema.tableMerchants);
  }
}
