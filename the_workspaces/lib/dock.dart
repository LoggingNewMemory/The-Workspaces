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

    for (var dir in [systemApps, userApps]) {
      if (await dir.exists()) {
        await for (var entity in dir.list()) {
          if (entity.path.endsWith('.desktop')) {
            final lines = await File(entity.path).readAsLines();
            String? name, exec, iconName;
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
              exec = exec.replaceAll(RegExp(r'%[a-zA-Z]'), '').trim();
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

  Future<Map<String, dynamic>> _resolveIcon(String? iconName) async {
    if (iconName == null || iconName.isEmpty)
      return {'path': null, 'isSvg': false};
    if (iconName.startsWith('/') && await File(iconName).exists()) {
      return {'path': iconName, 'isSvg': iconName.endsWith('.svg')};
    }

    List<String> paths = [
      '/usr/share/icons/breeze/apps/48/$iconName.svg',
      '/usr/share/icons/breeze/apps/128/$iconName.svg',
      '/usr/share/icons/hicolor/scalable/apps/$iconName.svg',
      '/usr/share/icons/hicolor/48x48/apps/$iconName.png',
      '/usr/share/pixmaps/$iconName.png',
      '/usr/share/pixmaps/$iconName.svg',
    ];

    for (String path in paths) {
      if (await File(path).exists())
        return {'path': path, 'isSvg': path.endsWith('.svg')};
    }
    return {'path': null, 'isSvg': false};
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
          width: isHovered ? 1200.0 : 600.0,
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
                    Widget iconWidget = app.iconPath != null
                        ? (app.isSvg
                              ? SvgPicture.file(
                                  File(app.iconPath!),
                                  width: 48,
                                  height: 48,
                                )
                              : Image.file(
                                  File(app.iconPath!),
                                  width: 48,
                                  height: 48,
                                ))
                        : Text(
                            app.name.substring(0, 1).toUpperCase(),
                            style: const TextStyle(
                              fontSize: 24,
                              color: Colors.white,
                            ),
                          );

                    return GestureDetector(
                      onTap: () {
                        Process.start(
                          'sh',
                          ['-c', app.exec],
                          environment: {
                            'DISPLAY':
                                '', // Cut off access to the host X11 server
                            'QT_QPA_PLATFORM':
                                'wayland', // Force Qt apps to use Wayland
                            'GDK_BACKEND':
                                'wayland', // Force GTK apps to use Wayland
                          },
                          includeParentEnvironment:
                              true, // Keep the WAYLAND_DISPLAY from tinywl!
                        );
                      },
                      child: Tooltip(
                        message: app.name,
                        child: Container(
                          width: 60,
                          height: 60,
                          margin: const EdgeInsets.symmetric(horizontal: 6),
                          child: Center(child: iconWidget),
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
