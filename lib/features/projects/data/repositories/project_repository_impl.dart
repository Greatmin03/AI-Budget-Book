import 'dart:async';

// sqflite 도 `Transaction`(DB 트랜잭션)을 export 하므로 도메인 엔티티와 충돌한다.
// 이 파일의 `Transaction` 은 전부 도메인 엔티티이므로 sqflite 쪽 이름만 숨긴다.
import 'package:sqflite/sqflite.dart' hide Transaction;

import '../../../../core/database/db_schema.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../statistics/domain/entities/statistics.dart';
import '../../../transactions/data/models/transaction_dto.dart';
import '../../../transactions/domain/entities/transaction.dart';
import '../../domain/entities/project.dart';
import '../../domain/repositories/project_repository.dart';

class ProjectRepositoryImpl implements ProjectRepository {
  ProjectRepositoryImpl(this._db);

  final Database _db;
  final StreamController<void> _changes = StreamController<void>.broadcast();

  static const String _table = DbSchema.tableProjects;
  static const String _net = DbSchema.netAmountExpr;

  /// 프로젝트 집계도 소비 기준을 따른다(자산 이동·수입 제외).
  static const String _spending = DbSchema.spendingOnly;

  @override
  Stream<void> get changes => _changes.stream;

  void _notify() {
    if (!_changes.isClosed) _changes.add(null);
  }

  @override
  Future<List<ProjectSummary>> findAll({bool includeArchived = false}) async {
    final String archiveFilter =
        includeArchived ? '' : 'WHERE ${DbSchema.pjIsArchived} = 0 ';

    final List<Map<String, Object?>> rows = await _db.rawQuery(
      'SELECT p.*, '
      'COALESCE(('
      '  SELECT SUM($_net) FROM ${DbSchema.tableTransactions} t '
      '  WHERE t.${DbSchema.tProjectId} = p.${DbSchema.pjId} AND $_spending'
      '), 0) AS total, '
      '('
      '  SELECT COUNT(*) FROM ${DbSchema.tableTransactions} t '
      // 합계가 소비 기준이므로 건수도 같은 기준이어야 한다.
      // 기준이 다르면 "5건 450,000원" 인데 5건을 더해도 450,000원이 안 된다.
      '  WHERE t.${DbSchema.tProjectId} = p.${DbSchema.pjId} AND $_spending'
      ') AS cnt '
      'FROM $_table p '
      '$archiveFilter'
      'ORDER BY p.${DbSchema.pjIsArchived} ASC, '
      '         p.${DbSchema.pjCreatedAt} DESC',
    );

    return rows
        .map(
          (Map<String, Object?> row) => ProjectSummary(
            project: _fromRow(row),
            total: _int(row['total']),
            transactionCount: _int(row['cnt']),
          ),
        )
        .toList();
  }

