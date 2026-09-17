# Benchmark conclusions

- Use PowerShell as the harness for process-start benchmarks instead of C because starting a process in PowerShell only adds ~0.05 ms overhead on this machine.

## Quick reference

Fastest observed on this machine with warm caches:

- Start a process (launch call returns) — ~1.3 ms.
- Start pwsh without profiles (reach its first command) — ~145 ms.
