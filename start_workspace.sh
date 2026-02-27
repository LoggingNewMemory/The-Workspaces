#!/bin/bash

# 1. The exact, absolute path to your Flutter binary
FLUTTER_HUD="/home/yamada/CODE/The-Workspaces/the_workspaces/build/linux/x64/release/bundle/the_workspaces"

# 2. Force GTK to use Wayland globally
export GDK_BACKEND=wayland

# 3. Launch the compositor 
./compositor/tinywl -s "$FLUTTER_HUD"