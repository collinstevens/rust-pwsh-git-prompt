#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <wchar.h>

#if defined(_M_X64)
#define BENCHMARK_ARCHITECTURE "X64"
#elif defined(_M_ARM64)
#define BENCHMARK_ARCHITECTURE "Arm64"
#elif defined(_M_IX86)
#define BENCHMARK_ARCHITECTURE "X86"
#else
#error Unsupported architecture
#endif

static int parse_count(const wchar_t *text, int minimum)
{
    wchar_t *end = NULL;
    long value = wcstol(text, &end, 10);
    if (end == text || *end != L'\0' || value < minimum || value > 100000) {
        return -1;
    }
    return (int)value;
}

static void print_samples(const double *samples, int count)
{
    putchar('[');
    for (int index = 0; index < count; index++) {
        printf("%s%.9f", index == 0 ? "" : ",", samples[index]);
    }
    putchar(']');
}

int wmain(int argc, wchar_t **argv)
{
    if (argc != 4) {
        fputs("Usage: process-start.exe <pwsh-path> <iterations> <warmups>\n", stderr);
        return 1;
    }

    int iterations = parse_count(argv[2], 1);
    int warmups = parse_count(argv[3], 0);
    if (iterations < 0 || warmups < 0) {
        fputs("Invalid iteration or warmup count.\n", stderr);
        return 1;
    }

    wchar_t command_template[32768];
    if (swprintf_s(command_template, 32768,
                   L"\"%ls\" -NoLogo -NoProfile -NonInteractive -Command exit", argv[1]) < 0) {
        fputs("Command line is too long.\n", stderr);
        return 1;
    }

    int count = iterations + warmups;
    double *samples = calloc((size_t)count, sizeof(*samples));
    if (samples == NULL) {
        fputs("Could not allocate sample storage.\n", stderr);
        return 1;
    }

    LARGE_INTEGER frequency;
    QueryPerformanceFrequency(&frequency);

    for (int index = 0; index < count; index++) {
        wchar_t command[32768];
        wcscpy_s(command, 32768, command_template);
        STARTUPINFOW startup = {0};
        startup.cb = sizeof(startup);
        PROCESS_INFORMATION process = {0};
        LARGE_INTEGER started;
        LARGE_INTEGER finished;

        QueryPerformanceCounter(&started);
        BOOL launched = CreateProcessW(NULL, command, NULL, NULL, TRUE,
                                       CREATE_NO_WINDOW, NULL, NULL, &startup, &process);
        QueryPerformanceCounter(&finished);

        if (!launched) {
            fprintf(stderr, "CreateProcessW failed: %lu\n", GetLastError());
            free(samples);
            return 1;
        }

        DWORD wait_result = WaitForSingleObject(process.hProcess, INFINITE);
        DWORD exit_code = 0;
        BOOL exit_code_read = GetExitCodeProcess(process.hProcess, &exit_code);
        CloseHandle(process.hThread);
        CloseHandle(process.hProcess);
        if (wait_result != WAIT_OBJECT_0 || !exit_code_read || exit_code != 0) {
            fprintf(stderr, "Child did not exit successfully: wait=%lu, exit=%lu\n",
                    wait_result, exit_code);
            free(samples);
            return 1;
        }

        samples[index] = (finished.QuadPart - started.QuadPart) * 1000.0 / frequency.QuadPart;
    }

    printf("{\"Architecture\":\"%s\",\"Compiler\":\"MSVC %d\","
           "\"StopwatchFrequency\":%lld,\"WarmupSamplesMs\":",
           BENCHMARK_ARCHITECTURE, _MSC_FULL_VER, frequency.QuadPart);
    print_samples(samples, warmups);
    fputs(",\"SamplesMs\":", stdout);
    print_samples(samples + warmups, iterations);
    puts("}");
    free(samples);
    return 0;
}
