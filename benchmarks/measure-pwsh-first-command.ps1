param(
    [ValidateRange(1, 100000)]
    [int] $Iterations = 30,

    [string] $PwshPath = (Join-Path $PSHOME 'pwsh.exe')
)

$ErrorActionPreference = 'Stop'
$executable = (Get-Item -LiteralPath $PwshPath).FullName
$measurements = [System.Collections.Generic.List[double]]::new()
$command = '$timestamp = [System.Diagnostics.Stopwatch]::GetTimestamp(); [Console]::WriteLine($timestamp); exit'

for ($iteration = 0; $iteration -le $Iterations; $iteration++) {
    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $executable
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    foreach ($argument in @('-NoLogo', '-NoProfile', '-NonInteractive', '-Command', $command)) {
        $startInfo.ArgumentList.Add($argument)
    }

    $child = [System.Diagnostics.Process]::new()
    $child.StartInfo = $startInfo
    try {
        $started = [System.Diagnostics.Stopwatch]::GetTimestamp()
        $null = $child.Start()
        $outputTask = $child.StandardOutput.ReadToEndAsync()
        $errorTask = $child.StandardError.ReadToEndAsync()
        $child.WaitForExit()
        $finished = [System.Diagnostics.Stopwatch]::GetTimestamp()
        $outputText = $outputTask.GetAwaiter().GetResult()
        $errorText = $errorTask.GetAwaiter().GetResult()
        if ($child.ExitCode -ne 0) {
            throw "PowerShell exited with code $($child.ExitCode): $errorText"
        }

        $finished = [long]::Parse($outputText.Trim(), [System.Globalization.CultureInfo]::InvariantCulture)

        $measurements.Add(($finished - $started) * 1000.0 / [System.Diagnostics.Stopwatch]::Frequency)
    }
    finally {
        $child.Dispose()
    }
}

$sorted = @($measurements | Select-Object -Skip 1 | Sort-Object)
$middle = [int] [math]::Floor($Iterations / 2)
$median = if ($Iterations % 2 -eq 0) {
    ($sorted[$middle - 1] + $sorted[$middle]) / 2
}
else {
    $sorted[$middle]
}

[pscustomobject]@{
    Benchmark = 'pwsh-first-command'
    TimestampUtc = [DateTime]::UtcNow.ToString('o')
    MachineName = [Environment]::MachineName
    OS = [System.Runtime.InteropServices.RuntimeInformation]::OSDescription
    OSArchitecture = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()
    HarnessArchitecture = [System.Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture.ToString()
    HarnessPowerShellVersion = $PSVersionTable.PSVersion.ToString()
    Executable = $executable
    ExecutableVersion = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($executable).ProductVersion
    Arguments = @('-NoLogo', '-NoProfile', '-NonInteractive', '-Command', $command)
    WorkingDirectory = [Environment]::CurrentDirectory
    StopwatchFrequency = [System.Diagnostics.Stopwatch]::Frequency
    Iterations = $Iterations
    FirstLaunchMs = $measurements[0]
    MinimumMs = $sorted[0]
    MedianMs = $median
    P95Ms = $sorted[[int] [math]::Ceiling($Iterations * 0.95) - 1]
    MaximumMs = $sorted[-1]
    SamplesMs = @($measurements | Select-Object -Skip 1)
} | ConvertTo-Json -Depth 3
