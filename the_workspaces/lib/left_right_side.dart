import 'dart:io';
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
  List<String> dockedWindowIds = [];

  final List<Map<String, String>> dockableApps = [
    {'name': 'Firefox', 'class': 'firefox'},
    {'name': 'VS Code', 'class': 'code'},
    {'name': 'Terminal', 'class': 'konsole'},
    {'name': 'Dolphin', 'class': 'dolphin'},
  ];

  Future<void> _retileWindows(BuildContext context) async {
    if (dockedWindowIds.isEmpty) return;
    bool isLeft = widget.alignment == Alignment.centerLeft;
    final size = MediaQuery.of(context).size;

    int targetWidth = 400;
    int targetHeight = (size.height / dockedWindowIds.length).floor();
    int targetX = isLeft ? 0 : (size.width - targetWidth).toInt();

    for (int i = 0; i < dockedWindowIds.length; i++) {
      String winId = dockedWindowIds[i];
      int targetY = i * targetHeight;
      await Process.run('kdotool', [
        'windowmove',
        winId,
        targetX.toString(),
        targetY.toString(),
      ]);
      await Process.run('kdotool', [
        'windowsize',
        winId,
        targetWidth.toString(),
        targetHeight.toString(),
      ]);
    }
  }

  Future<void> _dockWindow(String windowClass, BuildContext context) async {
    try {
      var searchResult = await Process.run('kdotool', [
        'search',
        '--class',
        windowClass,
      ]);
      String output = searchResult.stdout.toString().trim();
      if (output.isEmpty) return;

      String windowId = output.split('\n').first;
      if (!dockedWindowIds.contains(windowId)) {
        setState(() => dockedWindowIds.add(windowId));
        await _retileWindows(context);
      }
    } catch (e) {
      debugPrint('Error docking window: $e');
    }
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
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutExpo,
          width: isHovered ? 400.0 : 20.0,
          height: double.infinity,
          decoration: BoxDecoration(
            color: isHovered ? Colors.black.withOpacity(0.85) : Colors.black45,
            border: Border(
              left: !isLeft && isHovered
                  ? const BorderSide(color: Colors.white24)
                  : BorderSide.none,
              right: isLeft && isHovered
                  ? const BorderSide(color: Colors.white24)
                  : BorderSide.none,
            ),
          ),
          child: DragTarget<String>(
            onAcceptWithDetails: (details) =>
                _dockWindow(details.data, context),
            builder: (context, candidateData, rejectedData) {
              if (!isHovered) return const SizedBox();
              return Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.label,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Divider(color: Colors.white24, height: 32),
                    Expanded(
                      child: ListView.builder(
                        itemCount: dockableApps.length,
                        itemBuilder: (context, index) {
                          final app = dockableApps[index];
                          Widget appTile = ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(
                              Icons.aspect_ratio,
                              color: Colors.white70,
                            ),
                            title: Text(
                              app['name']!,
                              style: const TextStyle(color: Colors.white),
                            ),
                            subtitle: Text(
                              'Class: ${app['class']}',
                              style: const TextStyle(
                                color: Colors.white30,
                                fontSize: 12,
                              ),
                            ),
                            trailing: IconButton(
                              icon: const Icon(
                                Icons.input,
                                color: Colors.blueAccent,
                              ),
                              onPressed: () =>
                                  _dockWindow(app['class']!, context),
                            ),
                          );
                          return Draggable<String>(
                            data: app['class'],
                            feedback: Material(
                              color: Colors.transparent,
                              child: Container(
                                width: 250,
                                padding: const EdgeInsets.all(8),
                                color: Colors.blueGrey.shade900,
                                child: Text(
                                  'Docking ${app['name']}...',
                                  style: const TextStyle(color: Colors.white),
                                ),
                              ),
                            ),
                            childWhenDragging: Opacity(
                              opacity: 0.3,
                              child: appTile,
                            ),
                            child: appTile,
                          );
                        },
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
