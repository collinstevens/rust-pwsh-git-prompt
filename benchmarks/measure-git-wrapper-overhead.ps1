[CmdletBinding()]
param(
    [ValidateRange(1, 100000)]
    [int] $Iterations = 50,

    [ValidateRange(2, 100)]
    [int] $Batches = 20,

    [ValidateRange(1, 100000)]
    [int] $Warmups = 10,

    [string] $GitWrapperPath = (Get-Command git -CommandType Application | Select-Object -First 1).Source,

    [string] $GitPath,

    [string] $WorkingDirectory = (Get-Location).Path
)

$ErrorActionPreference = 'Stop'
if (-not $IsWindows) {
    throw 'This benchmark requires PowerShell 7 on Windows.'
}
$wrapper = (Get-Item -LiteralPath $GitWrapperPath).FullName
if (-not $GitPath) {
    $installationDirectory = Split-Path (Split-Path $wrapper -Parent) -Parent
    $candidates = @(
        foreach ($relativePath in @('mingw64/bin/git.exe', 'mingw32/bin/git.exe', 'clangarm64/bin/git.exe')) {
            $candidate = Join-Path $installationDirectory $relativePath
            if (Test-Path -LiteralPath $candidate -PathType Leaf) {
                $candidate
            }
        }
    )
    if ($candidates.Count -ne 1) {
        throw 'Cannot identify the actual Git executable beside the wrapper. Specify -GitWrapperPath and -GitPath from the same Git installation.'
    }
    $GitPath = $candidates[0]
}
$directGit = (Get-Item -LiteralPath $GitPath).FullName
if ($wrapper -eq $directGit) {
    throw 'The wrapper and actual Git executable must be different files.'
}
$directory = Get-Item -LiteralPath $WorkingDirectory
if ($directory -isnot [System.IO.DirectoryInfo]) {
    throw 'WorkingDirectory must be a filesystem directory.'
}
$workingDirectory = $directory.FullName
$childArguments = @('--exec-path')

function Invoke-GitMeasurement {
    param([string] $Executable, [string[]] $Arguments)

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $Executable
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.WorkingDirectory = $workingDirectory
    foreach ($argument in $Arguments) {
        $startInfo.ArgumentList.Add($argument)
    }

    $child = [System.Diagnostics.Process]::new()
    $child.StartInfo = $startInfo
    try {
        $started = [System.Diagnostics.Stopwatch]::GetTimestamp()
        $launched = $child.Start()
        $launchReturned = [System.Diagnostics.Stopwatch]::GetTimestamp()
        if (-not $launched) {
            throw 'Process.Start did not create a process.'
        }
        $outputTask = $child.StandardOutput.ReadToEndAsync()
        $errorTask = $child.StandardError.ReadToEndAsync()
        $child.WaitForExit()
        $finished = [System.Diagnostics.Stopwatch]::GetTimestamp()
        $outputText = $outputTask.GetAwaiter().GetResult()
        $errorText = $errorTask.GetAwaiter().GetResult()
        if ($child.ExitCode -ne 0) {
            throw "Git exited with code $($child.ExitCode): $errorText"
        }
        [pscustomobject]@{
            LaunchCallMs = ($launchReturned - $started) * 1000.0 / [System.Diagnostics.Stopwatch]::Frequency
            LaunchToExitMs = ($finished - $started) * 1000.0 / [System.Diagnostics.Stopwatch]::Frequency
            Output = $outputText.Trim()
        }
    }
    finally {
        $child.Dispose()
    }
}

$wrapperVersion = (Invoke-GitMeasurement -Executable $wrapper -Arguments @('--version')).Output
$directVersion = (Invoke-GitMeasurement -Executable $directGit -Arguments @('--version')).Output
if ($wrapperVersion -notlike 'git version *' -or $wrapperVersion -cne $directVersion) {
    throw 'The wrapper and actual Git executable must report the same Git version.'
}
$expectedExecPath = (Invoke-GitMeasurement -Executable $directGit -Arguments $childArguments).Output
if (-not $expectedExecPath) {
    throw 'The actual Git executable returned an empty exec path.'
}
if ((Invoke-GitMeasurement -Executable $wrapper -Arguments $childArguments).Output -cne $expectedExecPath) {
    throw 'The wrapper and actual Git executable must report the same exec path.'
}

function Measure-GitBatch {
    param([string] $Executable)

    $samples = [System.Collections.Generic.List[object]]::new()
    $warmupSamples = [System.Collections.Generic.List[object]]::new()
    for ($iteration = 0; $iteration -lt ($Warmups + $Iterations); $iteration++) {
        $measurement = Invoke-GitMeasurement -Executable $Executable -Arguments $childArguments
        if ($measurement.Output -cne $expectedExecPath) {
            throw "Git returned an unexpected exec path: $($measurement.Output)"
        }
        $sample = [pscustomobject]@{
            LaunchCallMs = $measurement.LaunchCallMs
            LaunchToExitMs = $measurement.LaunchToExitMs
        }
        if ($iteration -lt $Warmups) {
            $warmupSamples.Add($sample)
        }
        else {
            $samples.Add($sample)
        }
    }
    [pscustomobject]@{
        WarmupSamples = $warmupSamples.ToArray()
        Samples = $samples.ToArray()
    }
}

