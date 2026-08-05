import '../../../statistics/domain/entities/statistics.dart';

/// 프로젝트(폴더).
///
/// 카테고리와 **직교하는** 묶음이다. `일본 여행` 하나에 숙박·식비·교통·쇼핑이
/// 모두 들어갈 수 있다. 카테고리는 "무엇에 썼나", 프로젝트는 "무엇을 위해 썼나".
class Project {
  const Project({
    required this.name,
    this.id,
    this.description,
    this.targetAmount,
    this.startedAt,
    this.endedAt,
    this.isArchived = false,
    this.createdAt,
    this.updatedAt,
  });

  final int? id;
  final String name;
  final String? description;

  /// 목표 금액(선택). 예산이 아니라 "이만큼 쓸 예정" 이다.
  final int? targetAmount;

  final DateTime? startedAt;
  final DateTime? endedAt;
  final bool isArchived;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get hasTarget => targetAmount != null && targetAmount! > 0;

  /// 진행 중인지(종료일이 없거나 아직 지나지 않았고, 보관되지 않음).
  bool get isOngoing {
    if (isArchived) return false;
    final DateTime? end = endedAt;
    return end == null || end.isAfter(DateTime.now());
  }

  /// 기간 표시용 문자열. 예: `8.1 ~ 8.5`
  String? get periodLabel {
    final DateTime? start = startedAt;
    if (start == null) return null;
    final DateTime? end = endedAt;
    final String from = '${start.month}.${start.day}';
    if (end == null) return '$from ~';
    return '$from ~ ${end.month}.${end.day}';
  }

  Project copyWith({
    int? id,
    String? name,
    String? description,
    int? targetAmount,
    DateTime? startedAt,
    DateTime? endedAt,
    bool? isArchived,
  }) {
    return Project(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      targetAmount: targetAmount ?? this.targetAmount,
      startedAt: startedAt ?? this.startedAt,
      endedAt: endedAt ?? this.endedAt,
      isArchived: isArchived ?? this.isArchived,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  @override
  String toString() => 'Project($name, target=$targetAmount)';
}

/// 프로젝트 + 집계. 목록 화면이 필요한 최소 정보.
class ProjectSummary {
  const ProjectSummary({
    required this.project,
    required this.total,
    required this.transactionCount,
  });

  final Project project;

  /// 실제 부담 합계(정산 차감, 자산 이동·수입 제외).
  final int total;
  final int transactionCount;

  /// 목표 대비 사용 비율(0~1+). 목표가 없으면 null.
  double? get targetRatio {
    final int? target = project.targetAmount;
    if (target == null || target <= 0) return null;
    return total / target;
  }

  bool get isOverTarget {
    final double? ratio = targetRatio;
    return ratio != null && ratio > 1;
  }
}

/// 프로젝트 상세 화면 데이터.
class ProjectDetail {
  const ProjectDetail({
    required this.project,
    required this.total,
    required this.transactionCount,
    required this.byCategory,
    required this.byBrand,
  });

  final Project project;
  final int total;
  final int transactionCount;

  /// 카테고리별 내역(금액 내림차순). 요구사항의 프로젝트 화면 구성.
  final List<CategoryAmount> byCategory;

  /// 브랜드별 내역.
  final List<BrandAmount> byBrand;

  bool get isEmpty => transactionCount == 0;

  double? get targetRatio {
    final int? target = project.targetAmount;
    if (target == null || target <= 0) return null;
    return total / target;
  }

  /// 목표까지 남은 금액. 목표가 없으면 null.
  int? get remainingToTarget {
    final int? target = project.targetAmount;
    if (target == null) return null;
    return target - total;
  }
}
