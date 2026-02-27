import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter/services.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize the window manager
  await windowManager.ensureInitialized();

  WindowOptions windowOptions = const WindowOptions(
    size: Size(1280, 720),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: true, // Hides it from your normal DE taskbar
    titleBarStyle: TitleBarStyle.hidden, // Removes the top bar
    fullScreen: true, // Takes over the monitor like an Android Launcher
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
            color: isActive ? Colors.black.withOpacity(0.9) : Colors.black45,
          ),
          child: isActive ? child : null,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Focus node catches keyboard inputs for the entire screen
    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        // Check if the key is pressed down and is the Escape key
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          windowManager.close();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF1E1E2E),
        body: Stack(
          children: [
            // CENTER
            const Center(
              child: Text(
                'MAIN LAUNCHER DASHBOARD\n(Escape to exit now works!)',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 24, color: Colors.white54),
              ),
            ),

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
    );
  }
}
