import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'api_client.dart';
import 'auth_token_store.dart';
import 'cognito_auth_service.dart';

class AuthSessionController extends ChangeNotifier {
  AuthSessionController() : _tokenStore = AuthTokenStore(), _authService = CognitoAuthService(AuthTokenStore()) {
    _apiClient = ApiClient(
      _tokenStore,
      onUnauthorized: _handleUnauthorized,
    );
  }

  final AuthTokenStore _tokenStore;
  late final ApiClient _apiClient;
  final CognitoAuthService _authService;

  bool _initialized = false;
  bool _busy = false;
  String? _statusText;
  String? _tokenPreview;
  Map<String, dynamic>? _currentUser;

  bool get initialized => _initialized;
  bool get busy => _busy;
  bool get isAuthenticated => _currentUser != null;
  String? get statusText => _statusText;
  String? get tokenPreview => _tokenPreview;
  Map<String, dynamic>? get currentUser => _currentUser;
  ApiClient get apiClient => _apiClient;
  CognitoAuthService get authService => _authService;

  Future<void> bootstrap() async {
    final consumedRedirectToken = await _authService
        .consumeRedirectTokenIfPresent();
    final token = await _tokenStore.getIdToken() ?? '';
    _tokenPreview = _previewToken(token);
    _statusText = consumedRedirectToken
        ? 'Cognito login completed. Refreshing current user...'
        : token.isEmpty
        ? 'Sign in with Cognito to start using the API.'
        : 'Saved login found. Refreshing current user...';

    if (token.isNotEmpty || consumedRedirectToken) {
      await refreshUser(silent: true);
    }

    _initialized = true;
    notifyListeners();
  }

  Future<void> signIn() async {
    await _runGuarded(() async {
      final launched = await _authService.launchLogin();
      if (!launched) {
        throw Exception('Could not open Cognito login page.');
      }
      _statusText = 'Redirecting to Cognito login...';
      notifyListeners();
    });
  }

  Future<void> signOut() async {
    await _runGuarded(() async {
      final launched = await _authService.launchLogout();
      if (!launched) {
        throw Exception('Could not open logout page.');
      }
      _currentUser = null;
      _tokenPreview = null;
      _statusText = 'Redirecting to logout...';
      notifyListeners();
    });
  }

  void _handleUnauthorized() {
    _currentUser = null;
    _tokenPreview = null;
    _statusText = 'Session expired. Please sign in again.';
    notifyListeners();
  }

  Future<void> clearLocalToken() async {
    await _runGuarded(() async {
      await _apiClient.clearToken();
      _currentUser = null;
      _tokenPreview = null;
      _statusText = 'Local token cleared.';
      notifyListeners();
    });
  }

  Future<void> refreshUser({bool silent = false}) async {
    try {
      final result = await _apiClient.me();
      final user = result['user'];
      _currentUser = user is Map<String, dynamic>
          ? user
          : user is Map
          ? user.cast<String, dynamic>()
          : result;
      final token = await _tokenStore.getIdToken() ?? '';
      _tokenPreview = _previewToken(token);
      _statusText = silent
          ? 'Signed in successfully.'
          : 'Authenticated successfully.';
    } on DioException catch (error) {
      _currentUser = null;
      _statusText = silent
          ? 'Stored login is unavailable: ${error.response?.statusCode ?? '-'}.'
          : 'Request failed: ${error.response?.statusCode ?? '-'} ${_stringify(error.response?.data) ?? error.message ?? 'Unknown error'}';
    }
    notifyListeners();
  }

  Future<void> checkHealth() async {
    await _runGuarded(() async {
      final result = await _apiClient.health();
      _statusText = 'Health OK: ${_stringify(result)}';
      notifyListeners();
    });
  }

  Future<void> _runGuarded(Future<void> Function() action) async {
    _busy = true;
    notifyListeners();
    try {
      await action();
    } on DioException catch (error) {
      _statusText =
          'Request failed: ${error.response?.statusCode ?? '-'} ${_stringify(error.response?.data) ?? error.message ?? 'Unknown error'}';
      notifyListeners();
    } catch (error) {
      _statusText = 'Error: $error';
      notifyListeners();
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  String? _previewToken(String? token) {
    if (token == null || token.isEmpty) {
      return null;
    }
    if (token.length <= 24) {
      return token;
    }
    return '${token.substring(0, 12)}...${token.substring(token.length - 12)}';
  }

  String? _stringify(Object? value) {
    if (value == null) {
      return null;
    }
    return value.toString();
  }
}