[CmdletBinding()]
param(
    [ValidateRange(1, 100000)]
    [int] $Iterations = 1000,

    [ValidateRange(1, 100000)]
    [int] $Warmups = 10,

    [string] $PwshPath = (Join-Path $PSHOME 'pwsh.exe')
)

$ErrorActionPreference = 'Stop'
if (-not $IsWindows) {
    throw 'This benchmark requires PowerShell 7 on Windows.'
}
$executable = (Get-Item -LiteralPath $PwshPath).FullName
$measurements = [System.Collections.Generic.List[double]]::new()
$warmupMeasurements = [System.Collections.Generic.List[double]]::new()
$workingDirectory = [Environment]::CurrentDirectory
$command = '$timestamp = [System.Diagnostics.Stopwatch]::GetTimestamp(); [Console]::WriteLine($timestamp); exit'

for ($iteration = 0; $iteration -lt ($Warmups + $Iterations); $iteration++) {
    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $executable
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.WorkingDirectory = $workingDirectory
    foreach ($argument in @('-NoLogo', '-NoProfile', '-NonInteractive', '-Command', $command)) {
        $startInfo.ArgumentList.Add($argument)
    }

    $child = [System.Diagnostics.Process]::new()
    $child.StartInfo = $startInfo
    try {
        $started = [System.Diagnostics.Stopwatch]::GetTimestamp()
        $launched = $child.Start()
        if (-not $launched) {
            throw 'Process.Start did not create a process.'
        }
        $outputTask = $child.StandardOutput.ReadToEndAsync()
        $errorTask = $child.StandardError.ReadToEndAsync()
        $child.WaitForExit()
        $outputText = $outputTask.GetAwaiter().GetResult()
        $errorText = $errorTask.GetAwaiter().GetResult()
        if ($child.ExitCode -ne 0) {
            throw "PowerShell exited with code $($child.ExitCode): $errorText"
        }

        $finished = [long]::Parse($outputText.Trim(), [System.Globalization.CultureInfo]::InvariantCulture)
        if ($finished -lt $started) {
            throw 'The child timestamp precedes the launch timestamp.'
        }
        $elapsed = ($finished - $started) * 1000.0 / [System.Diagnostics.Stopwatch]::Frequency
        if ($iteration -lt $Warmups) {
            $warmupMeasurements.Add($elapsed)
        }
        else {
            $measurements.Add($elapsed)
        }
    }
    finally {
        $child.Dispose()
    }
    if ($iteration + 1 -eq $Warmups) {
        Write-Verbose "Completed $Warmups warmup launches."
    }
    if ($measurements.Count -gt 0 -and ($measurements.Count % 100 -eq 0 -or $measurements.Count -eq $Iterations)) {
        Write-Verbose "Completed $($measurements.Count)/$Iterations measured launches."
    }
}

$sorted = @($measurements | Sort-Object)
$middle = [int] [math]::Floor($Iterations / 2)
$median = if ($Iterations % 2 -eq 0) {
    ($sorted[$middle - 1] + $sorted[$middle]) / 2
}
else {
    $sorted[$middle]
}
$mean = ($measurements | Measure-Object -Average).Average
$sumSquaredDeviation = 0.0
foreach ($measurement in $measurements) {
    $sumSquaredDeviation += ($measurement - $mean) * ($measurement - $mean)
}
$standardDeviation = if ($Iterations -gt 1) {
    [math]::Sqrt($sumSquaredDeviation / ($Iterations - 1))
}
else {
    $null
}

[pscustomobject]@{
    Benchmark = 'pwsh-startup'
    Metric = 'Parent timestamp immediately before Process.Start to the child timestamp in its first statement; output delivery and shutdown are excluded.'
    TimestampUtc = [DateTime]::UtcNow.ToString('o')
    MachineName = [Environment]::MachineName
    OS = [System.Runtime.InteropServices.RuntimeInformation]::OSDescription
    OSArchitecture = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()
    HarnessArchitecture = [System.Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture.ToString()
    HarnessPowerShellVersion = $PSVersionTable.PSVersion.ToString()
    HarnessDotNetVersion = [Environment]::Version.ToString()
    Executable = $executable
    ExecutableVersion = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($executable).ProductVersion
    Arguments = @('-NoLogo', '-NoProfile', '-NonInteractive', '-Command', $command)
    WorkingDirectory = $workingDirectory
    StopwatchFrequency = [System.Diagnostics.Stopwatch]::Frequency
    Iterations = $Iterations
    Warmups = $Warmups
    OutlierPolicy = 'Retain all measured samples.'
    FirstLaunchMs = $warmupMeasurements[0]
    MinimumMs = $sorted[0]
    MeanMs = $mean
    StandardDeviationMs = $standardDeviation
    MedianMs = $median
    P95Ms = $sorted[[int] [math]::Ceiling($Iterations * 0.95) - 1]
    P99Ms = $sorted[[int] [math]::Ceiling($Iterations * 0.99) - 1]
    MaximumMs = $sorted[-1]
    WarmupSamplesMs = $warmupMeasurements.ToArray()
    SamplesMs = $measurements.ToArray()
} | ConvertTo-Json -Depth 3
