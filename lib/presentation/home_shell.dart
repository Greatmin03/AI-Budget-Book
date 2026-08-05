import 'package:flutter/material.dart';

import '../core/di/injector.dart';
import '../features/assets/presentation/screens/assets_screen.dart';
import '../features/dashboard/presentation/screens/dashboard_screen.dart';
import '../features/ingest/domain/services/notification_ingest_service.dart';
import '../features/insights/presentation/screens/insights_screen.dart';
import '../features/projects/presentation/screens/project_list_screen.dart';
import '../features/search/presentation/screens/search_screen.dart';
import '../features/settings/presentation/screens/settings_screen.dart';
import '../features/statistics/presentation/screens/statistics_screen.dart';
import '../features/transactions/presentation/screens/transaction_list_screen.dart';
import 'widgets/permission_banner.dart';

/// 하단 탭(대시보드 / 거래 / 통계 / 자산 / 설정)을 담는 셸.
///
/// 분석·프로젝트는 탭을 더 늘리지 않고 상단 메뉴에서 진입한다.
/// 탭이 여섯 개가 되면 어느 것도 눈에 들어오지 않는다.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int _index = 0;
  bool _permissionGranted = true;

  static const List<String> _titles = <String>[
    '대시보드',
    '거래',
    '통계',
    '자산',
    '설정',
  ];

  NotificationIngestService get _ingest => Injector.instance.ingestService;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshPermission();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshPermission();
      _ingest.drainNativeQueue();
    }
  }

  Future<void> _refreshPermission() async {
    final bool granted =
        await Injector.instance.notifications.isPermissionGranted();
    if (!mounted) return;

    setState(() => _permissionGranted = granted);

    // 권한을 뒤늦게 허용한 경우에도 수집이 시작되도록 한다.
    if (granted && !_ingest.isRunning) {
      await _ingest.start();
    }
  }

  void _open(Widget screen) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => screen),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_index]),
        actions: <Widget>[
          if (_index != 4)
            IconButton(
              icon: const Icon(Icons.search),
              tooltip: '브랜드 검색',
              onPressed: () => _open(const SearchScreen()),
            ),
          PopupMenuButton<String>(
            tooltip: '더 보기',
            onSelected: (String value) {
              switch (value) {
                case 'insights':
                  _open(const InsightsScreen());
                case 'projects':
                  _open(const ProjectListScreen());
              }
            },
            itemBuilder: (BuildContext context) => const <PopupMenuEntry<String>>[
              PopupMenuItem<String>(
                value: 'insights',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.insights_outlined),
                  title: Text('분석'),
                  subtitle: Text('소비 분석 · 절약 제안'),
                ),
              ),
              PopupMenuItem<String>(
                value: 'projects',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.folder_outlined),
                  title: Text('프로젝트'),
                  subtitle: Text('여행 · 행사별 묶음'),
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          if (!_permissionGranted)
            PermissionBanner(onGranted: _refreshPermission),
          Expanded(
            child: IndexedStack(
              index: _index,
              children: const <Widget>[
                DashboardScreen(),
                TransactionListScreen(),
                StatisticsScreen(),
                AssetsScreen(),
                SettingsScreen(),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (int value) => setState(() => _index = value),
        destinations: const <NavigationDestination>[
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: '대시보드',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
            label: '거래',
          ),
          NavigationDestination(
            icon: Icon(Icons.bar_chart_outlined),
            selectedIcon: Icon(Icons.bar_chart),
            label: '통계',
          ),
          NavigationDestination(
            icon: Icon(Icons.account_balance_wallet_outlined),
            selectedIcon: Icon(Icons.account_balance_wallet),
            label: '자산',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: '설정',
          ),
        ],
      ),
    );
  }
}
