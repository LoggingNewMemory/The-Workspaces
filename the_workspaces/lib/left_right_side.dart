import 'package:flutter/material.dart';

class SidePanel extends StatefulWidget {
  final Alignment alignment;
  final String label;

  const SidePanel({super.key, required this.alignment, required this.label});

  @override
  State<SidePanel> createState() => _SidePanelState();
}

class _SidePanelState extends State<SidePanel> {
  bool isHovered = false;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: widget.alignment,
      child: MouseRegion(
        onEnter: (_) => setState(() => isHovered = true),
        onExit: (_) => setState(() => isHovered = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutExpo,
          width: isHovered ? 400.0 : 20.0,
          height: double.infinity,
          decoration: BoxDecoration(
            color: isHovered ? Colors.black.withOpacity(0.85) : Colors.black45,
            border: Border(
              // Add a subtle border facing the center of the screen
              left: widget.alignment == Alignment.centerRight && isHovered
                  ? const BorderSide(color: Colors.white24)
                  : BorderSide.none,
              right: widget.alignment == Alignment.centerLeft && isHovered
                  ? const BorderSide(color: Colors.white24)
                  : BorderSide.none,
            ),
          ),
          child: isHovered ? Center(child: Text(widget.label)) : null,
        ),
      ),
    );
  }
}
