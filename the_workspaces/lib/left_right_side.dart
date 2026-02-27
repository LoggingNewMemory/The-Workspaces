import 'dart:io';
import 'dart:convert';
import 'dart:async';
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
  Timer? _timer;

  // This will now be populated live from the C compositor
  List<Map<String, String>> activeWindows = [];

  @override
  void initState() {
    super.initState();
    _startWatchingCompositor();
  }

  void _startWatchingCompositor() {
    // Poll the /tmp file every 500ms for instant UI updates
    _timer = Timer.periodic(const Duration(milliseconds: 500), (_) async {
      try {
        final file = File('/tmp/workspace_windows.json');
        if (await file.exists()) {
          final content = await file.readAsString();
          final List<dynamic> decoded = jsonDecode(content);

          List<Map<String, String>> newWindows = decoded
              .map(
                (e) => {
                  'id': e['id'].toString(),
                  'name': e['name'].toString(),
                  'title': e['title'].toString(),
                },
              )
              .toList();

          // Only update the state if the window list actually changed
          if (newWindows.toString() != activeWindows.toString()) {
            setState(() => activeWindows = newWindows);
          }
        }
      } catch (e) {
        // Suppress read errors (happens occasionally if reading while C is writing)
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    bool isLeft = widget.alignment == Alignment.centerLeft;

    return Align(
      alignment: widget.alignment,
      child: MouseRegion(
        onEnter: (_) => setState(() => isHovered = true),
        onExit: (_) => setState(() => isHovered = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutExpo,
          width: isHovered ? 450.0 : 20.0, // Expanded width for the large cards
          height: double.infinity,
          decoration: BoxDecoration(
            color: isHovered
                ? const Color(0xFF11111B).withOpacity(0.9)
                : Colors.transparent,
            border: Border(
              left: !isLeft && isHovered
                  ? const BorderSide(color: Colors.white12)
                  : BorderSide.none,
              right: isLeft && isHovered
                  ? const BorderSide(color: Colors.white12)
                  : BorderSide.none,
            ),
          ),
          child: isHovered
              ? Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header matching your design
                      Text(
                        widget.label,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 2.0,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Divider(color: Colors.white24, height: 1),
                      const SizedBox(height: 24),

                      // The Window Cards
                      Expanded(
                        child: ListView.builder(
                          itemCount: activeWindows.length,
                          itemBuilder: (context, index) {
                            final win = activeWindows[index];
                            return _buildWindowCard(win);
                          },
                        ),
                      ),
                    ],
                  ),
                )
              : null,
        ),
      ),
    );
  }

  Widget _buildWindowCard(Map<String, String> win) {
    Widget card = Container(
      height: 220, // Large height to mimic a thumbnail
      margin: const EdgeInsets.only(bottom: 24),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2E), // Darker aesthetic background
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.5),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Placeholder for the App Icon / Graphic
          Center(
            child: Icon(
              win['name'] == 'Firefox' ? Icons.public : Icons.code,
              size: 80,
              color: Colors.white24,
            ),
          ),
          // Title Bar at the bottom of the card
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.6),
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(16),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    win['name']!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    win['title']!,
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );

    // Make the card draggable
    return Draggable<String>(
      data: win['id'],
      feedback: Opacity(opacity: 0.7, child: SizedBox(width: 400, child: card)),
      childWhenDragging: Opacity(opacity: 0.3, child: card),
      child: card,
    );
  }
}