function Get-SampleSummary {
    param([double[]] $Samples)

    $sorted = @($Samples | Sort-Object)
    $middle = [int] [math]::Floor($sorted.Count / 2)
    $median = if ($sorted.Count % 2 -eq 0) {
        ($sorted[$middle - 1] + $sorted[$middle]) / 2
    }
    else {
        $sorted[$middle]
    }
    $mean = ($Samples | Measure-Object -Average).Average
    $sumSquaredDeviation = 0.0
    foreach ($sample in $Samples) {
        $sumSquaredDeviation += ($sample - $mean) * ($sample - $mean)
    }
    $standardDeviation = if ($Samples.Count -gt 1) {
        [math]::Sqrt($sumSquaredDeviation / ($Samples.Count - 1))
    }
    else {
        $null
    }
    [pscustomobject]@{
        Count = $sorted.Count
        MinimumMs = $sorted[0]
        MeanMs = $mean
        StandardDeviationMs = $standardDeviation
        MedianMs = $median
        P95Ms = $sorted[[int] [math]::Ceiling($sorted.Count * 0.95) - 1]
        P99Ms = $sorted[[int] [math]::Ceiling($sorted.Count * 0.99) - 1]
        MaximumMs = $sorted[-1]
    }
}

function Get-GitSummary {
    param([object[]] $Samples)

    [pscustomobject]@{
        LaunchCall = Get-SampleSummary -Samples $Samples.LaunchCallMs
        LaunchToExit = Get-SampleSummary -Samples $Samples.LaunchToExitMs
    }
}

$batchResults = [System.Collections.Generic.List[object]]::new()
for ($batch = 0; $batch -lt $Batches; $batch++) {
    if ($batch % 2 -eq 0) {
        $order = @('Wrapper', 'DirectGit')
        $wrapperResult = Measure-GitBatch -Executable $wrapper
        $directResult = Measure-GitBatch -Executable $directGit
    }
    else {
        $order = @('DirectGit', 'Wrapper')
        $directResult = Measure-GitBatch -Executable $directGit
        $wrapperResult = Measure-GitBatch -Executable $wrapper
    }
    $wrapperBatchSummary = Get-GitSummary -Samples $wrapperResult.Samples
    $directBatchSummary = Get-GitSummary -Samples $directResult.Samples
    $batchResults.Add([pscustomobject]@{
        Batch = $batch + 1
        Order = $order
        Wrapper = $wrapperResult
        DirectGit = $directResult
        WrapperSummary = $wrapperBatchSummary
        DirectGitSummary = $directBatchSummary
        WrapperMinusDirectGitMeanMs = $wrapperBatchSummary.LaunchToExit.MeanMs - $directBatchSummary.LaunchToExit.MeanMs
        WrapperMinusDirectGitMedianMs = $wrapperBatchSummary.LaunchToExit.MedianMs - $directBatchSummary.LaunchToExit.MedianMs
    })
    Write-Verbose "Completed batch pair $($batch + 1)/$Batches ($Iterations measured launches per executable)."
}

$wrapperSummary = Get-GitSummary -Samples @($batchResults | ForEach-Object { $_.Wrapper.Samples })
$directSummary = Get-GitSummary -Samples @($batchResults | ForEach-Object { $_.DirectGit.Samples })
[pscustomobject]@{
    Benchmark = 'git-wrapper-overhead'
    Metrics = [pscustomobject]@{
        LaunchCall = 'Parent timestamp immediately before Process.Start until it returns; child readiness and exit are not guaranteed.'
        LaunchToExit = 'Parent timestamp immediately before Process.Start until WaitForExit returns; includes startup, exec-path output, redirected output handling, and shutdown.'
        WrapperOverhead = 'Wrapper minus direct Git launch-through-exit time; includes the extra process and environment setup, not just wrapper CPU time.'
    }
    MinimumInterpretation = 'Fastest observed warm-cache samples, not proven absolute startup floors. Minima are not subtracted to estimate wrapper overhead.'
    TimestampUtc = [DateTime]::UtcNow.ToString('o')
    MachineName = [Environment]::MachineName
    OS = [System.Runtime.InteropServices.RuntimeInformation]::OSDescription
    OSArchitecture = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()
    HarnessArchitecture = [System.Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture.ToString()
    HarnessPowerShellVersion = $PSVersionTable.PSVersion.ToString()
    HarnessDotNetVersion = [Environment]::Version.ToString()
    WrapperExecutable = $wrapper
    DirectGitExecutable = $directGit
    GitVersion = $directVersion
    Arguments = $childArguments
    ExecPath = $expectedExecPath
    WorkingDirectory = $workingDirectory
    StopwatchFrequency = [System.Diagnostics.Stopwatch]::Frequency
    IterationsPerBatch = $Iterations
    Batches = $Batches
    WarmupsPerBatch = $Warmups
    Preflight = 'Each executable runs --version and --exec-path before warmup; their outputs must match.'
    OutlierPolicy = 'Retain all measured samples.'
    Wrapper = $wrapperSummary
    DirectGit = $directSummary
    WrapperMinusDirectGitMeanMs = $wrapperSummary.LaunchToExit.MeanMs - $directSummary.LaunchToExit.MeanMs
    WrapperMinusDirectGitMedianMs = $wrapperSummary.LaunchToExit.MedianMs - $directSummary.LaunchToExit.MedianMs
    BatchResults = $batchResults.ToArray()
} | ConvertTo-Json -Depth 8
