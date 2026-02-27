#!/bin/bash

# Path to your compiled Flutter HUD
FLUTTER_HUD="./build/linux/x64/release/bundle/the_workspaces"

# Launch the compositor, and tell it to run the Flutter HUD once it's ready
./compositor/tinywl -s "$FLUTTER_HUD"