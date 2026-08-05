import 'package:flutter/material.dart';

import '../../../../core/di/injector.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/formatters.dart';
import '../../domain/entities/project.dart';
import 'project_detail_screen.dart';

/// 프로젝트(폴더) 목록.
class ProjectListScreen extends StatefulWidget {
  const ProjectListScreen({super.key});

  @override
  State<ProjectListScreen> createState() => _ProjectListScreenState();
}

class _ProjectListScreenState extends State<ProjectListScreen> {
  List<ProjectSummary> _projects = const <ProjectSummary>[];
  bool _isLoading = true;
  bool _showArchived = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final List<ProjectSummary> items = await Injector.instance.projects
          .findAll(includeArchived: _showArchived);
      if (!mounted) return;
      setState(() {
        _projects = items;
        _isLoading = false;
      });
    } on Object catch (e, stack) {
      AppLogger.e('프로젝트 목록 조회 실패', e, stack);
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  Future<void> _createOrEdit([Project? existing]) async {
    final Project? result = await showModalBottomSheet<Project>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _ProjectFormSheet(project: existing),
    );
    if (result == null) return;

    await Injector.instance.projects.save(result);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('프로젝트'),
        actions: <Widget>[
          IconButton(
            icon: Icon(
              _showArchived ? Icons.inventory_2 : Icons.inventory_2_outlined,
            ),
            tooltip: _showArchived ? '보관 숨기기' : '보관 보기',
            onPressed: () {
              setState(() => _showArchived = !_showArchived);
              _load();
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createOrEdit,
        icon: const Icon(Icons.add),
        label: const Text('프로젝트'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _projects.isEmpty
              ? _buildEmpty(context)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
                    children: <Widget>[
                      Text(
                        '카테고리와 별개로 거래를 묶습니다.\n'
                        '여행·이사·행사처럼 한 목적에 여러 카테고리가 섞일 때 씁니다.',
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.5,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 16),
                      ..._projects.map(
                        (ProjectSummary s) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _ProjectCard(
                            summary: s,
                            onTap: () async {
                              final int? id = s.project.id;
                              if (id == null) return;
                              await Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) =>
                                      ProjectDetailScreen(projectId: id),
                                ),
                              );
                              await _load();
                            },
                            onEdit: () => _createOrEdit(s.project),
                          ),
                        ),
                      ),
                    ],
                  ),
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
            Icon(Icons.folder_outlined, size: 48, color: scheme.outline),
            const SizedBox(height: 16),
            Text(
              '프로젝트가 없습니다.\n\n'
              '"일본 여행" 처럼 하나의 목적에 묶고 싶은 지출이 있으면\n'
              '프로젝트를 만들어 거래를 담아 보세요.',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProjectCard extends StatelessWidget {
  const _ProjectCard({
    required this.summary,
    required this.onTap,
    required this.onEdit,
  });

  final ProjectSummary summary;
  final VoidCallback onTap;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Project project = summary.project;
    final double? ratio = summary.targetRatio;

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: AppTheme.cardDecoration(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Row(
                    children: <Widget>[
                      Flexible(
                        child: Text(
                          project.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: project.isArchived ? scheme.outline : null,
                          ),
                        ),
                      ),
                      if (project.isArchived) ...<Widget>[
                        const SizedBox(width: 6),
                        Text(
                          '보관',
                          style: TextStyle(
                            fontSize: 10,
                            color: scheme.outline,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  onPressed: onEdit,
                  tooltip: '수정',
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              Formatters.signedWon(summary.total),
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              <String>[
                '${summary.transactionCount}건',
                if (project.periodLabel != null) project.periodLabel!,
              ].join(' · '),
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
            ),

            // 목표가 있으면 진행 막대를 보여 준다.
            if (ratio != null) ...<Widget>[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: ratio > 1 ? 1 : ratio,
                  minHeight: 6,
                  backgroundColor: scheme.surfaceContainerHighest,
                  color: summary.isOverTarget ? scheme.error : scheme.primary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '목표 ${Formatters.won(project.targetAmount!)} 중 '
                '${(ratio * 100).toStringAsFixed(0)}% 사용'
                '${summary.isOverTarget ? ' · 초과' : ''}',
                style: TextStyle(
                  fontSize: 11,
                  color: summary.isOverTarget
                      ? scheme.error
                      : scheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 프로젝트 생성/수정 시트.
class _ProjectFormSheet extends StatefulWidget {
  const _ProjectFormSheet({this.project});

  final Project? project;

  @override
  State<_ProjectFormSheet> createState() => _ProjectFormSheetState();
}

class _ProjectFormSheetState extends State<_ProjectFormSheet> {
  late final TextEditingController _nameController =
      TextEditingController(text: widget.project?.name ?? '');
  late final TextEditingController _targetController = TextEditingController(
    text: widget.project?.targetAmount?.toString() ?? '',
  );
  late DateTime? _startedAt = widget.project?.startedAt;
  late DateTime? _endedAt = widget.project?.endedAt;
  late bool _isArchived = widget.project?.isArchived ?? false;

  @override
  void dispose() {
    _nameController.dispose();
    _targetController.dispose();
    super.dispose();
  }

  bool get _canSave => _nameController.text.trim().isNotEmpty;

  Future<void> _pickRange() async {
    final DateTime now = DateTime.now();
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 2),
      initialDateRange: _startedAt == null
          ? null
          : DateTimeRange(start: _startedAt!, end: _endedAt ?? _startedAt!),
      helpText: '프로젝트 기간',
      saveText: '적용',
    );
    if (picked == null) return;
    setState(() {
      _startedAt = picked.start;
      _endedAt = picked.end;
    });
  }

  void _submit() {
    final String digits =
        _targetController.text.replaceAll(RegExp(r'[^0-9]'), '');
    final int? target = digits.isEmpty ? null : int.tryParse(digits);

    Navigator.of(context).pop(
      (widget.project ?? Project(name: _nameController.text.trim())).copyWith(
        name: _nameController.text.trim(),
        targetAmount: target,
        startedAt: _startedAt,
        endedAt: _endedAt,
        isArchived: _isArchived,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

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
            Text(
              widget.project == null ? '프로젝트 만들기' : '프로젝트 수정',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 18),

            TextField(
              controller: _nameController,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: '이름',
                border: OutlineInputBorder(),
                isDense: true,
                hintText: '예: 일본 여행',
              ),
            ),
            const SizedBox(height: 14),

            TextField(
              controller: _targetController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '목표 금액 (선택)',
                border: OutlineInputBorder(),
                isDense: true,
                suffixText: '원',
                helperText: '이 프로젝트에 쓸 예정인 금액',
              ),
            ),
            const SizedBox(height: 14),

            OutlinedButton.icon(
              onPressed: _pickRange,
              icon: const Icon(Icons.date_range_outlined, size: 18),
              label: Text(
                _startedAt == null
                    ? '기간 설정 (선택)'
                    : '${_startedAt!.month}.${_startedAt!.day}'
                        ' ~ ${(_endedAt ?? _startedAt!).month}.'
                        '${(_endedAt ?? _startedAt!).day}',
              ),
            ),

            if (widget.project != null) ...<Widget>[
              const SizedBox(height: 6),
              SwitchListTile(
                value: _isArchived,
                onChanged: (bool value) => setState(() => _isArchived = value),
                contentPadding: EdgeInsets.zero,
                title: const Text('보관', style: TextStyle(fontSize: 14)),
                subtitle: const Text(
                  '목록에서 숨깁니다. 거래는 그대로 남습니다.',
                  style: TextStyle(fontSize: 11),
                ),
              ),
            ],
            const SizedBox(height: 20),

            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _canSave ? _submit : null,
                child: const Text('저장'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
