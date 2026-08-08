import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth_session_controller.dart';
import '../../ui/speed_ui.dart';

class LogsPage extends StatefulWidget {
  const LogsPage({super.key, required this.authSession});

  final AuthSessionController authSession;

  @override
  State<LogsPage> createState() => _LogsPageState();
}

class _LogsPageState extends State<LogsPage> {
  late Future<Map<String, dynamic>> _logsFuture;
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _logsFuture = widget.authSession.apiClient.logs();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final future = widget.authSession.apiClient.logs();
    setState(() {
      _logsFuture = future;
    });
    await future;
  }

  @override
  Widget build(BuildContext context) {
    return SpeedShell(
      title: 'Entry Logs',
      subtitle: 'Speed Burger · Drive-Thru System',
      trailing: OutlinedButton(
        onPressed: () => context.go('/dashboard'),
        child: const Text('Dashboard'),
      ),
      child: FutureBuilder<Map<String, dynamic>>(
        future: _logsFuture,
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

          final rows = ((snapshot.data?['logs'] as List?) ?? const [])
              .cast<Map>()
              .map((row) => row.cast<String, dynamic>())
              .toList();

          final filtered = _query.isEmpty
              ? rows
              : rows
                    .where(
                      (row) =>
                          (row['plate_number']?.toString().toLowerCase() ?? '')
                              .contains(_query),
                    )
                    .toList();

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Review gate entry and exit history for campus vehicles.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      onChanged: (value) {
                        setState(() {
                          _query = value.trim().toLowerCase();
                        });
                      },
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search),
                        hintText: 'Search by plate number...',
                        filled: true,
                        fillColor: SpeedColors.surface,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: SpeedColors.line),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: SpeedColors.line),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SpeedPill(
                    text: _query.isEmpty
                        ? '${rows.length} entries'
                        : '${filtered.length} of ${rows.length} entries',
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Expanded(
                child: SpeedCard(
                  padding: EdgeInsets.zero,
                  child: filtered.isEmpty
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(36),
                            child: Text('No logs match that plate number.'),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(14),
                          itemBuilder: (context, index) {
                            final row = filtered[index];
                            final status = (row['status']?.toString() ?? '-')
                                .toUpperCase();

                            return Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                border: Border.all(color: SpeedColors.line),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: ListTile(
                                leading: Text(
                                  '${row['id'] ?? '-'}',
                                  style: Theme.of(context).textTheme.labelSmall,
                                ),
                                title: Text(
                                  row['plate_number']?.toString() ?? '-',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                subtitle: Text(
                                  row['entry_time']?.toString() ?? '-',
                                  style: const TextStyle(
                                    color: SpeedColors.inkSoft,
                                  ),
                                ),
                                trailing: status == 'IN'
                                    ? const SpeedBadge(
                                        text: 'IN',
                                        background: Color(0xFFEAF7EF),
                                        foreground: Color(0xFF1F7A4D),
                                      )
                                    : status == 'OUT'
                                    ? const SpeedBadge(
                                        text: 'OUT',
                                        background: Color(0xFFFFF3DC),
                                        foreground: Color(0xFF6B4708),
                                      )
                                    : SpeedBadge(
                                        text: status,
                                        background: const Color(0xFFEEF1F4),
                                        foreground: SpeedColors.inkSoft,
                                      ),
                              ),
                            );
                          },
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 10),
                          itemCount: filtered.length,
                        ),
                ),
              ),
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
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
