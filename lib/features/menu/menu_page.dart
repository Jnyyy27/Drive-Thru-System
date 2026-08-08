import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth_session_controller.dart';
import '../../core/voice_assistant_controller.dart';
import '../../ui/speed_ui.dart';

class MenuPage extends StatefulWidget {
  const MenuPage({
    super.key,
    required this.authSession,
    this.initialPlateNumber,
    this.initialDirection,
    this.initialAssistantMessage,
  });

  final AuthSessionController authSession;
  final String? initialPlateNumber;
  final String? initialDirection;
  final String? initialAssistantMessage;

  @override
  State<MenuPage> createState() => _MenuPageState();
}

class _MenuPageState extends State<MenuPage> {
  late Future<Map<String, dynamic>> _menuFuture;
  final TextEditingController _chatController = TextEditingController();
  final VoiceAssistantController _voice = VoiceAssistantController();
  final List<Map<String, dynamic>> _chatHistory = <Map<String, dynamic>>[];
  bool _chatBusy = false;
  String? _chatStatus;
  String? _plateNumber;
  String _direction = 'IN';
  List<Map<String, dynamic>> _menuContextItems = const <Map<String, dynamic>>[];
  int _voiceSessionId = 0;
  bool _voiceAutoSubmitting = false;

  @override
  void initState() {
    super.initState();
    _menuFuture = widget.authSession.apiClient.menu();
    _voice.addListener(_onVoiceChanged);
    _voice.initialize();
    _plateNumber = widget.initialPlateNumber;
    final incomingDirection = (widget.initialDirection ?? '').toUpperCase();
    if (incomingDirection == 'IN' || incomingDirection == 'OUT') {
      _direction = incomingDirection;
    }
    if ((widget.initialAssistantMessage ?? '').trim().isNotEmpty) {
      _chatHistory.add({
        'role': 'assistant',
        'content': widget.initialAssistantMessage!.trim(),
      });
      _voice.speak(widget.initialAssistantMessage!.trim());
    }
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
    _chatController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final future = widget.authSession.apiClient.menu();
    setState(() {
      _menuFuture = future;
    });
    await future;
  }

