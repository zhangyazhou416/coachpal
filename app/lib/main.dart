import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/db/connection.dart';
import 'core/db/database.dart';
import 'core/data/asset_loader.dart';
import 'core/repo/repository.dart';
import 'core/theme/palette.dart';
import 'features/body/body_page.dart';
import 'features/chat/chat_page.dart';
import 'features/meal/meal_page.dart';
import 'features/profile/profile_page.dart';
import 'features/trends/trends_page.dart';
import 'features/workout/workout_page.dart';

final databaseProvider = Provider<AppDatabase>((ref) => openDatabase());

final repoProvider = Provider<Repo>((ref) => Repo(ref.read(databaseProvider)));

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: FitFuelApp()));
}

class FitFuelApp extends ConsumerWidget {
  const FitFuelApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.read(databaseProvider);
    // 首次启动导入内置食物/动作资产（后台执行）
    AssetLoader(db).loadIfEmpty().catchError((_) {});
    return MaterialApp(
      title: 'FitFuel',
      theme: buildLightTheme(),
      darkTheme: buildDarkTheme(),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = const [
      ChatPage(),
      RecordHubPage(),
      TrendsPage(),
      ProfilePage(),
    ];
    return Scaffold(
      body: pages[_index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.chat_bubble_outline), label: '教练'),
          NavigationDestination(icon: Icon(Icons.edit_note_outlined), label: '记录'),
          NavigationDestination(icon: Icon(Icons.trending_up_outlined), label: '趋势'),
          NavigationDestination(icon: Icon(Icons.person_outline), label: '我的'),
        ],
      ),
    );
  }
}

/// 记录页：饮食 / 训练 / 身体 三合一 Tab。
class RecordHubPage extends StatelessWidget {
  const RecordHubPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('记录'),
          toolbarHeight: 0,
          bottom: const TabBar(tabs: [
            Tab(text: '饮食'),
            Tab(text: '训练'),
            Tab(text: '身体'),
          ]),
        ),
        body: const TabBarView(children: [
          MealPage(),
          WorkoutPage(),
          BodyPage(),
        ]),
      ),
    );
  }
}
