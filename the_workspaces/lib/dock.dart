import 'package:flutter/material.dart';

class DockPanel extends StatefulWidget {
  const DockPanel({super.key});

  @override
  State<DockPanel> createState() => _DockPanelState();
}

class _DockPanelState extends State<DockPanel> {
  bool isHovered = false;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: MouseRegion(
        onEnter: (_) => setState(() => isHovered = true),
        onExit: (_) => setState(() => isHovered = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutExpo,
          width: isHovered ? 800.0 : 600.0,
          height: isHovered ? 120.0 : 20.0,
          decoration: BoxDecoration(
            color: isHovered ? Colors.black.withOpacity(0.85) : Colors.black45,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            border: isHovered
                ? const Border(top: BorderSide(color: Colors.white24))
                : const Border(),
          ),
          child: isHovered
              ? const Center(child: Text('[MACOS DOCK - APPS GO HERE]'))
              : null,
        ),
      ),
    );
  }
}
