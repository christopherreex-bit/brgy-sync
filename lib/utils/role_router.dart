import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../screens/resident/resident_shell.dart';
import '../screens/dashboard/dashboard_shell.dart';
import '../screens/auth/login_screen.dart';
import '../screens/auth/register_screen.dart';
import '../screens/auth/change_temporary_password_screen.dart';
import '../screens/dashboard/case_queue_screen.dart';
import '../screens/dashboard/case_detail_screen.dart';
import '../screens/dashboard/update_status_screen.dart';
import '../screens/dashboard/distributions_screen.dart';
import '../screens/dashboard/audit_trail_screen.dart';
import '../screens/dashboard/sla_monitoring_screen.dart';
import '../screens/dashboard/overdue_cases_screen.dart';
import '../screens/dashboard/compliance_report_screen.dart';
import '../screens/dashboard/sla_config_screen.dart';
import '../screens/dashboard/budget_overview_screen.dart';
import '../screens/dashboard/program_detail_screen.dart';
import '../screens/dashboard/allocation_setup_screen.dart';
import '../screens/dashboard/expenditure_summary_screen.dart';
import '../screens/dashboard/analytics_dashboard_screen.dart';
import '../screens/dashboard/service_demand_screen.dart';
import '../screens/dashboard/report_builder_screen.dart';
import '../screens/dashboard/report_archive_screen.dart';
import '../screens/dashboard/account_management_screen.dart';
import '../screens/dashboard/user_management_screen.dart';
import '../screens/dashboard/walk_in_intake_screen.dart';
import '../screens/dashboard/citizen_registry_screen.dart';
import '../screens/dashboard/cash_position_screen.dart';
import '../screens/dashboard/delegation_history_screen.dart';

