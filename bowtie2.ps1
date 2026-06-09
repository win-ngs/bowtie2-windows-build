$ErrorActionPreference = 'Stop'

$ScriptArgs = [string[]]@($args)
$PatchSourceDir = Join-Path $PSScriptRoot 'bowtie2-2.5.5-80e1011-patch'
$SourceDir = if (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'bowtie2-align-s.exe')) {
    $PSScriptRoot
} else {
    $PatchSourceDir
}

function Write-Fail {
    param([string]$Message)
    [Console]::Error.WriteLine("(ERR): $Message")
    exit 1
}

function Write-Info {
    param(
        [bool]$Enabled,
        [string]$Message
    )
    if ($Enabled) {
        [Console]::Error.WriteLine("(INFO): $Message")
    }
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
        [string[]]$Arguments,
        [string]$StderrPath,
        [switch]$StdoutToStderr
    )

    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $FilePath
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.Arguments = Join-NativeArguments $Arguments

    $proc = [System.Diagnostics.Process]::Start($psi)
    $stdoutStream = if ($StdoutToStderr) {
        [Console]::OpenStandardError()
    } else {
        [Console]::OpenStandardOutput()
    }
    $stdoutTask = $proc.StandardOutput.BaseStream.CopyToAsync($stdoutStream)

    $stderrStream = $null
    try {
        if ([string]::IsNullOrEmpty($StderrPath)) {
            $stderrStream = [Console]::OpenStandardError()
        } else {
            $stderrStream = [System.IO.File]::Open($StderrPath, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write)
        }

        $stderrTask = $proc.StandardError.BaseStream.CopyToAsync($stderrStream)
        $proc.WaitForExit()
        $stdoutTask.GetAwaiter().GetResult()
        $stderrTask.GetAwaiter().GetResult()
    } finally {
        if ($stderrStream -and -not [string]::IsNullOrEmpty($StderrPath)) {
            $stderrStream.Dispose()
        }
    }

    return $proc.ExitCode
}

function Get-OptionValue {
    param(
        [string[]]$Values,
        [int]$Index,
        [string]$Option
    )

    if ($Values[$Index].StartsWith("$Option=", [System.StringComparison]::Ordinal)) {
        return $Values[$Index].Substring($Option.Length + 1)
    }

    if ($Index + 1 -ge $Values.Count) {
        Write-Fail "$Option requires an argument."
    }

    return $Values[$Index + 1]
}

function Find-IndexBase {
    param([string[]]$Values)

    for ($i = 0; $i -lt $Values.Count; $i++) {
        $arg = $Values[$i]
        if ($arg -eq '-x' -or $arg -eq '--index') {
            if ($i + 1 -ge $Values.Count) {
                Write-Fail "$arg requires an argument."
            }
            return $Values[$i + 1]
        }
        if ($arg.StartsWith('--index=', [System.StringComparison]::Ordinal)) {
            return $arg.Substring('--index='.Length)
        }
        if ($arg.Length -gt 2 -and $arg.StartsWith('-x', [System.StringComparison]::Ordinal)) {
            return $arg.Substring(2)
        }
    }
    return $null
}

