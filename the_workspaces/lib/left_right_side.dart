import 'dart:io';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'app_info.dart';

class SidePanel extends StatefulWidget {
  final Alignment alignment;
  final String label;

  const SidePanel({super.key, required this.alignment, required this.label});

  @override
  State<SidePanel> createState() => _SidePanelState();
}

class _SidePanelState extends State<SidePanel> {
  bool isHovered = false;

  // Stores the apps you drag and drop into this zone
  List<AppInfo> pinnedApps = [];

  void _launchApp(String execCommand) {
    Process.start('sh', ['-c', execCommand]);
    windowManager.close();
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
          width: isHovered ? 300.0 : 20.0,
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
          // Wrap the inner content in a DragTarget
          child: DragTarget<AppInfo>(
            onAcceptWithDetails: (details) {
              // When an app is dropped, add it to the pinned list
              if (!pinnedApps.any((app) => app.name == details.data.name)) {
                setState(() {
                  pinnedApps.add(details.data);
                });
              }
            },
            builder: (context, candidateData, rejectedData) {
              if (!isHovered) return const SizedBox();

              // If dragging an item over this zone, highlight it slightly
              final isTargeted = candidateData.isNotEmpty;

              return Container(
                color: isTargeted ? Colors.white10 : Colors.transparent,
                padding: const EdgeInsets.all(16),
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
                    const Divider(color: Colors.white24),
                    const SizedBox(height: 16),

                    if (pinnedApps.isEmpty)
                      const Expanded(
                        child: Center(
                          child: Text(
                            'Drag apps from the dock\nand drop them here.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white30),
                          ),
                        ),
                      ),

                    // Display the pinned apps
                    Expanded(
                      child: ListView.builder(
                        itemCount: pinnedApps.length,
                        itemBuilder: (context, index) {
                          final app = pinnedApps[index];
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: Colors.white12,
                              child: Text(app.name.substring(0, 1)),
                            ),
                            title: Text(
                              app.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: IconButton(
                              icon: const Icon(
                                Icons.close,
                                size: 16,
                                color: Colors.white30,
                              ),
                              onPressed: () =>
                                  setState(() => pinnedApps.removeAt(index)),
                            ),
                            onTap: () => _launchApp(app.exec),
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
