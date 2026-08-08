import 'package:url_launcher/url_launcher.dart';

import 'auth_token_store.dart';
import 'url_state.dart';

class CognitoAuthService {
  CognitoAuthService(this._tokenStore);

  final AuthTokenStore _tokenStore;

  static const String _authBaseUrl = String.fromEnvironment(
    'AUTH_BASE_URL',
    defaultValue: 'https://vehicleentrysystem.duckdns.org',
  );

  String get authBaseUrl => _authBaseUrl;

  Uri buildLoginUri() {
    final base = Uri.parse('$_authBaseUrl/login');
    return base.replace(
      queryParameters: <String, String>{
        'next': _dashboardReturnUri().toString(),
      },
    );
  }

  Uri buildLogoutUri() {
    final base = Uri.parse('$_authBaseUrl/logout');
    return base.replace(
      queryParameters: <String, String>{'next': _dashboardReturnUri().toString()},
    );
  }

  Future<bool> launchLogin() async {
    return launchUrl(buildLoginUri(), webOnlyWindowName: '_self');
  }

  Future<bool> launchLogout() async {
    await _tokenStore.clear();
    return launchUrl(buildLogoutUri(), webOnlyWindowName: '_self');
  }

  Future<bool> consumeRedirectTokenIfPresent() async {
    final idToken = _extractIdTokenFromUri(Uri.base);
    if (idToken.isEmpty) {
      return false;
    }

    await _tokenStore.saveIdToken(idToken);
    clearBrowserFragment(_dashboardReturnUri());
    return true;
  }

  String _extractIdTokenFromUri(Uri uri) {
    final fragment = uri.fragment.trim();
    if (fragment.isNotEmpty) {
      final fragmentParams = Uri.splitQueryString(fragment);
      final fragmentToken = (fragmentParams['id_token'] ?? '').trim();
      if (fragmentToken.isNotEmpty) {
        return fragmentToken;
      }
    }

    final queryToken = (uri.queryParameters['id_token'] ?? '').trim();
    if (queryToken.isNotEmpty) {
      return queryToken;
    }

    final path = uri.path.trim();
    const legacyPrefix = '/id_token=';
    if (path.startsWith(legacyPrefix)) {
      return path.substring(legacyPrefix.length).trim();
    }

    return '';
  }

  Uri _dashboardReturnUri() {
    return Uri.base.replace(
      path: '/dashboard',
      queryParameters: <String, String>{},
      fragment: '',
    );
  }
}
