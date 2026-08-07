import 'dart:html' as html;

void clearBrowserFragment() {
  final cleanUri = Uri.base.replace(fragment: '');
  html.window.history.replaceState(
    null,
    html.document.title,
    cleanUri.toString(),
  );
}
