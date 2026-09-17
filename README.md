# rust-pwsh-git-prompt

An investigation and prototype of a fast replacement for posh-git and Starship, specifically for Windows 11+ and modern PowerShell (`pwsh`). Only `pwsh` is supported; legacy Windows PowerShell (`powershell.exe`) is not supported.

The motivation is observed prompt delays of roughly 500 ms to 2 seconds, especially on corporate machines with additional scanning and endpoint detection and response (EDR) software. The goal is to understand the minimum work required for prompt operations and reduce their latency.

Before implementing a replacement, we are investigating theoretical performance floors and how to measure them. The first use case is displaying the current directory's Git branch:

1. Obtain PowerShell's current filesystem location.
2. Determine whether that location belongs to a Git repository.
3. Read the current branch name.

The investigation will distinguish process startup, executable lookup, repository discovery, filesystem access, and in-memory work. Fresh reads and cached answers have different freshness guarantees and will be evaluated separately. Performance claims need measurements, including on machines with corporate security software.

Windows-specific APIs and optimizations are in scope; cross-platform support is not a goal. Despite the repository name, the implementation language and architecture are undecided. Rust, C, and C++ are candidates, with choices driven by evidence.

Work proceeds one small, reviewable step at a time, following [AGENTS.md](AGENTS.md).
