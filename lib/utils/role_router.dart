import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../screens/resident/resident_shell.dart';
import '../screens/dashboard/dashboard_shell.dart';
import '../screens/auth/login_screen.dart';
import '../screens/auth/register_screen.dart';
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

final appRouter = GoRouter(
  initialLocation: '/login',
  routes: [
    GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
    GoRoute(path: '/register', builder: (context, state) => const RegisterScreen()),

    // ─── Resident Portal ──────────────────────────────────────────
    GoRoute(
      path: '/resident',
      builder: (context, state) => const ResidentShell(),
    ),

    // ─── Dashboard ────────────────────────────────────────────────
    ShellRoute(
      builder: (context, state, child) => DashboardShell(child: child),
      routes: [
        GoRoute(path: '/dashboard', builder: (context, state) => const CaseQueueScreen()),
        GoRoute(path: '/dashboard/case/:caseId', builder: (context, state) {
          final caseId = state.pathParameters['caseId']!;
          return CaseDetailScreen(caseId: caseId);
        }),
        GoRoute(path: '/dashboard/case/:caseId/update-status', builder: (context, state) {
          final caseId = state.pathParameters['caseId']!;
          return UpdateStatusScreen(caseId: caseId);
        }),
        GoRoute(path: '/dashboard/distributions', builder: (context, state) => const DistributionsScreen()),
        GoRoute(path: '/dashboard/audit', builder: (context, state) => const AuditTrailScreen()),
        GoRoute(path: '/dashboard/sla-monitoring', builder: (context, state) => const SlaMonitoringScreen()),
        GoRoute(path: '/dashboard/overdue', builder: (context, state) => const OverdueCasesScreen()),
        GoRoute(path: '/dashboard/compliance-report', builder: (context, state) => const ComplianceReportScreen()),
        GoRoute(path: '/dashboard/sla-config', builder: (context, state) => const SlaConfigScreen()),
        GoRoute(path: '/dashboard/budget', builder: (context, state) => const BudgetOverviewScreen()),
        GoRoute(path: '/dashboard/budget/:programId', builder: (context, state) {
          final programId = state.pathParameters['programId']!;
          return ProgramDetailScreen(programId: programId);
        }),
        GoRoute(path: '/dashboard/allocation-setup', builder: (context, state) => const AllocationSetupScreen()),
        GoRoute(path: '/dashboard/expenditure', builder: (context, state) => const ExpenditureSummaryScreen()),
        GoRoute(path: '/dashboard/analytics', builder: (context, state) => const AnalyticsDashboardScreen()),
        GoRoute(path: '/dashboard/service-demand', builder: (context, state) => const ServiceDemandScreen()),
        GoRoute(path: '/dashboard/report-builder', builder: (context, state) => const ReportBuilderScreen()),
        GoRoute(path: '/dashboard/report-archive', builder: (context, state) => const ReportArchiveScreen()),
        GoRoute(path: '/dashboard/account-management', builder: (context, state) => const AccountManagementScreen()),
      ],
    ),
  ],
  redirect: (context, state) {
    final auth = context.read<AuthService>();
    final isLoggedIn = auth.isLoggedIn;
    final isOnAuthScreen = state.matchedLocation == '/login' || state.matchedLocation == '/register';

    if (!isLoggedIn && !isOnAuthScreen) return '/login';
    if (isLoggedIn && isOnAuthScreen) {
      final user = auth.currentUserModel;
      if (user != null && user.role == 'resident') return '/resident';
      return '/dashboard';
    }
    return null;
  },
);
