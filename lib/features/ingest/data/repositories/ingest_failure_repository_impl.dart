import '../../../../core/database/db_schema.dart';
import '../../domain/repositories/ingest_failure_repository.dart';
import '../datasources/ingest_failure_local_datasource.dart';

class IngestFailureRepositoryImpl implements IngestFailureRepository {
  IngestFailureRepositoryImpl(this._local);

  final IngestFailureLocalDataSource _local;

  @override
  Future<void> record({
    required String? packageName,
    required String? title,
    required String? text,
    required DateTime? postedAt,
    required String reason,
  }) {
    return _local.insert(<String, Object?>{
      DbSchema.fPackage: packageName,
      DbSchema.fTitle: title,
      DbSchema.fText: text,
      DbSchema.fPostedAt: postedAt?.millisecondsSinceEpoch,
      DbSchema.fReason: reason,
      DbSchema.fCreatedAt: DateTime.now().millisecondsSinceEpoch,
    });
  }

  @override
  Future<List<IngestFailureRecord>> recent({int limit = 50}) async {
    final List<Map<String, Object?>> rows = await _local.recent(limit);
    return rows.map(_fromRow).toList();
  }

  @override
  Future<int> clear() => _local.clear();

  static IngestFailureRecord _fromRow(Map<String, Object?> row) {
    return IngestFailureRecord(
      reason: (row[DbSchema.fReason] as String?) ?? '알 수 없음',
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (row[DbSchema.fCreatedAt] as int?) ?? 0,
      ),
      packageName: row[DbSchema.fPackage] as String?,
      title: row[DbSchema.fTitle] as String?,
      text: row[DbSchema.fText] as String?,
      postedAt: row[DbSchema.fPostedAt] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(row[DbSchema.fPostedAt]! as int),
    );
  }
}