function Resolve-IndexBase {
    param([string]$IndexBase)

    if ([string]::IsNullOrEmpty($IndexBase)) {
        return $null
    }

    if ((Test-Path -LiteralPath "$IndexBase.1.bt2") -or (Test-Path -LiteralPath "$IndexBase.1.bt2l")) {
        return $IndexBase
    }

    if (-not [string]::IsNullOrEmpty($env:BOWTIE2_INDEXES)) {
        $candidate = Join-Path $env:BOWTIE2_INDEXES $IndexBase
        if ((Test-Path -LiteralPath "$candidate.1.bt2") -or (Test-Path -LiteralPath "$candidate.1.bt2l")) {
            return $candidate
        }
    }

    Write-Fail "`"$IndexBase`" does not exist or is not a Bowtie 2 index."
}

function Test-HelpOrVersion {
    param([string[]]$Values)

    foreach ($arg in $Values) {
        if ($arg -in @('-h', '--help', '--usage', '--version')) {
            return $true
        }
    }
    return $false
}

function Test-UnsupportedWrapperOption {
    param([string]$Arg)

    $unsupportedWithValue = @(
        '--un', '--un-gz', '--un-bz2', '--un-lz4', '--un-zst',
        '--al', '--al-gz', '--al-bz2', '--al-lz4', '--al-zst',
        '--un-conc', '--un-conc-gz', '--un-conc-bz2', '--un-conc-lz4', '--un-conc-zst',
        '--al-conc', '--al-conc-gz', '--al-conc-bz2', '--al-conc-lz4', '--al-conc-zst',
        '--un-mates', '--un-mates-gz', '--un-mates-bz2', '--un-mates-lz4', '--un-mates-zst'
    )

    foreach ($option in $unsupportedWithValue) {
        if ($Arg -eq $option -or $Arg.StartsWith("$option=", [System.StringComparison]::Ordinal)) {
            return $option
        }
    }

    if ($Arg -eq '--bam') {
        return '--bam'
    }

    return $null
}

$largeIndex = $false
$verbose = $false
$debug = $false
$sanitized = $false
$keep = $false
$tempDirectory = [System.IO.Path]::GetTempPath()
$logFile = $null
$refString = $null
$bt2Args = New-Object System.Collections.Generic.List[string]
$tempPaths = New-Object System.Collections.Generic.List[string]

for ($i = 0; $i -lt $ScriptArgs.Count; $i++) {
    $arg = $ScriptArgs[$i]
    $unsupported = Test-UnsupportedWrapperOption $arg
    if ($unsupported) {
        Write-Fail "$unsupported is not supported by the native PowerShell wrapper yet. Use direct SAM output options or extend this wrapper without shell pipelines."
    }

    if ($arg -eq '--large-index') {
        $largeIndex = $true
        continue
    }
    if ($arg -eq '--debug') {
        $debug = $true
        continue
    }
    if ($arg -eq '--sanitized') {
        $sanitized = $true
        continue
    }
    if ($arg -eq '--verbose') {
        $verbose = $true
        $bt2Args.Add($arg)
        continue
    }
    if ($arg -eq '--keep') {
        $keep = $true
        continue
    }
    if ($arg -eq '--no-named-pipes') {
        continue
    }
    if ($arg -eq '--log-file' -or $arg.StartsWith('--log-file=', [System.StringComparison]::Ordinal)) {
        $logFile = Get-OptionValue $ScriptArgs $i '--log-file'
        if ($arg -eq '--log-file') { $i++ }
        continue
    }
    if ($arg -eq '--temp-directory' -or $arg.StartsWith('--temp-directory=', [System.StringComparison]::Ordinal)) {
        $tempDirectory = Get-OptionValue $ScriptArgs $i '--temp-directory'
        if ($arg -eq '--temp-directory') { $i++ }
        continue
    }
    if ($arg -eq '--ref-string' -or $arg.StartsWith('--ref-string=', [System.StringComparison]::Ordinal)) {
        $refString = Get-OptionValue $ScriptArgs $i '--ref-string'
        if ($arg -eq '--ref-string') { $i++ }
        continue
    }
    if ($arg -eq '--reference-string' -or $arg.StartsWith('--reference-string=', [System.StringComparison]::Ordinal)) {
        $refString = Get-OptionValue $ScriptArgs $i '--reference-string'
        if ($arg -eq '--reference-string') { $i++ }
        continue
    }

    $bt2Args.Add($arg)
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

try {
    if (-not [string]::IsNullOrEmpty($refString)) {
        if (-not (Test-Path -LiteralPath $tempDirectory)) {
            [void][System.IO.Directory]::CreateDirectory($tempDirectory)
        }

        $tempBase = Join-Path $tempDirectory ("bowtie2_ref_{0}_{1}" -f $PID, ([Guid]::NewGuid().ToString('N')))
        $refPath = "$tempBase.fa"
        [System.IO.File]::WriteAllText($refPath, ">1`n$refString`n", [System.Text.Encoding]::ASCII)
        $tempPaths.Add($refPath)

        $buildExe = Join-Path $SourceDir 'bowtie2-build-s.exe'
        if (-not (Test-Path -LiteralPath $buildExe)) {
            Write-Fail 'bowtie2-build-s.exe does not exist; build Bowtie 2 first.'
        }

        $buildArgs = [string[]]@('--wrapper', 'basic-0', $refPath, $tempBase)
        Write-Info $verbose "Building temporary reference-string index: $tempBase"
        $buildExit = Invoke-Native $buildExe $buildArgs $logFile -StdoutToStderr
        if ($buildExit -ne 0) {
            Write-Fail "bowtie2-build exited with value $buildExit while building --reference-string index."
        }

        foreach ($suffixPath in @('.1.bt2', '.2.bt2', '.3.bt2', '.4.bt2', '.rev.1.bt2', '.rev.2.bt2')) {
            $tempPaths.Add("$tempBase$suffixPath")
        }

        $bt2Args.Add('--index')
        $bt2Args.Add($tempBase)
    }

    $hasHelpOrVersion = Test-HelpOrVersion $bt2Args.ToArray()
    $indexBase = Find-IndexBase $bt2Args.ToArray()
    $resolvedIndexBase = $null
    if (-not $hasHelpOrVersion) {
        $resolvedIndexBase = Resolve-IndexBase $indexBase
    } elseif (-not [string]::IsNullOrEmpty($indexBase)) {
        $resolvedIndexBase = Resolve-IndexBase $indexBase
    }

    $useLarge = $false
    if ($largeIndex) {
        $useLarge = $true
        if (-not [string]::IsNullOrEmpty($resolvedIndexBase) -and -not (Test-Path -LiteralPath "$resolvedIndexBase.1.bt2l")) {
            Write-Fail "Cannot find the large index $resolvedIndexBase.1.bt2l."
        }
    } elseif (-not [string]::IsNullOrEmpty($resolvedIndexBase)) {
        $largeExists = Test-Path -LiteralPath "$resolvedIndexBase.1.bt2l"
        $smallExists = Test-Path -LiteralPath "$resolvedIndexBase.1.bt2"
        if ($largeExists -and -not $smallExists) {
            $useLarge = $true
        }
    }

    $alignName = if ($useLarge) { "bowtie2-align-l$suffix.exe" } else { "bowtie2-align-s$suffix.exe" }
    $alignExe = Join-Path $SourceDir $alignName
    if (-not (Test-Path -LiteralPath $alignExe)) {
        Write-Fail "$alignName does not exist; build Bowtie 2 first."
    }

    Write-Info $verbose "Using $(if ($useLarge) { 'large' } else { 'small' }) aligner: $alignName"
    $nativeArgs = [string[]](@('--wrapper', 'basic-0') + $bt2Args.ToArray())
    Write-Info $verbose "Command: `"$alignExe`" $($nativeArgs -join ' ')"
    $exitCode = Invoke-Native $alignExe $nativeArgs $logFile
    exit $exitCode
} finally {
    if (-not $keep) {
        foreach ($path in $tempPaths) {
            if (Test-Path -LiteralPath $path) {
                Remove-Item -LiteralPath $path -Force
            }
        }
    }
}
