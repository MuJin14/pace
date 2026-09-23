import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/activity/pages/activity_detail_page.dart';
import '../../features/activity/pages/activity_list_page.dart';
import '../../features/auth/pages/login_page.dart';
import '../../features/auth/pages/register_page.dart';
import '../../features/auth/providers/auth_provider.dart';
import '../../features/badges/pages/badges_page.dart';
import '../../features/friends/pages/chat_page.dart';
import '../../features/friends/pages/friends_page.dart';
import '../../features/friends/pages/friends_search_page.dart';
import '../../features/goals/pages/goals_page.dart';
import '../../features/home/pages/home_page.dart';
import '../../features/home/pages/main_shell.dart';
import '../../features/leaderboard/pages/leaderboard_page.dart';
import '../../features/profile/pages/profile_page.dart';
import '../theme/app_theme.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier(0);
  ref.listen(authProvider, (_, __) => refresh.value++);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: refresh,
    redirect: (context, state) {
      final auth = ref.read(authProvider);
      final loc = state.uri.path;

      if (auth.isLoading) {
        return loc == '/splash' ? null : '/splash';
      }

      final loggedIn = auth.value != null;

      if (!loggedIn) {
        if (loc == '/login' || loc == '/register') return null;
        return '/login';
      }

      if (loc == '/login' || loc == '/register' || loc == '/splash') {
        return '/home';
      }
      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, __) => const SplashScreen()),
      GoRoute(path: '/login', builder: (_, __) => const LoginPage()),
      GoRoute(path: '/register', builder: (_, __) => const RegisterPage()),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => MainShell(navigationShell: shell),
        branches: [
          StatefulShellBranch(
            routes: [GoRoute(path: '/home', builder: (_, __) => const HomePage())],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: '/activity', builder: (_, __) => const ActivityListPage())],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: '/leaderboard', builder: (_, __) => const LeaderboardPage())],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: '/friends', builder: (_, __) => const FriendsPage())],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: '/profile', builder: (_, __) => const ProfilePage())],
          ),
        ],
      ),
      GoRoute(
        path: '/activity/:id',
        builder: (context, state) => ActivityDetailPage(
          activityId: int.parse(state.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: '/chat/:friendId',
        builder: (context, state) => ChatPage(
          friendId: int.parse(state.pathParameters['friendId']!),
          friendName: (state.extra as String?) ?? '聊天',
        ),
      ),
      GoRoute(path: '/friends/search', builder: (_, __) => const FriendsSearchPage()),
      GoRoute(path: '/goals', builder: (_, __) => const GoalsPage()),
      GoRoute(path: '/badges', builder: (_, __) => const BadgesPage()),
    ],
  );
});

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: AppColors.primaryGradient,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white.withValues(alpha: 0.4)),
                ),
                child: const Icon(Icons.directions_run, size: 48, color: Colors.white),
              ),
              const SizedBox(height: 20),
              const Text(
                '校园跑',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 32),
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
