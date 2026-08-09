import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/api_client.dart';
import '../../core/auth_session_controller.dart';
import '../../core/voice_assistant_controller.dart';
import '../../ui/speed_ui.dart';

enum _StatusKind { info, success, error }

class ScanChatPage extends StatefulWidget {
  const ScanChatPage({super.key, required this.authSession});

  final AuthSessionController authSession;

  @override
  State<ScanChatPage> createState() => _ScanChatPageState();
}

class _ScanChatPageState extends State<ScanChatPage> {
  final ImagePicker _imagePicker = ImagePicker();

  final TextEditingController _messageController = TextEditingController();
  final ScrollController _chatScrollController = ScrollController();
  final VoiceAssistantController _voice = VoiceAssistantController();

  bool _busy = false;
  String _direction = 'IN';
  String? _statusText;
  _StatusKind _statusKind = _StatusKind.info;
  String? _plateNumber;
  String? _selectedImageName;
  Uint8List? _selectedImageBytes;
  final List<Map<String, dynamic>> _history = <Map<String, dynamic>>[];
  int _voiceSessionId = 0;
  bool _voiceAutoSubmitting = false;

  // Assistant now lives as a floating bubble instead of a fixed side
  // panel, so we track whether it's expanded and whether a reply
  // arrived while it was collapsed (shown as a small unread dot).
  bool _assistantExpanded = false;
  bool _assistantUnread = false;

  void _openAssistant() {
    setState(() {
      _assistantExpanded = true;
      _assistantUnread = false;
    });
  }

  void _closeAssistant() {
    setState(() {
      _assistantExpanded = false;
    });
  }

