# CppBox v1.0.2

Fixes the F5 build-and-debug configuration for the active C++ file.

## Download

[Download CppBox v1.0.2](https://github.com/squarequasar/cppbox/releases/download/v1.0.2/CppBox_Setup_v1.0.2.exe)

## What's Changed

- Runs the compiler directly instead of using a shell command chain.
- Adds debug information and disables optimization for debugging.
- Uses matching build output paths for compilation and GDB.
- Passes the compiler's library path to build and debug processes.
- Displays v1.0.2 in the launcher.

Installation progress, cancellation, the portable environment, and clean workspace behavior are retained from v1.0.1.

## Quick Start

1. Download and run `CppBox_Setup_v1.0.2.exe` where you want CppBox to be stored.
2. Open the CppBox desktop shortcut and install the environment through the launcher.
3. Open VS Code and trust the workspace when prompted.
4. Ensure Microsoft's C/C++ Extension Pack is installed; install it from Extensions if it is missing.
5. Save your `.cpp` file in `workspace` and press F5 to build and debug it.

Internet access is required during initial setup. The setup file removes itself after extracting CppBox.

made by squarequasar
