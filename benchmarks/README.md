# Benchmarks

Run these benchmarks from PowerShell 7 on Windows.

Record conclusions as actionable one-liners in [CONCLUSIONS.md](CONCLUSIONS.md): state what to do and briefly explain the measurement-based reason. For example: "Use PowerShell as the harness for process-start benchmarks instead of C because starting a process in PowerShell only adds ~0.05 ms overhead on this machine." A timing summary alone is not a conclusion. Put timing summaries in the quick reference and save supporting measurements and environment details locally in `results/`. Raw results are ignored by Git. Add a conclusion only when the evidence supports an action, and update it when further measurements change that recommendation.

## Git branch

```powershell
pwsh -NoProfile -File .\benchmarks\measure-git-branch.ps1 -Verbose
```

This runs `git --no-pager branch` in PowerShell's current filesystem location, measuring from immediately before `Process.Start()` until `WaitForExit()` returns. It includes process launch, Git initialization, repository discovery, listing local branches, redirected output, and shutdown. Output is drained asynchronously; terminal rendering and executable lookup are excluded. A failed Git command stops the benchmark.

The script records ten warmup launches separately, then measures 1,000 launches by default. JSON output includes executable and environment details, every sample, minimum, mean, median, sample standard deviation, p95, p99, and maximum. All measured samples are retained. These are warm-cache observations, with no overhead subtracted.

Use `-Iterations` and `-Warmups` to adjust sampling, `-GitPath` to select a Git executable, and `-WorkingDirectory` to select a repository or a directory within it:

```powershell
.\benchmarks\measure-git-branch.ps1 -WorkingDirectory 'C:\path\to\repo' -Iterations 100
New-Item -ItemType Directory -Path benchmarks/results -Force | Out-Null
.\benchmarks\measure-git-branch.ps1 > benchmarks/results/git-branch.json
```

This measures listing all local branches; timings depend on the repository, branch count, Git configuration, inherited environment, and machine load. Run one benchmark at a time.

## Current Git branch

```powershell
pwsh -NoProfile -File .\benchmarks\measure-git-current-branch.ps1 -Verbose
```

This runs `git --no-pager branch --show-current` to print the current branch name. It uses the same launch-through-exit timing, output capture, ten warmups, 1,000 measured launches, JSON statistics, and parameters as the Git branch benchmark above. A detached HEAD produces empty output and is still a successful command; running outside a repository stops the benchmark with Git's error.

```powershell
New-Item -ItemType Directory -Path benchmarks/results -Force | Out-Null
.\benchmarks\measure-git-current-branch.ps1 > benchmarks/results/git-current-branch.json
```

## Git launch through exit

```powershell
pwsh -NoProfile -File .\benchmarks\measure-git-launch-to-exit.ps1 -Verbose
```

This runs `git --version` as a minimal-command baseline, measuring from immediately before `Process.Start()` until `WaitForExit()` returns. The interval includes process launch, Git initialization, version output, redirected output handling, and shutdown; it does not isolate startup or measure when Git becomes ready. Executable lookup and terminal rendering are excluded. No repository is required.

It uses the same ten warmups, 1,000 measured launches, JSON statistics, and `-Iterations`, `-Warmups`, `-GitPath`, and `-WorkingDirectory` parameters as the Git branch benchmarks. Use this baseline to investigate how much of their elapsed time comes from running Git with minimal command work. Separate runs do not isolate the exact cost of branch lookup.

```powershell
New-Item -ItemType Directory -Path benchmarks/results -Force | Out-Null
.\benchmarks\measure-git-launch-to-exit.ps1 > benchmarks/results/git-launch-to-exit.json
```

## Git wrapper overhead

```powershell
pwsh -NoProfile -File .\benchmarks\measure-git-wrapper-overhead.ps1 -Verbose
```

