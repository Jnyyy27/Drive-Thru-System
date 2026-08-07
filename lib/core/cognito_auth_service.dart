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
      queryParameters: <String, String>{'next': _currentReturnUri().toString()},
    );
  }

  Uri buildLogoutUri() {
    final base = Uri.parse('$_authBaseUrl/logout');
    return base.replace(
      queryParameters: <String, String>{'next': _currentReturnUri().toString()},
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
    final fragment = Uri.base.fragment.trim();
    if (fragment.isEmpty) {
      return false;
    }

    final params = Uri.splitQueryString(fragment);
    final idToken = (params['id_token'] ?? '').trim();
    if (idToken.isEmpty) {
      return false;
    }

    await _tokenStore.saveIdToken(idToken);
    clearBrowserFragment();
    return true;
  }

  Uri _currentReturnUri() {
    return Uri.base.replace(fragment: '');
  }
}
