import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
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

  // IPC State for active windows
  List<Map<String, String>> activeWindows = [];
  Timer? _timer;

  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadLinuxApps();
    _startWatchingCompositor();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  // --- IPC: Watch the C Compositor for active windows ---
  void _startWatchingCompositor() {
    _timer = Timer.periodic(const Duration(milliseconds: 250), (_) async {
      try {
        final file = File('/tmp/workspace_state.json');
        if (await file.exists()) {
          final content = await file.readAsString();
          final decoded = jsonDecode(content);
          final List<dynamic> activeData = decoded['active'];

          List<Map<String, String>> newWindows = activeData
              .map(
                (e) => {
                  'id': e['id'].toString(),
                  'name': e['name'].toString(),
                  'title': e['title'].toString(),
                },
              )
              .toList();

          if (newWindows.toString() != activeWindows.toString()) {
            setState(() => activeWindows = newWindows);
          }
        }
      } catch (e) {
        // Suppress read errors
      }
    });
  }

  // --- Load Installed Apps ---
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

  void _launchApp(String execCommand) {
    Process.start(
      'sh',
      ['-c', execCommand],
      environment: {
        'DISPLAY': '', // Prevent escaping to host X11
        'QT_QPA_PLATFORM': 'wayland',
        'GDK_BACKEND': 'wayland',
      },
      includeParentEnvironment: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Calculate total items: Active Apps + Divider + Installed Apps
    int totalItems =
        installedApps.length +
        activeWindows.length +
        (activeWindows.isNotEmpty ? 1 : 0);

    return Align(
      alignment: Alignment.bottomCenter,
      child: MouseRegion(
        onEnter: (_) => setState(() => isHovered = true),
        onExit: (_) => setState(() => isHovered = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutExpo,
          width: isHovered ? MediaQuery.of(context).size.width * 0.9 : 600.0,
          height: isHovered ? 100.0 : 20.0,
          decoration: BoxDecoration(
            color: isHovered ? Colors.black.withOpacity(0.85) : Colors.black45,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: isHovered
                ? const Border(top: BorderSide(color: Colors.white24))
                : const Border(),
          ),
          child: isHovered
              ? Listener(
                  // Convert vertical mouse scroll to horizontal list scroll
                  onPointerSignal: (pointerSignal) {
                    if (pointerSignal is PointerScrollEvent) {
                      final offset =
                          _scrollController.offset +
                          pointerSignal.scrollDelta.dy;
                      _scrollController.jumpTo(
                        offset.clamp(
                          0.0,
                          _scrollController.position.maxScrollExtent,
                        ),
                      );
                    }
                  },
                  child: ListView.builder(
                    controller: _scrollController,
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 16,
                    ),
                    itemCount: totalItems,
                    itemBuilder: (context, index) {
                      // 1. Render Active Windows (Draggable)
                      if (index < activeWindows.length) {
                        final win = activeWindows[index];
                        Widget activeIcon = Container(
                          width: 60,
                          height: 60,
                          margin: const EdgeInsets.symmetric(horizontal: 6),
                          decoration: BoxDecoration(
                            color: Colors.blueAccent.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: Colors.blueAccent,
                              width: 2,
                            ), // Highlight active apps
                          ),
                          child: Center(
                            child: Text(
                              win['name']!.substring(0, 1).toUpperCase(),
                              style: const TextStyle(
                                fontSize: 24,
                                color: Colors.blueAccent,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        );

                        return Tooltip(
                          message: "Active: ${win['title']}",
                          // Relax the generic type to <Map> to guarantee the drop is accepted
                          child: Draggable<Map>(
                            data: win,
                            feedback: Opacity(opacity: 0.8, child: activeIcon),
                            childWhenDragging: Opacity(
                              opacity: 0.3,
                              child: activeIcon,
                            ),
                            child: activeIcon,
                          ),
                        );
                      }
                      // 2. Render Divider
                      else if (index == activeWindows.length &&
                          activeWindows.isNotEmpty) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16.0),
                          child: VerticalDivider(
                            color: Colors.white24,
                            thickness: 2,
                          ),
                        );
                      }
                      // 3. Render Installed Apps (Launchers)
                      else {
                        int appIndex =
                            index -
                            activeWindows.length -
                            (activeWindows.isNotEmpty ? 1 : 0);
                        final app = installedApps[appIndex];

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
                          onTap: () => _launchApp(app.exec),
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
                      }
                    },
                  ),
                )
              : null,
        ),
      ),
    );
  }
}