This compares the Git for Windows wrapper (`cmd/git.exe`) with the actual Git executable (`mingw64/bin/git.exe` on x64) from the same installation. Both run `--exec-path`: a successful early exit during option parsing, before command dispatch, command-path setup, or repository discovery. It prints one path and exits. Unlike `--version`, it skips built-in command dispatch; unlike running Git without arguments, it avoids usage output and a failure exit. See the [Git option handler](https://github.com/git-for-windows/git/blob/v2.55.0.windows.3/git.c#L147-L185) and [wrapper documentation](https://gitforwindows.org/git-wrapper.html).

Each launch records two intervals from immediately before `Process.Start()`: **LaunchCall**, ending when that call returns, and **LaunchToExit**, ending when `WaitForExit()` returns. LaunchCall does not establish that Git is ready; for the wrapper, it only measures launching the wrapper process. LaunchToExit includes initialization, path output, redirected output handling, and shutdown. Use the launch-through-exit difference to estimate the wrapper's added elapsed cost, including its extra process and environment setup.

The default run alternates wrapper-first and direct-Git-first batch pairs: 20 pairs, each with ten warmups and 50 measured launches per executable, totaling 1,000 measured launches each. Processes run sequentially with the same parent environment, working directory, redirected output, and no new window. The wrapper can modify its child's environment as part of its normal behavior. Absolute executable paths are resolved before measurement. Preflight calls check that both executables report the same version and exec path; every measured call must succeed and return that path.

JSON contains both executable paths, Git and harness versions, machine details, all warmup and measured samples, pooled and per-batch summaries, and wrapper-minus-direct mean and median launch-through-exit differences. Summaries include minimum, mean, median, sample standard deviation, p95, p99, and maximum. All outliers are retained. Minimum times are the fastest observed with warm caches, not proven absolute startup floors. The difference between independent minima is not an estimate of wrapper overhead. No harness overhead is subtracted. Alternating order reduces order bias but does not eliminate scheduling, machine-load, or security-software effects.

`-GitWrapperPath` defaults to the Git application on `PATH`; it must be the wrapper. The actual executable is detected under the installation's `mingw64`, `mingw32`, or `clangarm64` directory. Use `-GitPath` for an explicit actual executable, and select both paths from the same installation. No repository is required. `-WorkingDirectory`, `-Iterations` (per batch), `-Batches`, and `-Warmups` (per batch) are configurable.

```powershell
New-Item -ItemType Directory -Path benchmarks/results -Force | Out-Null
.\benchmarks\measure-git-wrapper-overhead.ps1 > benchmarks/results/git-wrapper-overhead.json
.\benchmarks\measure-git-wrapper-overhead.ps1 -GitWrapperPath 'C:\Program Files\Git\cmd\git.exe' -GitPath 'C:\Program Files\Git\mingw64\bin\git.exe' -Iterations 25 -Batches 4
```

Run one benchmark at a time. This isolates the practical cost of the wrapper route for a minimal successful Git invocation; it does not measure readiness for a repository command or establish which invocation is fastest on every machine.

## PowerShell startup

Each startup script starts a fresh `pwsh.exe` using its absolute path with `-NoLogo -NoProfile -NonInteractive`, redirects output, and creates no new window.

```powershell
pwsh -NoProfile -File .\benchmarks\measure-pwsh-launch-to-exit.ps1
pwsh -NoProfile -File .\benchmarks\measure-pwsh-startup.ps1 -Verbose
```

The launch-to-exit benchmark runs `exit` and measures from immediately before the parent starts the process until it observes termination.

The startup benchmark records a timestamp as the child's first statement. It compares that timestamp with the parent's launch timestamp, excluding output delivery and shutdown. It includes the parent's launch preparation and the cost of resolving and invoking the child's timestamp call; it does not measure interactive prompt readiness. No launcher overhead is subtracted.

The startup benchmark records ten warmup launches separately, then measures 1,000 fresh processes by default. It retains all measured samples and reports minimum, mean, median, sample standard deviation, p95, and p99. Use `-Warmups` to adjust warmup. The launch-to-exit benchmark still uses one initial launch and 30 measured launches. `measure-pwsh-first-command.ps1` is a compatibility entry point to the startup benchmark with its original one-warmup, 30-sample defaults.

These are warm-cache measurements; even the initial launch is not guaranteed to be cold. The fixed sample count is not an adaptive convergence check. Results are observed timings, not proven theoretical floors.

Use `-Iterations` to change the sample count or `-PwshPath` to select a different PowerShell executable:

```powershell
.\benchmarks\measure-pwsh-startup.ps1 -Iterations 1000 -PwshPath 'C:\Program Files\PowerShell\7\pwsh.exe'
```

Each script emits JSON containing machine and executable details, summary statistics, and all measured samples. Save results with output redirection:

```powershell
New-Item -ItemType Directory -Path benchmarks/results -Force | Out-Null
.\benchmarks\measure-pwsh-startup.ps1 > benchmarks/results/pwsh-startup.json
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
New-Item -ItemType Directory -Path benchmarks/results -Force | Out-Null
.\benchmarks\measure-process-start-overhead.ps1 -Verbose > benchmarks/results/process-start.json
```

`-PwshPath` selects the child executable and `-NativeHarnessPath` selects the compiled C harness. `-Iterations`, `-Batches`, and `-Warmups` override the sampling budget. JSON output includes machine/runtime/compiler details, raw warmup and measured samples for each pair, and pooled and per-batch summary statistics including mean, median, sample standard deviation, and p95. A positive PowerShell-minus-C difference means the PowerShell launch path took longer in that run.

The mean difference also has an approximate 95% percentile-bootstrap confidence interval, using 10,000 resamples of whole batch pairs and a recorded random seed. The resampling unit is a paired batch's mean difference, rather than treating every launch as independent. This interval assumes independent, representative batch pairs; persistent time trends or differences between the parents can invalidate that assumption. It describes uncertainty in the mean difference, not the range of individual launch times. With very few batch pairs, treat the interval as exploratory. The reported median difference is a separate statistic without a confidence interval.

The methodology draws on BenchmarkDotNet's [good practices](https://benchmarkdotnet.org/articles/guides/good-practices.html), [measurement stages](https://benchmarkdotnet.org/articles/guides/how-it-works.html), and [accuracy configuration](https://benchmarkdotnet.org/articles/configs/jobs.html): optimized builds without a debugger, separate warmup, repeated measurements, environment reporting, and explicit uncertainty. This is a custom harness, not a BenchmarkDotNet run. It uses a fixed sampling budget, not BenchmarkDotNet's adaptive warmup or error-based stopping. More samples do not certify convergence or remove systematic bias.

All measured samples, including slow outliers, remain in the statistics because scheduling and security-software delays are relevant to this workload. No overhead is subtracted: PowerShell dispatch and .NET launch preparation are part of what this comparison measures. The PowerShell harness stays alive across pairs; the C harness starts afresh for each pair and warms up before measurement. This run does not estimate variation across independent PowerShell harness launches.

For comparisons, use the same power conditions, avoid unrelated heavy workloads, and repeat on each target machine. Scheduling, inherited handles, cache state, and security software treating the two parent executables differently can affect the result. The difference cannot be directly subtracted from the separate startup benchmarks.

API references: [CreateProcessW](https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-createprocessw), [.NET 10 process launch implementation](https://github.com/dotnet/runtime/blob/v10.0.0/src/libraries/System.Diagnostics.Process/src/System/Diagnostics/Process.Windows.cs), and [Windows high-resolution timing](https://learn.microsoft.com/en-us/windows/win32/sysinfo/acquiring-high-resolution-time-stamps).
