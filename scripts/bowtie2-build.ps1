$ErrorActionPreference = 'Stop'

$ScriptArgs = [string[]]@($args)
# The scripts directory is one level below the release root; executables must stay in that parent directory.
$SourceDir = Split-Path -Parent $PSScriptRoot

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

function Get-GzipUncompressedSize {
    param([string]$Path)

    $total = [int64]0
    $buffer = New-Object byte[] 8192
    $file = [System.IO.File]::OpenRead($Path)
    try {
        $gzip = [System.IO.Compression.GzipStream]::new($file, [System.IO.Compression.CompressionMode]::Decompress)
        try {
            while (($read = $gzip.Read($buffer, 0, $buffer.Length)) -gt 0) {
                $total += $read
            }
        } finally {
            $gzip.Dispose()
        }
    } finally {
        $file.Dispose()
    }
    return $total
}

function Test-SaisEnabled {
    param([string]$BuildExe)

    if (-not (Test-Path -LiteralPath $BuildExe)) {
        return $false
    }

    $output = & $BuildExe --version 2>$null
    return (($output -join "`n") -match 'USE_SAIS')
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

$smallExe = Join-Path $SourceDir "bowtie2-build-s$suffix.exe"
$largeExe = Join-Path $SourceDir "bowtie2-build-l$suffix.exe"
$buildExe = $smallExe

$delta = 200
$smallIndexMaxSize = [int64](4 * [math]::Pow(1024, 3) - $delta)
if (Test-SaisEnabled $smallExe) {
    $smallIndexMaxSize = [int64](2 * [math]::Pow(1024, 3) - $delta)
}

$argv = New-Object System.Collections.Generic.List[string]
foreach ($arg in $remaining) {
    $argv.Add($arg)
}

$fastas = New-Object System.Collections.Generic.List[string]
if (($argv -notcontains '-c') -and $argv.Count -ge 2) {
    for ($idx = $argv.Count - 2; $idx -ge 0; $idx--) {
        $arg = $argv[$idx]
        if ($arg.StartsWith('-') -or ($arg -match '^\d+$')) {
            break
        }
        $fastas.Insert(0, $arg)
        $argv.RemoveAt($idx)
    }

    if ($fastas.Count -gt 0) {
        $argv.Insert($argv.Count - 1, ($fastas -join ','))
    }
}

if ($largeIndex) {
    $buildExe = $largeExe
} elseif ($fastas.Count -gt 0) {
    $totalSize = [int64]0
    foreach ($fasta in $fastas) {
        if (Test-Path -LiteralPath $fasta) {
            if ($fasta.EndsWith('.gz', [System.StringComparison]::OrdinalIgnoreCase)) {
                $totalSize += Get-GzipUncompressedSize $fasta
            } elseif ($fasta.EndsWith('.zst', [System.StringComparison]::OrdinalIgnoreCase)) {
                [Console]::Error.WriteLine("$($MyInvocation.MyCommand.Name) cannot determine the uncompressed size of ZSTD compressed files. Ensure the uncompressed file size is suitable for the selected index.")
            } else {
                $totalSize += (Get-Item -LiteralPath $fasta).Length
            }
        }
    }

    if ($totalSize -gt $smallIndexMaxSize) {
        $buildExe = $largeExe
    }
}

if (-not (Test-Path -LiteralPath $buildExe)) {
    Write-Fail "$(Split-Path $buildExe -Leaf) does not exist; keep the .exe files next to the scripts directory."
}

$nativeArgs = [string[]](@('--wrapper', 'basic-0') + $argv.ToArray())
if ($verbose) {
    [Console]::Error.WriteLine("(INFO): Command: `"$buildExe`" $($nativeArgs -join ' ')")
}

exit (Invoke-Native $buildExe $nativeArgs)
