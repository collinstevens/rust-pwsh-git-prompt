# Benchmark conclusions

- Use PowerShell as the harness for process-start benchmarks instead of C because starting a process in PowerShell only adds ~0.05 ms overhead on this machine.
- Listing local branches with `git --no-pager branch`, including process launch through exit, took ~25.5 ms median and ~28.5 ms p95 in this repository on this machine (1,000 measured launches after ten warmups; raw results in `results/git-branch.json`).

## Quick reference

Fastest observed on this machine with warm caches:

- Start a process (launch call returns) — ~1.3 ms.
- Start pwsh without profiles (reach its first command) — ~145 ms.
- List local Git branches (launch through exit) — ~23.8 ms.
