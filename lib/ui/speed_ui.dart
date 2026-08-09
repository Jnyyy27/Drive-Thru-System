import 'package:flutter/material.dart';

class SpeedColors {
  static const bg = Color(0xFFF4F6F8);
  static const surface = Color(0xFFFFFFFF);
  static const ink = Color(0xFF10182B);
  static const inkSoft = Color(0xFF5B6678);
  static const inkFaint = Color(0xFF8A93A3);
  static const navy = Color(0xFF1B3358);
  static const navyDeep = Color(0xFF102237);
  static const amber = Color(0xFFF2A93B);
  static const line = Color(0xFFE2E6EB);
  static const green = Color(0xFF2F9E68);
}

class SpeedShell extends StatelessWidget {
  const SpeedShell({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SpeedColors.bg,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 28),
              child: Column(
                children: [
                  _Topbar(title: title, subtitle: subtitle, trailing: trailing),
                  const SizedBox(height: 16),
                  // Hairline separates the fixed console header from
                  // scrolling content, so long pages (Logs/Orders) don't
                  // make the header feel like it's part of the list.
                  Container(height: 1, color: SpeedColors.line),
                  const SizedBox(height: 20),
                  Expanded(child: child),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Topbar extends StatelessWidget {
  const _Topbar({
    required this.title,
    required this.subtitle,
    required this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: SpeedColors.navy,
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                color: SpeedColors.navy.withValues(alpha: 0.25),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: const Icon(
            Icons.local_shipping_outlined,
            color: Colors.white,
            size: 22,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                subtitle ?? 'Speed Burger',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  letterSpacing: 1.4,
                  color: SpeedColors.inkSoft,
                ),
              ),
              const SizedBox(height: 2),
              Text(title, style: Theme.of(context).textTheme.titleLarge),
            ],
          ),
        ),
        trailing == null ? const SizedBox.shrink() : trailing!,
      ],
    );
  }
}

/// Small header used above a group of cards (e.g. "Quick actions").
/// Centralizes the styling so every page gets the same treatment
/// instead of each screen inlining its own Text(style: labelSmall).
class SpeedSectionLabel extends StatelessWidget {
  const SpeedSectionLabel(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          text.toUpperCase(),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            letterSpacing: 1.1,
            color: SpeedColors.inkSoft,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (trailing != null) ...[const Spacer(), trailing!],
      ],
    );
  }
}

/// Base surface used throughout the console. Pass [onTap] to make it
/// interactive: it will lift on hover/press and tint its border toward
/// [accent], so clickable cards read as clickable before the user is
/// already touching them.
class SpeedCard extends StatefulWidget {
  const SpeedCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.onTap,
    this.accent,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? accent;

  @override
  State<SpeedCard> createState() => _SpeedCardState();
}

class _SpeedCardState extends State<SpeedCard> {
  bool _hovered = false;
  bool _pressed = false;

  bool get _interactive => widget.onTap != null;

  @override
  Widget build(BuildContext context) {
    final accent = widget.accent ?? SpeedColors.navy;
    final lifted = _interactive && (_hovered || _pressed);

    final card = AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOut,
      transform: lifted
          ? Matrix4.translationValues(0.0, -2.0, 0.0)
          : Matrix4.identity(),
      decoration: BoxDecoration(
        color: SpeedColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: lifted ? accent.withValues(alpha: 0.55) : SpeedColors.line,
          width: lifted ? 1.4 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: SpeedColors.ink.withValues(alpha: lifted ? 0.10 : 0.04),
            blurRadius: lifted ? 18 : 8,
            offset: Offset(0, lifted ? 8 : 2),
          ),
        ],
      ),
      padding: widget.padding,
      child: widget.child,
    );

    if (!_interactive) return card;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: card,
      ),
    );
  }
}

class SpeedPill extends StatelessWidget {
  const SpeedPill({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: SpeedColors.surface,
        border: Border.all(color: SpeedColors.line),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: Theme.of(
          context,
        ).textTheme.labelMedium?.copyWith(color: SpeedColors.inkSoft),
      ),
    );
  }
}

class SpeedBadge extends StatelessWidget {
  const SpeedBadge({
    super.key,
    required this.text,
    required this.background,
    required this.foreground,
  });

  final String text;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(color: foreground),
      ),
    );
  }
}
