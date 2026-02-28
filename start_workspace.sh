#!/bin/bash

# 1. The exact, absolute path to your Flutter binary
FLUTTER_HUD="/home/yamada/CODE/The-Workspaces/the_workspaces/build/linux/x64/release/bundle/the_workspaces"

# 2. Force GTK to use Wayland globally
export GDK_BACKEND=wayland

# 3. Launch the compositor IN THE BACKGROUND
./compositor/tinywl -s "$FLUTTER_HUD" &
TINYWL_PID=$!

# 4. Wait for the wlroots window to initialize and gain focus
# (Increased slightly to 2 seconds to ensure the window is fully mapped before we send the command)
sleep 0.1

# 5. Tell KDE Plasma 6 to toggle fullscreen on the currently active window
if command -v qdbus6 &> /dev/null; then
    qdbus6 org.kde.kglobalaccel /component/kwin invokeShortcut "Window Fullscreen"
elif command -v qdbus &> /dev/null; then
    qdbus org.kde.kglobalaccel /component/kwin invokeShortcut "Window Fullscreen"
else
    echo "Warning: Neither qdbus6 nor qdbus found. Could not auto-fullscreen."
fi

# 6. Keep the script running until you close the workspace
wait $TINYWL_PID