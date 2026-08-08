import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/api_client.dart';
import '../../core/auth_session_controller.dart';
import '../../core/voice_assistant_controller.dart';
import '../../ui/speed_ui.dart';

class ScanChatPage extends StatefulWidget {
  const ScanChatPage({super.key, required this.authSession});

  final AuthSessionController authSession;

  @override
  State<ScanChatPage> createState() => _ScanChatPageState();
}

class _ScanChatPageState extends State<ScanChatPage> {
  final ImagePicker _imagePicker = ImagePicker();

  final TextEditingController _messageController = TextEditingController();
  final VoiceAssistantController _voice = VoiceAssistantController();

  bool _busy = false;
  String _direction = 'IN';
  String? _statusText;
  String? _plateNumber;
  String? _selectedImageName;
  Uint8List? _selectedImageBytes;
  final List<Map<String, dynamic>> _history = <Map<String, dynamic>>[];
  int _voiceSessionId = 0;
  bool _voiceAutoSubmitting = false;

  @override
  void initState() {
    super.initState();
    _voice.addListener(_onVoiceChanged);
    _voice.initialize();
  }

  void _onVoiceChanged() {
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  @override
  void dispose() {
    _voice.removeListener(_onVoiceChanged);
    _voice.dispose();
    _messageController.dispose();
    super.dispose();
  }

  ApiClient get _apiClient => widget.authSession.apiClient;

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
        _history.clear();
      });
    });
  }

  Future<void> _sendChat() async {
    _voiceSessionId = 0;
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

      setState(() {
        _history.add({'role': 'user', 'content': message});
        _history.add({'role': 'assistant', 'content': reply});
        _messageController.clear();
        _statusText = 'Assistant response received.';
      });

      await _voice.speak(reply);
    });
  }

  Future<void> _toggleVoiceInput() async {
    if (_busy) {
      return;
    }
    if (_voice.isListening) {
      _voiceSessionId = 0;
      await _voice.stopListening();
      return;
    }

    final currentSessionId = ++_voiceSessionId;

    await _voice.startListening(
      onResult: (recognized) {
        if (!mounted ||
            currentSessionId != _voiceSessionId ||
            _voiceAutoSubmitting) {
          return;
        }
        setState(() {
          _messageController
            ..text = recognized
            ..selection = TextSelection.collapsed(offset: recognized.length);
        });
      },
      onFinalResult: (recognized) async {
        if (!mounted ||
            currentSessionId != _voiceSessionId ||
            _voiceAutoSubmitting) {
          return;
        }

        final cleaned = recognized.trim();
        if (cleaned.isEmpty) {
          return;
        }

        _voiceAutoSubmitting = true;
        _voiceSessionId = 0;
        try {
          if (mounted) {
            setState(() {
              _messageController
                ..text = cleaned
                ..selection = TextSelection.collapsed(offset: cleaned.length);
            });
          }
          await _voice.stopListening();
          await _sendChat();
        } finally {
          _voiceAutoSubmitting = false;
        }
      },
    );
  }

  Future<void> _submitEntry() async {
    if (_plateNumber == null || _plateNumber!.isEmpty) {
      setState(() {
        _statusText = 'Detect a plate before submitting entry.';
      });
      return;
    }

    await _runGuarded(() async {
      final result = await _apiClient.submitEntry(plateNumber: _plateNumber!);
      final direction = (result['direction'] ?? '').toString().toUpperCase();
      final transactionMessage =
          (result['transaction_message'] ?? 'Entry submitted.').toString();
      final welcomeMessage = (result['welcome_message'] ?? '').toString();

      setState(() {
        if (direction == 'IN' || direction == 'OUT') {
          _direction = direction;
        }
        _statusText = transactionMessage;
        _history.clear();
        if (welcomeMessage.isNotEmpty) {
          _history.add({'role': 'assistant', 'content': welcomeMessage});
        }
      });

      // Only speak the welcome on this page for OUT direction.
      // For IN, the menu page will speak it after navigation.
      if (welcomeMessage.isNotEmpty && direction != 'IN') {
        await _voice.speak(welcomeMessage);
      }

      if (mounted && direction == 'IN') {
        context.go(
          '/menu',
          extra: <String, dynamic>{
            'plate_number': _plateNumber,
            'direction': direction,
            'welcome_message': welcomeMessage,
          },
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SpeedShell(
      title: 'Scan and Assistant',
      subtitle: 'Speed Burger · Drive-Thru System',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SpeedPill(text: _busy ? 'Working...' : 'Ready'),
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: _busy ? null : () => context.go('/dashboard'),
            child: const Text('Dashboard'),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 1000;
          final panels = <Widget>[
            _buildScanPanel(theme),
            _buildChatPanel(theme),
          ];

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Scan or upload a plate image, set direction, and continue with assistant ordering.',
                style: TextStyle(color: SpeedColors.inkSoft),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: SingleChildScrollView(
                  child: wide
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: panels[0]),
                            const SizedBox(width: 20),
                            Expanded(child: panels[1]),
                          ],
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
            ],
          );
        },
      ),
    );
  }

  Widget _buildScanPanel(ThemeData theme) {
    return _panel(
      theme,
      title: 'Vehicle Entry',
      subtitle:
          'Pick from gallery or use the camera, then upload to detect plate.',
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
          if (_statusText != null)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFAFBFC),
                border: Border.all(color: SpeedColors.line),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                _statusText!,
                style: const TextStyle(color: SpeedColors.inkSoft),
              ),
            ),
          const Text(
            'After plate detection, submit entry to record IN/OUT and initialize chatbot response.',
            style: TextStyle(color: SpeedColors.inkSoft, fontSize: 12),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _platePreview(_plateNumber ?? '-- -- --')),
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
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _busy || _plateNumber == null || _plateNumber!.isEmpty
                  ? null
                  : _submitEntry,
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('Submit Entry'),
            ),
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
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF10223D), Color(0xFF17355E), Color(0xFF1E4A78)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0x33FFFFFF)),
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0x24FFFFFF),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.support_agent,
                  color: Color(0xFFFFD67A),
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Drive-Thru Assistant',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                        color: Color(0xB3F6F9FC),
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Speed Burger Assistant',
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFF6F9FC),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'Send a driver request after plate detection.',
            style: TextStyle(color: Color(0xCCF6F9FC), fontSize: 12),
          ),
          if ((_voice.statusText ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              _voice.statusText!,
              style: const TextStyle(color: Color(0xCCF6F9FC), fontSize: 12),
            ),
          ],
          const SizedBox(height: 12),
          Container(
            constraints: const BoxConstraints(minHeight: 90, maxHeight: 260),
            child: SingleChildScrollView(
              child: _history.isEmpty
                  ? const _AssistantBubble(
                      text:
                          'Welcome to Speed Burger! Start by scanning a plate and sending an order message.',
                      isUser: false,
                    )
                  : Column(
                      children: _history
                          .map(
                            (entry) => _AssistantBubble(
                              text: '${entry['content']}',
                              isUser: entry['role'] == 'user',
                            ),
                          )
                          .toList(),
                    ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _messageController,
                  minLines: 1,
                  maxLines: 3,
                  style: const TextStyle(color: Color(0xFFF6F9FC)),
                  decoration: InputDecoration(
                    hintText: 'Ask, e.g. I want 2 fish burgers and 1 cola',
                    hintStyle: const TextStyle(color: Color(0x99F6F9FC)),
                    filled: true,
                    fillColor: const Color(0x55050C14),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0x40FFFFFF)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0x40FFFFFF)),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _busy ? null : _sendChat,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFFFD67A),
                  foregroundColor: const Color(0xFF16253E),
                ),
                child: const Text('Send'),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                onPressed: _busy ? null : _toggleVoiceInput,
                style: IconButton.styleFrom(
                  backgroundColor: _voice.isListening
                      ? const Color(0xFFFFD67A)
                      : const Color(0x29FFFFFF),
                  foregroundColor: _voice.isListening
                      ? const Color(0xFF16253E)
                      : Colors.white,
                ),
                icon: Icon(_voice.isListening ? Icons.mic : Icons.mic_none),
                tooltip: _voice.isListening
                    ? 'Stop voice input'
                    : 'Start voice input',
              ),
            ],
          ),
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
    return SpeedCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(subtitle, style: const TextStyle(color: SpeedColors.inkSoft)),
          const SizedBox(height: 20),
          child,
        ],
      ),
    );
  }

  Widget _platePreview(String plate) {
    final isEmpty = plate == '-- -- --';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isEmpty ? const Color(0xFFFAFBFC) : const Color(0xFFFFF8EA),
        border: Border.all(
          color: isEmpty ? SpeedColors.line : SpeedColors.amber,
          width: 1.5,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: isEmpty ? SpeedColors.inkFaint : SpeedColors.amber,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              plate,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isEmpty ? SpeedColors.inkFaint : SpeedColors.ink,
                fontWeight: isEmpty ? FontWeight.w500 : FontWeight.w700,
                letterSpacing: 0.6,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String? _stringify(Object? value) {
    if (value == null) {
      return null;
    }
    return value.toString();
  }
}

class _AssistantBubble extends StatelessWidget {
  const _AssistantBubble({required this.text, required this.isUser});

  final String text;
  final bool isUser;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
        constraints: const BoxConstraints(maxWidth: 380),
        decoration: BoxDecoration(
          color: isUser ? const Color(0xFFFFD67A) : const Color(0x29FFFFFF),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: isUser ? const Color(0xFF16253E) : Colors.white,
            fontWeight: isUser ? FontWeight.w600 : FontWeight.w500,
            height: 1.35,
          ),
        ),
      ),
    );
  }
}
