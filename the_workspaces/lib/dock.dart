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

  // --- Optimization: Icon Cache & Theme State ---
  String _activeIconTheme = 'hicolor'; // Fallback default
  final Map<String, Map<String, dynamic>> _iconCache = {};

  @override
  void initState() {
    super.initState();
    _initializeAppData();
    _startWatchingCompositor();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _initializeAppData() async {
    await _detectSystemIconTheme();
    await _loadLinuxApps();
  }

  // --- Detect Active XDG Icon Theme ---
  Future<void> _detectSystemIconTheme() async {
    try {
      final gsettings = await Process.run('gsettings', [
        'get',
        'org.gnome.desktop.interface',
        'icon-theme',
      ]);
      if (gsettings.exitCode == 0) {
        String theme = gsettings.stdout.toString().replaceAll("'", "").trim();
        if (theme.isNotEmpty) {
          _activeIconTheme = theme;
          return;
        }
      }

      final gtkConf = File(
        '${Platform.environment['HOME']}/.config/gtk-3.0/settings.ini',
      );
      if (await gtkConf.exists()) {
        final lines = await gtkConf.readAsLines();
        for (var line in lines) {
          if (line.startsWith('gtk-icon-theme-name=')) {
            _activeIconTheme = line.split('=')[1].trim();
            return;
          }
        }
      }
    } catch (e) {
      // Silently fallback to 'hicolor' if detection fails
    }
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
    final home = Platform.environment['HOME'];

    List<Directory> appDirs = [
      Directory('/usr/share/applications'),
      Directory('$home/.local/share/applications'),
      Directory('/var/lib/flatpak/exports/share/applications'),
      Directory('$home/.local/share/flatpak/exports/share/applications'),
      Directory('/var/lib/snapd/desktop/applications'), // Added Snap back
    ];

    for (var dir in appDirs) {
      if (await dir.exists()) {
        await for (var entity in dir.list()) {
          if (entity.path.endsWith('.desktop')) {
            try {
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
            } catch (e) {
              // Gracefully skip unreadable or corrupted .desktop files
            }
          }
        }
      }
    }

    // Deduplicate apps
    final seen = <String>{};
    parsedApps.retainWhere((app) => seen.add(app.name));

    parsedApps.sort((a, b) => a.name.compareTo(b.name));
    setState(() => installedApps = parsedApps);
  }

  // --- XDG Compliant Icon Resolver ---
  Future<Map<String, dynamic>> _resolveIcon(String? iconName) async {
    if (iconName == null || iconName.isEmpty)
      return {'path': null, 'isSvg': false};

    // Return cached result immediately
    if (_iconCache.containsKey(iconName)) return _iconCache[iconName]!;

    // 1. Absolute Paths
    if (iconName.startsWith('/')) {
      if (File(iconName).existsSync()) {
        final result = {
          'path': iconName,
          'isSvg': iconName.toLowerCase().endsWith('.svg'),
        };
        _iconCache[iconName] = result;
        return result;
      }
      return {'path': null, 'isSvg': false};
    }

    String baseName = iconName;
    if (baseName.endsWith('.png') ||
        baseName.endsWith('.svg') ||
        baseName.endsWith('.xpm')) {
      baseName = baseName.substring(0, baseName.lastIndexOf('.'));
    }

    final home = Platform.environment['HOME'];
    final List<String> extensions = ['.svg', '.png', '.xpm'];

    final List<String> targetThemes = [_activeIconTheme];
    if (_activeIconTheme != 'hicolor') targetThemes.add('hicolor');

    // Re-expanded bases to include Snap
    final List<String> bases = [
      '$home/.local/share/icons',
      '/usr/share/icons',
      '/var/lib/flatpak/exports/share/icons',
      '/snap/current/usr/share/icons',
    ];

    // Re-expanded sizes to catch high-res only apps (like Arduino/scrcpy)
    final List<String> sizes = [
      'scalable',
      '512x512',
      '256x256',
      '128x128',
      '96x96',
      '72x72',
      '64x64',
      '48x48',
      '32x32',
      '24x24',
      '22x22',
      '16x16',
    ];

    // Re-expanded categories to catch system tools (like Avahi)
    final List<String> categories = [
      'apps',
      'actions',
      'devices',
      'places',
      'status',
      'categories',
      'mimetypes',
      'panel',
    ];

    // 2. Search targeted XDG Themes
    for (var theme in targetThemes) {
      for (var base in bases) {
        for (var size in sizes) {
          for (var category in categories) {
            for (var ext in extensions) {
              String path = '$base/$theme/$size/$category/$baseName$ext';
              if (File(path).existsSync()) {
                final result = {'path': path, 'isSvg': ext == '.svg'};
                _iconCache[iconName] = result; // Cache it
                return result;
              }
            }
          }
        }
      }
    }

    // 3. Fallback: /usr/share/pixmaps (Legacy /opt/ apps)
    for (var ext in extensions) {
      String path = '/usr/share/pixmaps/$baseName$ext';
      if (File(path).existsSync()) {
        final result = {'path': path, 'isSvg': ext == '.svg'};
        _iconCache[iconName] = result;
        return result;
      }
    }

    // 4. Desperate Fallback: Check root of icon directories (rare, but happens)
    for (var base in bases) {
      for (var ext in extensions) {
        String path = '$base/$baseName$ext';
        if (File(path).existsSync()) {
          final result = {'path': path, 'isSvg': ext == '.svg'};
          _iconCache[iconName] = result;
          return result;
        }
      }
    }

    _iconCache[iconName] = {'path': null, 'isSvg': false};
    return _iconCache[iconName]!;
  }

  void _launchApp(String execCommand) {
    Process.start(
      'sh',
      ['-c', execCommand],
      environment: {
        'DISPLAY': '',
        'QT_QPA_PLATFORM': 'wayland',
        'GDK_BACKEND': 'wayland',
      },
      includeParentEnvironment: true,
    );
  }

  @override
  Widget build(BuildContext context) {
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
                            ),
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
                      } else if (index == activeWindows.length &&
                          activeWindows.isNotEmpty) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16.0),
                          child: VerticalDivider(
                            color: Colors.white24,
                            thickness: 2,
                          ),
                        );
                      } else {
                        int appIndex =
                            index -
                            activeWindows.length -
                            (activeWindows.isNotEmpty ? 1 : 0);
                        final app = installedApps[appIndex];

                        Widget fallbackText = Text(
                          app.name.substring(0, 1).toUpperCase(),
                          style: const TextStyle(
                            fontSize: 24,
                            color: Colors.white,
                          ),
                        );

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
                                      errorBuilder:
                                          (context, error, stackTrace) =>
                                              fallbackText,
                                    ))
                            : fallbackText;

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
