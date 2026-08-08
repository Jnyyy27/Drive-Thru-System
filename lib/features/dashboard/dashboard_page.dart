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
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.authSession,
      builder: (context, _) {
        final user =
            widget.authSession.currentUser ?? const <String, dynamic>{};

        return SpeedShell(
          title: 'Drive-Thru System',
          subtitle: 'Speed Burger',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              OutlinedButton(
                onPressed: widget.authSession.busy
                    ? null
                    : () async {
                        await widget.authSession.refreshUser();
                      },
                child: const Text('Refresh'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: widget.authSession.busy
                    ? null
                    : widget.authSession.signOut,
                child: const Text('Log out'),
              ),
            ],
          ),
          child: ListView(
            children: [
              _heroCard(context, user),
              const SizedBox(height: 20),
              Text(
                'Quick actions',
                style: Theme.of(context).textTheme.labelSmall,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 20,
                runSpacing: 20,
                children: [
                  _navCard(
                    context,
                    title: 'Scan and Chat',
                    description:
                        'Capture a plate, confirm direction, and continue the drive-thru assistant flow.',
                    icon: Icons.camera_alt_outlined,
                    onTap: () => context.go('/scan'),
                  ),
                  _navCard(
                    context,
                    title: 'Menu',
                    description:
                        'Browse menu items, categories, availability, and prices.',
                    icon: Icons.restaurant_menu_outlined,
                    onTap: () => context.go('/menu'),
                  ),
                  _navCard(
                    context,
                    title: 'Logs',
                    description: 'Review recent entry logs.',
                    icon: Icons.receipt_long_outlined,
                    onTap: () => context.go('/logs'),
                  ),
                  _navCard(
                    context,
                    title: 'Orders',
                    description: 'Inspect live queue and order lines.',
                    icon: Icons.local_shipping_outlined,
                    onTap: () => context.go('/orders'),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _heroCard(BuildContext context, Map<String, dynamic> user) {
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
              child: Text(
                (user['email']?.toString().isNotEmpty ?? false)
                    ? user['email'].toString()[0].toUpperCase()
                    : 'U',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
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
                      decoration: const BoxDecoration(
                        color: SpeedColors.green,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'Signed in',
                      style: TextStyle(
                        fontSize: 12,
                        color: SpeedColors.inkSoft,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${user['email'] ?? '-'}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  'Role: ${user['role'] ?? '-'}',
                  style: const TextStyle(color: SpeedColors.inkSoft),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF8EA),
              border: Border.all(color: SpeedColors.amber, width: 1.4),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '${user['role'] ?? '-'}',
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: const Color(0xFF6B4708)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _navCard(
    BuildContext context, {
    required String title,
    required String description,
    required IconData icon,
    required VoidCallback? onTap,
  }) {
    return SizedBox(
      width: 280,
      child: SpeedCard(
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEEF2F7),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: 22, color: SpeedColors.navy),
                ),
                const SizedBox(height: 16),
                Text(title, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                Text(
                  description,
                  style: const TextStyle(
                    color: SpeedColors.inkSoft,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  onTap == null ? 'Pending implementation' : 'Open',
                  style: const TextStyle(
                    color: SpeedColors.navy,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