  Future<void> _sendChat() async {
    _voiceSessionId = 0;
    final message = _chatController.text.trim();
    if (message.isEmpty) {
      setState(() {
        _chatStatus = 'Type a message first.';
      });
      return;
    }
    if (_plateNumber == null || _plateNumber!.isEmpty) {
      setState(() {
        _chatStatus = 'No active plate session. Scan and submit entry first.';
      });
      return;
    }

    setState(() {
      _chatBusy = true;
      _chatStatus = null;
      _chatHistory.add({'role': 'user', 'content': message});
    });

    try {
      final result = await widget.authSession.apiClient.assistantChat(
        plateNumber: _plateNumber!,
        direction: _direction,
        message: message,
        history: List<Map<String, dynamic>>.from(_chatHistory),
        menuItems: _menuContextItems,
      );

      final reply = (result['reply'] ?? '').toString();
      final responseDirection = (result['direction'] ?? '')
          .toString()
          .toUpperCase();

      setState(() {
        if (responseDirection == 'IN' || responseDirection == 'OUT') {
          _direction = responseDirection;
        }
        if (reply.isNotEmpty) {
          _chatHistory.add({'role': 'assistant', 'content': reply});
        }
        _chatController.clear();
      });

      if (reply.isNotEmpty) {
        await _voice.speak(reply);
      }
    } catch (error) {
      setState(() {
        _chatStatus = 'Chat failed: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _chatBusy = false;
        });
      }
    }
  }

  Future<void> _toggleVoiceInput() async {
    if (_chatBusy) {
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
          _chatController
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
              _chatController
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

  @override
  Widget build(BuildContext context) {
    return SpeedShell(
      title: 'Menu',
      subtitle: 'Speed Burger · Drive-Thru System',
      trailing: OutlinedButton(
        onPressed: () => context.go('/dashboard'),
        child: const Text('Dashboard'),
      ),
      child: FutureBuilder<Map<String, dynamic>>(
        future: _menuFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _ErrorState(
              message: snapshot.error.toString(),
              onRetry: _refresh,
            );
          }

          final data = snapshot.data ?? const <String, dynamic>{};
          final items = ((data['items'] as List?) ?? const [])
              .cast<Map>()
              .map((item) => item.cast<String, dynamic>())
              .toList();
          final categories = ((data['categories'] as List?) ?? const [])
              .map((category) => category.toString())
              .toList();

          _menuContextItems = items
              .map(
                (item) => <String, dynamic>{
                  'name': item['name']?.toString() ?? '',
                  'price': item['price'],
                  'description': item['description']?.toString() ?? '',
                  'available':
                      item['available'] == true || item['available'] == 1,
                },
              )
              .toList();

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Browse the current burgers, sides, and drinks on offer.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final category in categories) SpeedPill(text: category),
                ],
              ),
              const SizedBox(height: 14),
              Expanded(
                child: Stack(
                  children: [
                    ListView.separated(
                      padding: const EdgeInsets.only(bottom: 260),
                      itemBuilder: (context, index) {
                        final item = items[index];
                        final isAvailable =
                            item['available'] == true || item['available'] == 1;
                        final imageUrl = item['image_url']?.toString();

                        return SpeedCard(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _MenuImageThumb(imageUrl: imageUrl),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            item['name']?.toString() ?? '-',
                                            style: Theme.of(
                                              context,
                                            ).textTheme.titleMedium,
                                          ),
                                        ),
                                        Text(
                                          'RM ${item['price'] ?? '-'}',
                                          style: const TextStyle(
                                            color: SpeedColors.navy,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      item['description']?.toString() ??
                                          'No description',
                                      style: const TextStyle(
                                        color: SpeedColors.inkSoft,
                                        height: 1.35,
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    Wrap(
                                      spacing: 8,
                                      children: [
                                        SpeedPill(
                                          text:
                                              item['category']?.toString() ??
                                              '-',
                                        ),
                                        isAvailable
                                            ? const SpeedBadge(
                                                text: 'Available',
                                                background: Color(0xFFEAF7EF),
                                                foreground: Color(0xFF1F7A4D),
                                              )
                                            : const SpeedBadge(
                                                text: 'Unavailable',
                                                background: Color(0xFFFFF3DC),
                                                foreground: Color(0xFF6B4708),
                                              ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemCount: items.length,
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: _MenuChatbot(
                        busy: _chatBusy,
                        status: _chatStatus,
                        voiceStatus: _voice.statusText,
                        isListening: _voice.isListening,
                        history: _chatHistory,
                        controller: _chatController,
                        plateNumber: _plateNumber,
                        direction: _direction,
                        onSend: _sendChat,
                        onToggleVoiceInput: _toggleVoiceInput,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SpeedCard(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(onPressed: onRetry, child: const Text('Retry')),
            ],
          ),
        ),
      ),
    );
  }
}

class _MenuImageThumb extends StatelessWidget {
  const _MenuImageThumb({required this.imageUrl});

  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    if (imageUrl == null || imageUrl!.isEmpty) {
      return _fallback();
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: 96,
        height: 96,
        child: Image.network(
          imageUrl!,
          fit: BoxFit.cover,
          webHtmlElementStrategy: WebHtmlElementStrategy.prefer,
          errorBuilder: (context, error, stackTrace) => _fallback(),
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) {
              return child;
            }
            return Container(
              color: const Color(0xFFF3F5F8),
              child: const Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _fallback() {
    return Container(
      width: 96,
      height: 96,
      decoration: BoxDecoration(
        color: const Color(0xFFF3F5F8),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Icon(Icons.fastfood, color: SpeedColors.inkFaint),
    );
  }
}

class _MenuChatbot extends StatelessWidget {
  const _MenuChatbot({
    required this.busy,
    required this.status,
    required this.voiceStatus,
    required this.isListening,
    required this.history,
    required this.controller,
    required this.plateNumber,
    required this.direction,
    required this.onSend,
    required this.onToggleVoiceInput,
  });

  final bool busy;
  final String? status;
  final String? voiceStatus;
  final bool isListening;
  final List<Map<String, dynamic>> history;
  final TextEditingController controller;
  final String? plateNumber;
  final String direction;
  final VoidCallback onSend;
  final VoidCallback onToggleVoiceInput;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF10223D), Color(0xFF17355E), Color(0xFF1E4A78)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x33FFFFFF)),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Speed Burger Assistant',
            style: TextStyle(
              color: Color(0xFFF6F9FC),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Plate: ${plateNumber ?? '-'} · Direction: $direction',
            style: const TextStyle(color: Color(0xCCF6F9FC), fontSize: 12),
          ),
          if (status != null && status!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              status!,
              style: const TextStyle(color: Color(0x99F6F9FC), fontSize: 12),
            ),
          ],
          if (voiceStatus != null && voiceStatus!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              voiceStatus!,
              style: const TextStyle(color: Color(0xCCF6F9FC), fontSize: 12),
            ),
          ],
          const SizedBox(height: 8),
          SizedBox(
            height: 100,
            child: SingleChildScrollView(
              child: history.isEmpty
                  ? const _MenuBubble(
                      text:
                          'Submit entry from scan to start the menu assistant.',
                      isUser: false,
                    )
                  : Column(
                      children: history
                          .map(
                            (entry) => _MenuBubble(
                              text: (entry['content'] ?? '').toString(),
                              isUser: entry['role'] == 'user',
                            ),
                          )
                          .toList(),
                    ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  minLines: 1,
                  maxLines: 3,
                  style: const TextStyle(
                    color: Color(0xFFF6F9FC),
                    fontSize: 13,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Ask for order suggestions...',
                    hintStyle: const TextStyle(color: Color(0x99F6F9FC)),
                    isDense: true,
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
                onPressed: busy ? null : onSend,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFFFD67A),
                  foregroundColor: const Color(0xFF16253E),
                ),
                child: Text(busy ? '...' : 'Send'),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                onPressed: busy ? null : onToggleVoiceInput,
                style: IconButton.styleFrom(
                  backgroundColor: isListening
                      ? const Color(0xFFFFD67A)
                      : const Color(0x29FFFFFF),
                  foregroundColor: isListening
                      ? const Color(0xFF16253E)
                      : Colors.white,
                ),
                icon: Icon(isListening ? Icons.mic : Icons.mic_none),
                tooltip: isListening ? 'Stop voice input' : 'Start voice input',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MenuBubble extends StatelessWidget {
  const _MenuBubble({required this.text, required this.isUser});

  final String text;
  final bool isUser;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: isUser ? const Color(0xFFFFD67A) : const Color(0x29FFFFFF),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: isUser ? const Color(0xFF16253E) : Colors.white,
            fontSize: 12.5,
            height: 1.3,
          ),
        ),
      ),
    );
  }
}
