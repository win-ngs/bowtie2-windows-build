$ErrorActionPreference = 'Stop'

$ScriptArgs = [string[]]@($args)
$PatchSourceDir = Join-Path $PSScriptRoot 'bowtie2-2.5.5-80e1011-patch'
$SourceDir = if (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'bowtie2-inspect-s.exe')) {
    $PSScriptRoot
} else {
    $PatchSourceDir
}

function Write-Fail {
    param([string]$Message)
    [Console]::Error.WriteLine("(ERR): $Message")
    exit 1
}

function ConvertTo-NativeArgument {
    param([string]$Argument)

    if ($null -eq $Argument -or $Argument.Length -eq 0) {
        return '""'
    }
    if ($Argument -notmatch '[\s"]') {
        return $Argument
    }

    $result = New-Object System.Text.StringBuilder
    [void]$result.Append('"')
    $backslashes = 0
    foreach ($ch in $Argument.ToCharArray()) {
        if ($ch -eq '\') {
            $backslashes++
        } elseif ($ch -eq '"') {
            if ($backslashes -gt 0) {
                [void]$result.Append(('\' * ($backslashes * 2 + 1)))
                $backslashes = 0
            } else {
                [void]$result.Append('\')
            }
            [void]$result.Append('"')
        } else {
            if ($backslashes -gt 0) {
                [void]$result.Append(('\' * $backslashes))
                $backslashes = 0
            }
            [void]$result.Append($ch)
        }
    }
    if ($backslashes -gt 0) {
        [void]$result.Append(('\' * ($backslashes * 2)))
    }
    [void]$result.Append('"')
    return $result.ToString()
}

function Join-NativeArguments {
    param([string[]]$Arguments)

    $quoted = foreach ($arg in $Arguments) {
        ConvertTo-NativeArgument $arg
    }
    return ($quoted -join ' ')
}

function Invoke-Native {
    param(
        [string]$FilePath,
        [string[]]$Arguments
    )

    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $FilePath
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.Arguments = Join-NativeArguments $Arguments

    $proc = [System.Diagnostics.Process]::Start($psi)
    $stdoutTask = $proc.StandardOutput.BaseStream.CopyToAsync([Console]::OpenStandardOutput())
    $stderrTask = $proc.StandardError.BaseStream.CopyToAsync([Console]::OpenStandardError())
    $proc.WaitForExit()
    $stdoutTask.GetAwaiter().GetResult()
    $stderrTask.GetAwaiter().GetResult()
    return $proc.ExitCode
}

$largeIndex = $false
$verbose = $false
$debug = $false
$sanitized = $false
$remaining = New-Object System.Collections.Generic.List[string]

for ($i = 0; $i -lt $ScriptArgs.Count; $i++) {
    switch ($ScriptArgs[$i]) {
        '--large-index' { $largeIndex = $true; continue }
        '--verbose' {
            $verbose = $true
            $remaining.Add($ScriptArgs[$i])
            continue
        }
        '--debug' { $debug = $true; continue }
        '--sanitized' { $sanitized = $true; continue }
        default { $remaining.Add($ScriptArgs[$i]) }
    }
}

if ($debug -and $sanitized) {
    Write-Fail '--debug and --sanitized are mutually exclusive.'
}

$suffix = ''
if ($debug) {
    $suffix = '-debug'
} elseif ($sanitized) {
    $suffix = '-sanitized'
}

$smallExe = Join-Path $SourceDir "bowtie2-inspect-s$suffix.exe"
$largeExe = Join-Path $SourceDir "bowtie2-inspect-l$suffix.exe"
$inspectExe = $smallExe

if ($largeIndex) {
    $inspectExe = $largeExe
} elseif ($remaining.Count -ge 1) {
    $idxBase = $remaining[$remaining.Count - 1]
    $largeExists = Test-Path -LiteralPath "$idxBase.1.bt2l"
    $smallExists = Test-Path -LiteralPath "$idxBase.1.bt2"
    if ($largeExists -and -not $smallExists) {
        $inspectExe = $largeExe
    }
}

if (-not (Test-Path -LiteralPath $inspectExe)) {
    Write-Fail "$(Split-Path $inspectExe -Leaf) does not exist; build Bowtie 2 first."
}

$nativeArgs = [string[]](@('--wrapper', 'basic-0') + $remaining.ToArray())
if ($verbose) {
    [Console]::Error.WriteLine("(INFO): Command: `"$inspectExe`" $($nativeArgs -join ' ')")
}

exit (Invoke-Native $inspectExe $nativeArgs)
