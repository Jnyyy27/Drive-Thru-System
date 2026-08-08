import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';

import 'core/auth_session_controller.dart';
import 'features/auth/login_page.dart';
import 'features/dashboard/dashboard_page.dart';
import 'features/logs/logs_page.dart';
import 'features/menu/menu_page.dart';
import 'features/orders/orders_page.dart';
import 'features/scan/scan_chat_page.dart';
import 'ui/speed_ui.dart';

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final AuthSessionController _authSession;
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _authSession = AuthSessionController()..bootstrap();
    _router = GoRouter(
      initialLocation: '/dashboard',
      refreshListenable: _authSession,
      redirect: (context, state) {
        final onLegacyTokenRoute = state.matchedLocation.startsWith(
          '/id_token=',
        );

        if (!_authSession.initialized) {
          return null;
        }

        final onLogin = state.matchedLocation == '/login';
        if (onLegacyTokenRoute) {
          return _authSession.isAuthenticated ? '/dashboard' : '/login';
        }
        if (!_authSession.isAuthenticated && !onLogin) {
          return '/login';
        }
        if (_authSession.isAuthenticated && onLogin) {
          return '/dashboard';
        }
        return null;
      },
      routes: [
        GoRoute(
          path: '/id_token=:token',
          builder: (context, state) =>
              const Scaffold(body: Center(child: CircularProgressIndicator())),
        ),
        GoRoute(
          path: '/login',
          builder: (context, state) => LoginPage(authSession: _authSession),
        ),
        GoRoute(
          path: '/dashboard',
          builder: (context, state) => DashboardPage(authSession: _authSession),
        ),
        GoRoute(
          path: '/scan',
          builder: (context, state) => ScanChatPage(authSession: _authSession),
        ),
        GoRoute(
          path: '/menu',
          builder: (context, state) {
            final extra = state.extra;
            Map<String, dynamic>? handoff;
            if (extra is Map) {
              handoff = extra.map(
                (key, value) => MapEntry(key.toString(), value),
              );
            }

            return MenuPage(
              authSession: _authSession,
              initialPlateNumber: handoff?['plate_number']?.toString(),
              initialDirection: handoff?['direction']?.toString(),
              initialAssistantMessage: handoff?['welcome_message']?.toString(),
            );
          },
        ),
        GoRoute(
          path: '/logs',
          builder: (context, state) => LogsPage(authSession: _authSession),
        ),
        GoRoute(
          path: '/orders',
          builder: (context, state) => OrdersPage(authSession: _authSession),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF0F766E);

    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'Drive Thru Console',
      routerConfig: _router,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: SpeedColors.bg,
        useMaterial3: true,
        textTheme: GoogleFonts.manropeTextTheme().copyWith(
          titleLarge: GoogleFonts.spaceGrotesk(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: SpeedColors.navyDeep,
          ),
          titleMedium: GoogleFonts.spaceGrotesk(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: SpeedColors.navyDeep,
          ),
          labelSmall: GoogleFonts.ibmPlexMono(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: SpeedColors.inkSoft,
          ),
        ),
        cardTheme: const CardThemeData(
          color: SpeedColors.surface,
          elevation: 0,
          margin: EdgeInsets.zero,
        ),
      ),
    );
  }
}
