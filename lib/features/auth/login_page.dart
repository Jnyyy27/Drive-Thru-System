import 'package:flutter/material.dart';

import '../../core/auth_session_controller.dart';
import '../../ui/speed_ui.dart';

class LoginPage extends StatelessWidget {
  const LoginPage({super.key, required this.authSession});

  final AuthSessionController authSession;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: authSession,
      builder: (context, _) {
        return Scaffold(
          backgroundColor: SpeedColors.bg,
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 580),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: SpeedCard(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                color: SpeedColors.navy,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                Icons.local_shipping_outlined,
                                color: Colors.white,
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'SPEED BURGER',
                                  style: Theme.of(context).textTheme.labelSmall,
                                ),
                                Text(
                                  'Drive-Thru Console',
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        const Text(
                          'Sign in with Cognito to access live plate scan, assistant chat, and operations dashboards.',
                          style: TextStyle(
                            color: SpeedColors.inkSoft,
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: 18),
                        _statusChip(
                          authSession.statusText ?? 'Ready to sign in.',
                        ),
                        const SizedBox(height: 18),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: authSession.busy
                                ? null
                                : authSession.signIn,
                            icon: const Icon(Icons.login),
                            label: Text(
                              authSession.busy
                                  ? 'Opening Cognito...'
                                  : 'Sign in with Cognito',
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        const Divider(color: SpeedColors.line),
                        const SizedBox(height: 10),
                        Text(
                          'Auth URL: ${authSession.authService.authBaseUrl}',
                          style: const TextStyle(color: SpeedColors.inkFaint),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'API URL: ${authSession.apiClient.baseUrl}',
                          style: const TextStyle(color: SpeedColors.inkFaint),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _statusChip(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: SpeedColors.line),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(text, style: const TextStyle(color: SpeedColors.inkSoft)),
    );
  }
}
