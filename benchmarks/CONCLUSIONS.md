# Benchmark conclusions

- Use PowerShell as the harness for process-start benchmarks instead of C because starting a process in PowerShell only adds ~0.05 ms overhead on this machine.
- Invoke the actual Git executable by absolute path for latency-sensitive calls because bypassing the Git for Windows wrapper saved ~7.4 ms in both mean and median launch-through-exit time across 20 alternating batch pairs of `git --exec-path` on this machine.

## Quick reference

Fastest observed on this machine with warm caches:

- Start a process (launch call returns) — ~1.3 ms.
- Start pwsh without profiles (reach its first command) — ~145 ms.
- Run `git --version` (launch through exit) — ~21.6 ms.
- Run `git --exec-path` through the wrapper (launch through exit) — ~21.2 ms; invoke actual Git directly — ~14.2 ms.
- Launch actual Git (launch call returns, before readiness is guaranteed) — ~1.2 ms.
- List local Git branches (launch through exit) — ~23.8 ms.
- Get the current Git branch name (launch through exit) — ~23.1 ms.
