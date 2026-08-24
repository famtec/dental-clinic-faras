import 'package:flutter/material.dart';

import '../services/api_service.dart';
import 'patients_list_screen.dart';
import 'today_schedule_screen.dart';

class HomeScreen extends StatefulWidget {
  final ApiService apiService;
  final VoidCallback onLogout;
  final GlobalKey<TodayScheduleScreenState> todayScheduleKey;

  const HomeScreen({
    super.key,
    required this.apiService,
    required this.onLogout,
    required this.todayScheduleKey,
  });

  @override
  State<HomeScreen> createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  /// يُستدعى من الشاشة الرئيسية (main.dart) عند فتح التطبيق عبر إشعار حجز
  /// جديد، حتى يرى الطبيب جدول اليوم مباشرة حتى لو كان مفتوحاً على تبويب
  /// المرضى وقتها.
  void showTodayTab() {
    if (mounted) setState(() => _currentIndex = 0);
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      TodayScheduleScreen(
        key: widget.todayScheduleKey,
        apiService: widget.apiService,
        onSessionExpired: widget.onLogout,
      ),
      PatientsListScreen(
        apiService: widget.apiService,
        onSessionExpired: widget.onLogout,
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(_currentIndex == 0 ? 'جدول اليوم' : 'المرضى'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'تسجيل الخروج',
            onPressed: widget.onLogout,
          ),
        ],
      ),
      body: IndexedStack(index: _currentIndex, children: screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) => setState(() => _currentIndex = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.today_outlined),
            selectedIcon: Icon(Icons.today),
            label: 'اليوم',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_outline),
            selectedIcon: Icon(Icons.people),
            label: 'المرضى',
          ),
        ],
      ),
    );
  }
}
