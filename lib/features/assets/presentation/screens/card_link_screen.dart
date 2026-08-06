import 'package:flutter/material.dart';

import '../../../../core/di/injector.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/entities/account.dart';
import '../../domain/entities/card_account_link.dart';

/// 카드 → 계좌 연결.
///
/// 알림은 `KB국민카드` 같은 **카드 이름**만 준다. 그 카드가 어느 계좌에서
/// 빠져나가는지는 앱이 알 수 없다. 이름이 비슷하다고 짐작하지 않는다 —
/// 틀리면 잔액이 조용히 어긋나고 사용자가 알아채기 어렵다.
///
/// 한 번 연결하면 **과거 거래에도 소급 적용**되고, 이후 수집되는 거래는
/// 저장 시점에 자동으로 계좌가 붙는다.
class CardLinkScreen extends StatefulWidget {
  const CardLinkScreen({super.key});

  @override
  State<CardLinkScreen> createState() => _CardLinkScreenState();
}

class _CardLinkScreenState extends State<CardLinkScreen> {
  List<CardAccountLink> _links = const <CardAccountLink>[];
  List<Account> _accounts = const <Account>[];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final Injector di = Injector.instance;
      final List<CardAccountLink> links = await di.cardAccountLinks.findAll();
      final List<Account> accounts = await di.accounts.findAll();
      if (!mounted) return;
      setState(() {
        _links = links;
        _accounts = accounts;
        _isLoading = false;
      });
    } on Object catch (e, stack) {
      AppLogger.e('카드 연결 조회 실패', e, stack);
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  Future<void> _pick(CardAccountLink link) async {
    if (_accounts.isEmpty) {
      _notify('먼저 자산 화면에서 계좌를 추가하세요.');
      return;
    }

    final _PickResult? result = await showModalBottomSheet<_PickResult>(
      context: context,
      useSafeArea: true,
      builder: (_) => _AccountPickerSheet(link: link, accounts: _accounts),
    );
    if (result == null) return;

    final int? accountId = result.accountId;
    try {
      final String message;
      if (accountId == null) {
        final int n =
            await Injector.instance.cardAccountLinks.unlink(link.cardName);
        message = '연결을 해제했습니다. 거래 $n건이 잔액에서 빠졌습니다.';
      } else {
        final int n = await Injector.instance.cardAccountLinks.link(
          cardName: link.cardName,
          accountId: accountId,
        );
        message = n == 0
            ? '연결했습니다. 앞으로 수집되는 거래가 잔액에 반영됩니다.'
            : '연결했습니다. 과거 거래 $n건이 잔액에 반영되었습니다.';
      }
      await _load();
      _notify(message);
    } on Object catch (e, stack) {
      AppLogger.e('카드 연결 저장 실패', e, stack);
      _notify('저장하지 못했습니다. ($e)');
    }
  }

  void _notify(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('카드 연결')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _links.isEmpty
              ? _buildEmpty(context)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                    children: <Widget>[
                      _buildIntro(context),
                      const SizedBox(height: 16),
                      AppTheme.cardSurface(
                        context,
                        child: Column(
                          children: List<Widget>.generate(_links.length, (int i) {
                            final CardAccountLink link = _links[i];
                            return Column(
                              children: <Widget>[
                                if (i > 0) const Divider(height: 1),
                                _CardTile(link: link, onTap: () => _pick(link)),
                              ],
                            );
                          }),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _buildIntro(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Text(
      '알림으로 들어온 거래는 카드 이름만 알 수 있습니다.\n'
      '카드를 계좌에 연결하면 그 계좌 잔액에 자동으로 반영됩니다.\n'
      '연결하는 순간 과거 거래에도 함께 적용됩니다.',
      style: TextStyle(
        fontSize: 12,
        height: 1.6,
        color: scheme.onSurfaceVariant,
      ),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(Icons.credit_card_off_outlined, size: 48, color: scheme.outline),
            const SizedBox(height: 16),
            Text(
              '카드 이름이 있는 거래가 아직 없습니다.\n\n'
              '결제 알림이 한 번이라도 수집되면\n'
              '여기에서 계좌를 연결할 수 있습니다.',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}

class _CardTile extends StatelessWidget {
  const _CardTile({required this.link, required this.onTap});

  final CardAccountLink link;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(
        link.isLinked ? Icons.link : Icons.link_off,
        color: link.isLinked ? scheme.primary : scheme.outline,
      ),
      title: Text(
        link.cardName,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        link.isLinked
            ? '${link.accountName} · 거래 ${link.transactionCount}건'
            : '연결 안 됨 · 거래 ${link.transactionCount}건은 잔액에 반영되지 않습니다',
        style: TextStyle(
          fontSize: 11,
          color: link.isLinked ? scheme.onSurfaceVariant : scheme.error,
        ),
      ),
      trailing: const Icon(Icons.chevron_right, size: 20),
      onTap: onTap,
    );
  }
}

/// 시트가 돌려주는 선택. [accountId] 가 null 이면 연결 해제다.
///
/// `null` 하나로 "취소" 와 "해제" 를 둘 다 표현할 수 없어서 감싼다.
class _PickResult {
  const _PickResult(this.accountId);

  final int? accountId;
}

class _AccountPickerSheet extends StatelessWidget {
  const _AccountPickerSheet({required this.link, required this.accounts});

  final CardAccountLink link;
  final List<Account> accounts;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
              child: Text(
                link.cardName,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(
                '이 카드로 결제하면 어느 계좌에서 빠져나가나요?',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ),
            const Divider(height: 1),
            ...accounts.map(
              (Account account) => ListTile(
                title: Text(account.name),
                subtitle: Text(
                  account.type.label,
                  style: const TextStyle(fontSize: 11),
                ),
                // 선택 상태는 색이 아니라 아이콘으로 보여 준다.
                trailing: account.id == link.accountId
                    ? Icon(Icons.check, color: scheme.primary)
                    : null,
                onTap: () =>
                    Navigator.of(context).pop(_PickResult(account.id)),
              ),
            ),
            if (link.isLinked) ...<Widget>[
              const Divider(height: 1),
              ListTile(
                leading: Icon(Icons.link_off, color: scheme.error),
                title: Text(
                  '연결 해제',
                  style: TextStyle(color: scheme.error),
                ),
                subtitle: const Text(
                  '이 연결로 반영된 거래도 잔액에서 빠집니다.',
                  style: TextStyle(fontSize: 11),
                ),
                onTap: () =>
                    Navigator.of(context).pop(const _PickResult(null)),
              ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
