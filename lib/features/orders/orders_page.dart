import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth_session_controller.dart';
import '../../ui/speed_ui.dart';

class OrdersPage extends StatefulWidget {
  const OrdersPage({super.key, required this.authSession});

  final AuthSessionController authSession;

  @override
  State<OrdersPage> createState() => _OrdersPageState();
}

class _OrdersPageState extends State<OrdersPage> {
  late Future<Map<String, dynamic>> _ordersFuture;

  @override
  void initState() {
    super.initState();
    _ordersFuture = widget.authSession.apiClient.ordersDisplay();
  }

  Future<void> _refresh() async {
    final future = widget.authSession.apiClient.ordersDisplay();
    setState(() {
      _ordersFuture = future;
    });
    await future;
  }

  @override
  Widget build(BuildContext context) {
    return SpeedShell(
      title: 'Order Display',
      subtitle: 'Speed Burger · Drive-Thru System',
      trailing: OutlinedButton(
        onPressed: () => context.go('/dashboard'),
        child: const Text('Dashboard'),
      ),
      child: FutureBuilder<Map<String, dynamic>>(
        future: _ordersFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _ErrorState(
              message: snapshot.error.toString(),
              onRetry: _refresh,
            );
          }

          final data = snapshot.data ?? const <String, dynamic>{};
          final orders = ((data['orders'] as List?) ?? const [])
              .cast<Map>()
              .map((row) => row.cast<String, dynamic>())
              .toList();
          final counts =
              (data['status_counts'] as Map?)?.cast<String, dynamic>() ??
              const <String, dynamic>{};

          return ListView(
            children: [
              Text(
                'Monitor current drive-thru queue and service load in real time.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: counts.entries
                    .map(
                      (entry) =>
                          SpeedPill(text: '${entry.key}: ${entry.value}'),
                    )
                    .toList(),
              ),
              const SizedBox(height: 20),
              for (final order in orders) ...[
                SpeedCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Order #${order['order_id']} - ${order['plate_number']}',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          SpeedPill(text: order['status']?.toString() ?? '-'),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Total: RM ${order['total_amount']}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        'Created: ${order['created_at'] ?? '-'}',
                        style: const TextStyle(color: SpeedColors.inkSoft),
                      ),
                      const SizedBox(height: 12),
                      ...(((order['lines'] as List?) ?? const [])
                          .cast<Map>()
                          .map((line) => line.cast<String, dynamic>())
                          .map(
                            (line) => Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      '${line['quantity']} x ${line['name']}',
                                    ),
                                  ),
                                  Text(
                                    'RM ${line['subtotal']}',
                                    style: const TextStyle(
                                      color: SpeedColors.navy,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SpeedCard(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(onPressed: onRetry, child: const Text('Retry')),
            ],
          ),
        ),
      ),
    );
  }
}
