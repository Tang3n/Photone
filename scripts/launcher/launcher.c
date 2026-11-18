/* Photone.exe: starts Photone in the Windows build (bin/), in place of a .bat. It is the
   program itself, not a door to another one: Python's own library (python\python3xx.dll) is
   loaded into this process and run as `python -X utf8 -m photone <what was given>`, so the
   window, the task bar and the task manager all say Photone and show its icon, and no console
   opens. Built by scripts/launcher/build.sh (mingw); scripts/build_windows.py copies the
   built file, which is kept in the repository so that building needs no C compiler. */
#include <windows.h>
#include <shellapi.h>
#include <wchar.h>

static int fail(const wchar_t *what) {
    MessageBoxW(NULL, what, L"Photone", MB_ICONERROR);
    return 1;
}

int WINAPI wWinMain(HINSTANCE instance, HINSTANCE none, PWSTR line, int show) {
    wchar_t folder[32768], find[32768], library[32768];
    DWORD length = GetModuleFileNameW(NULL, folder, 32000);
    while (length > 0 && folder[length - 1] != L'\\') length--;
    folder[length] = 0;  /* where this file is, with its last backslash */

    /* Whichever Python 3 the build brought: python313.dll today (not python3.dll, the stub). */
    WIN32_FIND_DATAW found;
    swprintf(find, 32768, L"%lspython\\python3??.dll", folder);
    HANDLE search = FindFirstFileW(find, &found);
    if (search == INVALID_HANDLE_VALUE) return fail(L"The folder \"python\" that belongs beside Photone.exe is missing.");
    /* ("?" may stand for nothing, so the stub is found too: the longer name is the real one.) */
    while (wcslen(found.cFileName) <= wcslen(L"python3.dll"))
        if (!FindNextFileW(search, &found)) return fail(L"Python's library is missing from the folder \"python\".");
    FindClose(search);
    swprintf(library, 32768, L"%lspython\\%ls", folder, found.cFileName);
    HMODULE python = LoadLibraryExW(library, NULL, LOAD_WITH_ALTERED_SEARCH_PATH);
    if (!python) return fail(L"Python could not be loaded from the folder \"python\".");
    int (*run)(int, wchar_t **) = (int (*)(int, wchar_t **))(void *)GetProcAddress(python, "Py_Main");
    if (!run) return fail(L"This Python has no Py_Main.");

    int given;
    wchar_t **words = CommandLineToArgvW(GetCommandLineW(), &given);
    /* A worker process that Python's multiprocessing starts is this same file with Python's
       own arguments: those go through as they are. */
    int worker = 0;
    for (int i = 1; i < given; i++) worker |= !wcscmp(words[i], L"--multiprocessing-fork");
    wchar_t **all = calloc(given + 5, sizeof *all);
    int count = 0;
    all[count++] = words[0];
    if (!worker) {
        all[count++] = L"-X"; all[count++] = L"utf8";  /* files are read as UTF-8 everywhere */
        all[count++] = L"-m"; all[count++] = L"photone";
    }
    for (int i = 1; i < given; i++) all[count++] = words[i];
    return run(count, all);
}
