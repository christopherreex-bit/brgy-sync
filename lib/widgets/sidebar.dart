import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../utils/constants.dart';

class Sidebar extends StatefulWidget {
  const Sidebar({super.key});

  @override
  State<Sidebar> createState() => _SidebarState();
}

class _SidebarState extends State<Sidebar> {
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final user = auth.currentUserModel;
    if (user == null) return const SizedBox.shrink();

    final roleLabel = user.role.toUpperCase();
    final initials = user.name.isNotEmpty
        ? user.name.split(' ').map((w) => w[0]).take(2).join()
        : '?';

    final currentLocation = GoRouterState.of(context).uri.toString();

    return SizedBox(
      width: 260,
      child: ColoredBox(
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
            // Navigation — always-visible custom scrollbar
            Expanded(
              child: Stack(
                children: [
                  ListView(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    children: [
                      if (user.isStaff || user.isOfficer || user.isCaptain) ...[
                        _sectionHeader('CASE MONITORING'),
                        _navItem(context, Icons.list_alt, 'Case Queue', '/dashboard', currentLocation),
                        _navItem(context, Icons.assignment, 'Distributions', '/dashboard/distributions', currentLocation),
                        _navItem(context, Icons.history, 'Audit Trail', '/dashboard/audit', currentLocation),
                      ],
                      if (user.isOfficer || user.isCaptain) ...[
                        _sectionHeader('CHARTER COMPLIANCE'),
                        _navItem(context, Icons.timer, 'SLA Monitoring', '/dashboard/sla-monitoring', currentLocation),
                        _navItem(context, Icons.warning_amber, 'Overdue Cases', '/dashboard/overdue', currentLocation),
                        _navItem(context, Icons.assessment, 'Compliance Report', '/dashboard/compliance-report', currentLocation),
                        if (user.isCaptain)
                          _navItem(context, Icons.settings, 'SLA Configuration', '/dashboard/sla-config', currentLocation),
                      ],
                      if (user.isOfficer || user.isCaptain) ...[
                        _sectionHeader('BUDGET TRACKING'),
                        _navItem(context, Icons.account_balance_wallet, 'Budget Overview', '/dashboard/budget', currentLocation),
                        if (user.isCaptain)
                          _navItem(context, Icons.tune, 'Allocation Setup', '/dashboard/allocation-setup', currentLocation),
                        _navItem(context, Icons.receipt_long, 'Expenditure Summary', '/dashboard/expenditure', currentLocation),
                      ],
                      if (user.isCaptain) ...[
                        _sectionHeader('ANALYTICS & REPORTING'),
                        _navItem(context, Icons.dashboard, 'Analytics Dashboard', '/dashboard/analytics', currentLocation),
                        _navItem(context, Icons.trending_up, 'Service Demand', '/dashboard/service-demand', currentLocation),
                        _navItem(context, Icons.description, 'Report Builder', '/dashboard/report-builder', currentLocation),
                        _navItem(context, Icons.archive, 'Report Archive', '/dashboard/report-archive', currentLocation),
                      ],
                      if (user.isCaptain) ...[
                        _sectionHeader('ADMINISTRATION'),
                        _navItem(context, Icons.manage_accounts, 'Account Management', '/dashboard/account-management', currentLocation),
                      ],
                      // Bottom padding so last item isn't hidden behind logout
                      const SizedBox(height: 8),
                    ],
                  ),
                  // Custom always-visible scrollbar track + thumb
                  Positioned(
                    right: 0,
                    top: 0,
                    bottom: 0,
                    child: _CustomScrollbar(
                      controller: _scrollController,
                    ),
                  ),
                ],
              ),
            ),
            // Logout
            const Divider(color: Colors.white12, height: 1),
            _logoutTile(context, auth),
          ],
        ),
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

  Widget _navItem(BuildContext context, IconData icon, String label, String route, String currentLocation) {
    final isActive = currentLocation == route || currentLocation.startsWith('$route/');
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      decoration: BoxDecoration(
        color: isActive ? kNavyLight : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => context.go(route),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Icon(icon, color: isActive ? Colors.white : kSidebarInactive, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(label,
                      style: TextStyle(
                          color: isActive ? Colors.white : kSidebarInactive,
                          fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                          fontSize: 13)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _logoutTile(BuildContext context, AuthService auth) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () async {
          await auth.logout();
          if (context.mounted) context.go('/login');
        },
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(Icons.logout, color: Colors.white70, size: 20),
              SizedBox(width: 12),
              Text('Log Out', style: TextStyle(color: Colors.white70, fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Custom scrollbar that's always visible with a track and thumb
class _CustomScrollbar extends StatefulWidget {
  final ScrollController controller;
  const _CustomScrollbar({required this.controller});

  @override
  State<_CustomScrollbar> createState() => _CustomScrollbarState();
}

class _CustomScrollbarState extends State<_CustomScrollbar> {
  double _thumbHeight = 0;
  double _thumbTop = 0;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_update);
    WidgetsBinding.instance.addPostFrameCallback((_) => _update());
  }

  @override
  void dispose() {
    widget.controller.removeListener(_update);
    super.dispose();
  }

  void _update() {
    if (!widget.controller.hasClients) return;
    final position = widget.controller.position;
    if (!position.hasContentDimensions || position.maxScrollExtent <= 0) {
      if (_visible) setState(() => _visible = false);
      return;
    }
    setState(() {
      _visible = true;
      final trackHeight = position.viewportDimension;
      // Thumb size proportional to content ratio, min 30px
      final contentRatio = position.viewportDimension / (position.viewportDimension + position.maxScrollExtent);
      _thumbHeight = (trackHeight * contentRatio).clamp(30.0, trackHeight);
      // Thumb position
      final scrollFraction = position.pixels / position.maxScrollExtent;
      _thumbTop = scrollFraction * (trackHeight - _thumbHeight);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) return const SizedBox(width: 12);

    return GestureDetector(
      onVerticalDragUpdate: (details) {
        if (!widget.controller.hasClients) return;
        final position = widget.controller.position;
        if (position.maxScrollExtent <= 0) return;
        // Convert drag delta to scroll delta
        final trackHeight = position.viewportDimension - _thumbHeight;
        if (trackHeight <= 0) return;
        final scrollDelta = details.delta.dy * (position.maxScrollExtent / trackHeight);
        widget.controller.jumpTo((widget.controller.offset + scrollDelta).clamp(0.0, position.maxScrollExtent));
      },
      child: Container(
        width: 12,
        color: Colors.white.withValues(alpha: 0.05),
        child: Stack(
          children: [
            Positioned(
              top: _thumbTop,
              left: 2,
              right: 2,
              child: Container(
                height: _thumbHeight,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
