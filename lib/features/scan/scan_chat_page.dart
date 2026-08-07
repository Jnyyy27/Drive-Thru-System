import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/api_client.dart';
import '../../core/auth_token_store.dart';
import '../../core/cognito_auth_service.dart';

class ScanChatPage extends StatefulWidget {
  const ScanChatPage({super.key});

  @override
  State<ScanChatPage> createState() => _ScanChatPageState();
}

class _ScanChatPageState extends State<ScanChatPage> {
  final AuthTokenStore _tokenStore = AuthTokenStore();
  late final ApiClient _apiClient = ApiClient(_tokenStore);
  late final CognitoAuthService _authService = CognitoAuthService(_tokenStore);
  final ImagePicker _imagePicker = ImagePicker();

  final TextEditingController _messageController = TextEditingController();

  bool _busy = false;
  String _direction = 'IN';
  String? _statusText;
  String? _tokenPreview;
  String? _plateNumber;
  String? _reply;
  String? _selectedImageName;
  Uint8List? _selectedImageBytes;
  Map<String, dynamic>? _currentUser;
  Map<String, dynamic>? _lastOrder;
  final List<Map<String, dynamic>> _history = <Map<String, dynamic>>[];

  @override
  void initState() {
    super.initState();
    _bootstrapAuth();
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _bootstrapAuth() async {
    final consumedRedirectToken = await _authService
        .consumeRedirectTokenIfPresent();
    final token = await _apiClient.currentToken() ?? '';
    if (!mounted) {
      return;
    }
    setState(() {
      _tokenPreview = _previewToken(token);
      _statusText = consumedRedirectToken
          ? 'Cognito login completed. Refreshing current user...'
          : token.isEmpty
          ? 'Sign in with Cognito to start using the API.'
          : 'Saved login found. Refreshing current user...';
    });

    if (token.isNotEmpty || consumedRedirectToken) {
      await _hydrateCurrentUser(silent: true);
    }
  }

  Future<void> _runGuarded(Future<void> Function() action) async {
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
    });
    try {
      await action();
    } on DioException catch (error) {
      final details = error.response?.data;
      setState(() {
        _statusText =
            'Request failed: ${error.response?.statusCode ?? '-'} ${_stringify(details) ?? error.message ?? 'Unknown error'}';
      });
    } catch (error) {
      setState(() {
        _statusText = 'Error: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _hydrateCurrentUser({bool silent = false}) async {
    try {
      final result = await _apiClient.me();
      final user = result['user'];
      if (!mounted) {
        return;
      }
      setState(() {
        _currentUser = user is Map<String, dynamic>
            ? user
            : user is Map
            ? user.cast<String, dynamic>()
            : result;
        _statusText = silent
            ? 'Signed in successfully.'
            : 'Authenticated successfully.';
      });
    } on DioException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _currentUser = null;
        _statusText = silent
            ? 'Stored login is unavailable: ${error.response?.statusCode ?? '-'}.'
            : 'Request failed: ${error.response?.statusCode ?? '-'} ${_stringify(error.response?.data) ?? error.message ?? 'Unknown error'}';
      });
    }
  }

  Future<void> _login() async {
    await _runGuarded(() async {
      final launched = await _authService.launchLogin();
      if (!launched) {
        throw Exception('Could not open Cognito login page.');
      }
      setState(() {
        _statusText = 'Redirecting to Cognito login...';
      });
    });
  }

  Future<void> _logout() async {
    await _runGuarded(() async {
      final launched = await _authService.launchLogout();
      if (!launched) {
        throw Exception('Could not open logout page.');
      }
      setState(() {
        _currentUser = null;
        _tokenPreview = null;
        _plateNumber = null;
        _reply = null;
        _lastOrder = null;
        _selectedImageBytes = null;
        _selectedImageName = null;
        _history.clear();
        _statusText = 'Redirecting to logout...';
      });
    });
  }

  Future<void> _clearLocalToken() async {
    await _runGuarded(() async {
      await _apiClient.clearToken();
      setState(() {
        _currentUser = null;
        _tokenPreview = null;
        _statusText = 'Local token cleared.';
      });
    });
  }

  Future<void> _checkHealth() async {
    await _runGuarded(() async {
      final result = await _apiClient.health();
      setState(() {
        _statusText = 'Health OK: ${_stringify(result)}';
      });
    });
  }

  Future<void> _checkMe() async {
    await _runGuarded(() async {
      await _hydrateCurrentUser();
    });
  }

  Future<void> _pickAndDetect(ImageSource source) async {
    await _runGuarded(() async {
      final image = await _imagePicker.pickImage(
        source: source,
        imageQuality: 92,
        preferredCameraDevice: CameraDevice.rear,
      );
      if (image == null) {
        setState(() {
          _statusText = 'Image selection cancelled.';
        });
        return;
      }

      final bytes = await image.readAsBytes();
      final result = await _apiClient.detectPlate(image);
      setState(() {
        _selectedImageBytes = bytes;
        _selectedImageName = image.name;
        _plateNumber = (result['plate_number'] ?? result['plate'])?.toString();
        _statusText = _plateNumber == null
            ? 'Scan completed but no plate returned.'
            : 'Plate detected: $_plateNumber';
        _reply = null;
        _lastOrder = null;
        _history.clear();
      });
    });
  }

  Future<void> _sendChat() async {
    final message = _messageController.text.trim();
    if (_plateNumber == null || _plateNumber!.isEmpty) {
      setState(() {
        _statusText = 'Detect a plate before sending chat.';
      });
      return;
    }
    if (message.isEmpty) {
      setState(() {
        _statusText = 'Enter a message first.';
      });
      return;
    }

    await _runGuarded(() async {
      final result = await _apiClient.assistantChat(
        plateNumber: _plateNumber!,
        direction: _direction,
        message: message,
        history: List<Map<String, dynamic>>.from(_history),
      );

      final reply = (result['reply'] ?? '').toString();
      final order = (result['order'] as Map?)?.cast<String, dynamic>();

      setState(() {
        _history.add({'role': 'user', 'content': message});
        _history.add({'role': 'assistant', 'content': reply});
        _reply = reply;
        _lastOrder = order;
        _messageController.clear();
        _statusText = 'Assistant response received.';
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Drive Thru Console'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Text(
                _busy ? 'Working...' : 'Ready',
                style: theme.textTheme.labelLarge,
              ),
            ),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 1100;
          final panels = <Widget>[
            _buildAccessPanel(theme),
            _buildScanPanel(theme),
            _buildChatPanel(theme),
            _buildResponsePanel(theme),
          ];

          return Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFFF6F6F2), Color(0xFFE8F3F0)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: wide
                    ? Wrap(
                        spacing: 20,
                        runSpacing: 20,
                        children: panels
                            .map(
                              (panel) => SizedBox(
                                width: (constraints.maxWidth - 60) / 2,
                                child: panel,
                              ),
                            )
                            .toList(),
                      )
                    : Column(
                        children: [
                          for (final panel in panels) ...[
                            panel,
                            const SizedBox(height: 20),
                          ],
                        ],
                      ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildAccessPanel(ThemeData theme) {
    return _panel(
      theme,
      title: 'Authentication',
      subtitle:
          'Sign in through Cognito Hosted UI and return here with a token automatically.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _infoRow('API Base URL', _apiClient.baseUrl),
          const SizedBox(height: 12),
          _infoRow('Auth Base URL', _authService.authBaseUrl),
          const SizedBox(height: 16),
          Text(
            _tokenPreview == null
                ? 'No local token stored yet.'
                : 'Stored ID token: $_tokenPreview',
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton(
                onPressed: _busy ? null : _login,
                child: const Text('Sign In with Cognito'),
              ),
              OutlinedButton(
                onPressed: _busy ? null : _logout,
                child: const Text('Sign Out'),
              ),
              OutlinedButton(
                onPressed: _busy ? null : _clearLocalToken,
                child: const Text('Clear Local Token'),
              ),
              OutlinedButton(
                onPressed: _busy ? null : _checkHealth,
                child: const Text('Test Health'),
              ),
              OutlinedButton(
                onPressed: _busy ? null : _checkMe,
                child: const Text('Test /me'),
              ),
            ],
          ),
          if (_currentUser != null) ...[
            const SizedBox(height: 16),
            Text('Current User', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            _jsonBox(_currentUser!),
          ],
        ],
      ),
    );
  }

  Widget _buildScanPanel(ThemeData theme) {
    return _panel(
      theme,
      title: 'Plate Detection',
      subtitle:
          'Pick from gallery or use the camera, then upload to /api/detect-plate.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton.icon(
                onPressed: _busy
                    ? null
                    : () => _pickAndDetect(ImageSource.camera),
                icon: const Icon(Icons.photo_camera_outlined),
                label: const Text('Use Camera'),
              ),
              OutlinedButton.icon(
                onPressed: _busy
                    ? null
                    : () => _pickAndDetect(ImageSource.gallery),
                icon: const Icon(Icons.upload_file_outlined),
                label: const Text('Pick File'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _infoRow(
                  'Detected Plate',
                  _plateNumber ?? 'Not scanned yet',
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _direction,
                  decoration: const InputDecoration(
                    labelText: 'Direction',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'IN', child: Text('IN')),
                    DropdownMenuItem(value: 'OUT', child: Text('OUT')),
                  ],
                  onChanged: _busy
                      ? null
                      : (value) {
                          if (value == null) {
                            return;
                          }
                          setState(() {
                            _direction = value;
                          });
                        },
                ),
              ),
            ],
          ),
          if (_selectedImageBytes != null) ...[
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.memory(
                _selectedImageBytes!,
                height: 220,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
            if (_selectedImageName != null) ...[
              const SizedBox(height: 8),
              Text(_selectedImageName!, style: theme.textTheme.bodySmall),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildChatPanel(ThemeData theme) {
    return _panel(
      theme,
      title: 'Assistant Chat',
      subtitle: 'Send a driver message with plate and direction context.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _messageController,
            minLines: 3,
            maxLines: 5,
            decoration: const InputDecoration(
              labelText: 'Driver Message',
              hintText: 'Example: I want 2 fish burgers and 1 cola',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _busy ? null : _sendChat,
            child: const Text('Send to Assistant'),
          ),
          const SizedBox(height: 16),
          Text('Conversation', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          if (_history.isEmpty)
            Text('No messages yet.', style: theme.textTheme.bodyMedium)
          else
            Column(
              children: _history
                  .map(
                    (entry) => Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: entry['role'] == 'assistant'
                            ? const Color(0xFFE7F6F2)
                            : const Color(0xFFFFF6E5),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text('${entry['role']}: ${entry['content']}'),
                    ),
                  )
                  .toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildResponsePanel(ThemeData theme) {
    return _panel(
      theme,
      title: 'Latest Response',
      subtitle: 'Inspect backend output while you wire the rest of the app.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _infoRow('Status', _statusText ?? 'Idle'),
          const SizedBox(height: 16),
          if (_reply != null) ...[
            Text('Assistant Reply', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            _jsonBox({'reply': _reply}),
            const SizedBox(height: 16),
          ],
          if (_lastOrder != null) ...[
            Text('Order Payload', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            _jsonBox(_lastOrder!),
          ] else
            Text('No order payload yet.', style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }

  Widget _panel(
    ThemeData theme, {
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.headlineSmall),
            const SizedBox(height: 6),
            Text(subtitle, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 20),
            child,
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 6),
        SelectableText(value),
      ],
    );
  }

  Widget _jsonBox(Map<String, dynamic> data) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(14),
      ),
      child: SelectableText(
        _stringify(data) ?? '{}',
        style: const TextStyle(
          color: Color(0xFFE2E8F0),
          fontFamily: 'Courier',
          fontSize: 13,
          height: 1.4,
        ),
      ),
    );
  }

  String? _stringify(Object? value) {
    if (value == null) {
      return null;
    }
    return value.toString();
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
}
