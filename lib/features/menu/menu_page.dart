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
  final ScrollController _chatScrollController = ScrollController();
  final VoiceAssistantController _voice = VoiceAssistantController();
  final List<Map<String, dynamic>> _chatHistory = <Map<String, dynamic>>[];
  bool _chatBusy = false;
  String? _chatStatus;
  String? _plateNumber;
  String _direction = 'IN';
  String? _selectedCategory;
  List<Map<String, dynamic>> _menuContextItems = const <Map<String, dynamic>>[];
  int _voiceSessionId = 0;
  bool _voiceAutoSubmitting = false;

  // Assistant is a floating bubble here too, matching the scan page,
  // instead of a bar permanently docked over the menu list.
  bool _assistantExpanded = false;
  bool _assistantUnread = false;

  List<Map<String, dynamic>> _cartLines = <Map<String, dynamic>>[];
  double _cartTotal = 0;
  int? _cartOrderId;
  String _cartOrderStatus = 'Pending';
  bool _cartBusy = false;
  String? _cartStatus;

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
      // Arriving here with a welcome message means the assistant has
      // something to say right away — open it instead of leaving the
      // operator to notice and tap the bubble themselves.
      _assistantExpanded = true;
      _voice.speak(widget.initialAssistantMessage!.trim());
    }
    if ((_plateNumber ?? '').isNotEmpty) {
      _loadCart();
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
    _chatScrollController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final future = widget.authSession.apiClient.menu();
    setState(() {
      _menuFuture = future;
    });
    await future;
    if ((_plateNumber ?? '').isNotEmpty) {
      await _loadCart();
    }
  }

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

  void _appendChat(Map<String, dynamic> entry) {
    _chatHistory.add(entry);
    if (!_assistantExpanded) {
      _assistantUnread = true;
    }
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
      _appendChat({'role': 'user', 'content': message});
    });
    _scrollChatToBottom();

    try {
      final result = await widget.authSession.apiClient.assistantChat(
        plateNumber: _plateNumber!,
        direction: _direction,
        message: message,
        history: List<Map<String, dynamic>>.from(_chatHistory),
        menuItems: _menuContextItems,
      );

      final orderUpdate =
          (result['order'] as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{};
      final showCheckoutDialog =
          orderUpdate['saved'] == true && orderUpdate['checkout'] == true;
      final chatCheckoutLines =
          ((orderUpdate['order_lines'] as List?) ?? const [])
              .cast<Map>()
              .map((line) => line.cast<String, dynamic>())
              .toList();
      final chatCheckoutOrderId = int.tryParse(
        '${orderUpdate['order_id'] ?? ''}',
      );
      final chatCheckoutTotal =
          double.tryParse('${orderUpdate['total_amount'] ?? ''}') ??
          chatCheckoutLines.fold<double>(
            0,
            (sum, line) =>
                sum + (double.tryParse('${line['subtotal'] ?? 0}') ?? 0),
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
          _appendChat({'role': 'assistant', 'content': reply});
        }
        _chatController.clear();
      });
      _scrollChatToBottom();

      if (reply.isNotEmpty) {
        await _voice.speak(reply);
      }
      if ((_plateNumber ?? '').isNotEmpty) {
        await _loadCart();
      }
      if (showCheckoutDialog && mounted) {
        await _showConfirmedOrderDialog(
          orderId: chatCheckoutOrderId,
          lines: chatCheckoutLines,
          total: chatCheckoutTotal,
        );
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

  int get _cartItemCount {
    var total = 0;
    for (final line in _cartLines) {
      total += int.tryParse('${line['quantity'] ?? 0}') ?? 0;
    }
    return total;
  }

  bool get _canEditCart => _cartOrderStatus == 'Pending';

  int _quantityForMenuItem(int menuId) {
    for (final line in _cartLines) {
      final lineMenuId = int.tryParse('${line['menu_id'] ?? ''}');
      if (lineMenuId == menuId) {
        return int.tryParse('${line['quantity'] ?? 0}') ?? 0;
      }
    }
    return 0;
  }

  Future<void> _loadCart() async {
    final plate = (_plateNumber ?? '').trim();
    if (plate.isEmpty) {
      return;
    }
    try {
      final snapshot = await widget.authSession.apiClient.orderCart(
        plateNumber: plate,
      );
      if (!mounted) return;
      setState(() {
        _applyCartSnapshot(snapshot);
      });
    } catch (_) {
      // Keep UI usable even when cart refresh fails briefly.
    }
  }

  void _applyCartSnapshot(Map<String, dynamic> snapshot) {
    final lines = ((snapshot['lines'] as List?) ?? const [])
        .cast<Map>()
        .map((line) => line.cast<String, dynamic>())
        .toList();

    final order = (snapshot['order'] as Map?)?.cast<String, dynamic>();
    _cartLines = lines;
    _cartOrderId = order == null ? null : int.tryParse('${order['order_id']}');
    _cartOrderStatus = (order?['status'] ?? 'Pending').toString();
    _cartTotal =
        double.tryParse('${order?['total_amount'] ?? 0}') ??
        lines.fold<double>(
          0,
          (sum, line) =>
              sum + (double.tryParse('${line['subtotal'] ?? 0}') ?? 0),
        );
    _cartStatus = null;
  }

  Future<void> _addToCart(Map<String, dynamic> item) async {
    final plate = (_plateNumber ?? '').trim();
    final menuId = int.tryParse('${item['menu_id'] ?? ''}');
    if (plate.isEmpty || menuId == null) {
      setState(() {
        _cartStatus = 'Scan and submit entry first.';
      });
      return;
    }

    setState(() {
      _cartBusy = true;
      _cartStatus = null;
    });
    try {
      final snapshot = await widget.authSession.apiClient.addCartItem(
        plateNumber: plate,
        menuId: menuId,
        quantity: 1,
      );
      if (!mounted) return;
      setState(() {
        _applyCartSnapshot(snapshot);
        _cartStatus = '${item['name']} added to cart.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _cartStatus = 'Add failed: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _cartBusy = false;
        });
      }
    }
  }

  Future<void> _updateCartQuantity(int menuId, int quantity) async {
    final plate = (_plateNumber ?? '').trim();
    if (plate.isEmpty) {
      return;
    }

    setState(() {
      _cartBusy = true;
      _cartStatus = null;
    });
    try {
      final snapshot = await widget.authSession.apiClient
          .updateCartItemQuantity(
            plateNumber: plate,
            menuId: menuId,
            quantity: quantity,
          );
      if (!mounted) return;
      setState(() {
        _applyCartSnapshot(snapshot);
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _cartStatus = 'Cart update failed: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _cartBusy = false;
        });
      }
    }
  }

  Future<Map<String, dynamic>?> _confirmManualOrder() async {
    final plate = (_plateNumber ?? '').trim();
    if (plate.isEmpty) {
      return null;
    }

    setState(() {
      _cartBusy = true;
      _cartStatus = null;
    });
    try {
      final snapshot = await widget.authSession.apiClient.confirmCartOrder(
        plateNumber: plate,
      );
      if (!mounted) return null;
      setState(() {
        _applyCartSnapshot(snapshot);
        _cartStatus =
            (snapshot['message'] ?? 'Order confirmed and sent to kitchen.')
                .toString();
      });
      return snapshot;
    } catch (error) {
      if (!mounted) return null;
      setState(() {
        _cartStatus = 'Confirm failed: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _cartBusy = false;
        });
      }
    }
    return null;
  }

  Future<void> _confirmManualOrderAndShowDialog() async {
    if (!_canEditCart || _cartLines.isEmpty || _cartBusy) {
      return;
    }

    final snapshot = await _confirmManualOrder();
    if (!mounted || snapshot == null) {
      return;
    }

    final order =
        (snapshot['confirmed_order'] as Map?)?.cast<String, dynamic>() ??
        (snapshot['order'] as Map?)?.cast<String, dynamic>();
    final lines =
        ((snapshot['confirmed_lines'] as List?) ??
                (snapshot['lines'] as List?) ??
                const [])
            .cast<Map>()
            .map((line) => line.cast<String, dynamic>())
            .toList();
    final total =
        double.tryParse('${order?['total_amount'] ?? _cartTotal}') ??
        _cartTotal;

    await _showConfirmedOrderDialog(
      orderId: int.tryParse('${order?['order_id'] ?? ''}'),
      lines: lines,
      total: total,
    );
  }

  Future<void> _showConfirmedOrderDialog({
    required int? orderId,
    required List<Map<String, dynamic>> lines,
    required double total,
  }) async {
    if (!mounted) {
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Order Confirmed'),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  orderId == null
                      ? 'Your order has been sent to kitchen.'
                      : 'Order #$orderId has been sent to kitchen.',
                ),
                const SizedBox(height: 10),
                _buildOrderDetailsList(maxHeight: 220, linesOverride: lines),
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Text(
                      'Total',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const Spacer(),
                    Text(
                      'RM ${total.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: SpeedColors.navy,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Done'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _incrementMenuItem(Map<String, dynamic> item) async {
    final menuId = int.tryParse('${item['menu_id'] ?? ''}');
    if (menuId == null) {
      return;
    }
    final currentQty = _quantityForMenuItem(menuId);
    if (currentQty <= 0) {
      await _addToCart(item);
      return;
    }
    await _updateCartQuantity(menuId, currentQty + 1);
  }

  Future<void> _decrementMenuItem(Map<String, dynamic> item) async {
    final menuId = int.tryParse('${item['menu_id'] ?? ''}');
    if (menuId == null) {
      return;
    }
    final currentQty = _quantityForMenuItem(menuId);
    if (currentQty <= 0) {
      return;
    }
    await _updateCartQuantity(menuId, currentQty - 1);
  }

  List<String> _orderedCategories(List<String> rawCategories) {
    const preferred = <String>['Burger', 'Side', 'Drink', 'Combo'];
    final seen = <String>{};
    final ordered = <String>[];

    for (final category in preferred) {
      ordered.add(category);
      seen.add(category.toLowerCase());
    }

    for (final category in rawCategories) {
      final cleaned = category.trim();
      if (cleaned.isEmpty) continue;
      final key = cleaned.toLowerCase();
      if (seen.add(key)) {
        ordered.add(cleaned);
      }
    }

    return ordered;
  }

  Widget _buildOrderDetailsList({
    required double maxHeight,
    List<Map<String, dynamic>>? linesOverride,
    bool editable = false,
    Future<void> Function(int menuId, int nextQuantity)? onAdjustQuantity,
  }) {
    final lines = linesOverride ?? _cartLines;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: lines.isEmpty
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Text(
                'No items in cart.',
                style: TextStyle(color: SpeedColors.inkSoft),
              ),
            )
          : ListView.separated(
              shrinkWrap: true,
              itemCount: lines.length,
              separatorBuilder: (_, _) => const Divider(height: 14),
              itemBuilder: (context, index) {
                final line = lines[index];
                final quantity = int.tryParse('${line['quantity'] ?? ''}') ?? 0;
                final menuId = int.tryParse('${line['menu_id'] ?? ''}');
                final unitPrice =
                    double.tryParse('${line['unit_price'] ?? 0}') ?? 0;
                final subtotal =
                    double.tryParse('${line['subtotal'] ?? 0}') ?? 0;
                final canEditLine =
                    editable &&
                    menuId != null &&
                    _canEditCart &&
                    !_cartBusy &&
                    onAdjustQuantity != null;

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            line['name']?.toString() ?? '-',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '$quantity x RM ${unitPrice.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: SpeedColors.inkSoft,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (editable)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            onPressed: canEditLine && quantity > 0
                                ? () => onAdjustQuantity(menuId!, quantity - 1)
                                : null,
                            icon: const Icon(Icons.remove_circle_outline),
                            visualDensity: VisualDensity.compact,
                            splashRadius: 16,
                          ),
                          SizedBox(
                            width: 20,
                            child: Text(
                              '$quantity',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: canEditLine && quantity < 20
                                ? () => onAdjustQuantity(menuId!, quantity + 1)
                                : null,
                            icon: const Icon(Icons.add_circle_outline),
                            visualDensity: VisualDensity.compact,
                            splashRadius: 16,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'RM ${subtotal.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: SpeedColors.navy,
                            ),
                          ),
                        ],
                      )
                    else
                      Text(
                        'RM ${subtotal.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: SpeedColors.navy,
                        ),
                      ),
                  ],
                );
              },
            ),
    );
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
    const normalSidePanelWidth = 360.0;
    final viewport = MediaQuery.sizeOf(context);
    final sideGutter = ((viewport.width - 980) / 2).clamp(0.0, double.infinity);
    final canDockSideBubble = sideGutter >= 96;
    final sidePanelWidth = normalSidePanelWidth;
    final sidePanelMaxHeight = (viewport.height - 120).clamp(320.0, 560.0);
    final useSideFloating = canDockSideBubble;

    return SpeedShell(
      title: 'Menu',
      subtitle: 'Speed Burger · Drive-Thru System',
      trailing: OutlinedButton(
        onPressed: () => context.go('/dashboard'),
        child: const Text('Dashboard'),
      ),
      floating: useSideFloating
          ? AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              transitionBuilder: (child, animation) => ScaleTransition(
                scale: animation,
                alignment: Alignment.bottomRight,
                child: FadeTransition(opacity: animation, child: child),
              ),
              child: _assistantExpanded
                  ? _buildAssistantPanel(
                      key: const ValueKey('panel-side'),
                      width: sidePanelWidth,
                      maxHeight: sidePanelMaxHeight,
                    )
                  : _buildAssistantBubble(key: const ValueKey('bubble-side')),
            )
          : null,
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
          final orderedCategories = _orderedCategories(categories);

          // Assistant context always sees the full menu, independent of
          // whatever category filter the operator currently has active.
          _menuContextItems = items
              .map(
                (item) => <String, dynamic>{
                  'name': item['name']?.toString() ?? '',
                  'category': item['category']?.toString() ?? '',
                  'price': item['price'],
                  'description': item['description']?.toString() ?? '',
                  'available':
                      item['available'] == true || item['available'] == 1,
                },
              )
              .toList();

          final filteredItems = _selectedCategory == null
              ? items
              : items
                    .where(
                      (item) =>
                          (item['category']?.toString() ?? '') ==
                          _selectedCategory,
                    )
                    .toList();

          return LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 640;
              final panelMaxHeight = (constraints.maxHeight - 48).clamp(
                320.0,
                560.0,
              );
              final listBottomPadding = useSideFloating ? 12.0 : 16.0;

              return Stack(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Browse the current burgers, sides, and drinks on offer.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 14),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _CategoryChip(
                                  label: 'All',
                                  selected: _selectedCategory == null,
                                  onTap: () =>
                                      setState(() => _selectedCategory = null),
                                ),
                                for (final category in orderedCategories)
                                  _CategoryChip(
                                    label: category,
                                    selected: _selectedCategory == category,
                                    onTap: () => setState(
                                      () => _selectedCategory = category,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  IconButton.filledTonal(
                                    onPressed: (_plateNumber ?? '').isEmpty
                                        ? null
                                        : _openCartDialog,
                                    tooltip: 'Open cart',
                                    icon: const Icon(
                                      Icons.shopping_cart,
                                      size: 20,
                                    ),
                                  ),
                                  if (_cartItemCount > 0)
                                    Positioned(
                                      right: -2,
                                      top: -2,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 5,
                                          vertical: 1,
                                        ),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFE0554F),
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                          border: Border.all(
                                            color: Colors.white,
                                            width: 1.2,
                                          ),
                                        ),
                                        child: Text(
                                          '$_cartItemCount',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 10,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'RM ${_cartTotal.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  color: SpeedColors.navy,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Expanded(
                        child: RefreshIndicator(
                          onRefresh: _refresh,
                          child: filteredItems.isEmpty
                              ? ListView(
                                  padding: EdgeInsets.only(
                                    bottom: listBottomPadding,
                                  ),
                                  children: const [
                                    SizedBox(height: 80),
                                    Center(
                                      child: Text(
                                        'No items in this category.',
                                        style: TextStyle(
                                          color: SpeedColors.inkSoft,
                                        ),
                                      ),
                                    ),
                                  ],
                                )
                              : ListView.separated(
                                  padding: EdgeInsets.only(
                                    bottom: listBottomPadding,
                                  ),
                                  itemBuilder: (context, index) {
                                    final item = filteredItems[index];
                                    final isAvailable =
                                        item['available'] == true ||
                                        item['available'] == 1;
                                    final imageUrl = item['image_url']
                                        ?.toString();

                                    return Opacity(
                                      opacity: isAvailable ? 1.0 : 0.55,
                                      child: SpeedCard(
                                        child: Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            _MenuImageThumb(imageUrl: imageUrl),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Row(
                                                    children: [
                                                      Expanded(
                                                        child: Text(
                                                          item['name']
                                                                  ?.toString() ??
                                                              '-',
                                                          style:
                                                              Theme.of(context)
                                                                  .textTheme
                                                                  .titleMedium,
                                                        ),
                                                      ),
                                                      const SizedBox(width: 8),
                                                      isAvailable
                                                          ? const SpeedBadge(
                                                              text: 'Available',
                                                              background: Color(
                                                                0xFFEAF7EF,
                                                              ),
                                                              foreground: Color(
                                                                0xFF1F7A4D,
                                                              ),
                                                            )
                                                          : const SpeedBadge(
                                                              text:
                                                                  'Unavailable',
                                                              background: Color(
                                                                0xFFFFF3DC,
                                                              ),
                                                              foreground: Color(
                                                                0xFF6B4708,
                                                              ),
                                                            ),
                                                      const SizedBox(width: 8),
                                                      Text(
                                                        'RM ${item['price'] ?? '-'}',
                                                        style: const TextStyle(
                                                          color:
                                                              SpeedColors.navy,
                                                          fontWeight:
                                                              FontWeight.w700,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 8),
                                                  Text(
                                                    item['description']
                                                            ?.toString() ??
                                                        'No description',
                                                    style: const TextStyle(
                                                      color:
                                                          SpeedColors.inkSoft,
                                                      height: 1.35,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 10),
                                                  Wrap(
                                                    spacing: 8,
                                                    children: [
                                                      SpeedPill(
                                                        text:
                                                            item['category']
                                                                ?.toString() ??
                                                            '-',
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 10),
                                                  Row(
                                                    children: [
                                                      const Spacer(),
                                                      IconButton(
                                                        onPressed:
                                                            !isAvailable ||
                                                                _cartBusy ||
                                                                (_plateNumber ??
                                                                        '')
                                                                    .isEmpty ||
                                                                !_canEditCart
                                                            ? null
                                                            : () =>
                                                                  _decrementMenuItem(
                                                                    item,
                                                                  ),
                                                        icon: const Icon(
                                                          Icons
                                                              .remove_circle_outline,
                                                        ),
                                                      ),
                                                      Text(
                                                        '${_quantityForMenuItem(int.tryParse('${item['menu_id'] ?? ''}') ?? -1)}',
                                                        style: const TextStyle(
                                                          fontWeight:
                                                              FontWeight.w700,
                                                        ),
                                                      ),
                                                      IconButton(
                                                        onPressed:
                                                            !isAvailable ||
                                                                _cartBusy ||
                                                                (_plateNumber ??
                                                                        '')
                                                                    .isEmpty ||
                                                                !_canEditCart
                                                            ? null
                                                            : () =>
                                                                  _incrementMenuItem(
                                                                    item,
                                                                  ),
                                                        icon: const Icon(
                                                          Icons.add_circle,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                  separatorBuilder: (_, _) =>
                                      const SizedBox(height: 12),
                                  itemCount: filteredItems.length,
                                ),
                        ),
                      ),
                      if ((_cartStatus ?? '').isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Text(
                          _cartStatus!,
                          style: const TextStyle(
                            color: SpeedColors.inkSoft,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (!useSideFloating)
                    Positioned(
                      right: 16,
                      bottom: 8,
                      left: isNarrow && _assistantExpanded ? 16 : null,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        transitionBuilder: (child, animation) =>
                            ScaleTransition(
                              scale: animation,
                              alignment: Alignment.bottomRight,
                              child: FadeTransition(
                                opacity: animation,
                                child: child,
                              ),
                            ),
                        child: _assistantExpanded
                            ? _buildAssistantPanel(
                                key: const ValueKey('panel'),
                                width: isNarrow ? null : 380,
                                maxHeight: panelMaxHeight,
                              )
                            : _buildAssistantBubble(
                                key: const ValueKey('bubble'),
                              ),
                      ),
                    ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _openCartDialog() async {
    if (!mounted) {
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> adjustQuantity(int menuId, int nextQuantity) async {
              setDialogState(() {});
              await _updateCartQuantity(menuId, nextQuantity);
              if (!mounted) {
                return;
              }
              setDialogState(() {});
            }

            return AlertDialog(
              title: const Text('Your Cart'),
              content: SizedBox(
                width: 480,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          _cartOrderId == null
                              ? 'Draft order'
                              : 'Order #$_cartOrderId · $_cartOrderStatus',
                          style: const TextStyle(color: SpeedColors.inkSoft),
                        ),
                        const Spacer(),
                        Text(
                          '$_cartItemCount item(s)',
                          style: const TextStyle(
                            color: SpeedColors.navy,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _buildOrderDetailsList(
                      maxHeight: 280,
                      editable: true,
                      onAdjustQuantity: adjustQuantity,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Text(
                          'Total',
                          style: TextStyle(
                            color: SpeedColors.inkSoft,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          'RM ${_cartTotal.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: SpeedColors.navy,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
                FilledButton.icon(
                  onPressed: _cartBusy || _cartLines.isEmpty || !_canEditCart
                      ? null
                      : () async {
                          Navigator.of(context).pop();
                          await _confirmManualOrderAndShowDialog();
                        },
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('Confirm Order'),
                ),
              ],
            );
          },
        );
      },
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

  Widget _buildAssistantPanel({
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
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Drive-Thru Assistant',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                        color: Color(0xB3F6F9FC),
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Speed Burger Assistant',
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFF6F9FC),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Plate: ${_plateNumber ?? '-'} · Direction: $_direction',
                      style: const TextStyle(
                        color: Color(0xCCF6F9FC),
                        fontSize: 12,
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
          if (_chatStatus != null && _chatStatus!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              _chatStatus!,
              style: const TextStyle(color: Color(0x99F6F9FC), fontSize: 12),
            ),
          ],
          if ((_voice.statusText ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              _voice.statusText!,
              style: const TextStyle(color: Color(0xCCF6F9FC), fontSize: 12),
            ),
          ],
          const SizedBox(height: 12),
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 100),
              child: _chatHistory.isEmpty
                  ? const _MenuBubble(
                      text:
                          'Submit entry from scan to start the menu assistant.',
                      isUser: false,
                    )
                  : ListView.builder(
                      controller: _chatScrollController,
                      shrinkWrap: true,
                      itemCount: _chatHistory.length,
                      itemBuilder: (context, index) {
                        final entry = _chatHistory[index];
                        return _MenuBubble(
                          text: (entry['content'] ?? '').toString(),
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
                  controller: _chatController,
                  minLines: 1,
                  maxLines: 3,
                  style: const TextStyle(color: Color(0xFFF6F9FC)),
                  onSubmitted: _chatBusy ? null : (_) => _sendChat(),
                  decoration: InputDecoration(
                    hintText: 'Ask for order suggestions...',
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
                onPressed: _chatBusy ? null : _sendChat,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFFFD67A),
                  foregroundColor: const Color(0xFF16253E),
                ),
                child: _chatBusy
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
                onPressed: _chatBusy ? null : _toggleVoiceInput,
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

/// Clickable category filter chip. SpeedPill has no selected state, so
/// this is a small local variant that fills with the navy accent when
/// active instead of always looking the same regardless of selection.
class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? SpeedColors.navy : SpeedColors.surface,
          border: Border.all(
            color: selected ? SpeedColors.navy : SpeedColors.line,
          ),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : SpeedColors.inkSoft,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            fontSize: 13,
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

class _MenuBubble extends StatelessWidget {
  const _MenuBubble({required this.text, required this.isUser});

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
