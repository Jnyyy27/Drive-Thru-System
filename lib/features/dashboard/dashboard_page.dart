import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth_session_controller.dart';
import '../../ui/speed_ui.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key, required this.authSession});

  final AuthSessionController authSession;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  late Timer _clockTimer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    // Keep the greeting/clock on the hero card ticking so the console
    // reads as "live" on a shift screen rather than a static snapshot.
    _clockTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _clockTimer.cancel();
    super.dispose();
  }

  String get _greeting {
    final hour = _now.hour;
    if (hour < 5) return 'Working late';
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    if (hour < 22) return 'Good evening';
    return 'Working late';
  }

  String get _timeLabel {
    final h = _now.hour % 12 == 0 ? 12 : _now.hour % 12;
    final m = _now.minute.toString().padLeft(2, '0');
    final period = _now.hour >= 12 ? 'PM' : 'AM';
    return '$h:$m $period';
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.authSession,
      builder: (context, _) {
        final user = widget.authSession.currentUser;

        return SpeedShell(
          title: 'Drive-Thru System',
          subtitle: 'Speed Burger',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              OutlinedButton.icon(
                onPressed: widget.authSession.busy
                    ? null
                    : () async {
                        await widget.authSession.refreshUser();
                      },
                icon: widget.authSession.busy
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh, size: 18),
                label: Text(widget.authSession.busy ? 'Refreshing' : 'Refresh'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: widget.authSession.busy
                    ? null
                    : widget.authSession.signOut,
                icon: const Icon(Icons.logout, size: 18),
                label: const Text('Log out'),
              ),
            ],
          ),
          child: ListView(
            children: [
              _heroCard(context, user),
              const SizedBox(height: 24),
              const SpeedSectionLabel('Quick actions'),
              const SizedBox(height: 12),
              _quickActionsGrid(context),
            ],
          ),
        );
      },
    );
  }

  Widget _heroCard(BuildContext context, Map<String, dynamic>? user) {
    final hasUser = user != null && (user['email']?.toString().isNotEmpty ?? false);
    final email = hasUser ? user['email'].toString() : null;
    final role = hasUser ? (user['role']?.toString() ?? '-') : null;

    return SpeedCard(
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(23),
              gradient: const LinearGradient(
                colors: [SpeedColors.navy, SpeedColors.navyDeep],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Center(
              child: email != null
                  ? Text(
                      email[0].toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    )
                  : const Icon(Icons.person_outline, color: Colors.white, size: 22),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: widget.authSession.busy
                            ? SpeedColors.amber
                            : SpeedColors.green,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      widget.authSession.busy
                          ? 'Refreshing…'
                          : (hasUser ? 'Signed in' : 'Loading session'),
                      style: const TextStyle(
                        fontSize: 12,
                        color: SpeedColors.inkSoft,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      _timeLabel,
                      style: const TextStyle(
                        fontSize: 12,
                        color: SpeedColors.inkSoft,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  hasUser ? '$_greeting, ${email!.split('@').first}' : 'Loading…',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (hasUser) ...[
                  const SizedBox(height: 2),
                  Text(
                    email!,
                    style: const TextStyle(color: SpeedColors.inkSoft, fontSize: 13),
                  ),
                ],
              ],
            ),
          ),
          if (role != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF8EA),
                border: Border.all(color: SpeedColors.amber, width: 1.4),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                role,
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(color: const Color(0xFF6B4708)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _quickActionsGrid(BuildContext context) {
    final actions = <_QuickAction>[
      _QuickAction(
        title: 'Scan and Chat',
        description:
            'Capture a plate, confirm direction, and continue the drive-thru assistant flow.',
        icon: Icons.camera_alt_outlined,
        accent: SpeedColors.amber,
        onTap: () => context.go('/scan'),
      ),
      _QuickAction(
        title: 'Menu',
        description: 'Browse menu items, categories, availability, and prices.',
        icon: Icons.restaurant_menu_outlined,
        accent: SpeedColors.green,
        onTap: () => context.go('/menu'),
      ),
      _QuickAction(
        title: 'Logs',
        description: 'Review recent entry logs.',
        icon: Icons.receipt_long_outlined,
        accent: SpeedColors.navy,
        onTap: () => context.go('/logs'),
      ),
      _QuickAction(
        title: 'Orders',
        description: 'Inspect live queue and order lines.',
        icon: Icons.local_shipping_outlined,
        accent: const Color(0xFF2563EB),
        onTap: () => context.go('/orders'),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        // Fixed-column grid so cards line up in even rows instead of the
        // ragged gaps a Wrap leaves at odd container widths.
        final width = constraints.maxWidth;
        final columns = width >= 1000
            ? 4
            : width >= 720
                ? 3
                : width >= 460
                    ? 2
                    : 1;

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: actions.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 20,
            mainAxisSpacing: 20,
            childAspectRatio: 1.35,
          ),
          itemBuilder: (context, index) => _navCard(context, actions[index]),
        );
      },
    );
  }

  Widget _navCard(BuildContext context, _QuickAction action) {
    // SpeedCard now owns hover/press lift + accent tinting, so this is
    // just layout — no more hand-rolled InkWell per card.
    return SpeedCard(
      onTap: action.onTap,
      accent: action.accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: action.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(action.icon, size: 22, color: action.accent),
              ),
              const Spacer(),
              Icon(
                Icons.arrow_outward,
                size: 18,
                color: action.onTap == null
                    ? SpeedColors.inkSoft.withValues(alpha: 0.4)
                    : SpeedColors.inkSoft,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(action.title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Expanded(
            child: Text(
              action.description,
              style: const TextStyle(
                color: SpeedColors.inkSoft,
                height: 1.35,
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            action.onTap == null ? 'Pending implementation' : 'Open',
            style: TextStyle(
              color: action.onTap == null ? SpeedColors.inkSoft : action.accent,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickAction {
  const _QuickAction({
    required this.title,
    required this.description,
    required this.icon,
    required this.accent,
    required this.onTap,
  });

  final String title;
  final String description;
  final IconData icon;
  final Color accent;
  final VoidCallback? onTap;
}