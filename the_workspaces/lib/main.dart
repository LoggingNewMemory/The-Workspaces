import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import 'left_right_side.dart';
import 'dock.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  WindowOptions windowOptions = const WindowOptions(
    size: Size(1920, 1080),
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
        backgroundColor: Colors.transparent,
        body: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E2E).withOpacity(0.5),
            image: systemWallpaperPath != null
                ? DecorationImage(
                    image: FileImage(File(systemWallpaperPath!)),
                    fit: BoxFit.cover,
                  )
                : null,
          ),
          child: const Stack(
            children: [
              SidePanel(
                alignment: Alignment.centerLeft,
                label: 'DOCK ACTIVE WINDOWS',
              ),
              SidePanel(
                alignment: Alignment.centerRight,
                label: 'DOCK ACTIVE WINDOWS',
              ),
              DockPanel(),
            ],
          ),
        ),
      ),
    );
  }
}
