![CppBox](assets/CppBox_banner.png)

**Portable C++ environment for Windows.**

![Version](https://img.shields.io/badge/version-v1.0.1-161616)
![Platform](https://img.shields.io/badge/platform-Windows-555555)
![Portable](https://img.shields.io/badge/environment-portable-777777)

[![Download CppBox v1.0.1](https://img.shields.io/badge/Download-CppBox%20v1.0.1-161616?style=for-the-badge)](https://github.com/squarequasar/cppbox/releases/latest)

## What is CppBox?

CppBox is a portable C++ environment for Windows. Its launcher downloads and keeps VS Code and the WinLibs compiler inside the CppBox folder, so they do not need to be installed system-wide. Your source files stay in a clean `workspace` folder.

## Quick Start

1. [Download CppBox v1.0.1](https://github.com/squarequasar/cppbox/releases/latest).
2. Extract the downloaded ZIP.
3. Run `CppBox_Setup_v1.0.1.exe`.
4. Follow the launcher. It creates a `cppbox` folder beside the setup file and a desktop shortcut.

On the first setup, CppBox needs an internet connection to download VS Code, the compiler, and Microsoft's C/C++ Extension Pack. The setup file removes itself after it finishes extracting CppBox. When VS Code asks whether you trust the workspace, choose **Trust**.

## What's Included

| Component | What it does |
| --- | --- |
| CppBox launcher | Shows installation progress, supports cancellation, can be moved, displays the version, and provides install, open-folder, and repair actions. |
| Visual Studio Code | Runs from the CppBox folder with separate user data. |
| WinLibs GCC and GDB | Compiles and debugs C++ programs without a system-wide compiler install. |
| Workspace | Keeps `.cpp` source files separate from internal files and build output. |
| C/C++ Extension Pack | Installed automatically by the setup flow into portable VS Code. |

## Requirements

- 64-bit Windows.
- Internet access during the initial environment setup.
- Enough free disk space for VS Code and the compiler. The exact amount depends on the downloaded versions; no fixed minimum is stated.

## Latest Release: CppBox v1.0.1

CppBox v1.0.1 adds actual download progress with cancellation, a movable launcher that displays its version, and automatic installation of Microsoft's C/C++ Extension Pack.

See the [v1.0.1 release notes](docs/RELEASE_NOTES_v1.0.1.md) or [download the latest release](https://github.com/squarequasar/cppbox/releases/latest).

Previous release: [CppBox v1.0.0](https://github.com/squarequasar/cppbox/releases/tag/v1.0.0).

## Developer Information

- [Development log](docs/DEVLOG.txt)
- [Build notes](docs/BUILD_NOTES.txt)
- Source: `src/`

made by squarequasar
