import 'package:web/web.dart' as web;

void clearBrowserFragment([Uri? replacement]) {
  final cleanUri =
      replacement ??
      Uri.base.replace(
        path: '/dashboard',
        queryParameters: <String, String>{},
        fragment: '',
      );
  web.window.history.replaceState(
    null,
    web.document.title,
    cleanUri.toString(),
  );
}
