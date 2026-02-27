import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await windowManager.ensureInitialized();

  WindowOptions windowOptions = const WindowOptions(
    size: Size(1280, 720),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: true,
    titleBarStyle: TitleBarStyle.hidden,
    fullScreen: true,
  );

  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  runApp(const TheWorkspaceLauncher());
}

class TheWorkspaceLauncher extends StatelessWidget {
  const TheWorkspaceLauncher({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'The Workspace',
      theme: ThemeData.dark(),
      debugShowCheckedModeBanner: false,
      home: const WorkspaceDashboard(),
    );
  }
}

class WorkspaceDashboard extends StatefulWidget {
  const WorkspaceDashboard({super.key});

  @override
  State<WorkspaceDashboard> createState() => _WorkspaceDashboardState();
}

class _WorkspaceDashboardState extends State<WorkspaceDashboard> {
  String activeZone = '';
  String? systemWallpaperPath;

  @override
  void initState() {
    super.initState();
    _fetchKdeWallpaper();
  }

  // Parses the KDE Plasma configuration file to find the current active wallpaper
  Future<void> _fetchKdeWallpaper() async {
    if (!Platform.isLinux) return;

    try {
      final home = Platform.environment['HOME'];
      final file = File(
        '$home/.config/plasma-org.kde.plasma.desktop-appletsrc',
      );

      if (await file.exists()) {
        final lines = await file.readAsLines();

        // We read backwards because the active configuration is usually appended at the bottom
        for (var line in lines.reversed) {
          line = line.trim();
          if (line.startsWith('Image=file://')) {
            setState(() {
              systemWallpaperPath = line.substring(
                13,
              ); // Strips 'Image=file://'
            });
            return;
          } else if (line.startsWith('Image=/')) {
            setState(() {
              systemWallpaperPath = line.substring(6); // Strips 'Image='
            });
            return;
          }
        }
      }
    } catch (e) {
      debugPrint('Could not fetch KDE wallpaper: $e');
    }
  }

  Widget buildTriggerZone({
    required String zone,
    required Alignment alignment,
    required double restingWidth,
    required double restingHeight,
    required double expandedWidth,
    required double expandedHeight,
    required Widget child,
  }) {
    bool isActive = activeZone == zone;

    return Align(
      alignment: alignment,
      child: MouseRegion(
        onEnter: (_) => setState(() => activeZone = zone),
        onExit: (_) => setState(() => activeZone = ''),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutExpo,
          width: isActive ? expandedWidth : restingWidth,
          height: isActive ? expandedHeight : restingHeight,
          decoration: BoxDecoration(
            color: isActive ? Colors.black.withOpacity(0.85) : Colors.black45,
          ),
          child: isActive ? child : null,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          windowManager.close();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Scaffold(
        body: Container(
          // Set the background image to the system wallpaper, fallback to dark color
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E2E),
            image: systemWallpaperPath != null
                ? DecorationImage(
                    image: FileImage(File(systemWallpaperPath!)),
                    fit: BoxFit.cover,
                  )
                : null,
          ),
          child: Stack(
            children: [
              // LEFT ZONE
              buildTriggerZone(
                zone: 'L',
                alignment: Alignment.centerLeft,
                restingWidth: 20,
                restingHeight: double.infinity,
                expandedWidth: 400,
                expandedHeight: double.infinity,
                child: const Center(child: Text('[Workspaces / Apps]')),
              ),

              // RIGHT ZONE
              buildTriggerZone(
                zone: 'R',
                alignment: Alignment.centerRight,
                restingWidth: 20,
                restingHeight: double.infinity,
                expandedWidth: 400,
                expandedHeight: double.infinity,
                child: const Center(child: Text('[Workspaces / Apps]')),
              ),

              // TOP ZONE
              buildTriggerZone(
                zone: 'U',
                alignment: Alignment.topCenter,
                restingWidth: double.infinity,
                restingHeight: 20,
                expandedWidth: double.infinity,
                expandedHeight: 250,
                child: const Center(child: Text('[MUSIC & NOTIFICATIONS]')),
              ),

              // BOTTOM ZONE
              buildTriggerZone(
                zone: 'D',
                alignment: Alignment.bottomCenter,
                restingWidth: 600,
                restingHeight: 20,
                expandedWidth: 800,
                expandedHeight: 120,
                child: const Center(child: Text('[MACOS DOCK]')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
