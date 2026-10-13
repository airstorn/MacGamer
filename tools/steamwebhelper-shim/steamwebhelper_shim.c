#include <windows.h>
#include <stdio.h>
#include <string.h>

static void append(wchar_t *dst, size_t cap, const wchar_t *src) {
    wcsncat(dst, src, cap - wcslen(dst) - 1);
}

int WINAPI wWinMain(HINSTANCE hi, HINSTANCE hp, LPWSTR cmd, int show) {
    (void)hi; (void)hp; (void)show;
    wchar_t module[MAX_PATH];
    GetModuleFileNameW(NULL, module, MAX_PATH);
    wchar_t *slash = wcsrchr(module, L'\\');
    if (!slash) return 1;
    *slash = 0;
    wchar_t realExe[MAX_PATH];
    _snwprintf(realExe, MAX_PATH, L"%s\\steamwebhelper.real.exe", module);

    wchar_t cmdline[32768];
    cmdline[0] = 0;
    append(cmdline, 32768, L"\"");
    append(cmdline, 32768, realExe);
    append(cmdline, 32768, L"\" ");
    if (cmd && cmd[0]) {
        append(cmdline, 32768, cmd);
        append(cmdline, 32768, L" ");
    }
    append(cmdline, 32768, L"--disable-gpu --single-process --disable-gpu-compositing");

    STARTUPINFOW si;
    PROCESS_INFORMATION pi;
    ZeroMemory(&si, sizeof(si));
    si.cb = sizeof(si);
    ZeroMemory(&pi, sizeof(pi));
    if (!CreateProcessW(realExe, cmdline, NULL, NULL, FALSE, 0, NULL, module, &si, &pi)) {
        return (int)GetLastError();
    }
    WaitForSingleObject(pi.hProcess, INFINITE);
    DWORD code = 0;
    GetExitCodeProcess(pi.hProcess, &code);
    CloseHandle(pi.hProcess);
    CloseHandle(pi.hThread);
    return (int)code;
}
