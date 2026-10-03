![CppBox](assets/CppBox_banner.png)

**Portable C++ environment for Windows.**

![Version](https://img.shields.io/badge/version-v1.0.2-161616)
![Platform](https://img.shields.io/badge/platform-Windows-555555)
![Portable](https://img.shields.io/badge/environment-portable-777777)

[![Download CppBox v1.0.2](https://img.shields.io/badge/Download-CppBox%20v1.0.2-161616?style=for-the-badge)](https://github.com/squarequasar/cppbox/releases/tag/v1.0.2)

## What is CppBox?

CppBox is a portable C++ environment for Windows. Its launcher downloads and keeps VS Code and the WinLibs compiler inside the CppBox folder, so they do not need to be installed system-wide. Your source files stay in a clean `workspace` folder.

## Quick Start

1. [Download CppBox v1.0.2](https://github.com/squarequasar/cppbox/releases/tag/v1.0.2).
2. Run `CppBox_Setup_v1.0.2.exe` where you want the `cppbox` folder to be created.
3. Open CppBox using its desktop shortcut and install the environment through the launcher.
4. Open VS Code, trust the workspace when prompted, and write your code in `workspace`.

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

## Latest Release: CppBox v1.0.2

CppBox v1.0.2 fixes the F5 build-and-debug configuration for the active C++ file. Build output stays outside the workspace. The installation and launcher features from v1.0.1 are retained.

Previous release: [CppBox v1.0.1](https://github.com/squarequasar/cppbox/releases/tag/v1.0.1).

[Release notes](docs/RELEASE_NOTES_v1.0.2.md)

## Developer Information

- [Development log](docs/DEVLOG.txt)
- [Build notes](docs/BUILD_NOTES.txt)
- Source: `src/`

made by squarequasar
