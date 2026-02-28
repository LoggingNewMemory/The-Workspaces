import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'dart:ui' as ui;
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
      width: 290,
      height: 250, // 200px for video + 50px for footer
      margin: const EdgeInsets.only(bottom: 20.0),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2E),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.5),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        children: [
          // 1. The Live Wayland Thumbnail
          SizedBox(
            height: 200,
            width: 290,
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(12),
              ),
              child: WindowThumbnail(windowId: win['id']!),
            ),
          ),

          // 2. The Flutter Footer
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.02),
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(12),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontWeight: FontWeight.w500,
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
                      size: 18,
                    ),
                    tooltip: 'Undock & Restore',
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

// --- NEW WIDGET: Live polling of the C Compositor's buffer ---
class WindowThumbnail extends StatefulWidget {
  final String windowId;

  const WindowThumbnail({super.key, required this.windowId});

  @override
  State<WindowThumbnail> createState() => _WindowThumbnailState();
}

class _WindowThumbnailState extends State<WindowThumbnail> {
  ui.Image? _image;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startPolling();
  }

  void _startPolling() {
    // Poll at ~30 FPS (every 33ms)
    _timer = Timer.periodic(const Duration(milliseconds: 33), (_) async {
      try {
        final file = File('/tmp/thumb_${widget.windowId}.rgba');
        if (await file.exists()) {
          final bytes = await file.readAsBytes();

          // Ensure file isn't mid-write (290 * 200 pixels * 4 bytes per pixel)
          if (bytes.length == 290 * 200 * 4) {
            ui.decodeImageFromPixels(
              bytes,
              290,
              200,
              ui
                  .PixelFormat
                  .bgra8888, // Standard Wayland DRM Little-Endian format (change to rgba8888 if colors are swapped)
              (img) {
                if (mounted) {
                  final oldImage = _image;
                  setState(() => _image = img);
                  oldImage
                      ?.dispose(); // Prevent memory leaks in the Flutter engine
                }
              },
            );
          }
        }
      } catch (e) {
        // Suppress read lock errors while C is writing
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_image == null) {
      return Container(
        color: Colors.black45,
        child: const Center(
          child: CircularProgressIndicator(
            color: Colors.white24,
            strokeWidth: 2,
          ),
        ),
      );
    }

    return RawImage(
      image: _image,
      width: 290,
      height: 200,
      fit: BoxFit.cover,
      filterQuality: FilterQuality.high,
    );
  }
}
