[CmdletBinding()]
param(
    [ValidateRange(1, 100000)]
    [int] $Iterations = 30,

    [string] $PwshPath = (Join-Path $PSHOME 'pwsh.exe')
)

& (Join-Path $PSScriptRoot 'measure-pwsh-startup.ps1') -Iterations $Iterations -Warmups 1 -PwshPath $PwshPath
