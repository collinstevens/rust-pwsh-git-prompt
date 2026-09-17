[CmdletBinding()]
param(
    [ValidateRange(1, 100000)]
    [int] $Iterations = 50,

    [ValidateRange(2, 100)]
    [int] $Batches = 20,

    [ValidateRange(1, 100000)]
    [int] $Warmups = 10,

    [string] $PwshPath = (Join-Path $PSHOME 'pwsh.exe'),

    [string] $NativeHarnessPath = (Join-Path $PSScriptRoot '.build/bin/process-start.exe')
)

$ErrorActionPreference = 'Stop'
if (-not $IsWindows) {
    throw 'This benchmark requires PowerShell 7 on Windows.'
}
if (-not (Test-Path -LiteralPath $NativeHarnessPath -PathType Leaf)) {
    throw 'Build the native harness first using the commands in benchmarks/README.md.'
}
$executable = (Get-Item -LiteralPath $PwshPath).FullName
$nativeHarness = (Get-Item -LiteralPath $NativeHarnessPath).FullName
$workingDirectory = [Environment]::CurrentDirectory
$childArguments = @('-NoLogo', '-NoProfile', '-NonInteractive', '-Command', 'exit')

function Measure-PowerShellBatch {
    $samples = [System.Collections.Generic.List[double]]::new()
    $warmupSamples = [System.Collections.Generic.List[double]]::new()
    for ($iteration = 0; $iteration -lt ($Warmups + $Iterations); $iteration++) {
        $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
        $startInfo.FileName = $executable
        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = $true
        $startInfo.WorkingDirectory = $workingDirectory
        foreach ($argument in $childArguments) {
            $startInfo.ArgumentList.Add($argument)
        }

        $child = [System.Diagnostics.Process]::new()
        $child.StartInfo = $startInfo
        try {
            $started = [System.Diagnostics.Stopwatch]::GetTimestamp()
            $launched = $child.Start()
            $finished = [System.Diagnostics.Stopwatch]::GetTimestamp()

            if (-not $launched) {
                throw 'Process.Start did not create a process.'
            }
            $child.WaitForExit()
            if ($child.ExitCode -ne 0) {
                throw "PowerShell child exited with code $($child.ExitCode)."
            }
            $elapsed = ($finished - $started) * 1000.0 / [System.Diagnostics.Stopwatch]::Frequency
            if ($iteration -lt $Warmups) {
                $warmupSamples.Add($elapsed)
            }
            else {
                $samples.Add($elapsed)
            }
        }
        finally {
            $child.Dispose()
        }
    }
    [pscustomobject]@{
        WarmupSamplesMs = $warmupSamples.ToArray()
        SamplesMs = $samples.ToArray()
    }
}

