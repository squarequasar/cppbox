#define UNICODE
#define _UNICODE

#include <windows.h>
#include <shellapi.h>
#include <wchar.h>

__attribute__((used)) static const wchar_t CPPBOX_BRAND[] =
    L"CppBox launcher made by squarequasar";

static void show_error(const wchar_t *message) {
    MessageBoxW(NULL, message, L"CppBox", MB_OK | MB_ICONERROR);
}

static int quote_arg(const wchar_t *input, wchar_t *output, size_t output_count) {
    size_t used = 0;
    if (used + 1 >= output_count) return 0;
    output[used++] = L'"';

    for (const wchar_t *p = input; *p; ++p) {
        if (*p == L'"') {
            if (used + 2 >= output_count) return 0;
            output[used++] = L'\\';
            output[used++] = L'"';
        } else {
            if (used + 1 >= output_count) return 0;
            output[used++] = *p;
        }
    }

    if (used + 2 >= output_count) return 0;
    output[used++] = L'"';
    output[used] = L'\0';
    return 1;
}

int WINAPI wWinMain(HINSTANCE instance, HINSTANCE previous, PWSTR command_line, int show_command) {
    (void)instance;
    (void)previous;
    (void)command_line;
    (void)show_command;
    (void)CPPBOX_BRAND;

    wchar_t exe_path[MAX_PATH];
    DWORD length = GetModuleFileNameW(NULL, exe_path, MAX_PATH);
    if (length == 0 || length >= MAX_PATH) {
        show_error(L"CppBox could not locate itself.");
        return 1;
    }

    wchar_t *last_slash = wcsrchr(exe_path, L'\\');
    if (!last_slash) {
        show_error(L"CppBox could not locate its folder.");
        return 1;
    }
    *last_slash = L'\0';

    wchar_t script_path[MAX_PATH];
    int script_ok = swprintf(
        script_path,
        MAX_PATH,
        L"%ls\\_cppbox_internal\\tools\\Launcher.ps1",
        exe_path
    );
    if (script_ok < 0 || script_ok >= MAX_PATH) {
        show_error(L"CppBox path is too long.");
        return 1;
    }

    DWORD attrs = GetFileAttributesW(script_path);
    if (attrs == INVALID_FILE_ATTRIBUTES || (attrs & FILE_ATTRIBUTE_DIRECTORY)) {
        show_error(L"CppBox internal launcher was not found.");
        return 1;
    }

    wchar_t quoted_script[MAX_PATH + 4];
    if (!quote_arg(script_path, quoted_script, sizeof(quoted_script) / sizeof(quoted_script[0]))) {
        show_error(L"CppBox could not prepare launcher path.");
        return 1;
    }

    wchar_t arguments[4096];
    int args_ok = swprintf(
        arguments,
        4096,
        L"-NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File %ls",
        quoted_script
    );
    if (args_ok < 0 || args_ok >= 4096) {
        show_error(L"CppBox launcher command is too long.");
        return 1;
    }

    SHELLEXECUTEINFOW exec_info;
    ZeroMemory(&exec_info, sizeof(exec_info));
    exec_info.cbSize = sizeof(exec_info);
    exec_info.fMask = SEE_MASK_NOCLOSEPROCESS;
    exec_info.hwnd = NULL;
    exec_info.lpVerb = L"open";
    exec_info.lpFile = L"powershell.exe";
    exec_info.lpParameters = arguments;
    exec_info.lpDirectory = exe_path;
    exec_info.nShow = SW_HIDE;

    if (!ShellExecuteExW(&exec_info)) {
        show_error(L"CppBox could not start PowerShell launcher.");
        return 1;
    }

    if (exec_info.hProcess) {
        CloseHandle(exec_info.hProcess);
    }

    return 0;
}
