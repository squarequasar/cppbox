# CppBox

CppBox is a portable C++ workspace for Windows.

It bundles a small launcher, an isolated VS Code setup flow, a C++ compiler setup flow, and a clean `workspace` folder for user code.

The goal is simple: download one setup file, run it, open CppBox, write C++.

![CppBox logo](assets/CppBox_clean_logo.png)

## Download

Use the release build from:

`release/CppBox_v1.0.0.zip`

Inside the zip:

`CppBox_Setup_v1.0.0.exe`

## Install

1. Download `CppBox_Setup_v1.0.0.exe`.
2. Run it on Windows.
3. It creates a `cppbox` folder next to itself.
4. It creates a `CppBox` desktop shortcut.
5. The setup file deletes itself after installation.

## First Launch

Open CppBox from the desktop shortcut or from:

`cppbox/CppBox.exe`

When VS Code asks whether you trust the workspace, click:

`Trust`

or:

`Доверять`

This is the normal VS Code workspace trust prompt.

## C++ Extension Pack

After first launch, install:

`C/C++ Extension Pack`

Publisher:

`Microsoft`

This gives VS Code proper C++ highlighting, IntelliSense, and a better editing experience.

## Where To Put Code

Put your `.cpp` files in:

`workspace`

Examples:

`hello.cpp`

`test.cpp`

`main.cpp`

## Running Code

Open the `.cpp` file you want to run and use the VS Code run button.

CppBox is configured so build artifacts do not clutter the visible workspace.

## Repair

If the environment breaks, open the CppBox launcher and press:

`Починить`

This resets the internal VS Code/compiler installation so CppBox can install itself again.

## Repository Structure

`src/Launcher.ps1` - graphical CppBox launcher.

`src/Setup-CppBox.ps1` - installer script for VS Code, compiler, and workspace config.

`src/launcher_src/` - small C wrappers used for the Windows launcher/setup executables.

`assets/` - CppBox logo and Windows icon.

`release/` - final v1.0.0 release artifact and SHA-256 files.

`docs/DEVLOG.txt` - full development log.

## Author

made by squarequasar