function Measure-NativeBatch {
    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $nativeHarness
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.WorkingDirectory = $workingDirectory
    foreach ($argument in @($executable, [string]$Iterations, [string]$Warmups)) {
        $startInfo.ArgumentList.Add($argument)
    }

    $runner = [System.Diagnostics.Process]::new()
    $runner.StartInfo = $startInfo
    try {
        $null = $runner.Start()
        $outputTask = $runner.StandardOutput.ReadToEndAsync()
        $errorTask = $runner.StandardError.ReadToEndAsync()
        $runner.WaitForExit()
        $outputText = $outputTask.GetAwaiter().GetResult()
        $errorText = $errorTask.GetAwaiter().GetResult()
        if ($runner.ExitCode -ne 0) {
            throw "Native harness exited with code $($runner.ExitCode): $errorText"
        }
        $result = $outputText | ConvertFrom-Json
        if ($result.Architecture -ne [System.Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture.ToString()) {
            throw 'Build the native harness for the same architecture as the PowerShell harness.'
        }
        if ($result.SamplesMs.Count -ne $Iterations -or $result.WarmupSamplesMs.Count -ne $Warmups) {
            throw 'Native harness returned an unexpected sample count.'
        }
        $result
    }
    finally {
        $runner.Dispose()
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
        MaximumMs = $sorted[-1]
    }
}

function Get-BatchDifferenceInterval {
    param([double[]] $Differences)

    $seed = 20260917
    $resamples = 10000
    $random = [System.Random]::new($seed)
    $bootstrapMeans = [double[]]::new($resamples)
    for ($resample = 0; $resample -lt $resamples; $resample++) {
        $sum = 0.0
        for ($index = 0; $index -lt $Differences.Count; $index++) {
            $sum += $Differences[$random.Next($Differences.Count)]
        }
        $bootstrapMeans[$resample] = $sum / $Differences.Count
    }
    [Array]::Sort($bootstrapMeans)
    [pscustomobject]@{
        Method = 'Paired-batch percentile bootstrap of the mean difference; assumes independent representative batch pairs.'
        ConfidenceLevel = 0.95
        Resamples = $resamples
        Seed = $seed
        BatchPairs = $Differences.Count
        EstimateMs = ($Differences | Measure-Object -Average).Average
        LowerMs = $bootstrapMeans[[int] [math]::Ceiling($resamples * 0.025) - 1]
        UpperMs = $bootstrapMeans[[int] [math]::Ceiling($resamples * 0.975) - 1]
        BatchDifferencesMs = $Differences
    }
}

$batchResults = [System.Collections.Generic.List[object]]::new()
for ($batch = 0; $batch -lt $Batches; $batch++) {
    if ($batch % 2 -eq 0) {
        $order = @('PowerShell', 'C')
        $powerShellResult = Measure-PowerShellBatch
        $nativeResult = Measure-NativeBatch
    }
    else {
        $order = @('C', 'PowerShell')
        $nativeResult = Measure-NativeBatch
        $powerShellResult = Measure-PowerShellBatch
    }
    $powerShellBatchSummary = Get-SampleSummary -Samples $powerShellResult.SamplesMs
    $nativeBatchSummary = Get-SampleSummary -Samples $nativeResult.SamplesMs
    $batchResults.Add([pscustomobject]@{
        Batch = $batch + 1
        Order = $order
        PowerShell = $powerShellResult
        C = $nativeResult
        PowerShellSummary = $powerShellBatchSummary
        CSummary = $nativeBatchSummary
        PowerShellMinusCMeanMs = $powerShellBatchSummary.MeanMs - $nativeBatchSummary.MeanMs
        PowerShellMinusCMedianMs = $powerShellBatchSummary.MedianMs - $nativeBatchSummary.MedianMs
    })
    Write-Verbose "Completed batch pair $($batch + 1)/$Batches ($Iterations measured launches per harness)."
}

$powerShellSummary = Get-SampleSummary -Samples @($batchResults | ForEach-Object { $_.PowerShell.SamplesMs })
$nativeSummary = Get-SampleSummary -Samples @($batchResults | ForEach-Object { $_.C.SamplesMs })
[pscustomobject]@{
    Benchmark = 'process-start-overhead'
    Metric = 'Elapsed time from before the launch call until it returns; waiting for exit is excluded.'
    TimestampUtc = [DateTime]::UtcNow.ToString('o')
    MachineName = [Environment]::MachineName
    OS = [System.Runtime.InteropServices.RuntimeInformation]::OSDescription
    OSArchitecture = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()
    HarnessArchitecture = [System.Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture.ToString()
    HarnessPowerShellVersion = $PSVersionTable.PSVersion.ToString()
    HarnessDotNetVersion = [Environment]::Version.ToString()
    NativeHarness = $nativeHarness
    NativeCompiler = $nativeResult.Compiler
    Executable = $executable
    ExecutableVersion = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($executable).ProductVersion
    Arguments = $childArguments
    WorkingDirectory = $workingDirectory
    StopwatchFrequency = [System.Diagnostics.Stopwatch]::Frequency
    IterationsPerBatch = $Iterations
    Batches = $Batches
    WarmupsPerBatch = $Warmups
    OutlierPolicy = 'Retain all measured samples.'
    PowerShell = $powerShellSummary
    C = $nativeSummary
    PowerShellMinusCMedianMs = $powerShellSummary.MedianMs - $nativeSummary.MedianMs
    PowerShellMinusCMeanInterval = Get-BatchDifferenceInterval -Differences $batchResults.PowerShellMinusCMeanMs
    BatchResults = $batchResults.ToArray()
} | ConvertTo-Json -Depth 8
