import 'dart:io';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'app_info.dart';

class DockPanel extends StatefulWidget {
  const DockPanel({super.key});

  @override
  State<DockPanel> createState() => _DockPanelState();
}

class _DockPanelState extends State<DockPanel> {
  bool isHovered = false;
  List<AppInfo> installedApps = [];

  @override
  void initState() {
    super.initState();
    _loadLinuxApps();
  }

  // Parses Linux .desktop files
  Future<void> _loadLinuxApps() async {
    List<AppInfo> parsedApps = [];
    final systemApps = Directory('/usr/share/applications');
    final userApps = Directory(
      '${Platform.environment['HOME']}/.local/share/applications',
    );

    final directories = [systemApps, userApps];

    for (var dir in directories) {
      if (await dir.exists()) {
        await for (var entity in dir.list()) {
          if (entity.path.endsWith('.desktop')) {
            final lines = await File(entity.path).readAsLines();

            String? name;
            String? exec;
            bool noDisplay = false;

            for (var line in lines) {
              if (line.startsWith('NoDisplay=true')) noDisplay = true;
              if (line.startsWith('Name=') && name == null)
                name = line.substring(5);
              if (line.startsWith('Exec=') && exec == null)
                exec = line.substring(5);
            }

            if (!noDisplay && name != null && exec != null) {
              // Clean up the exec command (remove %U, %F, etc.)
              exec = exec.replaceAll(RegExp(r'%[a-zA-Z]'), '').trim();
              parsedApps.add(AppInfo(name: name, exec: exec));
            }
          }
        }
      }
    }

    // Sort alphabetically and update UI
    parsedApps.sort((a, b) => a.name.compareTo(b.name));
    setState(() => installedApps = parsedApps);
  }

  void _launchApp(String execCommand) {
    // Execute the application natively
    Process.start('sh', ['-c', execCommand]);
    // Close the workspace launcher
    windowManager.close();
  }

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
          width: isHovered ? 1000.0 : 600.0, // Wider to fit the scrolling apps
          height: isHovered ? 120.0 : 20.0,
          decoration: BoxDecoration(
            color: isHovered ? Colors.black.withOpacity(0.85) : Colors.black45,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            border: isHovered
                ? const Border(top: BorderSide(color: Colors.white24))
                : const Border(),
          ),
          child: isHovered
              ? ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 20,
                  ),
                  itemCount: installedApps.length,
                  itemBuilder: (context, index) {
                    final app = installedApps[index];

                    Widget appIcon = Container(
                      width: 60,
                      height: 60,
                      margin: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        color: Colors.white12,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white30),
                      ),
                      child: Center(
                        child: Text(
                          app.name.substring(0, 1).toUpperCase(),
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    );

                    return GestureDetector(
                      onTap: () => _launchApp(app.exec),
                      child: Tooltip(
                        message: app.name,
                        // Make the icon Draggable!
                        child: Draggable<AppInfo>(
                          data: app,
                          feedback: Opacity(
                            opacity: 0.7,
                            child: appIcon,
                          ), // What you see while dragging
                          childWhenDragging: Opacity(
                            opacity: 0.3,
                            child: appIcon,
                          ),
                          child: appIcon,
                        ),
                      ),
                    );
                  },
                )
              : null,
        ),
      ),
    );
  }
}