final appRouter = GoRouter(
  initialLocation: '/login',
  routes: [
    GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
    GoRoute(
      path: '/register',
      builder: (context, state) => const RegisterScreen(),
    ),
    GoRoute(
      path: '/change-temporary-password',
      builder: (context, state) => const ChangeTemporaryPasswordScreen(),
    ),

    // ─── Resident Portal ──────────────────────────────────────────
    GoRoute(
      path: '/resident',
      builder: (context, state) => const ResidentShell(),
    ),

    // ─── Dashboard ────────────────────────────────────────────────
    ShellRoute(
      builder: (context, state, child) => DashboardShell(child: child),
      routes: [
        GoRoute(
          path: '/dashboard/citizen-registry',
          builder: (context, state) => const CitizenRegistryScreen(),
        ),
        GoRoute(
          path: '/dashboard',
          builder: (context, state) => const CaseQueueScreen(),
        ),
        GoRoute(
          path: '/dashboard/case/:caseId',
          builder: (context, state) {
            final caseId = state.pathParameters['caseId']!;
            return CaseDetailScreen(
              caseId: caseId,
              readOnly: state.uri.queryParameters['readonly'] == 'true',
            );
          },
        ),
        GoRoute(
          path: '/dashboard/case/:caseId/update-status',
          builder: (context, state) {
            final caseId = state.pathParameters['caseId']!;
            return UpdateStatusScreen(caseId: caseId);
          },
        ),
        GoRoute(
          path: '/dashboard/distributions',
          builder: (context, state) => const DistributionsScreen(),
        ),
        GoRoute(
          path: '/dashboard/walk-in',
          builder: (context, state) => const WalkInIntakeScreen(),
        ),
        GoRoute(
          path: '/dashboard/audit',
          builder: (context, state) => const AuditTrailScreen(),
        ),
        GoRoute(
          path: '/dashboard/sla-monitoring',
          builder: (context, state) => const SlaMonitoringScreen(),
        ),
        GoRoute(
          path: '/dashboard/overdue',
          builder: (context, state) => const OverdueCasesScreen(),
        ),
        GoRoute(
          path: '/dashboard/compliance-report',
          builder: (context, state) => const ComplianceReportScreen(),
        ),
        GoRoute(
          path: '/dashboard/sla-config',
          builder: (context, state) => const SlaConfigScreen(),
        ),
        GoRoute(
          path: '/dashboard/budget',
          builder: (context, state) => const BudgetOverviewScreen(),
        ),
        GoRoute(
          path: '/dashboard/cash-position',
          builder: (context, state) => const CashPositionScreen(),
        ),
        GoRoute(
          path: '/dashboard/budget-details',
          builder: (context, state) {
            final query = state.uri.queryParameters;
            return ProgramDetailScreen(
              programName: query['program'],
              fiscalYear: int.tryParse(query['year'] ?? ''),
              quarter: int.tryParse(query['quarter'] ?? ''),
            );
          },
        ),
        GoRoute(
          path: '/dashboard/budget/:programId',
          builder: (context, state) {
            final programId = state.pathParameters['programId']!;
            return ProgramDetailScreen(programId: programId);
          },
        ),
        GoRoute(
          path: '/dashboard/allocation-setup',
          builder: (context, state) => const AllocationSetupScreen(),
        ),
        GoRoute(
          path: '/dashboard/expenditure',
          builder: (context, state) => const ExpenditureSummaryScreen(),
        ),
        GoRoute(
          path: '/dashboard/analytics',
          builder: (context, state) => const AnalyticsDashboardScreen(),
        ),
        GoRoute(
          path: '/dashboard/service-demand',
          builder: (context, state) => const ServiceDemandScreen(),
        ),
        GoRoute(
          path: '/dashboard/report-builder',
          builder: (context, state) => const ReportBuilderScreen(),
        ),
        GoRoute(
          path: '/dashboard/report-archive',
          builder: (context, state) => const ReportArchiveScreen(),
        ),
        GoRoute(
          path: '/dashboard/account-management',
          builder: (context, state) => const AccountManagementScreen(),
        ),
        GoRoute(
          path: '/dashboard/delegation-history',
          builder: (context, state) => const DelegationHistoryScreen(),
        ),
        GoRoute(
          path: '/dashboard/user-management',
          builder: (context, state) => const UserManagementScreen(),
        ),
      ],
    ),
  ],
  redirect: (context, state) {
    final auth = context.read<AuthService>();
    final isLoggedIn = auth.isLoggedIn;
    final isOnAuthScreen =
        state.matchedLocation == '/login' ||
        state.matchedLocation == '/register';
    final isChangingTemporaryPassword =
        state.matchedLocation == '/change-temporary-password';

    if (!isLoggedIn && !isOnAuthScreen) return '/login';
    final user = auth.currentUserModel;
    if (isLoggedIn &&
        user?.hasActingCaptainAuthority == true &&
        (state.matchedLocation == '/dashboard/account-management' ||
            state.matchedLocation == '/dashboard/delegation-history')) {
      return '/dashboard';
    }
    if (isLoggedIn && user?.isTreasurer == true) {
      const financePaths = [
        '/dashboard/budget',
        '/dashboard/budget-details',
        '/dashboard/allocation-setup',
        '/dashboard/cash-position',
        '/dashboard/expenditure',
        '/dashboard/user-management',
      ];
      final allowed = financePaths.any(
        (path) =>
            state.matchedLocation == path ||
            state.matchedLocation.startsWith('$path/'),
      );
      if (!allowed && !isChangingTemporaryPassword) {
        return '/dashboard/budget';
      }
    }
    if (isLoggedIn &&
        user?.mustChangePassword == true &&
        !isChangingTemporaryPassword) {
      return '/change-temporary-password';
    }
    if (isLoggedIn &&
        isChangingTemporaryPassword &&
        user?.mustChangePassword != true) {
      if (user?.isResident == true) return '/resident';
      return user?.isTreasurer == true ? '/dashboard/budget' : '/dashboard';
    }
    if (isLoggedIn && isOnAuthScreen) {
      if (user != null && user.role == 'resident') return '/resident';
      return user?.isTreasurer == true ? '/dashboard/budget' : '/dashboard';
    }
    return null;
  },
);
