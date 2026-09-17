# Benchmarks

Run these benchmarks from PowerShell 7 on Windows.

Record concise findings in [CONCLUSIONS.md](CONCLUSIONS.md), naming the measured environment and linking supporting JSON in `results/`. Update conclusions when further measurements change the evidence.

## PowerShell startup

Each startup script starts a fresh `pwsh.exe` using its absolute path with `-NoLogo -NoProfile -NonInteractive`, redirects output, and creates no new window.

```powershell
pwsh -NoProfile -File .\benchmarks\measure-pwsh-launch-to-exit.ps1
pwsh -NoProfile -File .\benchmarks\measure-pwsh-first-command.ps1
```

The launch-to-exit benchmark runs `exit` and measures from immediately before the parent starts the process until it observes termination.

The first-command benchmark records a timestamp as the child's first statement. It compares that timestamp with the parent's launch timestamp, excluding output delivery and shutdown. It includes the cost of resolving and invoking the timestamp call; it does not measure interactive prompt readiness.

Both run one initial launch, report it separately, then summarize 30 subsequent launches by default. These are warm-cache measurements; the initial launch is not guaranteed to be cold. Results are observed timings, not proven theoretical floors.

Use `-Iterations` to change the sample count or `-PwshPath` to select a different PowerShell executable:

```powershell
.\benchmarks\measure-pwsh-first-command.ps1 -Iterations 100 -PwshPath 'C:\Program Files\PowerShell\7\pwsh.exe'
```

Each script emits JSON containing machine and executable details, summary statistics, and all measured samples. Save results with output redirection:

```powershell
.\benchmarks\measure-pwsh-first-command.ps1 > first-command-results.json
```

Run one benchmark at a time. Child processes inherit the parent's environment and process working directory. Profiles are skipped, but normal PowerShell initialization, installed security software, and machine load still affect the measurements.

## PowerShell versus C process launch

`measure-process-start-overhead.ps1` compares PowerShell invoking `.NET Process.Start()` with an optimized C program invoking `CreateProcessW`. Both launch the same absolute PowerShell executable with `-NoLogo -NoProfile -NonInteractive -Command exit`, no new window, and no child-output redirection. They inherit their environment and use the same working directory.

The measured interval starts immediately before the launch call and ends immediately after it returns. Waiting for the child to exit, checking its exit code, and disposing handles happen outside that interval. Both launch calls return before command readiness is guaranteed. Child initialization can run concurrently with the launch call.

The PowerShell measurement includes script method dispatch and .NET launch preparation. The C command line and startup structures are prepared before its timer. C supplies a quoted absolute executable path in the command line with a null application-name argument, matching the .NET 10 launch path. This compares these two launch implementations, not only the languages or timer precision.

Build the C harness with CMake and Visual Studio's Desktop development with C++ workload (or equivalent Build Tools). For x64 PowerShell, run from the repository root:

```powershell
cmake -S benchmarks/native -B benchmarks/.build -A x64
cmake --build benchmarks/.build --config Release
pwsh -NoProfile -File benchmarks/measure-process-start-overhead.ps1
```

Use `-A ARM64` with Arm64 PowerShell. The harness architectures must match. Generated build files are ignored by Git.

By default, 20 batch pairs each collect 50 samples per harness after ten warmup launches per harness, for 1,000 measured launches per harness. Warmup samples are recorded separately and excluded from statistics. The order alternates between PowerShell-first and C-first pairs. Samples are collected sequentially; the startup of the C harness and its output collection are excluded from its internal measurements. A default run takes several minutes. Add `-Verbose` for progress on the verbose stream while JSON stays on the success stream.

```powershell
.\benchmarks\measure-process-start-overhead.ps1 -Verbose > process-start-results.json
```

`-PwshPath` selects the child executable and `-NativeHarnessPath` selects the compiled C harness. `-Iterations`, `-Batches`, and `-Warmups` override the sampling budget. JSON output includes machine/runtime/compiler details, raw warmup and measured samples for each pair, and pooled and per-batch summary statistics including mean, median, sample standard deviation, and p95. A positive PowerShell-minus-C difference means the PowerShell launch path took longer in that run.

The mean difference also has an approximate 95% percentile-bootstrap confidence interval, using 10,000 resamples of whole batch pairs and a recorded random seed. The resampling unit is a paired batch's mean difference, rather than treating every launch as independent. This interval assumes independent, representative batch pairs; persistent time trends or differences between the parents can invalidate that assumption. It describes uncertainty in the mean difference, not the range of individual launch times. With very few batch pairs, treat the interval as exploratory. The reported median difference is a separate statistic without a confidence interval.

The methodology draws on BenchmarkDotNet's [good practices](https://benchmarkdotnet.org/articles/guides/good-practices.html), [measurement stages](https://benchmarkdotnet.org/articles/guides/how-it-works.html), and [accuracy configuration](https://benchmarkdotnet.org/articles/configs/jobs.html): optimized builds without a debugger, separate warmup, repeated measurements, environment reporting, and explicit uncertainty. This is a custom harness, not a BenchmarkDotNet run. It uses a fixed sampling budget, not BenchmarkDotNet's adaptive warmup or error-based stopping. More samples do not certify convergence or remove systematic bias.

All measured samples, including slow outliers, remain in the statistics because scheduling and security-software delays are relevant to this workload. No overhead is subtracted: PowerShell dispatch and .NET launch preparation are part of what this comparison measures. The PowerShell harness stays alive across pairs; the C harness starts afresh for each pair and warms up before measurement. This run does not estimate variation across independent PowerShell harness launches.

For comparisons, use the same power conditions, avoid unrelated heavy workloads, and repeat on each target machine. Scheduling, inherited handles, cache state, and security software treating the two parent executables differently can affect the result. The difference cannot be directly subtracted from the separate startup benchmarks.

API references: [CreateProcessW](https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-createprocessw), [.NET 10 process launch implementation](https://github.com/dotnet/runtime/blob/v10.0.0/src/libraries/System.Diagnostics.Process/src/System/Diagnostics/Process.Windows.cs), and [Windows high-resolution timing](https://learn.microsoft.com/en-us/windows/win32/sysinfo/acquiring-high-resolution-time-stamps).
