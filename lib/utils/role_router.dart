import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../screens/resident/resident_shell.dart';
import '../screens/dashboard/dashboard_shell.dart';
import '../screens/auth/login_screen.dart';
import '../screens/auth/register_screen.dart';

final appRouter = GoRouter(
  initialLocation: '/login',
  routes: [
    GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
    GoRoute(path: '/register', builder: (context, state) => const RegisterScreen()),
    ShellRoute(
      builder: (context, state, child) => child,
      routes: [
        GoRoute(
          path: '/resident',
          builder: (context, state) => const ResidentShell(),
        ),
        GoRoute(
          path: '/dashboard',
          builder: (context, state) => const DashboardShell(),
        ),
      ],
    ),
  ],
  redirect: (context, state) {
    final auth = context.read<AuthService>();
    final isLoggedIn = auth.isLoggedIn;
    final isOnAuthScreen = state.matchedLocation == '/login' ||
        state.matchedLocation == '/register';

    if (!isLoggedIn && !isOnAuthScreen) return '/login';
    if (isLoggedIn && isOnAuthScreen) {
      final user = auth.currentUserModel;
      if (user != null && user.role == 'resident') return '/resident';
      return '/dashboard';
    }
    return null;
  },
);
