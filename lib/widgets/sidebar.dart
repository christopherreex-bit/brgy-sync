import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../utils/constants.dart';

class Sidebar extends StatelessWidget {
  const Sidebar({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final user = auth.currentUserModel;
    if (user == null) return const SizedBox.shrink();

    final roleLabel = user.role.toUpperCase();
    final initials = user.name.isNotEmpty
        ? user.name.split(' ').map((w) => w[0]).take(2).join()
        : '?';

    return Container(
      width: 260,
      color: kNavy,
      child: Column(
        children: [
          // Branding
          Container(
            padding: const EdgeInsets.all(20),
            width: double.infinity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('BrgySync',
                    style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                Text('Brgy. Calzada-Tipas, Taguig',
                    style: TextStyle(color: Colors.grey.shade400, fontSize: 11)),
              ],
            ),
          ),
          const Divider(color: Colors.white12, height: 1),
          // User info
          Container(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: kNavyLight,
                  child: Text(initials,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(user.name,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                          overflow: TextOverflow.ellipsis),
                      Text(roleLabel,
                          style: TextStyle(color: Colors.grey.shade400, fontSize: 11)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(color: Colors.white12, height: 1),
          // Navigation
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                // ─── Case Monitoring ────────────────────────────
                if (user.isStaff || user.isOfficer || user.isCaptain) ...[
                  _sectionHeader('CASE MONITORING'),
                  _navItem(context, Icons.list_alt, 'Case Queue', '/dashboard'),
                  _navItem(context, Icons.assignment, 'Distributions', '/dashboard/distributions'),
                  _navItem(context, Icons.history, 'Audit Trail', '/dashboard/audit'),
                ],
                // ─── Charter Compliance ─────────────────────────
                if (user.isOfficer || user.isCaptain) ...[
                  _sectionHeader('CHARTER COMPLIANCE'),
                  _navItem(context, Icons.timer, 'SLA Monitoring', '/dashboard/sla-monitoring'),
                  _navItem(context, Icons.warning_amber, 'Overdue Cases', '/dashboard/overdue'),
                  _navItem(context, Icons.assessment, 'Compliance Report', '/dashboard/compliance-report'),
                  if (user.isCaptain)
                    _navItem(context, Icons.settings, 'SLA Configuration', '/dashboard/sla-config'),
                ],
                // ─── Budget Tracking ────────────────────────────
                if (user.isOfficer || user.isCaptain) ...[
                  _sectionHeader('BUDGET TRACKING'),
                  _navItem(context, Icons.account_balance_wallet, 'Budget Overview', '/dashboard/budget'),
                  if (user.isCaptain)
                    _navItem(context, Icons.tune, 'Allocation Setup', '/dashboard/allocation-setup'),
                  _navItem(context, Icons.receipt_long, 'Expenditure Summary', '/dashboard/expenditure'),
                ],
                // ─── Analytics & Reporting ──────────────────────
                if (user.isCaptain) ...[
                  _sectionHeader('ANALYTICS & REPORTING'),
                  _navItem(context, Icons.dashboard, 'Analytics Dashboard', '/dashboard/analytics'),
                  _navItem(context, Icons.trending_up, 'Service Demand', '/dashboard/service-demand'),
                  _navItem(context, Icons.description, 'Report Builder', '/dashboard/report-builder'),
                  _navItem(context, Icons.archive, 'Report Archive', '/dashboard/report-archive'),
                ],
              ],
            ),
          ),
          // Logout
          const Divider(color: Colors.white12, height: 1),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.white70),
            title: const Text('Log Out', style: TextStyle(color: Colors.white70)),
            onTap: () async {
              await auth.logout();
              if (context.mounted) context.go('/login');
            },
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(title,
          style: const TextStyle(
              color: kSidebarInactive, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
    );
  }

  Widget _navItem(BuildContext context, IconData icon, String label, String route) {
    final isActive = GoRouterState.of(context).matchedLocation == route;
    return ListTile(
      leading: Icon(icon, color: isActive ? Colors.white : kSidebarInactive, size: 20),
      title: Text(label,
          style: TextStyle(
              color: isActive ? Colors.white : kSidebarInactive,
              fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
              fontSize: 13)),
      dense: true,
      selected: isActive,
      selectedTileColor: kNavyLight,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      onTap: () => context.go(route),
    );
  }
}
