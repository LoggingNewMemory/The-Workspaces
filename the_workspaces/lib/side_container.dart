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
  bool isWindowHovering = false; // From Compositor IPC
  List<Map<String, String>> containedWindows = [];
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startWatchingCompositorState();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  // Polls the central Workspace JSON state (Fast 50ms polling for smooth hover)
  void _startWatchingCompositorState() {
    bool isLeft = widget.alignment == Alignment.centerLeft;
    int myHoverID = isLeft ? 1 : 2;

    _timer = Timer.periodic(const Duration(milliseconds: 50), (_) async {
      try {
        final file = File('/tmp/workspace_state.json');
        if (await file.exists()) {
          final content = await file.readAsString();
          final decoded = jsonDecode(content);

          // 1. Check if compositor is dragging a window over our edge
          bool currentlyHovering = (decoded['hover'] == myHoverID);
          if (currentlyHovering != isWindowHovering) {
            setState(() => isWindowHovering = currentlyHovering);
          }

          // 2. Parse docked windows for this side
          final List<dynamic> dockedData =
              decoded[isLeft ? 'docked_left' : 'docked_right'];
          List<Map<String, String>> newWindows = dockedData
              .map(
                (e) => {
                  'id': e['id'].toString(),
                  'name': e['name'].toString(),
                  'title': e['title'].toString(),
                },
              )
              .toList();

          if (newWindows.toString() != containedWindows.toString()) {
            setState(() => containedWindows = newWindows);
          }
        }
      } catch (e) {
        // Suppress read/parse errors during C file writes
      }
    });
  }

  // Request to Undock OR to handle drags originating from the Flutter Dock UI
  void _sendDockAction(String action, String id) {
    try {
      final file = File('/tmp/dock_action.txt');
      file.writeAsStringSync('$action $id\n');
    } catch (e) {
      debugPrint('Failed to send dock action: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isLeft = widget.alignment == Alignment.centerLeft;
    String dockActionType = isLeft ? 'DOCK_LEFT' : 'DOCK_RIGHT';

    return Align(
      alignment: widget.alignment,
      child: DragTarget<Map>(
        onWillAccept: (data) => true,
        onAccept: (data) {
          // Triggered ONLY if dragged from the Flutter bottom dock
          _sendDockAction(dockActionType, data['id']);
        },
        builder: (context, candidateData, rejectedData) {
          // Open if mouse is over it, a flutter drag is over it, OR the C compositor says a window is dragged over it!
          bool isExpanded =
              isHovered ||
              candidateData.isNotEmpty ||
              isWindowHovering ||
              containedWindows.isNotEmpty;

          return MouseRegion(
            onEnter: (_) => setState(() => isHovered = true),
            onExit: (_) => setState(() => isHovered = false),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutExpo,
              width: isExpanded ? 340.0 : 40.0,
              height: double.infinity,
              decoration: BoxDecoration(
                color: isExpanded
                    ? const Color(0xFF11111B).withOpacity(0.95)
                    : Colors.transparent,
                border: Border(
                  left: !isLeft && isExpanded
                      ? const BorderSide(color: Colors.white12)
                      : BorderSide.none,
                  right: isLeft && isExpanded
                      ? const BorderSide(color: Colors.white12)
                      : BorderSide.none,
                ),
              ),
              child: isExpanded
                  ? Padding(
                      padding: const EdgeInsets.only(
                        top: 48.0,
                        left: 24.0,
                        right: 24.0,
                        bottom: 24.0,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            (candidateData.isNotEmpty || isWindowHovering)
                                ? 'DROP APP HERE'
                                : widget.label,
                            style: TextStyle(
                              color:
                                  (candidateData.isNotEmpty || isWindowHovering)
                                  ? Colors.blueAccent
                                  : Colors.white60,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.5,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Divider(
                            color:
                                (candidateData.isNotEmpty || isWindowHovering)
                                ? Colors.blueAccent
                                : Colors.white12,
                            height: 1,
                          ),
                          const SizedBox(height: 16),

                          if (containedWindows.isEmpty)
                            const Expanded(
                              child: Center(
                                child: Text(
                                  "Drag an active app here\nto dock it.",
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: Colors.white30),
                                ),
                              ),
                            )
                          else
                            Expanded(
                              child: ListView.builder(
                                // Disable scrolling to maintain native compositor overlay alignment
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: containedWindows.length,
                                itemBuilder: (context, index) {
                                  return _buildListItem(
                                    containedWindows[index],
                                  );
                                },
                              ),
                            ),
                        ],
                      ),
                    )
                  : Container(
                      alignment: isLeft
                          ? Alignment.centerLeft
                          : Alignment.centerRight,
                      child: Container(
                        width: 4,
                        height: 60,
                        margin: EdgeInsets.only(
                          left: isLeft ? 2 : 0,
                          right: !isLeft ? 2 : 0,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildListItem(Map win) {
    String title = win['title'] ?? 'Unknown';

    return Container(
      height: 250, // 200px for native window view + 50px for flutter footer
      margin: const EdgeInsets.only(bottom: 20.0),
      decoration: BoxDecoration(
        color: Colors.black26, // Base background
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        children: [
          // 1. Placeholder space. The C Compositor will overlay the live Wayland window perfectly here.
          const SizedBox(height: 200),

          // 2. Flutter Footer (Will sit right beneath the live view)
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: const BoxDecoration(
                color: Colors.black45,
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(8)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.open_in_new,
                      color: Colors.blueAccent,
                      size: 20,
                    ),
                    tooltip: 'Undock App',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () {
                      _sendDockAction('UNDOCK', win['id']!);
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
