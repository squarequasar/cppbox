#define UNICODE
#define _UNICODE

#include <windows.h>
#include <shellapi.h>
#include <shlobj.h>
#include <shobjidl.h>
#include <stdio.h>
#include <wchar.h>

#include "payload.h"

__attribute__((used)) static const wchar_t CPPBOX_BRAND[] =
    L"CppBox setup made by squarequasar";

static void show_error(const wchar_t *message) {
    MessageBoxW(NULL, message, L"CppBox Setup", MB_OK | MB_ICONERROR);
}

static void show_info(const wchar_t *message) {
    MessageBoxW(NULL, message, L"CppBox Setup", MB_OK | MB_ICONINFORMATION);
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

static int get_exe_dir(wchar_t *dir, DWORD dir_count) {
    DWORD length = GetModuleFileNameW(NULL, dir, dir_count);
    if (length == 0 || length >= dir_count) return 0;
    wchar_t *last_slash = wcsrchr(dir, L'\\');
    if (!last_slash) return 0;
    *last_slash = L'\0';
    return 1;
}

static int write_payload_zip(const wchar_t *zip_path) {
    HANDLE file = CreateFileW(zip_path, GENERIC_WRITE, 0, NULL, CREATE_ALWAYS, FILE_ATTRIBUTE_TEMPORARY, NULL);
    if (file == INVALID_HANDLE_VALUE) return 0;

    DWORD written = 0;
    BOOL ok = WriteFile(file, CPPBOX_PAYLOAD, CPPBOX_PAYLOAD_SIZE, &written, NULL);
    CloseHandle(file);
    return ok && written == CPPBOX_PAYLOAD_SIZE;
}

static int run_powershell_wait(const wchar_t *working_dir, const wchar_t *command) {
    SHELLEXECUTEINFOW exec_info;
    ZeroMemory(&exec_info, sizeof(exec_info));
    exec_info.cbSize = sizeof(exec_info);
    exec_info.fMask = SEE_MASK_NOCLOSEPROCESS;
    exec_info.lpVerb = L"open";
    exec_info.lpFile = L"powershell.exe";
    exec_info.lpParameters = command;
    exec_info.lpDirectory = working_dir;
    exec_info.nShow = SW_HIDE;

    if (!ShellExecuteExW(&exec_info)) return 0;
    WaitForSingleObject(exec_info.hProcess, INFINITE);

    DWORD exit_code = 1;
    GetExitCodeProcess(exec_info.hProcess, &exit_code);
    CloseHandle(exec_info.hProcess);
    return exit_code == 0;
}

static void create_desktop_shortcut(const wchar_t *launcher_path) {
    wchar_t desktop_path[MAX_PATH];
    if (FAILED(SHGetFolderPathW(NULL, CSIDL_DESKTOPDIRECTORY, NULL, SHGFP_TYPE_CURRENT, desktop_path))) {
        return;
    }

    wchar_t shortcut_path[MAX_PATH];
    if (swprintf(shortcut_path, MAX_PATH, L"%ls\\CppBox.lnk", desktop_path) < 0) {
        return;
    }

    wchar_t work_dir[MAX_PATH];
    wcsncpy(work_dir, launcher_path, MAX_PATH - 1);
    work_dir[MAX_PATH - 1] = L'\0';
    wchar_t *last_slash = wcsrchr(work_dir, L'\\');
    if (last_slash) {
        *last_slash = L'\0';
    }

    HRESULT hr = CoInitialize(NULL);
    int did_initialize = SUCCEEDED(hr);
    if (FAILED(hr) && hr != RPC_E_CHANGED_MODE) {
        return;
    }

    IShellLinkW *shell_link = NULL;
    hr = CoCreateInstance(&CLSID_ShellLink, NULL, CLSCTX_INPROC_SERVER, &IID_IShellLinkW, (void **)&shell_link);
    if (SUCCEEDED(hr) && shell_link) {
        shell_link->lpVtbl->SetPath(shell_link, launcher_path);
        shell_link->lpVtbl->SetWorkingDirectory(shell_link, work_dir);
        shell_link->lpVtbl->SetIconLocation(shell_link, launcher_path, 0);
        shell_link->lpVtbl->SetDescription(shell_link, L"CppBox launcher");

        IPersistFile *persist_file = NULL;
        hr = shell_link->lpVtbl->QueryInterface(shell_link, &IID_IPersistFile, (void **)&persist_file);
        if (SUCCEEDED(hr) && persist_file) {
            persist_file->lpVtbl->Save(persist_file, shortcut_path, TRUE);
            persist_file->lpVtbl->Release(persist_file);
        }
        shell_link->lpVtbl->Release(shell_link);
    }

    if (did_initialize) {
        CoUninitialize();
    }
}

static void schedule_self_delete(void) {
    wchar_t self_path[MAX_PATH];
    DWORD length = GetModuleFileNameW(NULL, self_path, MAX_PATH);
    if (length == 0 || length >= MAX_PATH) {
        return;
    }

    wchar_t quoted_self[MAX_PATH + 4];
    if (!quote_arg(self_path, quoted_self, sizeof(quoted_self) / sizeof(quoted_self[0]))) {
        return;
    }

    wchar_t command[2048];
    int ok = swprintf(
        command,
        2048,
        L"/c ping 127.0.0.1 -n 3 > nul & del /f /q %ls",
        quoted_self
    );
    if (ok < 0 || ok >= 2048) {
        return;
    }

    ShellExecuteW(NULL, L"open", L"cmd.exe", command, NULL, SW_HIDE);
}

int WINAPI wWinMain(HINSTANCE instance, HINSTANCE previous, PWSTR command_line, int show_command) {
    (void)instance;
    (void)previous;
    (void)command_line;
    (void)show_command;
    (void)CPPBOX_BRAND;

    wchar_t exe_dir[MAX_PATH];
    if (!get_exe_dir(exe_dir, MAX_PATH)) {
        show_error(L"CppBox Setup could not locate its folder.");
        return 1;
    }

    wchar_t zip_path[MAX_PATH];
    if (swprintf(zip_path, MAX_PATH, L"%ls\\cppbox_payload.zip", exe_dir) < 0) {
        show_error(L"CppBox Setup path is too long.");
        return 1;
    }

    if (!write_payload_zip(zip_path)) {
        show_error(L"CppBox Setup could not write payload ZIP.");
        return 1;
    }

    wchar_t quoted_zip[MAX_PATH + 4];
    wchar_t quoted_dest[MAX_PATH + 4];
    if (!quote_arg(zip_path, quoted_zip, sizeof(quoted_zip) / sizeof(quoted_zip[0])) ||
        !quote_arg(exe_dir, quoted_dest, sizeof(quoted_dest) / sizeof(quoted_dest[0]))) {
        DeleteFileW(zip_path);
        show_error(L"CppBox Setup could not prepare extract paths.");
        return 1;
    }

    wchar_t ps_command[4096];
    int command_ok = swprintf(
        ps_command,
        4096,
        L"-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command \"Expand-Archive -LiteralPath %ls -DestinationPath %ls -Force\"",
        quoted_zip,
        quoted_dest
    );
    if (command_ok < 0 || command_ok >= 4096) {
        DeleteFileW(zip_path);
        show_error(L"CppBox Setup command is too long.");
        return 1;
    }

    if (!run_powershell_wait(exe_dir, ps_command)) {
        DeleteFileW(zip_path);
        show_error(L"CppBox Setup could not extract files.");
        return 1;
    }

    DeleteFileW(zip_path);

    wchar_t launcher_path[MAX_PATH];
    if (swprintf(launcher_path, MAX_PATH, L"%ls\\cppbox\\CppBox.exe", exe_dir) < 0) {
        show_info(L"CppBox was extracted.");
        return 0;
    }

    create_desktop_shortcut(launcher_path);
    ShellExecuteW(NULL, L"open", launcher_path, NULL, NULL, SW_SHOWNORMAL);
    schedule_self_delete();
    return 0;
}