  @override
  Future<Project?> findById(int id) async {
    final List<Map<String, Object?>> rows = await _db.query(
      _table,
      where: '${DbSchema.pjId} = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    return rows.isEmpty ? null : _fromRow(rows.first);
  }

  @override
  Future<List<Project>> selectable() async {
    final List<Map<String, Object?>> rows = await _db.query(
      _table,
      where: '${DbSchema.pjIsArchived} = 0',
      orderBy: '${DbSchema.pjCreatedAt} DESC',
    );
    return rows.map(_fromRow).toList();
  }

  @override
  Future<Project> save(Project project) async {
    final int now = DateTime.now().millisecondsSinceEpoch;
    final Map<String, Object?> values = <String, Object?>{
      DbSchema.pjName: project.name.trim(),
      DbSchema.pjDescription: project.description,
      DbSchema.pjTargetAmount: project.targetAmount,
      DbSchema.pjStartedAt: project.startedAt?.millisecondsSinceEpoch,
      DbSchema.pjEndedAt: project.endedAt?.millisecondsSinceEpoch,
      DbSchema.pjIsArchived: project.isArchived ? 1 : 0,
      DbSchema.pjUpdatedAt: now,
    };

    final int? id = project.id;
    if (id == null) {
      values[DbSchema.pjCreatedAt] = now;
      final int newId = await _db.insert(_table, values);
      AppLogger.i('프로젝트 생성: ${project.name}');
      _notify();
      return project.copyWith(id: newId);
    }

    await _db.update(
      _table,
      values,
      where: '${DbSchema.pjId} = ?',
      whereArgs: <Object?>[id],
    );
    _notify();
    return project;
  }

  @override
  Future<void> setArchived(int id, bool isArchived) async {
    await _db.update(
      _table,
      <String, Object?>{
        DbSchema.pjIsArchived: isArchived ? 1 : 0,
        DbSchema.pjUpdatedAt: DateTime.now().millisecondsSinceEpoch,
      },
      where: '${DbSchema.pjId} = ?',
      whereArgs: <Object?>[id],
    );
    _notify();
  }

  @override
  Future<void> delete(int id) async {
    // 거래의 project_id 는 ON DELETE SET NULL 로 자동 정리된다.
    // 거래 자체는 절대 지우지 않는다.
    await _db.delete(
      _table,
      where: '${DbSchema.pjId} = ?',
      whereArgs: <Object?>[id],
    );
    AppLogger.i('프로젝트 삭제: $id (거래는 유지)');
    _notify();
  }

  @override
  Future<ProjectDetail> detail(int id) async {
    final Project? project = await findById(id);
    if (project == null) {
      throw StateError('프로젝트를 찾을 수 없습니다: $id');
    }

    final List<Map<String, Object?>> totals = await _db.rawQuery(
      'SELECT COALESCE(SUM($_net), 0) AS total, COUNT(*) AS cnt '
      'FROM ${DbSchema.tableTransactions} t '
      'WHERE t.${DbSchema.tProjectId} = ? AND $_spending',
      <Object?>[id],
    );

    final List<Map<String, Object?>> categoryRows = await _db.rawQuery(
      'SELECT t.${DbSchema.tCategory} AS name, '
      'SUM($_net) AS amount, COUNT(*) AS cnt '
      'FROM ${DbSchema.tableTransactions} t '
      'WHERE t.${DbSchema.tProjectId} = ? AND $_spending '
      'GROUP BY t.${DbSchema.tCategory} '
      'ORDER BY amount DESC',
      <Object?>[id],
    );

    final List<Map<String, Object?>> brandRows = await _db.rawQuery(
      'SELECT t.${DbSchema.tBrand} AS brand, '
      'SUM($_net) AS amount, COUNT(*) AS cnt '
      'FROM ${DbSchema.tableTransactions} t '
      'WHERE t.${DbSchema.tProjectId} = ? AND $_spending '
      'GROUP BY t.${DbSchema.tBrand} '
      'ORDER BY amount DESC '
      'LIMIT 20',
      <Object?>[id],
    );

    return ProjectDetail(
      project: project,
      total: _int(totals.isEmpty ? null : totals.first['total']),
      transactionCount: _int(totals.isEmpty ? null : totals.first['cnt']),
      byCategory: categoryRows
          .map(
            (Map<String, Object?> row) => CategoryAmount(
              name: (row['name'] as String?) ?? '기타',
              amount: _int(row['amount']),
              count: _int(row['cnt']),
            ),
          )
          .toList(),
      byBrand: brandRows
          .map(
            (Map<String, Object?> row) => BrandAmount(
              brand: (row['brand'] as String?) ?? '미확인',
              amount: _int(row['amount']),
              count: _int(row['cnt']),
            ),
          )
          .toList(),
    );
  }

  @override
  Future<List<Transaction>> transactionsOf(int id, {int limit = 200}) async {
    final List<Map<String, Object?>> rows = await _db.rawQuery(
      'SELECT t.*, ${DbSchema.settledSumExpr} AS '
      '${TransactionDto.settledAmountColumn} '
      'FROM ${DbSchema.tableTransactions} t '
      'WHERE t.${DbSchema.tProjectId} = ? '
      'ORDER BY t.${DbSchema.tPaymentDatetime} DESC '
      'LIMIT ?',
      <Object?>[id, limit],
    );
    return rows.map(TransactionDto.fromRow).toList();
  }

  @override
  Future<void> assign({
    required int transactionId,
    required int? projectId,
  }) async {
    await _db.update(
      DbSchema.tableTransactions,
      <String, Object?>{
        DbSchema.tProjectId: projectId,
        DbSchema.tUpdatedAt: DateTime.now().millisecondsSinceEpoch,
      },
      where: '${DbSchema.tId} = ?',
      whereArgs: <Object?>[transactionId],
    );
    _notify();
  }

  static Project _fromRow(Map<String, Object?> row) {
    return Project(
      id: row[DbSchema.pjId] as int?,
      name: (row[DbSchema.pjName] as String?) ?? '',
      description: row[DbSchema.pjDescription] as String?,
      targetAmount: row[DbSchema.pjTargetAmount] as int?,
      startedAt: _toDate(row[DbSchema.pjStartedAt]),
      endedAt: _toDate(row[DbSchema.pjEndedAt]),
      isArchived: ((row[DbSchema.pjIsArchived] as int?) ?? 0) == 1,
      createdAt: _toDate(row[DbSchema.pjCreatedAt]),
      updatedAt: _toDate(row[DbSchema.pjUpdatedAt]),
    );
  }

  static DateTime? _toDate(Object? value) {
    if (value is int && value > 0) {
      return DateTime.fromMillisecondsSinceEpoch(value);
    }
    return null;
  }

  static int _int(Object? value) {
    if (value is int) return value;
    if (value is num) return value.round();
    return 0;
  }

  void dispose() => _changes.close();
}
