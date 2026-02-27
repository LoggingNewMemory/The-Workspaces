import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

// Import your new modular files
import 'left_right_side.dart';
import 'dock.dart';

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
  String? systemWallpaperPath;

  @override
  void initState() {
    super.initState();
    _fetchKdeWallpaper();
  }

  Future<void> _fetchKdeWallpaper() async {
    if (!Platform.isLinux) return;

    try {
      final home = Platform.environment['HOME'];
      final file = File(
        '$home/.config/plasma-org.kde.plasma.desktop-appletsrc',
      );

      if (await file.exists()) {
        final lines = await file.readAsLines();

        for (var line in lines.reversed) {
          line = line.trim();
          if (line.startsWith('Image=file://')) {
            setState(() {
              systemWallpaperPath = line.substring(13);
            });
            return;
          } else if (line.startsWith('Image=/')) {
            setState(() {
              systemWallpaperPath = line.substring(6);
            });
            return;
          }
        }
      }
    } catch (e) {
      debugPrint('Could not fetch KDE wallpaper: $e');
    }
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
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E2E),
            image: systemWallpaperPath != null
                ? DecorationImage(
                    image: FileImage(File(systemWallpaperPath!)),
                    fit: BoxFit.cover,
                  )
                : null,
          ),
          child: const Stack(
            children: [
              // LEFT ZONE
              SidePanel(
                alignment: Alignment.centerLeft,
                label: '[Workspaces / Apps]',
              ),

              // RIGHT ZONE
              SidePanel(
                alignment: Alignment.centerRight,
                label: '[Workspaces / Apps]',
              ),

              // TOP ZONE
              TopMusicNotificationPanel(),

              // BOTTOM ZONE (From dock.dart)
              DockPanel(),
            ],
          ),
        ),
      ),
    );
  }
}

// Extracted the Top Zone into its own local-state widget for consistency
class TopMusicNotificationPanel extends StatefulWidget {
  const TopMusicNotificationPanel({super.key});

  @override
  State<TopMusicNotificationPanel> createState() =>
      _TopMusicNotificationPanelState();
}

class _TopMusicNotificationPanelState extends State<TopMusicNotificationPanel> {
  bool isHovered = false;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: MouseRegion(
        onEnter: (_) => setState(() => isHovered = true),
        onExit: (_) => setState(() => isHovered = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutExpo,
          width: double.infinity,
          height: isHovered ? 250.0 : 20.0,
          decoration: BoxDecoration(
            color: isHovered ? Colors.black.withOpacity(0.85) : Colors.black45,
            border: isHovered
                ? const Border(bottom: BorderSide(color: Colors.white24))
                : const Border(),
          ),
          child: isHovered
              ? const Center(child: Text('[MUSIC & NOTIFICATIONS]'))
              : null,
        ),
      ),
    );
  }
}
