import '../../../transactions/domain/entities/transaction.dart';
import '../entities/project.dart';

abstract interface class ProjectRepository {
  /// 프로젝트 목록 + 집계(진행 중 먼저).
  Future<List<ProjectSummary>> findAll({bool includeArchived = false});

  Future<Project?> findById(int id);

  /// 거래에 붙일 수 있는 프로젝트(진행 중인 것만).
  Future<List<Project>> selectable();

  Future<Project> save(Project project);

  /// 보관/보관 해제. 삭제 대신 보관을 기본으로 한다.
  Future<void> setArchived(int id, bool isArchived);

  /// 프로젝트 삭제. 거래는 남고 연결만 끊어진다.
  Future<void> delete(int id);

  /// 프로젝트 상세(카테고리·브랜드 분해).
  Future<ProjectDetail> detail(int id);

  /// 이 프로젝트에 속한 거래(최신순).
  Future<List<Transaction>> transactionsOf(int id, {int limit = 200});

  /// 거래를 프로젝트에 붙이거나 뗀다.
  Future<void> assign({required int transactionId, required int? projectId});

  Stream<void> get changes;
}