  void _appendHistory(Map<String, dynamic> entry) {
    _history.add(entry);
    if (!_assistantExpanded) {
      _assistantUnread = true;
    }
  }

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
    _chatScrollController.dispose();
    super.dispose();
  }

  ApiClient get _apiClient => widget.authSession.apiClient;

  void _setStatus(String text, _StatusKind kind) {
    _statusText = text;
    _statusKind = kind;
  }

  // Keeps the conversation pinned to the latest message instead of
  // requiring the operator to scroll down after every reply.
  void _scrollChatToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_chatScrollController.hasClients) return;
      _chatScrollController.animateTo(
        _chatScrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
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
        _setStatus(
          'Request failed: ${error.response?.statusCode ?? '-'} ${_stringify(details) ?? error.message ?? 'Unknown error'}',
          _StatusKind.error,
        );
      });
    } catch (error) {
      setState(() {
        _setStatus('Error: $error', _StatusKind.error);
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
          _setStatus('Image selection cancelled.', _StatusKind.info);
        });
        return;
      }

      final bytes = await image.readAsBytes();
      final result = await _apiClient.detectPlate(image);
      setState(() {
        _selectedImageBytes = bytes;
        _selectedImageName = image.name;
        _plateNumber = (result['plate_number'] ?? result['plate'])?.toString();
        if (_plateNumber == null) {
          _setStatus(
            'Scan completed but no plate returned.',
            _StatusKind.error,
          );
        } else {
          _setStatus('Plate detected: $_plateNumber', _StatusKind.success);
        }
        _history.clear();
      });
    });
  }

  Future<void> _sendChat() async {
    _voiceSessionId = 0;
    final message = _messageController.text.trim();
    if (_plateNumber == null || _plateNumber!.isEmpty) {
      setState(() {
        _setStatus('Detect a plate before sending chat.', _StatusKind.error);
      });
      return;
    }
    if (message.isEmpty) {
      setState(() {
        _setStatus('Enter a message first.', _StatusKind.error);
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
        _appendHistory({'role': 'user', 'content': message});
        _appendHistory({'role': 'assistant', 'content': reply});
        _messageController.clear();
        _setStatus('Assistant response received.', _StatusKind.success);
      });
      _scrollChatToBottom();

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
        _setStatus(
          'Detect a plate before submitting entry.',
          _StatusKind.error,
        );
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
        _setStatus(transactionMessage, _StatusKind.success);
        _history.clear();
        if (welcomeMessage.isNotEmpty) {
          _history.add({'role': 'assistant', 'content': welcomeMessage});
        }
        // Pop the assistant open right when it becomes relevant, instead
        // of leaving the operator to notice and tap the bubble themselves.
        _assistantExpanded = true;
        _assistantUnread = false;
      });
      _scrollChatToBottom();

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

  /// Which step of Scan → Submit → Chat the operator is currently on,
  /// so the flow indicator can reflect real state rather than guesswork.
  int get _currentStep {
    if (_plateNumber == null || _plateNumber!.isEmpty) return 0;
    if (_history.isEmpty) return 1;
    return 2;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SpeedShell(
      title: 'Entry',
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
          final isNarrow = constraints.maxWidth < 640;
          // Cap the floating panel's height so it never grows past the
          // visible page, but keep it roomy on tall viewports.
          final panelMaxHeight = (constraints.maxHeight - 48).clamp(
            320.0,
            560.0,
          );

          return Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Scan or upload a plate image, set direction, and continue with assistant ordering.',
                    style: TextStyle(color: SpeedColors.inkSoft),
                  ),
                  const SizedBox(height: 14),
                  _FlowSteps(currentStep: _currentStep),
                  const SizedBox(height: 16),
                  Expanded(
                    child: SingleChildScrollView(
                      // Bottom padding keeps the floating bubble from
                      // ever covering the last bit of scan-panel content.
                      padding: const EdgeInsets.only(bottom: 88),
                      child: _buildScanPanel(theme),
                    ),
                  ),
                ],
              ),
              Positioned(
                right: 16,
                bottom: 8,
                left: isNarrow && _assistantExpanded ? 16 : null,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  transitionBuilder: (child, animation) => ScaleTransition(
                    scale: animation,
                    alignment: Alignment.bottomRight,
                    child: FadeTransition(opacity: animation, child: child),
                  ),
                  child: _assistantExpanded
                      ? _buildAssistantPanel(
                          theme,
                          key: const ValueKey('panel'),
                          width: isNarrow ? null : 380,
                          maxHeight: panelMaxHeight,
                        )
                      : _buildAssistantBubble(key: const ValueKey('bubble')),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildAssistantBubble({Key? key}) {
    return InkWell(
      key: key,
      onTap: _openAssistant,
      borderRadius: BorderRadius.circular(32),
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            colors: [Color(0xFF17355E), Color(0xFF1E4A78)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: SpeedColors.navy.withValues(alpha: 0.35),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            const Center(
              child: Icon(
                Icons.support_agent,
                color: Color(0xFFFFD67A),
                size: 30,
              ),
            ),
            if (_assistantUnread)
              Positioned(
                top: 2,
                right: 2,
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE0554F),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildScanPanel(ThemeData theme) {
    final hasPlate = _plateNumber != null && _plateNumber!.isNotEmpty;

    return _panel(
      theme,
      title: 'Vehicle Entry',
      subtitle:
          'Capture a plate, confirm direction, then submit to start the order.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CaptureArea(
            imageBytes: _selectedImageBytes,
            imageName: _selectedImageName,
            busy: _busy,
            onPick: () => _pickAndDetect(ImageSource.gallery),
          ),
          const SizedBox(height: 18),
          if (_statusText != null) ...[
            _StatusBanner(text: _statusText!, kind: _statusKind),
            const SizedBox(height: 16),
          ],
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _PlateChip(plate: _plateNumber)),
                const SizedBox(width: 12),
                _DirectionToggle(
                  value: _direction,
                  onChanged: _busy
                      ? null
                      : (value) => setState(() => _direction = value),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _busy || !hasPlate ? null : _submitEntry,
              icon: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.check_circle_outline),
              label: Text(_busy ? 'Submitting…' : 'Submit Entry'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAssistantPanel(
    ThemeData theme, {
    Key? key,
    double? width,
    required double maxHeight,
  }) {
    final content = Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF10223D), Color(0xFF17355E), Color(0xFF1E4A78)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0x33FFFFFF)),
        boxShadow: [
          BoxShadow(
            color: SpeedColors.navy.withValues(alpha: 0.35),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      padding: const EdgeInsets.all(18),
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
              IconButton(
                onPressed: _closeAssistant,
                icon: const Icon(Icons.close, color: Color(0xB3F6F9FC)),
                tooltip: 'Minimize assistant',
                visualDensity: VisualDensity.compact,
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
            Row(
              children: [
                if (_voice.isListening) ...[
                  const _PulsingDot(),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: Text(
                    _voice.statusText!,
                    style: const TextStyle(
                      color: Color(0xCCF6F9FC),
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 100),
              child: _history.isEmpty
                  ? const _AssistantBubble(
                      text:
                          'Welcome to Speed Burger! Start by scanning a plate and sending an order message.',
                      isUser: false,
                    )
                  : ListView.builder(
                      controller: _chatScrollController,
                      shrinkWrap: true,
                      itemCount: _history.length,
                      itemBuilder: (context, index) {
                        final entry = _history[index];
                        return _AssistantBubble(
                          text: '${entry['content']}',
                          isUser: entry['role'] == 'user',
                        );
                      },
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
                  onSubmitted: _busy ? null : (_) => _sendChat(),
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
                child: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(0xFF16253E),
                        ),
                      )
                    : const Text('Send'),
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

    return KeyedSubtree(
      key: key,
      child: width != null ? SizedBox(width: width, child: content) : content,
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

  String? _stringify(Object? value) {
    if (value == null) {
      return null;
    }
    return value.toString();
  }
}

/// Photo capture surface: a viewfinder-style frame that shows either
/// the captured plate photo or an empty-state placeholder, with the
/// capture buttons directly underneath so the whole thing reads as one
/// composed control instead of a stack of unrelated widgets.
class _CaptureArea extends StatelessWidget {
  const _CaptureArea({
    required this.imageBytes,
    required this.imageName,
    required this.busy,
    required this.onPick,
  });

  final Uint8List? imageBytes;
  final String? imageName;
  final bool busy;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final hasImage = imageBytes != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 240),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: Material(
                color: const Color(0xFFF7F8FA),
                borderRadius: BorderRadius.circular(14),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: busy ? null : onPick,
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: SpeedColors.line),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (hasImage)
                          Image.memory(imageBytes!, fit: BoxFit.cover)
                        else
                          const Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.add_a_photo_outlined,
                                  size: 30,
                                  color: SpeedColors.inkFaint,
                                ),
                                SizedBox(height: 8),
                                Text(
                                  'No plate captured yet',
                                  style: TextStyle(
                                    color: SpeedColors.inkFaint,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  'Tap to upload a vehicle photo',
                                  style: TextStyle(
                                    color: SpeedColors.inkFaint,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        const _CornerBrackets(),
                        if (hasImage)
                          Positioned(
                            top: 10,
                            right: 10,
                            child: _GhostChip(
                              icon: Icons.refresh,
                              label: 'Retake',
                              onTap: busy ? null : onPick,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        if (imageName != null) ...[
          const SizedBox(height: 8),
          Center(
            child: Text(
              imageName!,
              style: const TextStyle(color: SpeedColors.inkFaint, fontSize: 11),
            ),
          ),
        ],
      ],
    );
  }
}

/// Four small L-shaped corner marks over the capture frame, echoing a
/// camera viewfinder — a nod to what this panel actually does (scan a
/// plate) rather than a decorative flourish.
class _CornerBrackets extends StatelessWidget {
  const _CornerBrackets();

  static const double _size = 18;
  static const double _thickness = 2.5;
  static const double _inset = 10;

  @override
  Widget build(BuildContext context) {
    Widget bracket({required bool top, required bool left}) {
      return Positioned(
        top: top ? _inset : null,
        bottom: top ? null : _inset,
        left: left ? _inset : null,
        right: left ? null : _inset,
        child: IgnorePointer(
          child: Container(
            width: _size,
            height: _size,
            decoration: BoxDecoration(
              border: Border(
                top: top
                    ? const BorderSide(
                        color: SpeedColors.amber,
                        width: _thickness,
                      )
                    : BorderSide.none,
                bottom: !top
                    ? const BorderSide(
                        color: SpeedColors.amber,
                        width: _thickness,
                      )
                    : BorderSide.none,
                left: left
                    ? const BorderSide(
                        color: SpeedColors.amber,
                        width: _thickness,
                      )
                    : BorderSide.none,
                right: !left
                    ? const BorderSide(
                        color: SpeedColors.amber,
                        width: _thickness,
                      )
                    : BorderSide.none,
              ),
            ),
          ),
        ),
      );
    }

    return Stack(
      children: [
        bracket(top: true, left: true),
        bracket(top: true, left: false),
        bracket(top: false, left: true),
        bracket(top: false, left: false),
      ],
    );
  }
}

/// Small translucent pill for actions that float on top of imagery
/// (e.g. "Retake" over the captured photo).
class _GhostChip extends StatelessWidget {
  const _GhostChip({required this.icon, required this.label, this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: Colors.white),
              const SizedBox(width: 4),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Plate readout styled like an actual plate reading rather than a
/// generic labelled box: monospace, letter-spaced, and lit up in amber
/// once a real plate has been detected.
class _PlateChip extends StatelessWidget {
  const _PlateChip({required this.plate});

  final String? plate;

  @override
  Widget build(BuildContext context) {
    final hasPlate = plate != null && plate!.isNotEmpty;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: hasPlate ? const Color(0xFFFFF8EA) : const Color(0xFFFAFBFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: hasPlate ? SpeedColors.amber : SpeedColors.line,
          width: hasPlate ? 1.6 : 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: hasPlate ? SpeedColors.amber : SpeedColors.inkFaint,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'DETECTED PLATE',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.0,
                    color: SpeedColors.inkFaint,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  hasPlate ? plate! : '— — —',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 18,
                    letterSpacing: 2.0,
                    fontWeight: FontWeight.w700,
                    color: hasPlate ? SpeedColors.ink : SpeedColors.inkFaint,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Two-state IN / OUT control. A dropdown implies a longer list of
/// choices than actually exists here, so a segmented toggle reads the
/// state at a glance and is a single tap to change.
class _DirectionToggle extends StatelessWidget {
  const _DirectionToggle({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String>? onChanged;

  Widget _segment(String label, IconData icon, String segmentValue) {
    final selected = value == segmentValue;
    return InkWell(
      onTap: onChanged == null ? null : () => onChanged!(segmentValue),
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? SpeedColors.navy : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: selected ? Colors.white : SpeedColors.inkSoft,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: selected ? Colors.white : SpeedColors.inkSoft,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFBFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: SpeedColors.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _segment('IN', Icons.arrow_downward_rounded, 'IN'),
          _segment('OUT', Icons.arrow_upward_rounded, 'OUT'),
        ],
      ),
    );
  }
}

/// Color-coded status banner so a failed request looks obviously
/// different from a successful scan instead of both being flat gray.
class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.text, required this.kind});

  final String text;
  final _StatusKind kind;

  @override
  Widget build(BuildContext context) {
    late final Color bg;
    late final Color border;
    late final Color fg;
    late final IconData icon;

    switch (kind) {
      case _StatusKind.success:
        bg = const Color(0xFFF1FAF4);
        border = SpeedColors.green.withValues(alpha: 0.45);
        fg = SpeedColors.green;
        icon = Icons.check_circle_outline;
        break;
      case _StatusKind.error:
        bg = const Color(0xFFFDF0EF);
        border = const Color(0xFFE0554F).withValues(alpha: 0.45);
        fg = const Color(0xFFC7453F);
        icon = Icons.error_outline;
        break;
      case _StatusKind.info:
        bg = const Color(0xFFFAFBFC);
        border = SpeedColors.line;
        fg = SpeedColors.inkSoft;
        icon = Icons.info_outline;
        break;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: fg),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: TextStyle(color: fg, height: 1.3)),
          ),
        ],
      ),
    );
  }
}

/// Scan → Submit → Chat progress indicator, reflecting the operator's
/// actual position in the flow rather than being purely decorative.
class _FlowSteps extends StatelessWidget {
  const _FlowSteps({required this.currentStep});

  final int currentStep;

  static const _labels = ['Scan plate', 'Submit entry', 'Chat & order'];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < _labels.length; i++) ...[
          _StepChip(
            index: i + 1,
            label: _labels[i],
            state: i < currentStep
                ? _StepState.done
                : i == currentStep
                ? _StepState.active
                : _StepState.upcoming,
          ),
          if (i != _labels.length - 1)
            Expanded(
              child: Container(
                height: 1.5,
                margin: const EdgeInsets.symmetric(horizontal: 8),
                color: i < currentStep
                    ? SpeedColors.green.withValues(alpha: 0.5)
                    : SpeedColors.line,
              ),
            ),
        ],
      ],
    );
  }
}

enum _StepState { done, active, upcoming }

class _StepChip extends StatelessWidget {
  const _StepChip({
    required this.index,
    required this.label,
    required this.state,
  });

  final int index;
  final String label;
  final _StepState state;

  @override
  Widget build(BuildContext context) {
    final Color circleColor;
    final Color textColor;
    Widget circleChild;

    switch (state) {
      case _StepState.done:
        circleColor = SpeedColors.green;
        textColor = SpeedColors.ink;
        circleChild = const Icon(Icons.check, size: 14, color: Colors.white);
        break;
      case _StepState.active:
        circleColor = SpeedColors.navy;
        textColor = SpeedColors.ink;
        circleChild = Text(
          '$index',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        );
        break;
      case _StepState.upcoming:
        circleColor = SpeedColors.line;
        textColor = SpeedColors.inkFaint;
        circleChild = Text(
          '$index',
          style: const TextStyle(
            color: SpeedColors.inkFaint,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        );
        break;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: circleColor, shape: BoxShape.circle),
          child: circleChild,
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            color: textColor,
            fontSize: 13,
            fontWeight: state == _StepState.active
                ? FontWeight.w700
                : FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

/// Small pulsing dot next to the voice status line while actively
/// listening, so "Listening…" text reads as live rather than static.
class _PulsingDot extends StatefulWidget {
  const _PulsingDot();

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(begin: 0.3, end: 1.0).animate(_controller),
      child: const SizedBox(
        width: 7,
        height: 7,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Color(0xFFFFD67A),
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
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
