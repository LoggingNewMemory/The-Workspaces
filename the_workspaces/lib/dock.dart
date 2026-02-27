import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
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
            String? iconName;
            bool noDisplay = false;

            for (var line in lines) {
              if (line.startsWith('NoDisplay=true')) noDisplay = true;
              if (line.startsWith('Name=') && name == null)
                name = line.substring(5);
              if (line.startsWith('Exec=') && exec == null)
                exec = line.substring(5);
              if (line.startsWith('Icon=') && iconName == null)
                iconName = line.substring(5);
            }

            if (!noDisplay && name != null && exec != null) {
              // Clean up execution arguments
              exec = exec.replaceAll(RegExp(r'%[a-zA-Z]'), '').trim();

              // Resolve the icon
              final iconData = await _resolveIcon(iconName);

              parsedApps.add(
                AppInfo(
                  name: name,
                  exec: exec,
                  iconPath: iconData['path'],
                  isSvg: iconData['isSvg'] ?? false,
                ),
              );
            }
          }
        }
      }
    }

    parsedApps.sort((a, b) => a.name.compareTo(b.name));
    setState(() => installedApps = parsedApps);
  }

  // A robust icon resolver for KDE Plasma and Arch Linux
  Future<Map<String, dynamic>> _resolveIcon(String? iconName) async {
    if (iconName == null || iconName.isEmpty)
      return {'path': null, 'isSvg': false};

    // 1. Check if it's an absolute path already
    if (iconName.startsWith('/')) {
      if (await File(iconName).exists()) {
        return {'path': iconName, 'isSvg': iconName.endsWith('.svg')};
      }
    }

    // 2. Search common Linux & KDE icon directories
    // We prioritize SVGs (scalable) over PNGs for crispness
    List<String> searchPaths = [
      // KDE Breeze Theme (Standard on Plasma)
      '/usr/share/icons/breeze/apps/48/$iconName.svg',
      '/usr/share/icons/breeze/apps/128/$iconName.svg',
      // Standard Linux Hicolor Theme
      '/usr/share/icons/hicolor/scalable/apps/$iconName.svg',
      '/usr/share/icons/hicolor/48x48/apps/$iconName.png',
      '/usr/share/icons/hicolor/128x128/apps/$iconName.png',
      '/usr/share/icons/hicolor/256x256/apps/$iconName.png',
      // Pixmaps fallback
      '/usr/share/pixmaps/$iconName.png',
      '/usr/share/pixmaps/$iconName.svg',
    ];

    for (String path in searchPaths) {
      if (await File(path).exists()) {
        return {'path': path, 'isSvg': path.endsWith('.svg')};
      }
    }

    return {'path': null, 'isSvg': false};
  }

  void _launchApp(String execCommand) {
    // Launch natively. The HUD stays alive in the background!
    Process.start('sh', ['-c', execCommand]);
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
          width: isHovered ? 1200.0 : 600.0, // Expanded wide to fit icons
          height: isHovered ? 100.0 : 20.0,
          decoration: BoxDecoration(
            color: isHovered ? Colors.black.withOpacity(0.85) : Colors.black45,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: isHovered
                ? const Border(top: BorderSide(color: Colors.white24))
                : const Border(),
          ),
          child: isHovered
              ? ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 16,
                  ),
                  itemCount: installedApps.length,
                  itemBuilder: (context, index) {
                    final app = installedApps[index];

                    // Render the appropriate Icon
                    Widget iconWidget;
                    if (app.iconPath != null) {
                      if (app.isSvg) {
                        iconWidget = SvgPicture.file(
                          File(app.iconPath!),
                          width: 48,
                          height: 48,
                        );
                      } else {
                        iconWidget = Image.file(
                          File(app.iconPath!),
                          width: 48,
                          height: 48,
                        );
                      }
                    } else {
                      iconWidget = Text(
                        app.name.substring(0, 1).toUpperCase(),
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      );
                    }

                    Widget appContainer = Container(
                      width: 60,
                      height: 60,
                      margin: const EdgeInsets.symmetric(horizontal: 6),
                      decoration: BoxDecoration(
                        color: app.iconPath != null
                            ? Colors.transparent
                            : Colors.white12,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Center(child: iconWidget),
                    );

                    return GestureDetector(
                      onTap: () => _launchApp(app.exec),
                      child: Tooltip(
                        message: app.name,
                        child: Draggable<AppInfo>(
                          data: app,
                          feedback: Opacity(opacity: 0.8, child: appContainer),
                          childWhenDragging: Opacity(
                            opacity: 0.3,
                            child: appContainer,
                          ),
                          child: appContainer,
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
