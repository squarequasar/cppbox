# CppBox v1.0.2 Native Wrappers

These sources are used by the v1.0.2 release. The native wrapper logic is unchanged from v1.0.0; the updated interface and setup logic are in [`Launcher.ps1`](../Launcher.ps1) and [`Setup-CppBox.ps1`](../Setup-CppBox.ps1).

- `CppBoxLauncher.c` starts the PowerShell launcher without a console window.
- `CppBoxSetup.c` extracts the application, creates its desktop shortcut, starts the launcher, and schedules removal of the setup executable.
- The `.rc` files embed the application icon.

`payload.h` is generated during packaging and is not tracked. See [build notes](../../docs/BUILD_NOTES.txt).
