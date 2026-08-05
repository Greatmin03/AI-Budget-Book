import 'package:flutter/material.dart';

import '../../../ingest/domain/repositories/ingest_failure_repository.dart';
import '../controllers/settings_controller.dart';

/// 파싱 실패 알림 목록.
///
/// 파서를 개선할 때 어떤 형식을 놓쳤는지 보기 위한 화면이다.
class IngestFailuresSheet extends StatefulWidget {
  const IngestFailuresSheet({required this.controller, super.key});

  final SettingsController controller;

  @override
  State<IngestFailuresSheet> createState() => _IngestFailuresSheetState();
}

class _IngestFailuresSheetState extends State<IngestFailuresSheet> {
  late Future<List<IngestFailureRecord>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.controller.loadFailures();
  }

  void _reload() {
    setState(() => _future = widget.controller.loadFailures());
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
          child: Row(
            children: <Widget>[
              const Expanded(
                child: Text(
                  '파싱 실패 보관함',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
              TextButton(
                onPressed: () async {
                  await widget.controller.clearFailures();
                  _reload();
                },
                child: const Text('비우기'),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: FutureBuilder<List<IngestFailureRecord>>(
            future: _future,
            builder: (
              BuildContext context,
              AsyncSnapshot<List<IngestFailureRecord>> snapshot,
            ) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(child: Text('불러오지 못했습니다: ${snapshot.error}'));
              }

              final List<IngestFailureRecord> items =
                  snapshot.data ?? const <IngestFailureRecord>[];
              if (items.isEmpty) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text(
                      '실패한 알림이 없습니다.\n모든 결제 알림이 정상 처리되고 있습니다.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }

              return ListView.separated(
                itemCount: items.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (BuildContext context, int index) {
                  final IngestFailureRecord item = items[index];
                  return ListTile(
                    title: Text(
                      item.preview,
                      style: const TextStyle(fontSize: 13),
                    ),
                    subtitle: Text(
                      '${item.reason}'
                      '${item.packageName == null ? '' : '  ·  ${item.packageName}'}',
                      style: const TextStyle(fontSize: 11),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
