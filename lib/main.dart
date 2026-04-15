import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_gemma/flutter_gemma.dart';

import 'database/database_helper.dart';
import 'screens/add_edit_reminder.dart';
import 'screens/ai_chat_screen.dart';
import 'screens/all_reminders_screen.dart';
import 'screens/calendar_screen.dart';
import 'screens/home_screen.dart';
import 'services/notification_service.dart';
import 'state/app_state.dart';
import 'utils/constants.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FlutterGemma.initialize();
  await NotificationService.instance.initialize((payload) async {});
  
  // Cleanup junk reminders from previous sessions
  await DatabaseHelper.instance.cleanupJunkReminders();

  runApp(const SchedulerApp());
}

class SchedulerApp extends StatelessWidget {
  const SchedulerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppState(
        databaseHelper: DatabaseHelper.instance,
        notificationService: NotificationService.instance,
      )..initialize(),
      child: MaterialApp(
        title: 'AI Scheduler',
        debugShowCheckedModeBanner: false,
        themeMode: ThemeMode.dark,
        theme: _theme(),
        darkTheme: _theme(),
        home: const DashboardShell(),
      ),
    );
  }

  ThemeData _theme() {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.dark,
    ).copyWith(
      primary: AppColors.primary,
      secondary: AppColors.secondary,
      surface: AppColors.surface,
      tertiary: AppColors.accent,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.background,
      cardColor: AppColors.card,
      chipTheme: const ChipThemeData(
        side: BorderSide.none,
        shape: StadiumBorder(),
      ),
      textTheme: const TextTheme(
        headlineSmall: TextStyle(fontWeight: FontWeight.w700),
        titleLarge: TextStyle(fontWeight: FontWeight.w700),
        bodyLarge: TextStyle(fontSize: 16),
      ).apply(
        bodyColor: AppColors.textPrimary,
        displayColor: AppColors.textPrimary,
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: AppColors.surface,
      ),
    );
  }
}

class DashboardShell extends StatefulWidget {
  const DashboardShell({super.key});

  @override
  State<DashboardShell> createState() => _DashboardShellState();
}

class _DashboardShellState extends State<DashboardShell> {
  int _index = 0;

  final _screens = const [
    HomeScreen(),
    CalendarScreen(),
    AllRemindersScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, state, _) {
        if (state.isLoading) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        return Scaffold(
          extendBody: true,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.auto_awesome, color: AppColors.accent),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AiChatScreen()),
              ),
            ),
          ),
          body: AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: KeyedSubtree(
              key: ValueKey(_index),
              child: _screens[_index],
            ),
          ),
          floatingActionButton: FloatingActionButton(
            onPressed: () => AddEditReminderSheet.show(context),
            backgroundColor: const Color(0xFFFFB300),
            foregroundColor: Colors.white,
            shape: const CircleBorder(),
            child: const Icon(Icons.add),
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _index,
            height: 72,
            backgroundColor: AppColors.surface.withAlpha(242),
            indicatorColor: AppColors.accent.withAlpha(40),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home),
                label: 'Home',
              ),
              NavigationDestination(
                icon: Icon(Icons.calendar_month_outlined),
                selectedIcon: Icon(Icons.calendar_month),
                label: 'Calendar',
              ),
              NavigationDestination(
                icon: Icon(Icons.event_note_outlined),
                selectedIcon: Icon(Icons.event_note),
                label: 'All',
              ),
            ],
            onDestinationSelected: (value) => setState(() => _index = value),
          ),
        );
      },
    );
  }
}
