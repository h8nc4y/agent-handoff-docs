[CmdletBinding()]
param(
    [string]$Path = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$runtimeIsWindows = [Environment]::OSVersion.Platform -eq
    [PlatformID]::Win32NT

$scriptRoot = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($scriptRoot)) {
    $scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
}
$selfTestScriptPath = $MyInvocation.MyCommand.Path

if ([string]::IsNullOrWhiteSpace($Path)) {
    $Path = Split-Path -Parent $scriptRoot
}

$root = (Resolve-Path -LiteralPath $Path).Path
$scanner = Join-Path $root 'scripts/scan-private-markers.ps1'
if (-not (Test-Path -LiteralPath $scanner -PathType Leaf)) {
    throw "Missing scanner script: $scanner"
}
$processSupport = Join-Path $root 'scripts/private-marker-process.ps1'
if (-not (Test-Path -LiteralPath $processSupport -PathType Leaf)) {
    throw "Missing bounded process support script: $processSupport"
}
. $processSupport

$currentPowerShellExecutable = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
if ([string]::IsNullOrWhiteSpace($currentPowerShellExecutable) -or
    -not (Test-Path -LiteralPath $currentPowerShellExecutable -PathType Leaf)) {
    $hostExecutableName = if ($PSVersionTable.PSVersion.Major -le 5) {
        'powershell.exe'
    } elseif ($runtimeIsWindows) {
        'pwsh.exe'
    } else {
        'pwsh'
    }
    $currentPowerShellExecutable = Join-Path $PSHOME $hostExecutableName
}
if (-not (Test-Path -LiteralPath $currentPowerShellExecutable -PathType Leaf)) {
    throw "Cannot resolve the current PowerShell host executable: $currentPowerShellExecutable"
}

# Scanner-entrypoint fixtures need Git command discovery without inheriting the
# caller's complete PATH. Resolve Git once in the trusted parent, then pass a
# bounded path made only from its directory and fixed OS command directories.
$scannerGitCommands = @(
    Get-Command git -CommandType Application -ErrorAction SilentlyContinue
)
$scannerPathEntries = New-Object System.Collections.Generic.List[string]
if ($scannerGitCommands.Count -gt 0) {
    $scannerPathEntries.Add(
        (Split-Path -Parent $scannerGitCommands[0].Source)
    ) | Out-Null
}
if ($runtimeIsWindows) {
    if (-not [string]::IsNullOrWhiteSpace([Environment]::SystemDirectory)) {
        $scannerPathEntries.Add([Environment]::SystemDirectory) | Out-Null
    }
}
else {
    foreach ($systemPath in @('/usr/bin', '/bin')) {
        if (Test-Path -LiteralPath $systemPath -PathType Container) {
            $scannerPathEntries.Add($systemPath) | Out-Null
        }
    }
}
$scannerDefaultPath = @(
    $scannerPathEntries | Select-Object -Unique
) -join [IO.Path]::PathSeparator

$failures = New-Object System.Collections.Generic.List[string]

function Add-Failure {
    param([string]$Message)
    $failures.Add($Message) | Out-Null
}

function Test-NativePosixSessionEvidenceReady {
    param(
        [bool]$RuntimeIsWindows,
        [Parameter(Mandatory = $true)]
        [psobject]$Result,
        [bool]$GrandchildPayloadStarted,
        [bool]$DelayedSentinelObserved,
        [bool]$NoNewFailures
    )

    # The CI marker is an evidence boundary, not a progress message. Require
    # the target command to succeed and prove that the grandchild really
    # existed before accepting process-group cleanup as measured.
    return (
        -not $RuntimeIsWindows -and
        $NoNewFailures -and
        $Result.ExitCode -eq 0 -and
        -not $Result.TimedOut -and
        $Result.TreeStopped -and
        $Result.StreamsDrained -and
        $Result.DescendantPipeCleanupRequested -and
        $GrandchildPayloadStarted -and
        -not $DelayedSentinelObserved
    )
}

function Assert-NativePosixSessionEvidenceRegressions {
    $successfulResult = [pscustomobject]@{
        ExitCode = 0
        TimedOut = $false
        TreeStopped = $true
        StreamsDrained = $true
        DescendantPipeCleanupRequested = $true
    }
    if (-not (Test-NativePosixSessionEvidenceReady `
            -RuntimeIsWindows $false `
            -Result $successfulResult `
            -GrandchildPayloadStarted $true `
            -DelayedSentinelObserved $false `
            -NoNewFailures $true)) {
        Add-Failure 'Expected a complete native POSIX session result to be evidence-eligible.'
    }

    $nonzeroResult = [pscustomobject]@{
        ExitCode = 23
        TimedOut = $false
        TreeStopped = $true
        StreamsDrained = $true
        DescendantPipeCleanupRequested = $true
    }
    if (Test-NativePosixSessionEvidenceReady `
            -RuntimeIsWindows $false `
            -Result $nonzeroResult `
            -GrandchildPayloadStarted $true `
            -DelayedSentinelObserved $false `
            -NoNewFailures $true) {
        Add-Failure 'Native POSIX evidence must reject a nonzero target command.'
    }
    if (Test-NativePosixSessionEvidenceReady `
            -RuntimeIsWindows $false `
            -Result $successfulResult `
            -GrandchildPayloadStarted $false `
            -DelayedSentinelObserved $false `
            -NoNewFailures $true) {
        Add-Failure 'Native POSIX evidence must reject an unconfirmed grandchild spawn.'
    }
    $noPipeLeakResult = [pscustomobject]@{
        ExitCode = 0
        TimedOut = $false
        TreeStopped = $true
        StreamsDrained = $true
        DescendantPipeCleanupRequested = $false
    }
    if (Test-NativePosixSessionEvidenceReady `
            -RuntimeIsWindows $false `
            -Result $noPipeLeakResult `
            -GrandchildPayloadStarted $true `
            -DelayedSentinelObserved $false `
            -NoNewFailures $true) {
        Add-Failure 'Native POSIX evidence must reject a result without descendant pipe cleanup.'
    }
}

function Resolve-PhysicalDirectoryPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DirectoryPath
    )

    $resolvedPath = [IO.Path]::GetFullPath(
        (Resolve-Path -LiteralPath $DirectoryPath -ErrorAction Stop).Path
    )
    if ($runtimeIsWindows) {
        return $resolvedPath
    }

    # Resolve every ancestor rather than only the leaf. On macOS the temporary
    # directory commonly arrives through an alias such as /var while Git
    # reports the physical /private/var path.
    $rootPath = [IO.Path]::GetPathRoot($resolvedPath)
    $currentPath = $rootPath
    $relativePath = $resolvedPath.Substring($rootPath.Length)
    $separators = [char[]]@(
        [IO.Path]::DirectorySeparatorChar,
        [IO.Path]::AltDirectorySeparatorChar
    )
    $segments = $relativePath.Split(
        $separators,
        [StringSplitOptions]::RemoveEmptyEntries
    )
    foreach ($segment in $segments) {
        $candidatePath = [IO.Path]::Combine($currentPath, $segment)
        $candidateItem = [IO.DirectoryInfo]::new($candidatePath)
        if (-not $candidateItem.Exists) {
            throw "Physical path component is missing: $candidatePath"
        }
        $linkTarget = $candidateItem.ResolveLinkTarget($true)
        $currentPath = if ($null -eq $linkTarget) {
            [IO.Path]::GetFullPath($candidateItem.FullName)
        } else {
            [IO.Path]::GetFullPath($linkTarget.FullName)
        }
    }
    return $currentPath
}

function Assert-PhysicalTempRootAliasRegression {
    param(
        [Parameter(Mandatory = $true)]
        [string]$CanonicalTempRoot
    )

    if ($runtimeIsWindows) {
        return
    }

    $targetParent = Join-Path $CanonicalTempRoot 'physical-temp-root-target'
    $targetChild = Join-Path $targetParent 'child'
    $aliasParent = Join-Path $CanonicalTempRoot 'physical-temp-root-alias'
    New-Item -ItemType Directory -Path $targetChild | Out-Null
    New-Item `
        -ItemType SymbolicLink `
        -Path $aliasParent `
        -Target $targetParent | Out-Null
    try {
        $actual = Resolve-PhysicalDirectoryPath `
            -DirectoryPath (Join-Path $aliasParent 'child')
        $expected = Resolve-PhysicalDirectoryPath -DirectoryPath $targetChild
        if (-not [string]::Equals(
                $actual,
                $expected,
                [StringComparison]::Ordinal
            )) {
            Add-Failure (
                'Expected the physical temp-root alias regression to resolve ' +
                'an ancestor link to the target directory.'
            )
        }
    }
    finally {
        # Remove only the synthetic link. The target stays inside tempRoot and
        # is removed by the suite's existing final cleanup.
        Remove-Item -LiteralPath $aliasParent -Force
    }
}

function Get-ProcessEnvironmentSnapshot {
    $snapshot = @{}
    $environment = [Environment]::GetEnvironmentVariables('Process')
    foreach ($name in $environment.Keys) {
        $snapshot["$name"] = [string]$environment[$name]
    }
    return $snapshot
}

function Compare-ProcessEnvironmentSnapshot {
    param([hashtable]$Expected)

    $actual = Get-ProcessEnvironmentSnapshot
    $mismatches = New-Object System.Collections.Generic.List[string]
    foreach ($name in @($Expected.Keys + $actual.Keys) | Sort-Object -Unique) {
        if ($Expected.ContainsKey($name) -ne $actual.ContainsKey($name) -or
            ($Expected.ContainsKey($name) -and $Expected[$name] -cne $actual[$name])) {
            # Never include values: ambient environment data may be sensitive.
            $mismatches.Add($name) | Out-Null
        }
    }
    return @($mismatches)
}

function Assert-ProcessEnvironmentUnchanged {
    param(
        [hashtable]$Expected,
        [string]$Context
    )

    $mismatches = @(Compare-ProcessEnvironmentSnapshot -Expected $Expected)
    if ($mismatches.Count -gt 0) {
        Add-Failure "$Context changed parent environment variables: $($mismatches -join ', ')."
    }
}

function ConvertTo-SyntheticShellSingleQuotedLiteral {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Value
    )

    # POSIX shells represent one literal apostrophe by closing the single-
    # quoted segment, emitting a double-quoted apostrophe, and reopening it.
    # Build the delimiter from character codes so this PowerShell source stays
    # readable and the caller-controlled temp path is never evaluated as code.
    $singleQuote = [string][char]39
    $doubleQuote = [string][char]34
    $escapedQuote = $singleQuote +
        $doubleQuote +
        $singleQuote +
        $doubleQuote +
        $singleQuote
    return $singleQuote +
        $Value.Replace($singleQuote, $escapedQuote) +
        $singleQuote
}

function Test-BoundedResultHealthy {
    param([object]$Result)

    return $null -ne $Result -and
        -not $Result.TimedOut -and
        -not $Result.OutputLimitExceeded -and
        $Result.TreeStopped -and
        $Result.StreamsDrained
}

function Test-PrivateMarkerCommandIsDeferredDefinition {
    param(
        [Parameter(Mandatory = $true)]
        [Management.Automation.Language.CommandAst]$Command
    )

    $ancestor = $Command.Parent
    while ($null -ne $ancestor) {
        if ($ancestor -is
                [Management.Automation.Language.FunctionDefinitionAst] -or
            $ancestor -is
                [Management.Automation.Language.FunctionMemberAst] -or
            $ancestor -is
                [Management.Automation.Language.TypeDefinitionAst]) {
            return $true
        }
        if ($ancestor -is
            [Management.Automation.Language.ScriptBlockExpressionAst]) {
            # A stored scriptblock is data until some enclosing command receives
            # it. Conservatively treat command arguments and member invocation
            # as executable because invocation operators, pipeline cmdlets, and
            # ScriptBlock.Invoke*() can run those blocks.
            $container = $ancestor.Parent
            $expressionCanExecuteScriptBlock = $false
            while ($null -ne $container) {
                if ($container -is
                        [Management.Automation.Language.FunctionDefinitionAst] -or
                    $container -is
                        [Management.Automation.Language.FunctionMemberAst] -or
                    $container -is
                        [Management.Automation.Language.TypeDefinitionAst]) {
                    return $true
                }
                if ($container -is
                        [Management.Automation.Language.CommandAst] -or
                    $container -is
                        [Management.Automation.Language.InvokeMemberExpressionAst]) {
                    $expressionCanExecuteScriptBlock = $true
                    break
                }
                $container = $container.Parent
            }
            if (-not $expressionCanExecuteScriptBlock) {
                return $true
            }
        }
        $ancestor = $ancestor.Parent
    }
    return $false
}

function Test-FirstBoundedInvocationIsRawTransport {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Source
    )

    # Validate AST relationships, not lines or regex text. The raw assignment
    # must directly own one outer helper command, with no nested helper argument.
    $tokens = $null
    $parseErrors = $null
    $sourceAst = [Management.Automation.Language.Parser]::ParseInput(
        $Source,
        [ref]$tokens,
        [ref]$parseErrors
    )
    if ($parseErrors.Count -gt 0) {
        return $false
    }

    $rawAssignments = @(
        $sourceAst.FindAll(
            {
                param($node)
                return $node -is
                        [Management.Automation.Language.AssignmentStatementAst] -and
                    $node.Left -is
                        [Management.Automation.Language.VariableExpressionAst] -and
                    $node.Left.VariablePath.UserPath -eq 'rawTransportResult'
            },
            $true
        )
    )
    if ($rawAssignments.Count -ne 1 -or
        $rawAssignments[0].Right -isnot
            [Management.Automation.Language.PipelineAst]) {
        return $false
    }

    $rawPipelineElements = @($rawAssignments[0].Right.PipelineElements)
    if ($rawPipelineElements.Count -ne 1 -or
        $rawPipelineElements[0] -isnot
            [Management.Automation.Language.CommandAst] -or
        $rawPipelineElements[0].GetCommandName() -ne
            'Invoke-PrivateMarkerBoundedProcess') {
        return $false
    }
    $rawOuterCommand = $rawPipelineElements[0]
    $rawNestedCalls = @(
        $rawAssignments[0].Right.FindAll(
            {
                param($node)
                return $node -is
                        [Management.Automation.Language.CommandAst] -and
                    $node.GetCommandName() -eq
                        'Invoke-PrivateMarkerBoundedProcess'
            },
            $true
        )
    )
    if ($rawNestedCalls.Count -ne 1 -or
        (Test-PrivateMarkerCommandIsDeferredDefinition `
            -Command $rawOuterCommand)) {
        return $false
    }

    $eagerBoundedCalls = @(
        $sourceAst.FindAll(
            {
                param($node)
                return $node -is
                        [Management.Automation.Language.CommandAst] -and
                    $node.GetCommandName() -eq
                        'Invoke-PrivateMarkerBoundedProcess'
            },
            $true
        ) |
            Where-Object {
                -not (Test-PrivateMarkerCommandIsDeferredDefinition -Command $_)
            } |
            Sort-Object { $_.Extent.StartOffset }
    )
    return $eagerBoundedCalls.Count -gt 0 -and
        $eagerBoundedCalls[0].Extent.StartOffset -eq
            $rawOuterCommand.Extent.StartOffset -and
        $eagerBoundedCalls[0].Extent.EndOffset -eq
            $rawOuterCommand.Extent.EndOffset
}

function Assert-FirstBoundedInvocationValidatorRegressions {
    $cases = @(
        [pscustomobject]@{
            Name = 'direct-before'
            Expected = $false
            Source = @'
Invoke-PrivateMarkerBoundedProcess
$rawTransportResult = Invoke-PrivateMarkerBoundedProcess
'@
        },
        [pscustomobject]@{
            Name = 'function-before'
            Expected = $true
            Source = @'
function Invoke-Deferred {
    Invoke-PrivateMarkerBoundedProcess
}
$rawTransportResult = Invoke-PrivateMarkerBoundedProcess
'@
        },
        [pscustomobject]@{
            Name = 'uninvoked-scriptblock'
            Expected = $true
            Source = @'
$unused = { Invoke-PrivateMarkerBoundedProcess }
$rawTransportResult = Invoke-PrivateMarkerBoundedProcess
'@
        },
        [pscustomobject]@{
            Name = 'nested-inner'
            Expected = $false
            Source = @'
$rawTransportResult = Invoke-PrivateMarkerBoundedProcess -Value $(Invoke-PrivateMarkerBoundedProcess)
'@
        },
        [pscustomobject]@{
            Name = 'invoked-scriptblock-member'
            Expected = $false
            Source = @'
({ Invoke-PrivateMarkerBoundedProcess }).Invoke()
$rawTransportResult = Invoke-PrivateMarkerBoundedProcess
'@
        },
        [pscustomobject]@{
            Name = 'invoked-scriptblock-return-as-is'
            Expected = $false
            Source = @'
({ Invoke-PrivateMarkerBoundedProcess }).InvokeReturnAsIs()
$rawTransportResult = Invoke-PrivateMarkerBoundedProcess
'@
        }
    )
    foreach ($case in $cases) {
        $actual = Test-FirstBoundedInvocationIsRawTransport `
            -Source $case.Source
        if ($actual -ne $case.Expected) {
            Add-Failure "First-invocation validator regression failed: $($case.Name)."
        }
    }
}

function Assert-FirstBoundedInvocationIsRawTransport {
    # Parse the real self-test before any bounded helper runs, then apply the
    # same pure validator covered by the synthetic structural regressions.
    $source = [IO.File]::ReadAllText($selfTestScriptPath)
    if (-not (Test-FirstBoundedInvocationIsRawTransport -Source $source)) {
        Add-Failure 'Expected raw binary transport to be the first executable bounded helper invocation.'
    }
}

function Invoke-Scanner {
    param(
        [string]$ScanPath,
        [hashtable]$InheritedEnvironment = @{},
        [int]$MaxStdoutBytes = 16777216,
        [int]$MaxStderrBytes = 1048576
    )

    $arguments = @('-NoProfile')
    if ($PSVersionTable.PSVersion.Major -le 5 -and $runtimeIsWindows) {
        $arguments += @('-ExecutionPolicy', 'Bypass')
    }
    $arguments += @('-File', $scanner, '-Path', $ScanPath)

    $scannerIsolationRoot = Join-Path (
        [System.IO.Path]::GetTempPath()
    ) ("agent-handoff-docs-scanner-git-" + [System.Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $scannerIsolationRoot | Out-Null
    try {
        $scannerEnvironment = @{
            PATH = $scannerDefaultPath
        }
        foreach ($name in $InheritedEnvironment.Keys) {
            $scannerEnvironment["$name"] =
                [string]$InheritedEnvironment[$name]
        }
        $result = Invoke-PrivateMarkerBoundedProcess `
            -FileName $currentPowerShellExecutable `
            -Arguments $arguments `
            -IsolationRoot $scannerIsolationRoot `
            -InheritedEnvironment $scannerEnvironment `
            -TimeoutMilliseconds 30000 `
            -MaxStdoutBytes $MaxStdoutBytes `
            -MaxStderrBytes $MaxStderrBytes `
            -PassThroughGitEnvironment
        if (-not (Test-BoundedResultHealthy -Result $result)) {
            Add-Failure 'Scanner child exceeded its bounded runtime for a synthetic fixture.'
        }
        return $result
    }
    finally {
        if (Test-Path -LiteralPath $scannerIsolationRoot) {
            Remove-Item -LiteralPath $scannerIsolationRoot -Recurse -Force
        }
    }
}

function Invoke-IsolatedGit {
    param(
        [Parameter(Mandatory = $true)]
        [string]$GitPath,

        [Parameter(Mandatory = $true)]
        [string]$WorkingDirectory,

        [Parameter(Mandatory = $true)]
        [string]$IsolationRoot,

        [Parameter(Mandatory = $true)]
        [string[]]$Arguments,

        [hashtable]$InheritedEnvironment = @{},

        [AllowNull()]
        [byte[]]$StandardInputBytes = $null,

        [ValidateRange(1, [int]::MaxValue)]
        [int]$TimeoutMilliseconds = 20000
    )

    return Invoke-PrivateMarkerBoundedProcess `
        -FileName $GitPath `
        -Arguments (@('-C', $WorkingDirectory) + $Arguments) `
        -IsolationRoot $IsolationRoot `
        -WorkingDirectory $WorkingDirectory `
        -InheritedEnvironment $InheritedEnvironment `
        -StandardInputBytes $StandardInputBytes `
        -TimeoutMilliseconds $TimeoutMilliseconds
}

function Start-SynchronizedIndexMutator {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ReadyPath,

        [Parameter(Mandatory = $true)]
        [string]$ReleasePath,

        [Parameter(Mandatory = $true)]
        [string]$SwapPath,

        [Parameter(Mandatory = $true)]
        [string]$IndexPath,

        [Parameter(Mandatory = $true)]
        [string]$BackupPath
    )

    $escapedReady = $ReadyPath.Replace("'", "''")
    $escapedRelease = $ReleasePath.Replace("'", "''")
    $escapedSwap = $SwapPath.Replace("'", "''")
    $escapedIndex = $IndexPath.Replace("'", "''")
    $escapedBackup = $BackupPath.Replace("'", "''")
    $mutatorScript = @"
`$readyObserved = `$false
for (`$attempt = 0; `$attempt -lt 1500; `$attempt++) {
    if ([IO.File]::Exists('$escapedReady')) {
        `$readyObserved = `$true
        break
    }
    Start-Sleep -Milliseconds 10
}
if (-not `$readyObserved) {
    exit 3
}
[IO.File]::Replace(
    '$escapedSwap',
    '$escapedIndex',
    '$escapedBackup'
)
[IO.File]::WriteAllText(
    '$escapedRelease',
    'release',
    [Text.UTF8Encoding]::new(`$false)
)
"@
    $mutatorEncoded = [Convert]::ToBase64String(
        [Text.Encoding]::Unicode.GetBytes($mutatorScript)
    )
    $mutatorArguments = @('-NoProfile')
    if ($PSVersionTable.PSVersion.Major -le 5 -and $runtimeIsWindows) {
        $mutatorArguments += @('-ExecutionPolicy', 'Bypass')
    }
    $mutatorArguments += @('-EncodedCommand', $mutatorEncoded)
    $mutatorInfo = New-Object Diagnostics.ProcessStartInfo
    $mutatorInfo.FileName = $currentPowerShellExecutable
    $mutatorInfo.UseShellExecute = $false
    $mutatorInfo.CreateNoWindow = $true
    $mutatorArgumentList =
        $mutatorInfo.PSObject.Properties['ArgumentList']
    if ($null -ne $mutatorArgumentList) {
        foreach ($mutatorArgument in $mutatorArguments) {
            $mutatorInfo.ArgumentList.Add($mutatorArgument)
        }
    } else {
        $mutatorInfo.Arguments = (
            $mutatorArguments | ForEach-Object {
                ConvertTo-PrivateMarkerProcessArgument -Argument $_
            }
        ) -join ' '
    }
    return [Diagnostics.Process]::Start($mutatorInfo)
}

function New-WorktreeDriftScannerCopy {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DestinationDirectory,

        [Parameter(Mandatory = $true)]
        [string]$TargetPath,

        [Parameter(Mandatory = $true)]
        [string]$SwapPath,

        [Parameter(Mandatory = $true)]
        [string]$BackupPath
    )

    New-Item `
        -ItemType Directory `
        -Path $DestinationDirectory `
        -Force | Out-Null
    $scannerCopy = Join-Path `
        $DestinationDirectory `
        'scan-private-markers.ps1'
    Copy-Item -LiteralPath $scanner -Destination $scannerCopy
    Copy-Item `
        -LiteralPath $processSupport `
        -Destination (Join-Path `
            $DestinationDirectory `
            'private-marker-process.ps1')

    # Mutate only a disposable scanner copy at the exact boundary after every
    # initial snapshot and the first index recheck. Production receives no
    # caller-controlled delay or synchronization surface.
    $anchor = 'foreach ($target in $scanTargets) {'
    $scannerSource = [IO.File]::ReadAllText($scannerCopy)
    $anchorOffset = $scannerSource.IndexOf(
        $anchor,
        [StringComparison]::Ordinal
    )
    if ($anchorOffset -lt 0 -or
        $scannerSource.IndexOf(
            $anchor,
            $anchorOffset + $anchor.Length,
            [StringComparison]::Ordinal
        ) -ge 0) {
        throw 'Cannot locate the unique worktree-drift synchronization anchor.'
    }

    $driftInjection = @'
# Test-copy only: atomically replace a captured regular worktree file with
# different bytes of the same length before matching and final reporting.
[IO.File]::Replace(
    '__SWAP__',
    '__TARGET__',
    '__BACKUP__'
)

'@
    $driftInjection = $driftInjection.Replace(
        '__SWAP__',
        $SwapPath.Replace("'", "''")
    ).Replace(
        '__TARGET__',
        $TargetPath.Replace("'", "''")
    ).Replace(
        '__BACKUP__',
        $BackupPath.Replace("'", "''")
    )
    [IO.File]::WriteAllText(
        $scannerCopy,
        $scannerSource.Replace($anchor, $driftInjection + $anchor),
        [Text.UTF8Encoding]::new($false)
    )
    return $scannerCopy
}

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("agent-handoff-docs-scan-test-" + [System.Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tempRoot | Out-Null
$tempRoot = Resolve-PhysicalDirectoryPath -DirectoryPath $tempRoot

try {
    Assert-NativePosixSessionEvidenceRegressions
    Assert-PhysicalTempRootAliasRegression -CanonicalTempRoot $tempRoot
    Assert-FirstBoundedInvocationValidatorRegressions
    Assert-FirstBoundedInvocationIsRawTransport

    # This must remain the first top-level bounded helper invocation. Scanner
    # fixtures enter the owned Job first, so their nested Git calls reuse it and
    # cannot expose corruption in the initial Windows gate. Exercise binary
    # stdin, partial stdout/stderr writes, EOF, and a nonzero exit code without
    # framing.
    $rawTransportScript = @'
$stdin = [Console]::OpenStandardInput()
$readBuffer = New-Object byte[] 3
$stdout = [Console]::OpenStandardOutput()
$readCount = $stdin.Read($readBuffer, 0, $readBuffer.Length)
while ($readCount -gt 0) {
    $stdout.Write($readBuffer, 0, $readCount)
    $stdout.Flush()
    $readCount = $stdin.Read($readBuffer, 0, $readBuffer.Length)
}
$stderrBytes = [byte[]]@(255, 254, 128, 127, 13, 10, 1, 0)
$stderr = [Console]::OpenStandardError()
$stderr.Write($stderrBytes, 0, 3)
$stderr.Flush()
$stderr.Write($stderrBytes, 3, $stderrBytes.Length - 3)
$stderr.Flush()
exit 37
'@
    $rawTransportChildPath = Join-Path $tempRoot 'raw-transport-child.ps1'
    [IO.File]::WriteAllText(
        $rawTransportChildPath,
        $rawTransportScript,
        [Text.UTF8Encoding]::new($false)
    )
    $rawTransportArguments = @('-NoProfile')
    if ($PSVersionTable.PSVersion.Major -le 5 -and $runtimeIsWindows) {
        $rawTransportArguments += @('-ExecutionPolicy', 'Bypass')
    }
    $rawTransportArguments += @('-File', $rawTransportChildPath)
    $rawTransportInput = [byte[]]@(
        0, 128, 255, 1, 10, 13, 127, 254, 2, 129, 253, 3
    )
    $rawTransportResult = Invoke-PrivateMarkerBoundedProcess `
        -FileName $currentPowerShellExecutable `
        -Arguments $rawTransportArguments `
        -IsolationRoot (Join-Path $tempRoot 'raw-transport-isolation') `
        -StandardInputBytes $rawTransportInput `
        -TimeoutMilliseconds 5000 `
        -MaxStdoutBytes 64 `
        -MaxStderrBytes 64
    $expectedRawStderr = [byte[]]@(255, 254, 128, 127, 13, 10, 1, 0)
    if (-not (Test-BoundedResultHealthy -Result $rawTransportResult) -or
        $rawTransportResult.ExitCode -ne 37 -or
        [Convert]::ToBase64String($rawTransportResult.StdoutBytes) -ne
            [Convert]::ToBase64String($rawTransportInput) -or
        [Convert]::ToBase64String($rawTransportResult.StderrBytes) -ne
            [Convert]::ToBase64String($expectedRawStderr)) {
        Add-Failure 'Expected the containment gate to preserve binary stdin/stdout/stderr, EOF, and exit code exactly.'
    }

    # PowerShell accepts a UTF-8 preamble at its own input boundary, so the
    # synthetic echo above cannot expose Windows PowerShell 5.1 adding that
    # preamble before raw BaseStream writes. Exercise native Git at the same
    # top-level Job gate and compare its complete binary batch response.
    $rawGitCommands = @(
        Get-Command git -CommandType Application -ErrorAction SilentlyContinue
    )
    if ($rawGitCommands.Count -eq 0) {
        Add-Failure 'Expected native Git to be available for the raw containment-gate regression.'
    }
    else {
        $rawGitPath = $rawGitCommands[0].Source
        $rawGitRoot = Join-Path $tempRoot 'raw-git-transport'
        $rawGitIsolationRoot = Join-Path $tempRoot 'raw-git-isolation'
        New-Item -ItemType Directory -Path $rawGitRoot | Out-Null
        New-Item -ItemType Directory -Path $rawGitIsolationRoot | Out-Null

        $rawGitInitResult = Invoke-IsolatedGit `
            -GitPath $rawGitPath `
            -WorkingDirectory $rawGitRoot `
            -IsolationRoot $rawGitIsolationRoot `
            -Arguments @('init', '-q')
        if (-not (Test-BoundedResultHealthy -Result $rawGitInitResult) -or
            $rawGitInitResult.ExitCode -ne 0) {
            Add-Failure 'Expected the raw native Git transport fixture to initialize.'
        }
        else {
            $rawGitBlobBytes = [byte[]]@(0, 128, 255, 10, 13, 1, 2)
            [IO.File]::WriteAllBytes(
                (Join-Path $rawGitRoot 'blob.bin'),
                $rawGitBlobBytes
            )
            $rawGitHashResult = Invoke-IsolatedGit `
                -GitPath $rawGitPath `
                -WorkingDirectory $rawGitRoot `
                -IsolationRoot $rawGitIsolationRoot `
                -Arguments @('hash-object', '-w', '--', 'blob.bin')
            $rawGitObjectId = [Text.Encoding]::ASCII.GetString(
                $rawGitHashResult.StdoutBytes
            ).Trim()
            if (-not (Test-BoundedResultHealthy -Result $rawGitHashResult) -or
                $rawGitHashResult.ExitCode -ne 0 -or
                $rawGitObjectId -notmatch '^(?:[0-9a-f]{40}|[0-9a-f]{64})$') {
                Add-Failure 'Expected the raw native Git transport fixture to create a blob object.'
            }
            else {
                # The helper may temporarily select a BOM-less stdin encoding
                # for Process.Start(), but the caller's console contract must
                # be restored before this invocation returns.
                $inputCodePageBefore = [Console]::InputEncoding.CodePage
                $inputPreambleBefore = [Convert]::ToBase64String(
                    [Console]::InputEncoding.GetPreamble()
                )
                $rawGitBatchInput = [Text.Encoding]::ASCII.GetBytes(
                    "$rawGitObjectId`n"
                )
                $rawGitBatchResult = Invoke-IsolatedGit `
                    -GitPath $rawGitPath `
                    -WorkingDirectory $rawGitRoot `
                    -IsolationRoot $rawGitIsolationRoot `
                    -Arguments @('cat-file', '--batch') `
                    -StandardInputBytes $rawGitBatchInput
                $rawGitHeaderBytes = [Text.Encoding]::ASCII.GetBytes(
                    "$rawGitObjectId blob $($rawGitBlobBytes.Length)`n"
                )
                $expectedRawGitOutput = [byte[]](
                    @($rawGitHeaderBytes) +
                    @($rawGitBlobBytes) +
                    @(10)
                )
                if (-not (Test-BoundedResultHealthy -Result $rawGitBatchResult) -or
                    $rawGitBatchResult.ExitCode -ne 0 -or
                    $rawGitBatchResult.StderrBytes.Length -ne 0 -or
                    [Convert]::ToBase64String($rawGitBatchResult.StdoutBytes) -ne
                        [Convert]::ToBase64String($expectedRawGitOutput)) {
                    Add-Failure 'Expected native git cat-file batch transport to remain byte-exact without a UTF-8 preamble.'
                }
                if ([Console]::InputEncoding.CodePage -ne
                        $inputCodePageBefore -or
                    [Convert]::ToBase64String(
                        [Console]::InputEncoding.GetPreamble()
                    ) -ne $inputPreambleBefore) {
                    Add-Failure 'Expected the raw input transport to restore the caller console input encoding exactly.'
                }
            }
        }
    }

    # Run one real child on both Windows and POSIX to prove the minimum
    # environment's positive requirements and representative negative
    # boundaries. The probe reports names only and never emits environment
    # values.
    $environmentProbeScript = @'
$forbiddenNames = @(
    'AGENT_HANDOFF_DOCS_AMBIENT_NEGATIVE_PROBE',
    'AGENT_HANDOFF_DOCS_REQUESTED_NEGATIVE_PROBE',
    'AWS_ACCESS_KEY_ID',
    'GH_TOKEN',
    'SSH_AUTH_SOCK',
    'LD_PRELOAD',
    'NODE_OPTIONS',
    'PYTHONPATH',
    'GIT_SYNTHETIC_REQUESTED_OVERRIDE'
)
$failures = New-Object System.Collections.Generic.List[string]
foreach ($name in $forbiddenNames) {
    if ($null -ne [Environment]::GetEnvironmentVariable($name, 'Process')) {
        $failures.Add("forbidden:$name") | Out-Null
    }
}
foreach ($name in @(
    'HOME',
    'USERPROFILE',
    'XDG_CONFIG_HOME',
    'PATH',
    'TEMP',
    'TMP',
    'LC_ALL',
    'LANG',
    'GIT_CONFIG_NOSYSTEM',
    'GIT_CONFIG_GLOBAL',
    'GIT_CONFIG_SYSTEM',
    'GIT_NO_REPLACE_OBJECTS',
    'GIT_NO_LAZY_FETCH'
)) {
    if ([string]::IsNullOrWhiteSpace(
            [Environment]::GetEnvironmentVariable($name, 'Process')
        )) {
        $failures.Add("missing:$name") | Out-Null
    }
}
$isWindows = [Environment]::OSVersion.Platform -eq
    [PlatformID]::Win32NT
if ($isWindows) {
    foreach ($name in @('SystemRoot', 'WINDIR', 'ComSpec', 'PATHEXT')) {
        if ([string]::IsNullOrWhiteSpace(
                [Environment]::GetEnvironmentVariable($name, 'Process')
            )) {
            $failures.Add("windows-missing:$name") | Out-Null
        }
    }
}
elseif ([string]::IsNullOrWhiteSpace($env:TMPDIR)) {
    $failures.Add('posix-missing:TMPDIR') | Out-Null
}
if ($env:PATH -like '*AGENT_HANDOFF_DOCS_AMBIENT_PATH_PROBE*') {
    $failures.Add('ambient-path') | Out-Null
}
if ($env:GIT_CONFIG_NOSYSTEM -cne '1' -or
    $env:GIT_NO_REPLACE_OBJECTS -cne '1' -or
    $env:GIT_NO_LAZY_FETCH -cne '1') {
    $failures.Add('git-controls') | Out-Null
}
if ($failures.Count -gt 0) {
    [Console]::Error.Write($failures -join ',')
    exit 72
}
[Console]::Out.Write('minimum-environment-pass')
'@
    $environmentProbeEncoded = [Convert]::ToBase64String(
        [Text.Encoding]::Unicode.GetBytes($environmentProbeScript)
    )
    $environmentProbeArguments = @('-NoProfile')
    if ($PSVersionTable.PSVersion.Major -le 5 -and $runtimeIsWindows) {
        $environmentProbeArguments += @('-ExecutionPolicy', 'Bypass')
    }
    $environmentProbeArguments += @(
        '-EncodedCommand',
        $environmentProbeEncoded
    )
    $ambientProbeName =
        'AGENT_HANDOFF_DOCS_AMBIENT_NEGATIVE_PROBE'
    $ambientEnvironment =
        [Environment]::GetEnvironmentVariables('Process')
    $ambientProbeWasPresent = $ambientEnvironment.Contains($ambientProbeName)
    $ambientProbePrevious = [Environment]::GetEnvironmentVariable(
        $ambientProbeName,
        'Process'
    )
    $beforeEnvironmentProbe = Get-ProcessEnvironmentSnapshot
    try {
        [Environment]::SetEnvironmentVariable(
            $ambientProbeName,
            'synthetic-ambient-value',
            'Process'
        )
        $environmentProbeResult = Invoke-PrivateMarkerBoundedProcess `
            -FileName $currentPowerShellExecutable `
            -Arguments $environmentProbeArguments `
            -IsolationRoot (
                Join-Path $tempRoot 'minimum-environment-isolation'
            ) `
            -InheritedEnvironment @{
                AGENT_HANDOFF_DOCS_REQUESTED_NEGATIVE_PROBE =
                    'synthetic-requested-value'
                AWS_ACCESS_KEY_ID = 'synthetic-credential'
                GH_TOKEN = 'synthetic-credential'
                SSH_AUTH_SOCK = 'synthetic-agent'
                LD_PRELOAD = '/synthetic/not-a-library'
                NODE_OPTIONS = '--synthetic-option'
                PYTHONPATH = 'synthetic-python-path'
                GIT_SYNTHETIC_REQUESTED_OVERRIDE = 'synthetic-git-value'
                PATH = 'AGENT_HANDOFF_DOCS_AMBIENT_PATH_PROBE'
            } `
            -TimeoutMilliseconds 30000 `
            -MaxStdoutBytes 128 `
            -MaxStderrBytes 4096
    }
    finally {
        if ($ambientProbeWasPresent) {
            [Environment]::SetEnvironmentVariable(
                $ambientProbeName,
                $ambientProbePrevious,
                'Process'
            )
        }
        else {
            Remove-Item `
                -LiteralPath ('Env:\' + $ambientProbeName) `
                -Force `
                -ErrorAction SilentlyContinue
        }
    }
    $environmentProbeText = [Text.Encoding]::UTF8.GetString(
        $environmentProbeResult.StdoutBytes
    )
    if (-not (Test-BoundedResultHealthy -Result $environmentProbeResult) -or
        $environmentProbeResult.ExitCode -ne 0 -or
        $environmentProbeText -ne 'minimum-environment-pass') {
        Add-Failure (
            'Expected the bounded child to receive only the minimum ' +
            "cross-platform environment allowlist (exit " +
            "$($environmentProbeResult.ExitCode))."
        )
    }
    Assert-ProcessEnvironmentUnchanged `
        -Expected $beforeEnvironmentProbe `
        -Context 'Minimum child environment probe'

    # The scanner-entrypoint bridge is intentionally narrower than general
    # inheritance: explicit GIT_*, PATH, and documented local-marker inputs
    # pass for hostile-scanner fixtures, while unrelated requested and ambient
    # values stay absent.
    $passThroughProbeScript = @'
$gitPassed = $env:GIT_SYNTHETIC_PASS_THROUGH -ceq 'expected'
$pathPassed = @(
    $env:PATH -split [regex]::Escape([string][IO.Path]::PathSeparator)
) -contains 'synthetic-explicit-path'
$unrelatedBlocked =
    $null -eq $env:AGENT_HANDOFF_DOCS_REQUESTED_NEGATIVE_PROBE -and
    $null -eq $env:AWS_ACCESS_KEY_ID
if (-not $gitPassed -or -not $pathPassed -or -not $unrelatedBlocked) {
    exit 73
}
[Console]::Out.Write('pass-through-allowlist-pass')
'@
    $passThroughProbeEncoded = [Convert]::ToBase64String(
        [Text.Encoding]::Unicode.GetBytes($passThroughProbeScript)
    )
    $passThroughProbeArguments = @('-NoProfile')
    if ($PSVersionTable.PSVersion.Major -le 5 -and $runtimeIsWindows) {
        $passThroughProbeArguments += @('-ExecutionPolicy', 'Bypass')
    }
    $passThroughProbeArguments += @(
        '-EncodedCommand',
        $passThroughProbeEncoded
    )
    $passThroughProbeResult = Invoke-PrivateMarkerBoundedProcess `
        -FileName $currentPowerShellExecutable `
        -Arguments $passThroughProbeArguments `
        -IsolationRoot (
            Join-Path $tempRoot 'pass-through-environment-isolation'
        ) `
        -InheritedEnvironment @{
            GIT_SYNTHETIC_PASS_THROUGH = 'expected'
            PATH = 'synthetic-explicit-path'
            AGENT_HANDOFF_DOCS_REQUESTED_NEGATIVE_PROBE =
                'synthetic-requested-value'
            AWS_ACCESS_KEY_ID = 'synthetic-credential'
        } `
        -PassThroughGitEnvironment `
        -TimeoutMilliseconds 30000 `
        -MaxStdoutBytes 128 `
        -MaxStderrBytes 4096
    $passThroughProbeText = [Text.Encoding]::UTF8.GetString(
        $passThroughProbeResult.StdoutBytes
    )
    if (-not (Test-BoundedResultHealthy -Result $passThroughProbeResult) -or
        $passThroughProbeResult.ExitCode -ne 0 -or
        $passThroughProbeText -ne 'pass-through-allowlist-pass') {
        Add-Failure (
            'Expected the scanner-entrypoint environment bridge to pass only ' +
            "explicit Git/test inputs and PATH values (exit " +
            "$($passThroughProbeResult.ExitCode))."
        )
    }

    # A delayed grandchild sentinel distinguishes true tree cleanup from a
    # parent-only kill. The grandchild also keeps the redirected pipe open.
    $timeoutIsolationRoot = Join-Path $tempRoot 'timeout-isolation'
    $timeoutSentinel = Join-Path $tempRoot 'grandchild-survived-timeout'
    $escapedTimeoutSentinel = $timeoutSentinel.Replace("'", "''")
    $grandchildScript = @"
Start-Sleep -Milliseconds 1500
[System.IO.File]::WriteAllText('$escapedTimeoutSentinel', 'survived')
"@
    $grandchildEncoded = [Convert]::ToBase64String(
        [System.Text.Encoding]::Unicode.GetBytes($grandchildScript)
    )
    $escapedPowerShellExecutable = $currentPowerShellExecutable.Replace("'", "''")
    $parentScript = @"
& '$escapedPowerShellExecutable' -NoProfile -EncodedCommand '$grandchildEncoded'
Start-Sleep -Seconds 30
"@
    $parentEncoded = [Convert]::ToBase64String(
        [System.Text.Encoding]::Unicode.GetBytes($parentScript)
    )
    $timeoutArguments = @('-NoProfile')
    if ($PSVersionTable.PSVersion.Major -le 5 -and $runtimeIsWindows) {
        $timeoutArguments += @('-ExecutionPolicy', 'Bypass')
    }
    $timeoutArguments += @('-EncodedCommand', $parentEncoded)
    $beforeTimeoutEnvironment = Get-ProcessEnvironmentSnapshot
    $timeoutResult = Invoke-PrivateMarkerBoundedProcess `
        -FileName $currentPowerShellExecutable `
        -Arguments $timeoutArguments `
        -IsolationRoot $timeoutIsolationRoot `
        -TimeoutMilliseconds 300
    if (-not $timeoutResult.TimedOut -or
        -not $timeoutResult.TreeStopped -or
        -not $timeoutResult.StreamsDrained) {
        Add-Failure 'Expected the bounded child regression to time out and stop its process tree.'
    }
    for ($attempt = 0; $attempt -lt 25 -and
        -not (Test-Path -LiteralPath $timeoutSentinel); $attempt++) {
        Start-Sleep -Milliseconds 100
    }
    if (Test-Path -LiteralPath $timeoutSentinel) {
        Add-Failure 'Expected timeout cleanup to kill the grandchild before its delayed sentinel write.'
    }
    Assert-ProcessEnvironmentUnchanged `
        -Expected $beforeTimeoutEnvironment `
        -Context 'Bounded child timeout'

    # The direct child can exit before a grandchild that inherited stdout. A
    # kill-on-close job/process group must remain addressable after that exit;
    # otherwise stream draining times out and the delayed sentinel survives.
    $detachedSentinel = Join-Path $tempRoot 'detached-grandchild-survived'
    $detachedGrandchildStarted =
        Join-Path $tempRoot 'detached-grandchild-started'
    $escapedDetachedSentinel = $detachedSentinel.Replace("'", "''")
    $escapedDetachedGrandchildStarted =
        $detachedGrandchildStarted.Replace("'", "''")
    $detachedGrandchildScript = @"
[IO.File]::WriteAllText(
    '$escapedDetachedGrandchildStarted',
    'started',
    [Text.UTF8Encoding]::new(`$false)
)
Start-Sleep -Milliseconds 1500
[System.IO.File]::WriteAllText('$escapedDetachedSentinel', 'survived')
[Console]::Out.Write('late-output')
"@
    $detachedGrandchildEncoded = [Convert]::ToBase64String(
        [Text.Encoding]::Unicode.GetBytes($detachedGrandchildScript)
    )
    $detachedParentScript = @"
`$startInfo = New-Object System.Diagnostics.ProcessStartInfo
`$startInfo.FileName = '$escapedPowerShellExecutable'
`$startInfo.Arguments = '-NoProfile -EncodedCommand $detachedGrandchildEncoded'
`$startInfo.UseShellExecute = `$false
`$startInfo.CreateNoWindow = `$true
`$child = [System.Diagnostics.Process]::Start(`$startInfo)
`$child.Dispose()
"@
    $detachedParentEncoded = [Convert]::ToBase64String(
        [Text.Encoding]::Unicode.GetBytes($detachedParentScript)
    )
    $detachedArguments = @('-NoProfile')
    if ($PSVersionTable.PSVersion.Major -le 5 -and $runtimeIsWindows) {
        $detachedArguments += @('-ExecutionPolicy', 'Bypass')
    }
    $detachedArguments += @('-EncodedCommand', $detachedParentEncoded)
    $nativeGateFailureCountBefore = $failures.Count
    $detachedResult = Invoke-PrivateMarkerBoundedProcess `
        -FileName $currentPowerShellExecutable `
        -Arguments $detachedArguments `
        -IsolationRoot (Join-Path $tempRoot 'detached-isolation') `
        -TimeoutMilliseconds 5000 `
        -DrainTimeoutMilliseconds 3000 `
        -ForceNativePosixSessionGate:(-not $runtimeIsWindows)
    if ($detachedResult.TimedOut -or
        -not $detachedResult.TreeStopped -or
        -not $detachedResult.StreamsDrained -or
        ($runtimeIsWindows -and $detachedResult.ExitCode -ne 125) -or
        (-not $runtimeIsWindows -and $detachedResult.ExitCode -ne 0)) {
        Add-Failure 'Expected parent-first exit cleanup to stop the pipe-owning grandchild and drain both streams.'
    }
    $detachedGrandchildStartedObserved =
        Test-Path -LiteralPath $detachedGrandchildStarted -PathType Leaf
    if (-not $detachedGrandchildStartedObserved) {
        Add-Failure 'Expected the detached grandchild payload to confirm that it started.'
    }
    for ($attempt = 0; $attempt -lt 25 -and
        -not (Test-Path -LiteralPath $detachedSentinel); $attempt++) {
        Start-Sleep -Milliseconds 100
    }
    $detachedSentinelObserved =
        Test-Path -LiteralPath $detachedSentinel -PathType Leaf
    if ($detachedSentinelObserved) {
        Add-Failure 'Expected parent-first exit cleanup to kill the grandchild before its delayed sentinel write.'
    }
    if (Test-NativePosixSessionEvidenceReady `
            -RuntimeIsWindows $runtimeIsWindows `
            -Result $detachedResult `
            -GrandchildPayloadStarted $detachedGrandchildStartedObserved `
            -DelayedSentinelObserved $detachedSentinelObserved `
            -NoNewFailures:(
                $failures.Count -eq $nativeGateFailureCountBefore
            )) {
        Write-Host (
            'POSIX native session gate evidence: forced libc setsid(2) ' +
            'passed; external setsid selection bypassed.'
        )
    }

    # Repeat the zero-wait spawn pattern so the Windows launch gate and POSIX
    # process group prove the race is closed rather than merely becoming rare.
    $immediateRaceSentinels =
        New-Object System.Collections.Generic.List[string]
    for ($raceAttempt = 1; $raceAttempt -le 10; $raceAttempt++) {
        $raceSentinel = Join-Path `
            $tempRoot `
            "immediate-grandchild-survived-$raceAttempt"
        $immediateRaceSentinels.Add($raceSentinel) | Out-Null
        $escapedRaceSentinel = $raceSentinel.Replace("'", "''")
        $raceGrandchildScript = @"
Start-Sleep -Milliseconds 1000
[IO.File]::WriteAllText('$escapedRaceSentinel', 'survived')
"@
        $raceGrandchildEncoded = [Convert]::ToBase64String(
            [Text.Encoding]::Unicode.GetBytes($raceGrandchildScript)
        )
        $raceParentScript = @"
`$startInfo = New-Object Diagnostics.ProcessStartInfo
`$startInfo.FileName = '$escapedPowerShellExecutable'
`$startInfo.Arguments = '-NoProfile -EncodedCommand $raceGrandchildEncoded'
`$startInfo.UseShellExecute = `$false
`$startInfo.CreateNoWindow = `$true
`$child = [Diagnostics.Process]::Start(`$startInfo)
`$child.Dispose()
"@
        $raceParentEncoded = [Convert]::ToBase64String(
            [Text.Encoding]::Unicode.GetBytes($raceParentScript)
        )
        $raceArguments = @('-NoProfile')
        if ($PSVersionTable.PSVersion.Major -le 5 -and
            $runtimeIsWindows) {
            $raceArguments += @('-ExecutionPolicy', 'Bypass')
        }
        $raceArguments += @('-EncodedCommand', $raceParentEncoded)
        # Starting three PowerShell processes (gate, parent, grandchild) can
        # exceed five seconds on a loaded Windows host. The containment claim is
        # the zero-wait spawn plus sentinel suppression, so keep a wider but
        # still finite launch budget to avoid converting scheduler delay into a
        # false security failure.
        $raceResult = Invoke-PrivateMarkerBoundedProcess `
            -FileName $currentPowerShellExecutable `
            -Arguments $raceArguments `
            -IsolationRoot (
                Join-Path $tempRoot "immediate-race-isolation-$raceAttempt"
            ) `
            -TimeoutMilliseconds 10000 `
            -DrainTimeoutMilliseconds 3000 `
            -ForceNativePosixSessionGate:(
                -not $runtimeIsWindows -and $raceAttempt -eq 1
            )
        if ($raceResult.TimedOut -or
            -not $raceResult.TreeStopped -or
            -not $raceResult.StreamsDrained -or
            ($runtimeIsWindows -and $raceResult.ExitCode -ne 125) -or
            (-not $runtimeIsWindows -and $raceResult.ExitCode -ne 0)) {
            Add-Failure (
                "Expected immediate-spawn race attempt $raceAttempt to stop " +
                'its full process tree ' +
                "(exit $($raceResult.ExitCode), timeout " +
                "$($raceResult.TimedOut), tree " +
                "$($raceResult.TreeStopped), streams " +
                "$($raceResult.StreamsDrained))."
            )
        }
    }
    Start-Sleep -Milliseconds 1300
    foreach ($raceSentinel in $immediateRaceSentinels) {
        if (Test-Path -LiteralPath $raceSentinel) {
            Add-Failure 'Expected all 10 immediate-spawn process-tree attempts to suppress delayed sentinels.'
            break
        }
    }
    if (-not $runtimeIsWindows) {
        # kill(2) returns -1 for both ESRCH and EPERM. Only ESRCH is a
        # successful "already gone" cleanup state; permission and other
        # failures must keep TreeStopped false.
        if (-not [AgentHandoffDocs.PrivateMarkerPosixSignal]::
                IsSuccessfulResult(0, 0) -or
            -not [AgentHandoffDocs.PrivateMarkerPosixSignal]::
                IsSuccessfulResult(-1, 3) -or
            [AgentHandoffDocs.PrivateMarkerPosixSignal]::
                IsSuccessfulResult(-1, 1) -or
            [AgentHandoffDocs.PrivateMarkerPosixSignal]::
                IsSuccessfulResult(-1, 13)) {
            Add-Failure 'Expected POSIX group cleanup to accept success/ESRCH and reject EPERM/EACCES.'
        }
    }

    # The raw budget includes every serialized byte, including a visible prefix
    # and the platform's real newline (CRLF on Windows, LF on POSIX).
    $exactBudgetScript = @'
$prefixBytes = [System.Text.Encoding]::UTF8.GetBytes('scan-prefix:')
$newlineBytes = [System.Text.Encoding]::UTF8.GetBytes([Environment]::NewLine)
$fillLength = 128 - $prefixBytes.Length - $newlineBytes.Length
$fillBytes = [System.Text.Encoding]::UTF8.GetBytes(('x' * $fillLength))
$stream = [Console]::OpenStandardOutput()
$stream.Write($prefixBytes, 0, $prefixBytes.Length)
$stream.Write($fillBytes, 0, $fillBytes.Length)
$stream.Write($newlineBytes, 0, $newlineBytes.Length)
$stream.Flush()
'@
    $exactBudgetEncoded = [Convert]::ToBase64String(
        [System.Text.Encoding]::Unicode.GetBytes($exactBudgetScript)
    )
    $exactBudgetArguments = @('-NoProfile')
    if ($PSVersionTable.PSVersion.Major -le 5 -and $runtimeIsWindows) {
        $exactBudgetArguments += @('-ExecutionPolicy', 'Bypass')
    }
    $exactBudgetArguments += @('-EncodedCommand', $exactBudgetEncoded)
    $exactBudgetResult = Invoke-PrivateMarkerBoundedProcess `
        -FileName $currentPowerShellExecutable `
        -Arguments $exactBudgetArguments `
        -IsolationRoot (Join-Path $tempRoot 'exact-budget-isolation') `
        -TimeoutMilliseconds 5000 `
        -MaxStdoutBytes 128 `
        -MaxStderrBytes 65536
    if (-not (Test-BoundedResultHealthy -Result $exactBudgetResult) -or
        $exactBudgetResult.ExitCode -ne 0 -or
        $exactBudgetResult.StdoutBytes.Length -ne 128) {
        Add-Failure 'Expected prefix plus the platform newline to fit an exact 128-byte raw stdout budget.'
    }

    # A child that floods stdout must be stopped by the byte cap before the
    # runtime timeout, and retained output must never exceed the configured cap.
    $limitScript = @'
[Console]::Out.Write(('x' * 4096))
Start-Sleep -Seconds 30
'@
    $limitEncoded = [Convert]::ToBase64String(
        [System.Text.Encoding]::Unicode.GetBytes($limitScript)
    )
    $limitArguments = @('-NoProfile')
    if ($PSVersionTable.PSVersion.Major -le 5 -and $runtimeIsWindows) {
        $limitArguments += @('-ExecutionPolicy', 'Bypass')
    }
    $limitArguments += @('-EncodedCommand', $limitEncoded)
    $limitResult = Invoke-PrivateMarkerBoundedProcess `
        -FileName $currentPowerShellExecutable `
        -Arguments $limitArguments `
        -IsolationRoot (Join-Path $tempRoot 'limit-isolation') `
        -TimeoutMilliseconds 5000 `
        -MaxStdoutBytes 128 `
        -MaxStderrBytes 128
    if (-not $limitResult.OutputLimitExceeded -or
        $limitResult.TimedOut -or
        -not $limitResult.TreeStopped -or
        -not $limitResult.StreamsDrained -or
        $limitResult.StdoutBytes.Length -gt 128) {
        Add-Failure 'Expected stdout byte overflow to stop the child tree and stay within the configured output cap.'
    }

    # Prove the child-only Git boundary disables replace refs, lazy object
    # fetching, and all transport protocols even when the caller asks for the
    # opposite. The probe emits booleans only; it never prints ambient values.
    $gitBoundaryScript = @'
$protocolDenied = $false
for ($index = 0; $index -lt [int]$env:GIT_CONFIG_COUNT; $index++) {
    if ([Environment]::GetEnvironmentVariable("GIT_CONFIG_KEY_$index") -eq 'protocol.allow' -and
        [Environment]::GetEnvironmentVariable("GIT_CONFIG_VALUE_$index") -eq 'never') {
        $protocolDenied = $true
    }
}
[Console]::Out.Write(
    (($env:GIT_NO_REPLACE_OBJECTS -eq '1').ToString()) + '|' +
    (($env:GIT_NO_LAZY_FETCH -eq '1').ToString()) + '|' +
    $protocolDenied.ToString()
)
'@
    $gitBoundaryEncoded = [Convert]::ToBase64String(
        [System.Text.Encoding]::Unicode.GetBytes($gitBoundaryScript)
    )
    $gitBoundaryArguments = @('-NoProfile')
    if ($PSVersionTable.PSVersion.Major -le 5 -and $runtimeIsWindows) {
        $gitBoundaryArguments += @('-ExecutionPolicy', 'Bypass')
    }
    $gitBoundaryArguments += @('-EncodedCommand', $gitBoundaryEncoded)
    $gitBoundaryResult = Invoke-PrivateMarkerBoundedProcess `
        -FileName $currentPowerShellExecutable `
        -Arguments $gitBoundaryArguments `
        -IsolationRoot (Join-Path $tempRoot 'git-boundary-isolation') `
        -InheritedEnvironment @{
            GIT_NO_REPLACE_OBJECTS = '0'
            GIT_NO_LAZY_FETCH = '0'
        } `
        -TimeoutMilliseconds 5000 `
        -MaxStdoutBytes 128 `
        -MaxStderrBytes 65536
    $gitBoundaryText = [Text.Encoding]::UTF8.GetString(
        $gitBoundaryResult.StdoutBytes
    )
    if (-not (Test-BoundedResultHealthy -Result $gitBoundaryResult) -or
        $gitBoundaryResult.ExitCode -ne 0 -or
        $gitBoundaryText -ne 'True|True|True') {
        Add-Failure "Expected the child-only Git environment to disable replace refs, lazy fetch, and protocols (exit $($gitBoundaryResult.ExitCode), stdout '$gitBoundaryText', timeout $($gitBoundaryResult.TimedOut), limit $($gitBoundaryResult.OutputLimitExceeded), tree $($gitBoundaryResult.TreeStopped), streams $($gitBoundaryResult.StreamsDrained))."
    }

    if ($runtimeIsWindows) {
        # The trusted gate wrapper waits before doing anything except opening
        # its named event. After release, the actual requested target must
        # inherit the assigned Job; verify that identity inside the target.
        $jobIdentityScript = @'
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class SyntheticJobIdentityProbe
{
    [DllImport("kernel32.dll")]
    private static extern IntPtr GetCurrentProcess();
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool IsProcessInJob(
        IntPtr process,
        IntPtr job,
        out bool result
    );
    public static bool IsInJob()
    {
        bool result;
        return IsProcessInJob(
            GetCurrentProcess(),
            IntPtr.Zero,
            out result
        ) && result;
    }
}
"@
[Console]::Out.Write(
    [SyntheticJobIdentityProbe]::IsInJob().ToString()
)
'@
        $jobIdentityEncoded = [Convert]::ToBase64String(
            [Text.Encoding]::Unicode.GetBytes($jobIdentityScript)
        )
        $jobIdentityResult = Invoke-PrivateMarkerBoundedProcess `
            -FileName $currentPowerShellExecutable `
            -Arguments @(
                '-NoProfile',
                '-ExecutionPolicy',
                'Bypass',
                '-EncodedCommand',
                $jobIdentityEncoded
            ) `
            -IsolationRoot (Join-Path $tempRoot 'job-identity-isolation') `
            -TimeoutMilliseconds 10000 `
            -MaxStdoutBytes 64 `
            -MaxStderrBytes 65536
        $jobIdentityText = [Text.Encoding]::UTF8.GetString(
            $jobIdentityResult.StdoutBytes
        )
        if (-not (Test-BoundedResultHealthy -Result $jobIdentityResult) -or
            $jobIdentityResult.ExitCode -ne 0 -or
            $jobIdentityText -ne 'True') {
            Add-Failure "Expected the actual gated target process to inherit the assigned Windows Job (exit $($jobIdentityResult.ExitCode), stdout '$jobIdentityText', timeout $($jobIdentityResult.TimedOut), limit $($jobIdentityResult.OutputLimitExceeded), tree $($jobIdentityResult.TreeStopped), streams $($jobIdentityResult.StreamsDrained))."
        }
    }

    # The ambient OS variable is untrusted. A fresh child must derive the same
    # kernel branch from .NET even when OS is forged to the opposite platform.
    $forgedOsValue = if ($runtimeIsWindows) {
        'synthetic-posix'
    } else {
        'Windows_NT'
    }
    $escapedProcessSupport = $processSupport.Replace("'", "''")
    $platformProbeScript = @"
. '$escapedProcessSupport'
[Console]::Out.Write(
    `$script:privateMarkerIsWindows.ToString()
)
"@
    $platformProbeEncoded = [Convert]::ToBase64String(
        [Text.Encoding]::Unicode.GetBytes($platformProbeScript)
    )
    $platformProbeArguments = @('-NoProfile')
    if ($PSVersionTable.PSVersion.Major -le 5 -and $runtimeIsWindows) {
        $platformProbeArguments += @('-ExecutionPolicy', 'Bypass')
    }
    $platformProbeArguments += @(
        '-EncodedCommand',
        $platformProbeEncoded
    )
    $platformProbeResult = Invoke-PrivateMarkerBoundedProcess `
        -FileName $currentPowerShellExecutable `
        -Arguments $platformProbeArguments `
        -IsolationRoot (Join-Path `
            $tempRoot `
            'platform-probe-isolation') `
        -InheritedEnvironment @{ OS = $forgedOsValue } `
        -TimeoutMilliseconds 10000 `
        -MaxStdoutBytes 32 `
        -MaxStderrBytes 65536
    $platformProbeText = [Text.Encoding]::UTF8.GetString(
        $platformProbeResult.StdoutBytes
    )
    if (-not (Test-BoundedResultHealthy -Result $platformProbeResult) -or
        $platformProbeResult.ExitCode -ne 0 -or
        $platformProbeText -ne $runtimeIsWindows.ToString()) {
        Add-Failure "Expected runtime platform detection to ignore a forged OS variable (exit $($platformProbeResult.ExitCode), stdout '$platformProbeText')."
    }

    # The spaced directory also exercises the PS5.1 native argument fallback.
    $cleanRoot = Join-Path $tempRoot 'clean fixture'
    New-Item -ItemType Directory -Path $cleanRoot | Out-Null
    Set-Content -LiteralPath (Join-Path $cleanRoot 'README.md') -Value @(
        '# Clean synthetic fixture'
        'A completion notice is a claim, not evidence. Verify artifacts first.'
    ) -Encoding UTF8

    $cleanResult = Invoke-Scanner -ScanPath $cleanRoot
    if ($cleanResult.ExitCode -ne 0) {
        Add-Failure "Expected clean fixture to pass, but scanner exited $($cleanResult.ExitCode): $($cleanResult.Output.Trim())"
    }

    # A hostile nonexistent path must fail with a fixed diagnostic. Neither the
    # raw path nor Unicode direction/line controls may reach stdout or stderr.
    $hostileDirectionControl = [char]0x202E
    $hostileLineSeparator = [char]0x2028
    $hostileMissingPath = Join-Path $tempRoot (
        'missing-' + $hostileDirectionControl + $hostileLineSeparator + 'leaf'
    )
    $hostileMissingResult = Invoke-Scanner `
        -ScanPath $hostileMissingPath `
        -MaxStdoutBytes 256 `
        -MaxStderrBytes 65536
    $hostileMissingStdout = [System.Text.Encoding]::UTF8.GetString(
        $hostileMissingResult.StdoutBytes
    )
    $hostileMissingStderr = [System.Text.Encoding]::UTF8.GetString(
        $hostileMissingResult.StderrBytes
    )
    $hostileMissingDiagnostic = $hostileMissingStdout.TrimEnd(
        [char[]]@(13, 10)
    )
    if (-not (Test-BoundedResultHealthy -Result $hostileMissingResult) -or
        $hostileMissingResult.ExitCode -ne 2 -or
        $hostileMissingDiagnostic -ne
            'Private marker scan failed closed (integrity: scan-root-missing).' -or
        $hostileMissingResult.StdoutBytes.Length -gt 256 -or
        $hostileMissingResult.StderrBytes.Length -gt 65536 -or
        $hostileMissingStdout.Contains($hostileMissingPath) -or
        $hostileMissingStderr.Contains($hostileMissingPath) -or
        $hostileMissingStdout.Contains([string]$hostileDirectionControl) -or
        $hostileMissingStderr.Contains([string]$hostileDirectionControl) -or
        $hostileMissingStdout.Contains([string]$hostileLineSeparator) -or
        $hostileMissingStderr.Contains([string]$hostileLineSeparator)) {
        Add-Failure 'Expected a hostile nonexistent path to produce only the bounded fixed scan-root-missing diagnostic.'
    }

    $forgedOsScannerResult = Invoke-Scanner `
        -ScanPath $cleanRoot `
        -InheritedEnvironment @{ OS = $forgedOsValue }
    if ($forgedOsScannerResult.ExitCode -ne 0) {
        Add-Failure "Expected scanner platform selection to ignore a forged OS variable. Output: $($forgedOsScannerResult.Output.Trim())"
    }

    $markerRoot = Join-Path $tempRoot 'marker'
    New-Item -ItemType Directory -Path $markerRoot | Out-Null
    $syntheticMarker = ('g' + 'hp_') + 'synthetic_placeholder_only'
    Set-Content -LiteralPath (Join-Path $markerRoot 'leak.txt') -Value "synthetic marker: $syntheticMarker" -Encoding UTF8

    $markerResult = Invoke-Scanner -ScanPath $markerRoot
    if ($markerResult.ExitCode -eq 0) {
        Add-Failure 'Expected synthetic marker fixture to fail, but scanner exited 0.'
    }
    if ($markerResult.Output -notmatch 'github-classic-token-prefix') {
        Add-Failure "Expected synthetic marker output to name github-classic-token-prefix. Output: $($markerResult.Output.Trim())"
    }

    # Encoding regression: a marker directly after a multi-byte character must
    # still be detected when the scanner runs under Windows PowerShell 5.1.
    # Without an explicit UTF-8 read, 5.1 decodes BOM-less UTF-8 as ANSI and a
    # misread multi-byte character swallows the following ASCII bytes
    # (measured false negative). The fixture is written BOM-less on purpose;
    # the character is built from a code point to keep this file ASCII-only.
    $encodingRoot = Join-Path $tempRoot 'multibyte-adjacent'
    New-Item -ItemType Directory -Path $encodingRoot | Out-Null
    $multiByteContent = 'token after multi-byte char: ' + [char]0x3042 + $syntheticMarker
    [System.IO.File]::WriteAllText((Join-Path $encodingRoot 'leak.md'), $multiByteContent, [System.Text.UTF8Encoding]::new($false))
    $encodingResult = Invoke-Scanner -ScanPath $encodingRoot
    if ($encodingResult.ExitCode -eq 0) {
        Add-Failure 'Expected multi-byte-adjacent marker fixture to fail, but scanner exited 0.'
    }
    if ($encodingResult.Output -notmatch 'github-classic-token-prefix') {
        Add-Failure "Expected multi-byte-adjacent output to name github-classic-token-prefix. Output: $($encodingResult.Output.Trim())"
    }

    # Dotfiles such as .env are "all extension" to GetExtension and were once
    # silently skipped; on POSIX they are also hidden from enumeration unless
    # -Force is used. This non-git fixture fixes the working-tree contract.
    $dotfileRoot = Join-Path $tempRoot 'dotfile'
    New-Item -ItemType Directory -Path $dotfileRoot | Out-Null
    Set-Content -LiteralPath (Join-Path $dotfileRoot '.env') -Value "value: $syntheticMarker" -Encoding UTF8
    $dotfileResult = Invoke-Scanner -ScanPath $dotfileRoot
    if ($dotfileResult.Output -notmatch 'working-tree') {
        Add-Failure "Expected .env fixture to use working-tree mode. Output: $($dotfileResult.Output.Trim())"
    }
    if ($dotfileResult.ExitCode -eq 0) {
        Add-Failure 'Expected .env dotfile fixture to fail, but scanner exited 0.'
    }
    if ($dotfileResult.Output -notmatch 'github-classic-token-prefix') {
        Add-Failure "Expected .env dotfile output to name github-classic-token-prefix. Output: $($dotfileResult.Output.Trim())"
    }
    if ($dotfileResult.Output -notmatch '\.env') {
        Add-Failure "Expected .env dotfile output to name .env. Output: $($dotfileResult.Output.Trim())"
    }
    if ($dotfileResult.Output.Contains($syntheticMarker)) {
        Add-Failure 'Expected .env dotfile finding to stay redacted, but the raw marker leaked into output.'
    }

    # The working-tree fallback must use POSIX-aware exclusion boundaries and
    # emit a normalized relative path. A real finding outside excluded trees
    # proves the scan ran; marker files inside those trees must remain absent.
    $boundaryRoot = Join-Path $tempRoot 'working-tree-boundaries'
    $boundaryLeakDirectory = Join-Path $boundaryRoot (Join-Path 'nested' 'deep')
    New-Item -ItemType Directory -Path $boundaryLeakDirectory -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $boundaryLeakDirectory 'leak.md') -Value "value: $syntheticMarker" -Encoding UTF8

    foreach ($excludedDirectoryName in @('node_modules', '.cache')) {
        $excludedDirectory = Join-Path $boundaryRoot $excludedDirectoryName
        New-Item -ItemType Directory -Path $excludedDirectory -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $excludedDirectory 'ignored.md') -Value "value: $syntheticMarker" -Encoding UTF8
    }
    $nestedGitDirectory = Join-Path $boundaryRoot (Join-Path 'neutral' '.git')
    New-Item -ItemType Directory -Path $nestedGitDirectory -Force | Out-Null
    Set-Content `
        -LiteralPath (Join-Path $nestedGitDirectory 'ignored.md') `
        -Value "value: $syntheticMarker" `
        -Encoding UTF8
    $nestedGitFileDirectory = Join-Path $boundaryRoot 'neutral-file'
    New-Item `
        -ItemType Directory `
        -Path $nestedGitFileDirectory `
        -Force | Out-Null
    $nestedGitFileMarker = ('g' + 'hp_') +
        'synthetic_nested_git_file'
    Set-Content `
        -LiteralPath (Join-Path $nestedGitFileDirectory '.git') `
        -Value "gitdir: $nestedGitFileMarker" `
        -Encoding UTF8

    $boundaryResult = Invoke-Scanner -ScanPath $boundaryRoot
    if ($boundaryResult.Output -notmatch 'working-tree') {
        Add-Failure "Expected exclusion fixture to use working-tree mode. Output: $($boundaryResult.Output.Trim())"
    }
    if ($boundaryResult.ExitCode -eq 0) {
        Add-Failure 'Expected the non-excluded nested marker to fail the working-tree scan, but scanner exited 0.'
    }
    if ($boundaryResult.Output -notmatch 'nested/deep/leak\.md') {
        Add-Failure "Expected normalized relative path nested/deep/leak.md. Output: $($boundaryResult.Output.Trim())"
    }
    if ($boundaryResult.Output.Contains($boundaryRoot)) {
        Add-Failure "Expected working-tree findings to omit the absolute fixture root. Output: $($boundaryResult.Output.Trim())"
    }
    if ($boundaryResult.Output -match
        '(node_modules|\.cache|\.git)[\\/]ignored\.md' -or
        $boundaryResult.Output -match 'neutral-file[\\/]\.git') {
        Add-Failure "Expected nested .git files/directories, node_modules, and .cache marker files to stay excluded. Output: $($boundaryResult.Output.Trim())"
    }

    # A non-repository fallback that contains root-level Git metadata is
    # ambiguous/corrupt and must fail closed instead of excluding .git and
    # reporting a misleading clean working-tree result.
    $metadataRoot = Join-Path $tempRoot 'invalid-git-metadata'
    New-Item -ItemType Directory -Path (Join-Path $metadataRoot '.git') -Force |
        Out-Null
    Set-Content `
        -LiteralPath (Join-Path $metadataRoot 'README.md') `
        -Value 'synthetic clean content' `
        -Encoding UTF8
    $metadataResult = Invoke-Scanner -ScanPath $metadataRoot
    if ($metadataResult.ExitCode -ne 2 -or
        $metadataResult.Output -notmatch 'integrity: git-probe') {
        Add-Failure "Expected invalid root Git metadata to fail closed. Output: $($metadataResult.Output.Trim())"
    }

    # Higher-recall cloud / PEM prefixes, with one redaction regression each.
    # Fixtures are synthetic placeholders only; no real secrets are used.
    $prefixCases = @(
        @{ Rule = 'openai-api-key-prefix';            Marker = ('s' + 'k-') + 'SyntheticOpenAI000000000000' }
        @{ Rule = 'aws-access-key-id';                Marker = ('A' + 'KIA') + 'EXAMPLE0000000000000' }
        @{ Rule = 'gcp-api-key-prefix';               Marker = ('AIza') + 'Synthetic0000000000000000000000000000' }
        @{ Rule = 'slack-user-token-prefix';          Marker = ('xo' + 'xp-') + 'synthetic-placeholder' }
        @{ Rule = 'slack-legacy-app-token-prefix';    Marker = ('xo' + 'xa-') + 'synthetic-placeholder' }
        @{ Rule = 'slack-app-level-token-prefix';     Marker = ('xa' + 'pp-') + 'synthetic-placeholder' }
        @{ Rule = 'stripe-live-secret-key';           Marker = ('s' + 'k') + '_live_SyntheticPlaceholder0000' }
        @{ Rule = 'pem-private-key-block';            Marker = '-----' + ('BEGIN ' + 'OPENSSH PRIVATE KEY') + '-----' }
    )

    foreach ($case in $prefixCases) {
        $prefixRoot = Join-Path $tempRoot ('prefix-' + $case.Rule)
        New-Item -ItemType Directory -Path $prefixRoot | Out-Null
        Set-Content -LiteralPath (Join-Path $prefixRoot 'leak.txt') -Value "synthetic marker: $($case.Marker)" -Encoding UTF8

        $prefixResult = Invoke-Scanner -ScanPath $prefixRoot
        if ($prefixResult.ExitCode -eq 0) {
            Add-Failure "Expected $($case.Rule) fixture to fail, but scanner exited 0."
        }
        if ($prefixResult.Output -notmatch [regex]::Escape($case.Rule)) {
            Add-Failure "Expected output to name $($case.Rule). Output: $($prefixResult.Output.Trim())"
        }
        # Preserve redaction: the raw marker value must never appear in output.
        if ($prefixResult.Output.Contains($case.Marker)) {
            Add-Failure "Expected $($case.Rule) finding to be redacted, but the raw marker leaked into output."
        }
        if ($prefixResult.Output -notmatch '<redacted>') {
            Add-Failure "Expected $($case.Rule) finding to report '<redacted>'. Output: $($prefixResult.Output.Trim())"
        }
    }

    # windows-absolute-path: private-looking paths should be findings.
    # Split the literal so this test file does not make the scanner flag itself.
    $winPathRealRoot = Join-Path $tempRoot 'winpath-real'
    New-Item -ItemType Directory -Path $winPathRealRoot | Out-Null
    $realWinPath = 'C' + ':\Users\realperson\Secrets\config'
    Set-Content -LiteralPath (Join-Path $winPathRealRoot 'doc.md') -Value "See $realWinPath for details." -Encoding UTF8
    $winPathRealResult = Invoke-Scanner -ScanPath $winPathRealRoot
    if ($winPathRealResult.ExitCode -eq 0) {
        Add-Failure 'Expected real-looking Windows path fixture to fail, but scanner exited 0.'
    }
    if ($winPathRealResult.Output -notmatch 'windows-absolute-path') {
        Add-Failure "Expected real Windows path output to name windows-absolute-path. Output: $($winPathRealResult.Output.Trim())"
    }

    # windows-absolute-path: documented placeholders should not be findings.
    $winPathDocRoot = Join-Path $tempRoot 'winpath-doc'
    New-Item -ItemType Directory -Path $winPathDocRoot | Out-Null
    Set-Content -LiteralPath (Join-Path $winPathDocRoot 'doc.md') -Value @'
Use a placeholder path such as C:\path\to\repo in examples.
You can also write C:\Users\<name>\project to describe a user directory.
'@ -Encoding UTF8
    $winPathDocResult = Invoke-Scanner -ScanPath $winPathDocRoot
    if ($winPathDocResult.ExitCode -ne 0) {
        Add-Failure "Expected placeholder Windows path doc to pass, but scanner exited $($winPathDocResult.ExitCode): $($winPathDocResult.Output.Trim())"
    }

    # Sibling-skill URL allowlist: the related-skills link must pass, and any
    # other repository URL must stay a finding. URLs are assembled from parts
    # so the fixtures do not add allowlisted-looking literals to this file.
    $urlBase = 'https://' + 'github.com/'
    $allowedUrlRoot = Join-Path $tempRoot 'url-allowed'
    New-Item -ItemType Directory -Path $allowedUrlRoot | Out-Null
    $allowedUrl = $urlBase + 'h8nc4y/' + 'multi-agent-delegation'
    Set-Content -LiteralPath (Join-Path $allowedUrlRoot 'doc.md') -Value "Related: $allowedUrl" -Encoding UTF8
    $allowedUrlResult = Invoke-Scanner -ScanPath $allowedUrlRoot
    if ($allowedUrlResult.ExitCode -ne 0) {
        Add-Failure "Expected allowlisted sibling URL to pass, but scanner exited $($allowedUrlResult.ExitCode): $($allowedUrlResult.Output.Trim())"
    }

    $foreignUrlRoot = Join-Path $tempRoot 'url-foreign'
    New-Item -ItemType Directory -Path $foreignUrlRoot | Out-Null
    $foreignUrl = $urlBase + 'someone-else/private-repo-name'
    Set-Content -LiteralPath (Join-Path $foreignUrlRoot 'doc.md') -Value "See $foreignUrl" -Encoding UTF8
    $foreignUrlResult = Invoke-Scanner -ScanPath $foreignUrlRoot
    if ($foreignUrlResult.ExitCode -eq 0) {
        Add-Failure 'Expected non-allowlisted repository URL to fail, but scanner exited 0.'
    }
    if ($foreignUrlResult.Output -notmatch 'non-allowlisted-github-repo-url') {
        Add-Failure "Expected foreign URL output to name non-allowlisted-github-repo-url. Output: $($foreignUrlResult.Output.Trim())"
    }

    # A marker-dense line must retain a bounded useful report rather than
    # allocating or emitting one row for every URL.
    $denseUrlRoot = Join-Path $tempRoot 'url-dense'
    New-Item -ItemType Directory -Path $denseUrlRoot | Out-Null
    $denseUrls = 1..150 | ForEach-Object {
        $urlBase + "synthetic-owner/synthetic-repo-$_"
    }
    [IO.File]::WriteAllText(
        (Join-Path $denseUrlRoot 'dense.md'),
        ($denseUrls -join ' '),
        [Text.UTF8Encoding]::new($false)
    )
    $denseUrlResult = Invoke-Scanner -ScanPath $denseUrlRoot
    if ($denseUrlResult.ExitCode -eq 0 -or
        $denseUrlResult.OutputLimitExceeded -or
        $denseUrlResult.Output -notmatch
        'Additional findings omitted after 100 entries\.') {
        Add-Failure "Expected dense URL findings to fail with a bounded truncation notice. Output: $($denseUrlResult.Output.Trim())"
    }

    # Exercise production budget branches with lower constants in a disposable
    # scanner copy. This keeps the fixture fast while proving that zero-byte
    # files, non-text entries, line objects, and allowlisted regex matches all
    # have independent finite caps.
    $budgetScannerDirectory = Join-Path $tempRoot 'budget-scanner'
    New-Item `
        -ItemType Directory `
        -Path $budgetScannerDirectory `
        -Force | Out-Null
    $budgetScanner = Join-Path `
        $budgetScannerDirectory `
        'scan-private-markers.ps1'
    Copy-Item `
        -LiteralPath $processSupport `
        -Destination (Join-Path `
            $budgetScannerDirectory `
            'private-marker-process.ps1')
    $budgetScannerSource = [IO.File]::ReadAllText($scanner)
    $budgetReplacements = [ordered]@{
        '$maxScanTargets = 8192' = '$maxScanTargets = 4'
        '$maxWorkingTreeEntries = 32768' =
            '$maxWorkingTreeEntries = 5'
        '$maxScanLines = 1000000' = '$maxScanLines = 3'
        '$maxRegexMatches = 100000' = '$maxRegexMatches = 5'
        '$maxLocalMarkerBytes = 262144' =
            '$maxLocalMarkerBytes = 64'
        '$maxLocalMarkers = 256' = '$maxLocalMarkers = 2'
        '$maxLocalMarkerCharacters = 4096' =
            '$maxLocalMarkerCharacters = 8'
    }
    foreach ($budgetNeedle in $budgetReplacements.Keys) {
        if (-not $budgetScannerSource.Contains($budgetNeedle)) {
            throw "Cannot locate scanner budget constant: $budgetNeedle"
        }
        $budgetScannerSource = $budgetScannerSource.Replace(
            $budgetNeedle,
            $budgetReplacements[$budgetNeedle]
        )
    }
    [IO.File]::WriteAllText(
        $budgetScanner,
        $budgetScannerSource,
        [Text.UTF8Encoding]::new($false)
    )
    $originalScanner = $scanner
    try {
        $scanner = $budgetScanner

        $zeroTargetRoot = Join-Path $tempRoot 'zero-target-budget'
        New-Item -ItemType Directory -Path $zeroTargetRoot | Out-Null
        1..5 | ForEach-Object {
            [IO.File]::WriteAllBytes(
                (Join-Path $zeroTargetRoot "empty-$_.md"),
                [byte[]]@()
            )
        }
        $zeroTargetResult = Invoke-Scanner -ScanPath $zeroTargetRoot
        if ($zeroTargetResult.ExitCode -ne 2 -or
            $zeroTargetResult.Output -notmatch
            'integrity: scan-target-count') {
            Add-Failure "Expected zero-byte target count to fail closed at its budget. Output: $($zeroTargetResult.Output.Trim())"
        }

        $entryBudgetRoot = Join-Path $tempRoot 'entry-budget'
        New-Item -ItemType Directory -Path $entryBudgetRoot | Out-Null
        1..6 | ForEach-Object {
            [IO.File]::WriteAllBytes(
                (Join-Path $entryBudgetRoot "binary-$_.bin"),
                [byte[]]@(0)
            )
        }
        $entryBudgetResult = Invoke-Scanner -ScanPath $entryBudgetRoot
        if ($entryBudgetResult.ExitCode -ne 2 -or
            $entryBudgetResult.Output -notmatch
            'integrity: working-tree-entry-budget') {
            Add-Failure "Expected fallback entry enumeration to fail closed at its budget. Output: $($entryBudgetResult.Output.Trim())"
        }

        $lineBudgetRoot = Join-Path $tempRoot 'line-budget'
        New-Item -ItemType Directory -Path $lineBudgetRoot | Out-Null
        [IO.File]::WriteAllText(
            (Join-Path $lineBudgetRoot 'lines.md'),
            "one`ntwo`nthree`nfour",
            [Text.UTF8Encoding]::new($false)
        )
        $lineBudgetResult = Invoke-Scanner -ScanPath $lineBudgetRoot
        if ($lineBudgetResult.ExitCode -ne 2 -or
            $lineBudgetResult.Output -notmatch
            'integrity: scan-line-budget') {
            Add-Failure "Expected streaming line scan to fail closed at its budget. Output: $($lineBudgetResult.Output.Trim())"
        }

        $regexBudgetRoot = Join-Path $tempRoot 'regex-budget'
        New-Item -ItemType Directory -Path $regexBudgetRoot | Out-Null
        $allowedBudgetUrl = $urlBase +
            'h8nc4y/multi-agent-delegation'
        [IO.File]::WriteAllText(
            (Join-Path $regexBudgetRoot 'urls.md'),
            ((1..6 | ForEach-Object { $allowedBudgetUrl }) -join ' '),
            [Text.UTF8Encoding]::new($false)
        )
        $regexBudgetResult = Invoke-Scanner -ScanPath $regexBudgetRoot
        if ($regexBudgetResult.ExitCode -ne 2 -or
            $regexBudgetResult.Output -notmatch
            'integrity: scan-regex-match-budget') {
            Add-Failure "Expected lazy regex matching to fail closed at its budget. Output: $($regexBudgetResult.Output.Trim())"
        }

        $markerCountBudgetRoot = Join-Path `
            $tempRoot `
            'marker-count-budget'
        New-Item `
            -ItemType Directory `
            -Path $markerCountBudgetRoot | Out-Null
        $markerCountBudgetResult = Invoke-Scanner `
            -ScanPath $markerCountBudgetRoot `
            -InheritedEnvironment @{
                AGENT_HANDOFF_DOCS_PRIVATE_MARKERS =
                    "one`ntwo`nthree"
            }
        if ($markerCountBudgetResult.ExitCode -ne 2 -or
            $markerCountBudgetResult.Output -notmatch
            'integrity: local-marker-count') {
            Add-Failure "Expected streaming environment markers to fail closed at their count budget. Output: $($markerCountBudgetResult.Output.Trim())"
        }

        $markerLengthBudgetRoot = Join-Path `
            $tempRoot `
            'marker-length-budget'
        New-Item `
            -ItemType Directory `
            -Path $markerLengthBudgetRoot | Out-Null
        $markerLengthBudgetResult = Invoke-Scanner `
            -ScanPath $markerLengthBudgetRoot `
            -InheritedEnvironment @{
                AGENT_HANDOFF_DOCS_PRIVATE_MARKERS = '123456789'
            }
        if ($markerLengthBudgetResult.ExitCode -ne 2 -or
            $markerLengthBudgetResult.Output -notmatch
            'integrity: local-marker-length') {
            Add-Failure "Expected one local marker to fail closed at its character budget. Output: $($markerLengthBudgetResult.Output.Trim())"
        }

        $markerSizeBudgetRoot = Join-Path `
            $tempRoot `
            'marker-size-budget'
        New-Item `
            -ItemType Directory `
            -Path $markerSizeBudgetRoot | Out-Null
        [IO.File]::WriteAllText(
            (Join-Path `
                $markerSizeBudgetRoot `
                '.private-markers.local'),
            ('x' * 65),
            [Text.UTF8Encoding]::new($false)
        )
        $markerSizeBudgetResult = Invoke-Scanner `
            -ScanPath $markerSizeBudgetRoot
        if ($markerSizeBudgetResult.ExitCode -ne 2 -or
            $markerSizeBudgetResult.Output -notmatch
            'integrity: local-marker-type') {
            Add-Failure "Expected local marker bytes to fail closed at their size budget. Output: $($markerSizeBudgetResult.Output.Trim())"
        }
    }
    finally {
        $scanner = $originalScanner
    }

    # Unicode format and logical line-separator characters can reorder or forge
    # log text even though Char.IsControl does not classify them as controls.
    $unicodePathRoot = Join-Path $tempRoot 'unicode-display-path'
    New-Item -ItemType Directory -Path $unicodePathRoot | Out-Null
    $unicodePathName = 'format' + [char]0x202E +
        'line' + [char]0x2028 + 'name.md'
    $unicodePathMarker = ('g' + 'hp_') +
        'synthetic_unicode_display'
    [IO.File]::WriteAllText(
        (Join-Path $unicodePathRoot $unicodePathName),
        "synthetic marker: $unicodePathMarker",
        [Text.UTF8Encoding]::new($false)
    )
    $unicodePathResult = Invoke-Scanner -ScanPath $unicodePathRoot
    if ($unicodePathResult.ExitCode -eq 0 -or
        $unicodePathResult.Output -notmatch
        'format\\u202eline\\u2028name\.md' -or
        $unicodePathResult.Output.Contains([string][char]0x202E) -or
        $unicodePathResult.Output.Contains([string][char]0x2028)) {
        Add-Failure "Expected Unicode format/separator characters in displayed paths to be escaped. Output: $($unicodePathResult.Output.Trim())"
    }

    $localMarkerRoot = Join-Path $tempRoot 'local-marker'
    New-Item -ItemType Directory -Path $localMarkerRoot | Out-Null
    Set-Content -LiteralPath (Join-Path $localMarkerRoot '.private-markers.local') -Value 'local-only-marker' -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $localMarkerRoot 'leak.txt') -Value 'synthetic local-only-marker fixture' -Encoding UTF8

    $localMarkerResult = Invoke-Scanner -ScanPath $localMarkerRoot
    if ($localMarkerResult.ExitCode -eq 0) {
        Add-Failure 'Expected local marker fixture to fail, but scanner exited 0.'
    }
    if ($localMarkerResult.Output -notmatch 'local-private-marker-1') {
        Add-Failure "Expected local marker output to name local-private-marker-1. Output: $($localMarkerResult.Output.Trim())"
    }

    # git-tracked mode must resolve git's forward-slash paths on every
    # platform. The nested fixture catches Windows-only backslash conversion;
    # the dotfile catches missing -Force on Unix PowerShell.
    $gitCommand = Get-Command git -ErrorAction SilentlyContinue
    if ($null -ne $gitCommand) {
        $gitRoot = Join-Path $tempRoot 'git-tracked'
        $gitIsolationRoot = Join-Path $tempRoot 'git-isolation'
        $ambientHooksRoot = Join-Path $tempRoot 'ambient-hooks'
        $ambientFilterRoot = Join-Path $tempRoot 'ambient-filter'
        $ambientGitDirectory = Join-Path $tempRoot 'ambient-git-dir'
        $ambientWorkTree = Join-Path $tempRoot 'ambient-work-tree'
        $ambientObjectDirectory = Join-Path $tempRoot 'ambient-objects'
        $ambientIndexFile = Join-Path $tempRoot 'ambient-index'
        $ambientHome = Join-Path $tempRoot 'ambient-home'
        $ambientXdg = Join-Path $tempRoot 'ambient-xdg'
        $ambientExecPath = Join-Path $tempRoot 'ambient-git-exec'
        $hookSentinel = Join-Path $tempRoot 'ambient-hook-fired'
        $filterSentinel = Join-Path $tempRoot 'ambient-filter-fired'
        $traceSentinel = Join-Path $tempRoot 'ambient-trace-fired'
        foreach ($directory in @(
            $gitRoot,
            $ambientHooksRoot,
            $ambientFilterRoot,
            $ambientGitDirectory,
            $ambientWorkTree,
            $ambientObjectDirectory,
            $ambientHome,
            $ambientXdg,
            $ambientExecPath
        )) {
            New-Item -ItemType Directory -Path $directory | Out-Null
        }

        # Inject harmless ambient hook/filter commands and repository redirects
        # as an adversarial regression. The isolated wrapper must suppress all
        # of them, and must restore the caller's exact environment afterward.
        $hookPath = Join-Path $ambientHooksRoot 'post-index-change'
        $hookSentinelShellLiteral =
            ConvertTo-SyntheticShellSingleQuotedLiteral -Value (
                $hookSentinel.Replace([string][char]92, '/')
            )
        $hookContent = @"
#!/bin/sh
printf '%s\n' 'hook-fired' > $hookSentinelShellLiteral
"@
        [System.IO.File]::WriteAllText($hookPath, $hookContent, [System.Text.UTF8Encoding]::new($false))
        $filterPath = Join-Path $ambientFilterRoot 'clean-filter'
        $filterSentinelShellLiteral =
            ConvertTo-SyntheticShellSingleQuotedLiteral -Value (
                $filterSentinel.Replace([string][char]92, '/')
            )
        $filterContent = @"
#!/bin/sh
printf '%s\n' 'filter-fired' > $filterSentinelShellLiteral
cat
"@
        [System.IO.File]::WriteAllText($filterPath, $filterContent, [System.Text.UTF8Encoding]::new($false))
        $ambientAttributes = Join-Path $ambientFilterRoot 'global-attributes'
        [System.IO.File]::WriteAllText(
            $ambientAttributes,
            "*.md filter=handoff-test`n",
            [System.Text.UTF8Encoding]::new($false)
        )

        $chmodCommand = Get-Command chmod -ErrorAction SilentlyContinue
        if ($null -ne $chmodCommand) {
            $chmodIsolationRoot = Join-Path $tempRoot 'chmod-isolation'
            $chmodResult = Invoke-PrivateMarkerBoundedProcess `
                -FileName $chmodCommand.Source `
                -Arguments @('+x', $hookPath, $filterPath) `
                -IsolationRoot $chmodIsolationRoot `
                -TimeoutMilliseconds 10000
            if ($chmodResult.ExitCode -ne 0 -or
                $chmodResult.TimedOut -or
                -not $chmodResult.TreeStopped -or
                -not $chmodResult.StreamsDrained) {
                Add-Failure "Expected bounded synthetic hook/filter chmod to exit 0. Output: $($chmodResult.Output.Trim())"
            }
        }

        # Prove both sentinels are independently observable without the
        # environment variables that the minimum child allowlist now drops.
        # Remove the canary outputs before the hostile Git regression so only
        # an actual isolation failure can recreate them.
        $shellPathCandidates =
            New-Object System.Collections.Generic.List[string]
        $shellCommands = @(
            Get-Command `
                sh `
                -CommandType Application `
                -ErrorAction SilentlyContinue
        )
        foreach ($shellCommand in $shellCommands) {
            $shellPathCandidates.Add($shellCommand.Source) | Out-Null
        }
        if ($runtimeIsWindows) {
            $gitInstallRoot = Split-Path -Parent (
                Split-Path -Parent $gitCommand.Source
            )
            foreach ($relativeShellPath in @(
                'bin\sh.exe',
                'usr\bin\sh.exe'
            )) {
                $shellPathCandidates.Add(
                    (Join-Path $gitInstallRoot $relativeShellPath)
                ) | Out-Null
            }
        }
        else {
            foreach ($systemShellPath in @('/bin/sh', '/usr/bin/sh')) {
                $shellPathCandidates.Add($systemShellPath) | Out-Null
            }
        }
        $shellPath = @(
            $shellPathCandidates |
                Where-Object {
                    Test-Path -LiteralPath $_ -PathType Leaf
                } |
                Select-Object -Unique
        ) | Select-Object -First 1
        if ([string]::IsNullOrWhiteSpace($shellPath)) {
            Add-Failure 'Expected a shell to exercise synthetic hook/filter sentinel canaries.'
        }
        else {
            $sentinelCanaryIsolation =
                Join-Path $tempRoot 'sentinel-canary-isolation'
            $hookCanaryResult = Invoke-PrivateMarkerBoundedProcess `
                -FileName $shellPath `
                -Arguments @($hookPath) `
                -IsolationRoot $sentinelCanaryIsolation `
                -TimeoutMilliseconds 10000
            $filterCanaryResult = Invoke-PrivateMarkerBoundedProcess `
                -FileName $shellPath `
                -Arguments @($filterPath) `
                -IsolationRoot $sentinelCanaryIsolation `
                -StandardInputBytes ([byte[]]@()) `
                -TimeoutMilliseconds 10000
            if (-not (Test-BoundedResultHealthy -Result $hookCanaryResult) -or
                $hookCanaryResult.ExitCode -ne 0 -or
                -not (Test-Path -LiteralPath $hookSentinel)) {
                Add-Failure 'Expected the embedded hook sentinel path canary to be observable without ambient variables.'
            }
            if (-not (Test-BoundedResultHealthy -Result $filterCanaryResult) -or
                $filterCanaryResult.ExitCode -ne 0 -or
                -not (Test-Path -LiteralPath $filterSentinel)) {
                Add-Failure 'Expected the embedded filter sentinel path canary to be observable without ambient variables.'
            }
            [IO.File]::Delete($hookSentinel)
            [IO.File]::Delete($filterSentinel)
        }

        $beforeFixtureEnvironment = Get-ProcessEnvironmentSnapshot
        $ambientHooksGitPath = $ambientHooksRoot.Replace([string][char]92, '/')
        $ambientAttributesGitPath = $ambientAttributes.Replace([string][char]92, '/')
        $filterGitPath = $filterPath.Replace([string][char]92, '/')
        $adversarialEnvironment = @{
            GIT_CONFIG_COUNT = '4'
            GIT_CONFIG_KEY_0 = 'core.hooksPath'
            GIT_CONFIG_VALUE_0 = $ambientHooksGitPath
            GIT_CONFIG_KEY_1 = 'core.attributesFile'
            GIT_CONFIG_VALUE_1 = $ambientAttributesGitPath
            GIT_CONFIG_KEY_2 = 'filter.handoff-test.clean'
            GIT_CONFIG_VALUE_2 = "sh `"$filterGitPath`""
            GIT_CONFIG_KEY_3 = 'filter.handoff-test.required'
            GIT_CONFIG_VALUE_3 = 'true'
            GIT_CONFIG_NOSYSTEM = '0'
            GIT_ATTR_NOSYSTEM = '0'
            GIT_CONFIG_GLOBAL = $ambientAttributesGitPath
            GIT_CONFIG_SYSTEM = $ambientAttributesGitPath
            GIT_DIR = $ambientGitDirectory
            GIT_WORK_TREE = $ambientWorkTree
            GIT_INDEX_FILE = $ambientIndexFile
            GIT_OBJECT_DIRECTORY = $ambientObjectDirectory
            GIT_ALTERNATE_OBJECT_DIRECTORIES = $ambientObjectDirectory
            GIT_EXEC_PATH = $ambientExecPath
            GIT_TRACE2_EVENT = $traceSentinel.Replace([string][char]92, '/')
            GIT_NO_REPLACE_OBJECTS = '0'
            GIT_NO_LAZY_FETCH = '0'
            GIT_HANDOFF_PRESENT_EMPTY = ''
            HANDOFF_TEST_HOOK_SENTINEL = $hookSentinel
            HANDOFF_TEST_FILTER_SENTINEL = $filterSentinel
            HOME = $ambientHome
            USERPROFILE = $ambientHome
            XDG_CONFIG_HOME = $ambientXdg
        }

        function Invoke-CheckedFixtureGit {
            param(
                [string]$FixtureRoot,
                [string[]]$Arguments,
                [string]$Context
            )

            # GitHub's Windows PowerShell 5.1 runner can need more than the
            # normal 20-second probe budget after the full adversarial suite.
            # Keep setup finite while avoiding a runner-load false negative;
            # behavioral timeout fixtures continue to use their smaller,
            # explicit deadlines.
            $result = Invoke-IsolatedGit `
                -GitPath $gitCommand.Source `
                -WorkingDirectory $FixtureRoot `
                -IsolationRoot $gitIsolationRoot `
                -Arguments $Arguments `
                -InheritedEnvironment $adversarialEnvironment `
                -TimeoutMilliseconds 60000
            if ($result.ExitCode -ne 0 -or
                -not (Test-BoundedResultHealthy -Result $result)) {
                # Every caller assumes the requested setup mutation completed.
                # Stop at the first broken prerequisite so a later missing index
                # cannot mask the actual bounded-process failure.
                throw (
                    "$Context failed with exit $($result.ExitCode). " +
                    "Output: $($result.Output.Trim())"
                )
            }
            return $result
        }

        function New-CheckedGitFixture {
            param([string]$Name)

            $fixtureRoot = Join-Path $tempRoot $Name
            New-Item -ItemType Directory -Path $fixtureRoot -Force | Out-Null
            [void](Invoke-CheckedFixtureGit `
                -FixtureRoot $fixtureRoot `
                -Arguments @('init', '--quiet') `
                -Context "Initialize $Name")
            if (-not (Test-Path `
                    -LiteralPath (Join-Path $fixtureRoot '.git') `
                    -PathType Container)) {
                throw "Initialize $Name returned success without creating .git."
            }
            return $fixtureRoot
        }

        # The primary fixture has the same setup contract as every later Git
        # fixture. Fail here if init did not create a repository; otherwise a
        # later add can misreport the setup failure as "not a git repository."
        $gitRoot = New-CheckedGitFixture -Name 'git-tracked'
        Assert-ProcessEnvironmentUnchanged `
            -Expected $beforeFixtureEnvironment `
            -Context 'Isolated git init'

        # Preserve a valid clean alternate index. A later public-entrypoint
        # regression passes only GIT_INDEX_FILE; if the scanner trusts ambient
        # Git state, the real staged markers disappear and the test false-passes.
        [void](Invoke-CheckedFixtureGit `
            -FixtureRoot $gitRoot `
            -Arguments @('read-tree', '--empty') `
            -Context 'Create primary fixture empty index')
        $primaryIndexPath = Join-Path $gitRoot '.git/index'
        if (-not [IO.File]::Exists($primaryIndexPath)) {
            throw 'Create primary fixture empty index returned success without creating .git/index.'
        }
        Copy-Item `
            -LiteralPath $primaryIndexPath `
            -Destination $ambientIndexFile `
            -Force

        $nestedDirectory = Join-Path $gitRoot (Join-Path 'sub' 'deep')
        New-Item -ItemType Directory -Path $nestedDirectory -Force | Out-Null
        $nestedMarker = ('g' + 'hp_') + 'synthetic_nested_placeholder'
        Set-Content -LiteralPath (Join-Path $nestedDirectory 'leak.md') -Value "synthetic marker: $nestedMarker" -Encoding UTF8

        $dotfileMarker = ('xo' + 'xb-') + 'synthetic_dotfile_placeholder'
        Set-Content -LiteralPath (Join-Path $gitRoot '.editorconfig') -Value "synthetic marker: $dotfileMarker" -Encoding UTF8

        $trackedTextNames = @(
            'leak.env',
            'leak.pem',
            'leak.key',
            '.env',
            '.env.local',
            'NOTICE',
            '.hidden'
        )
        foreach ($trackedTextName in $trackedTextNames) {
            Set-Content `
                -LiteralPath (Join-Path $gitRoot $trackedTextName) `
                -Value "synthetic marker: $nestedMarker" `
                -Encoding UTF8
        }

        [void](Invoke-CheckedFixtureGit `
            -FixtureRoot $gitRoot `
            -Arguments @('add', '-A') `
            -Context 'Stage primary marker fixture')
        Assert-ProcessEnvironmentUnchanged `
            -Expected $beforeFixtureEnvironment `
            -Context 'Isolated git add'

        # The scanner's own Git probes receive the same hostile clone and must
        # still inspect only the explicit temp repository.
        $gitResult = Invoke-Scanner `
            -ScanPath $gitRoot `
            -InheritedEnvironment $adversarialEnvironment
        Assert-ProcessEnvironmentUnchanged `
            -Expected $beforeFixtureEnvironment `
            -Context 'Isolated scanner child'

        if (Test-Path -LiteralPath $hookSentinel) {
            Add-Failure 'Expected isolated git fixture to suppress the injected ambient hook, but its sentinel was created.'
        }
        if (Test-Path -LiteralPath $filterSentinel) {
            Add-Failure 'Expected isolated git fixture to suppress the injected ambient clean filter, but its sentinel was created.'
        }
        if (Test-Path -LiteralPath $traceSentinel) {
            Add-Failure 'Expected isolated git fixture to suppress the injected trace output, but its sentinel was created.'
        }

        if ($null -eq $gitResult) {
            Add-Failure 'Expected the isolated scanner child to return a result.'
        } else {
            if ($gitResult.Output -notmatch 'git-index\+worktree') {
                Add-Failure "Expected the git fixture to scan the index and worktree. Output: $($gitResult.Output.Trim())"
            }
            if ($gitResult.ExitCode -eq 0) {
                Add-Failure 'Expected git-tracked nested and dotfile markers to fail the scan, but scanner exited 0.'
            }
            if ($gitResult.Output -notmatch 'sub/deep/leak\.md') {
                Add-Failure "Expected git-tracked output to list sub/deep/leak.md. Output: $($gitResult.Output.Trim())"
            }
            if ($gitResult.Output -notmatch '\.editorconfig') {
                Add-Failure "Expected git-tracked output to list .editorconfig. Output: $($gitResult.Output.Trim())"
            }
            foreach ($trackedTextName in $trackedTextNames) {
                if ($gitResult.Output -notmatch
                    [regex]::Escape($trackedTextName)) {
                    Add-Failure "Expected tracked regular text path $trackedTextName to be scanned. Output: $($gitResult.Output.Trim())"
                }
            }
            if ($gitResult.Output.Contains($nestedMarker) -or
                $gitResult.Output.Contains($dotfileMarker)) {
                Add-Failure 'Expected git-tracked findings to stay redacted, but a raw marker leaked into output.'
            }
        }

        # GIT_INDEX_FILE alone is a direct false-pass regression: the alternate
        # index is valid and empty, while the explicit repository index contains
        # both markers. The public scanner must ignore the ambient redirect.
        $ambientIndexOnlyResult = Invoke-Scanner `
            -ScanPath $gitRoot `
            -InheritedEnvironment @{
                GIT_INDEX_FILE = $ambientIndexFile
            }
        if ($ambientIndexOnlyResult.ExitCode -eq 0 -or
            $ambientIndexOnlyResult.Output -notmatch 'sub/deep/leak\.md' -or
            $ambientIndexOnlyResult.Output -notmatch '\.editorconfig') {
            Add-Failure "Expected the public scanner to ignore ambient GIT_INDEX_FILE. Output: $($ambientIndexOnlyResult.Output.Trim())"
        }

        # Passing a repository subdirectory as the scan root must fail closed.
        # It must never fall back to a partial working-tree scan.
        $rootMismatchResult = Invoke-Scanner -ScanPath (Join-Path $gitRoot 'sub')
        if ($rootMismatchResult.ExitCode -ne 2 -or
            $rootMismatchResult.Output -notmatch 'integrity: git-root-mismatch') {
            Add-Failure "Expected repository root mismatch to fail closed. Output: $($rootMismatchResult.Output.Trim())"
        }

        # Normalize the original fixture before exercising index/worktree union
        # states with one dedicated path.
        Set-Content `
            -LiteralPath (Join-Path $nestedDirectory 'leak.md') `
            -Value 'synthetic clean content' `
            -Encoding UTF8
        Set-Content `
            -LiteralPath (Join-Path $gitRoot '.editorconfig') `
            -Value 'root = true' `
            -Encoding UTF8
        foreach ($trackedTextName in $trackedTextNames) {
            Set-Content `
                -LiteralPath (Join-Path $gitRoot $trackedTextName) `
                -Value 'synthetic clean content' `
                -Encoding UTF8
        }
        [void](Invoke-CheckedFixtureGit `
            -FixtureRoot $gitRoot `
            -Arguments @('add', '-A') `
            -Context 'Stage normalized union fixture')

        $unionPath = Join-Path $gitRoot 'union.md'
        $unionMarker = ('g' + 'hp_') + 'synthetic_union_placeholder'
        Set-Content `
            -LiteralPath $unionPath `
            -Value "staged marker: $unionMarker" `
            -Encoding UTF8
        [void](Invoke-CheckedFixtureGit `
            -FixtureRoot $gitRoot `
            -Arguments @('add', '--', 'union.md') `
            -Context 'Stage index-only marker')
        Set-Content `
            -LiteralPath $unionPath `
            -Value 'synthetic clean worktree content' `
            -Encoding UTF8
        $indexOnlyResult = Invoke-Scanner -ScanPath $gitRoot
        if ($indexOnlyResult.ExitCode -eq 0 -or
            $indexOnlyResult.Output -notmatch 'union\.md \[index\]') {
            Add-Failure "Expected staged-only index bytes to be scanned. Output: $($indexOnlyResult.Output.Trim())"
        }

        [void](Invoke-CheckedFixtureGit `
            -FixtureRoot $gitRoot `
            -Arguments @('add', '--', 'union.md') `
            -Context 'Stage clean union content')
        Set-Content `
            -LiteralPath $unionPath `
            -Value "worktree marker: $unionMarker" `
            -Encoding UTF8
        $worktreeOnlyResult = Invoke-Scanner -ScanPath $gitRoot
        if ($worktreeOnlyResult.ExitCode -eq 0 -or
            $worktreeOnlyResult.Output -notmatch 'union\.md \[worktree\]') {
            Add-Failure "Expected unstaged worktree bytes to be scanned. Output: $($worktreeOnlyResult.Output.Trim())"
        }

        Set-Content `
            -LiteralPath $unionPath `
            -Value "missing worktree marker: $unionMarker" `
            -Encoding UTF8
        [void](Invoke-CheckedFixtureGit `
            -FixtureRoot $gitRoot `
            -Arguments @('add', '--', 'union.md') `
            -Context 'Stage missing-worktree marker')
        Remove-Item -LiteralPath $unionPath -Force
        $missingWorktreeResult = Invoke-Scanner -ScanPath $gitRoot
        if ($missingWorktreeResult.ExitCode -eq 0 -or
            $missingWorktreeResult.Output -notmatch
            'union\.md \[index; worktree missing\]') {
            Add-Failure "Expected a missing worktree file to retain index scanning. Output: $($missingWorktreeResult.Output.Trim())"
        }

        # A same-length atomic replacement after snapshot capture must invalidate
        # both Git-index and fallback reports. The sentinel is created at
        # runtime from split text so the repository's own scanner never treats
        # this synthetic fixture source as a published credential.
        $worktreeDriftSentinel = ('g' + 'hp_') +
            'synthetic_same_length_worktree_drift'
        $worktreeDriftClean = 'c' * $worktreeDriftSentinel.Length

        $gitWorktreeDriftRoot = New-CheckedGitFixture `
            -Name 'git-worktree-content-drift'
        $gitWorktreeDriftTarget = Join-Path `
            $gitWorktreeDriftRoot `
            'tracked.md'
        [IO.File]::WriteAllText(
            $gitWorktreeDriftTarget,
            $worktreeDriftClean,
            [Text.UTF8Encoding]::new($false)
        )
        [void](Invoke-CheckedFixtureGit `
            -FixtureRoot $gitWorktreeDriftRoot `
            -Arguments @('add', '--', 'tracked.md') `
            -Context 'Stage worktree content-drift fixture')
        $gitWorktreeDriftSwap = Join-Path `
            $tempRoot `
            'git-worktree-content-drift-external-swap'
        $gitWorktreeDriftBackup = Join-Path `
            $tempRoot `
            'git-worktree-content-drift-backup'
        [IO.File]::WriteAllText(
            $gitWorktreeDriftSwap,
            $worktreeDriftSentinel,
            [Text.UTF8Encoding]::new($false)
        )
        $gitWorktreeDriftScanner = New-WorktreeDriftScannerCopy `
            -DestinationDirectory (Join-Path `
                $tempRoot `
                'git-worktree-drift-scanner') `
            -TargetPath $gitWorktreeDriftTarget `
            -SwapPath $gitWorktreeDriftSwap `
            -BackupPath $gitWorktreeDriftBackup
        $originalScanner = $scanner
        try {
            $scanner = $gitWorktreeDriftScanner
            $gitWorktreeDriftResult = Invoke-Scanner `
                -ScanPath $gitWorktreeDriftRoot
        }
        finally {
            $scanner = $originalScanner
        }
        if ($gitWorktreeDriftResult.ExitCode -ne 2 -or
            $gitWorktreeDriftResult.Output -notmatch
            'integrity: worktree-content-drift' -or
            $gitWorktreeDriftResult.Output.Contains(
                $worktreeDriftSentinel
            ) -or
            $gitWorktreeDriftResult.Output.Contains('tracked.md')) {
            Add-Failure "Expected same-length Git worktree content drift to fail closed without reflective output. Output: $($gitWorktreeDriftResult.Output.Trim())"
        }

        # Prove the external sentinel is scanner-detectable when it is the
        # stable observed content; otherwise the drift fixture could false-pass
        # without exercising a meaningful stale-clean transition.
        $gitWorktreeDriftControl = Invoke-Scanner `
            -ScanPath $gitWorktreeDriftRoot
        if ($gitWorktreeDriftControl.ExitCode -eq 0 -or
            $gitWorktreeDriftControl.Output -notmatch
            'github-classic-token-prefix') {
            Add-Failure 'Expected the stable worktree-drift sentinel to be scanner-detectable.'
        }

        $fallbackWorktreeDriftRoot = Join-Path `
            $tempRoot `
            'fallback-worktree-content-drift'
        New-Item `
            -ItemType Directory `
            -Path $fallbackWorktreeDriftRoot | Out-Null
        $fallbackWorktreeDriftTarget = Join-Path `
            $fallbackWorktreeDriftRoot `
            'tracked.md'
        [IO.File]::WriteAllText(
            $fallbackWorktreeDriftTarget,
            $worktreeDriftClean,
            [Text.UTF8Encoding]::new($false)
        )
        $fallbackWorktreeDriftSwap = Join-Path `
            $tempRoot `
            'fallback-worktree-content-drift-external-swap'
        $fallbackWorktreeDriftBackup = Join-Path `
            $tempRoot `
            'fallback-worktree-content-drift-backup'
        [IO.File]::WriteAllText(
            $fallbackWorktreeDriftSwap,
            $worktreeDriftSentinel,
            [Text.UTF8Encoding]::new($false)
        )
        $fallbackWorktreeDriftScanner = New-WorktreeDriftScannerCopy `
            -DestinationDirectory (Join-Path `
                $tempRoot `
                'fallback-worktree-drift-scanner') `
            -TargetPath $fallbackWorktreeDriftTarget `
            -SwapPath $fallbackWorktreeDriftSwap `
            -BackupPath $fallbackWorktreeDriftBackup
        $originalScanner = $scanner
        try {
            $scanner = $fallbackWorktreeDriftScanner
            $fallbackWorktreeDriftResult = Invoke-Scanner `
                -ScanPath $fallbackWorktreeDriftRoot
        }
        finally {
            $scanner = $originalScanner
        }
        if ($fallbackWorktreeDriftResult.ExitCode -ne 2 -or
            $fallbackWorktreeDriftResult.Output -notmatch
            'integrity: worktree-content-drift' -or
            $fallbackWorktreeDriftResult.Output.Contains(
                $worktreeDriftSentinel
            ) -or
            $fallbackWorktreeDriftResult.Output.Contains('tracked.md')) {
            Add-Failure "Expected same-length fallback worktree content drift to fail closed without reflective output. Output: $($fallbackWorktreeDriftResult.Output.Trim())"
        }

        # Replace the real index atomically after the first raw stage listing
        # has completed. A test-only scanner copy pauses at that exact boundary
        # so the fixture proves the final byte comparison without scheduler
        # timing assumptions or production-only sleeps.
        $driftRoot = New-CheckedGitFixture -Name 'index-drift'
        for ($driftFileIndex = 0; $driftFileIndex -lt 24; $driftFileIndex++) {
            $driftFileName = 'drift-{0:d2}.md' -f $driftFileIndex
            $driftContent = ('x' * 32768) + "-$driftFileIndex"
            [IO.File]::WriteAllText(
                (Join-Path $driftRoot $driftFileName),
                $driftContent,
                [Text.UTF8Encoding]::new($false)
            )
        }
        [void](Invoke-CheckedFixtureGit `
            -FixtureRoot $driftRoot `
            -Arguments @('add', '-A') `
            -Context 'Stage clean drift index')
        $driftIndexPath = Join-Path $driftRoot '.git/index'
        if (-not [IO.File]::Exists($driftIndexPath)) {
            throw 'Stage clean drift index returned success without creating .git/index.'
        }
        $cleanIndexTemplate = Join-Path $driftRoot '.git/clean-index-template'
        $changedIndexTemplate = Join-Path `
            $driftRoot `
            '.git/changed-index-template'
        [IO.File]::Copy($driftIndexPath, $cleanIndexTemplate, $true)
        $driftMarker = ('g' + 'hp_') + 'synthetic_index_drift'
        [IO.File]::WriteAllText(
            (Join-Path $driftRoot 'drift-00.md'),
            "mutated index marker: $driftMarker",
            [Text.UTF8Encoding]::new($false)
        )
        [void](Invoke-CheckedFixtureGit `
            -FixtureRoot $driftRoot `
            -Arguments @('add', '--', 'drift-00.md') `
            -Context 'Stage changed drift index')
        [IO.File]::Copy($driftIndexPath, $changedIndexTemplate, $true)
        [IO.File]::WriteAllText(
            (Join-Path $driftRoot 'drift-00.md'),
            ('x' * 32768) + '-0',
            [Text.UTF8Encoding]::new($false)
        )

        [IO.File]::Copy($cleanIndexTemplate, $driftIndexPath, $true)
        $swapIndexPath = Join-Path $driftRoot '.git/index-swap'
        $backupIndexPath = Join-Path $driftRoot '.git/index-backup'
        [IO.File]::Copy($changedIndexTemplate, $swapIndexPath, $true)
        if ([IO.File]::Exists($backupIndexPath)) {
            [IO.File]::Delete($backupIndexPath)
        }

        # Instrument only a disposable scanner copy. The production scanner
        # has no synchronization hooks or caller-controlled delay surface.
        $driftScannerDirectory = Join-Path $tempRoot 'drift-scanner'
        New-Item `
            -ItemType Directory `
            -Path $driftScannerDirectory `
            -Force | Out-Null
        $instrumentedScanner = Join-Path `
            $driftScannerDirectory `
            'scan-private-markers.ps1'
        Copy-Item `
            -LiteralPath $processSupport `
            -Destination (Join-Path `
                $driftScannerDirectory `
                'private-marker-process.ps1')
        $driftReadyPath = Join-Path $tempRoot 'index-drift-ready'
        $driftReleasePath = Join-Path $tempRoot 'index-drift-release'
        $driftAnchor = @'
if ($usingGitIndex) {
    $scanMode = 'git-index+worktree'
'@
        $driftScannerSource = [IO.File]::ReadAllText($scanner)
        $driftAnchorOffset = $driftScannerSource.IndexOf(
            $driftAnchor,
            [StringComparison]::Ordinal
        )
        if ($driftAnchorOffset -lt 0 -or
            $driftScannerSource.IndexOf(
                $driftAnchor,
                $driftAnchorOffset + $driftAnchor.Length,
                [StringComparison]::Ordinal
            ) -ge 0) {
            throw 'Cannot locate the unique index-drift synchronization anchor.'
        }
        $driftSyncInjection = @'
# Test-copy only: publish that snapshot construction and its first raw index
# recheck are complete, then pause before content matching. The production
# scanner has no synchronization surface.
[IO.File]::WriteAllText(
    '__DRIFT_READY__',
    'ready',
    [Text.UTF8Encoding]::new($false)
)
$driftReleased = $false
for ($driftSyncAttempt = 0;
    $driftSyncAttempt -lt 1500;
    $driftSyncAttempt++) {
    if ([IO.File]::Exists('__DRIFT_RELEASE__')) {
        $driftReleased = $true
        break
    }
    Start-Sleep -Milliseconds 10
}
if (-not $driftReleased) {
    Stop-ScanIntegrityFailure -Reason 'test-index-drift-sync'
}

'@
        $driftSyncInjection = $driftSyncInjection.Replace(
            '__DRIFT_READY__',
            $driftReadyPath.Replace("'", "''")
        ).Replace(
            '__DRIFT_RELEASE__',
            $driftReleasePath.Replace("'", "''")
        )
        $driftScannerSource = $driftScannerSource.Replace(
            $driftAnchor,
            $driftSyncInjection + $driftAnchor
        )
        [IO.File]::WriteAllText(
            $instrumentedScanner,
            $driftScannerSource,
            [Text.UTF8Encoding]::new($false)
        )

        # The mutator starts first but cannot replace the index until the
        # instrumented scanner publishes its post-snapshot signal.
        $escapedDriftReady = $driftReadyPath.Replace("'", "''")
        $escapedDriftRelease = $driftReleasePath.Replace("'", "''")
        $escapedSwapIndex = $swapIndexPath.Replace("'", "''")
        $escapedDriftIndex = $driftIndexPath.Replace("'", "''")
        $escapedBackupIndex = $backupIndexPath.Replace("'", "''")
        $mutatorScript = @"
`$readyObserved = `$false
for (`$attempt = 0; `$attempt -lt 1500; `$attempt++) {
    if ([IO.File]::Exists('$escapedDriftReady')) {
        `$readyObserved = `$true
        break
    }
    Start-Sleep -Milliseconds 10
}
if (-not `$readyObserved) {
    exit 3
}
[IO.File]::Replace(
    '$escapedSwapIndex',
    '$escapedDriftIndex',
    '$escapedBackupIndex'
)
[IO.File]::WriteAllText(
    '$escapedDriftRelease',
    'release',
    [Text.UTF8Encoding]::new(`$false)
)
"@
        $mutatorEncoded = [Convert]::ToBase64String(
            [Text.Encoding]::Unicode.GetBytes($mutatorScript)
        )
        $mutatorArguments = @('-NoProfile')
        if ($PSVersionTable.PSVersion.Major -le 5 -and
            $runtimeIsWindows) {
            $mutatorArguments += @('-ExecutionPolicy', 'Bypass')
        }
        $mutatorArguments += @('-EncodedCommand', $mutatorEncoded)
        $mutatorInfo = New-Object Diagnostics.ProcessStartInfo
        $mutatorInfo.FileName = $currentPowerShellExecutable
        $mutatorInfo.UseShellExecute = $false
        $mutatorInfo.CreateNoWindow = $true
        $mutatorArgumentList =
            $mutatorInfo.PSObject.Properties['ArgumentList']
        if ($null -ne $mutatorArgumentList) {
            foreach ($mutatorArgument in $mutatorArguments) {
                $mutatorInfo.ArgumentList.Add($mutatorArgument)
            }
        } else {
            $mutatorInfo.Arguments = (
                $mutatorArguments | ForEach-Object {
                    ConvertTo-PrivateMarkerProcessArgument -Argument $_
                }
            ) -join ' '
        }
        $mutator = [Diagnostics.Process]::Start($mutatorInfo)
        $originalScanner = $scanner
        try {
            $scanner = $instrumentedScanner
            $driftResult = Invoke-Scanner -ScanPath $driftRoot
            if (-not $mutator.WaitForExit(20000)) {
                $mutator.Kill()
                [void]$mutator.WaitForExit(5000)
                Add-Failure 'Expected the bounded index mutator to exit.'
            } elseif ($mutator.ExitCode -ne 0) {
                Add-Failure 'Expected the atomic index mutation to succeed.'
            }
        }
        finally {
            $scanner = $originalScanner
            $mutator.Dispose()
        }
        [IO.File]::Copy($cleanIndexTemplate, $driftIndexPath, $true)
        if ($driftResult.ExitCode -ne 2 -or
            $driftResult.Output -notmatch 'integrity: git-index-drift') {
            Add-Failure 'Expected an actual staged-index mutation to be caught by the final raw metadata comparison.'
        }

        # CE_INTENT_TO_ADD can change while mode/OID/stage/path bytes remain
        # identical. Swap an actual normal empty-file index for its ITA form
        # after the first stage recheck; only the final raw debug comparison can
        # detect this flags-only mutation.
        $flagDriftRoot = New-CheckedGitFixture -Name 'index-flag-drift'
        $flagDriftWorktreePath = Join-Path $flagDriftRoot 'intent.md'
        [IO.File]::WriteAllBytes($flagDriftWorktreePath, [byte[]]@())
        [void](Invoke-CheckedFixtureGit `
            -FixtureRoot $flagDriftRoot `
            -Arguments @('add', '--', 'intent.md') `
            -Context 'Stage normal empty flag-drift entry')
        $flagDriftIndexPath = Join-Path $flagDriftRoot '.git/index'
        $normalFlagIndexTemplate = Join-Path `
            $flagDriftRoot `
            '.git/normal-flag-index-template'
        $intentFlagIndexTemplate = Join-Path `
            $flagDriftRoot `
            '.git/intent-flag-index-template'
        [IO.File]::Copy(
            $flagDriftIndexPath,
            $normalFlagIndexTemplate,
            $true
        )
        $normalFlagStage = Invoke-CheckedFixtureGit `
            -FixtureRoot $flagDriftRoot `
            -Arguments @('ls-files', '-z', '--stage', '--') `
            -Context 'Read normal flag-drift stage bytes'
        [void](Invoke-CheckedFixtureGit `
            -FixtureRoot $flagDriftRoot `
            -Arguments @('rm', '--cached', '--', 'intent.md') `
            -Context 'Remove normal empty entry before ITA')
        [void](Invoke-CheckedFixtureGit `
            -FixtureRoot $flagDriftRoot `
            -Arguments @('add', '--intent-to-add', '--', 'intent.md') `
            -Context 'Create flags-only ITA entry')
        $intentFlagStage = Invoke-CheckedFixtureGit `
            -FixtureRoot $flagDriftRoot `
            -Arguments @('ls-files', '-z', '--stage', '--') `
            -Context 'Read ITA flag-drift stage bytes'
        if ([Convert]::ToBase64String($normalFlagStage.StdoutBytes) -cne
            [Convert]::ToBase64String($intentFlagStage.StdoutBytes)) {
            Add-Failure 'Expected normal empty and ITA stage metadata bytes to be identical for the flags-only drift fixture.'
        }
        [IO.File]::Copy(
            $flagDriftIndexPath,
            $intentFlagIndexTemplate,
            $true
        )
        [IO.File]::Copy(
            $normalFlagIndexTemplate,
            $flagDriftIndexPath,
            $true
        )
        $flagSwapIndexPath = Join-Path `
            $flagDriftRoot `
            '.git/index-flag-swap'
        $flagBackupIndexPath = Join-Path `
            $flagDriftRoot `
            '.git/index-flag-backup'
        [IO.File]::Copy(
            $intentFlagIndexTemplate,
            $flagSwapIndexPath,
            $true
        )
        foreach ($signalPath in @(
            $driftReadyPath,
            $driftReleasePath,
            $flagBackupIndexPath
        )) {
            [IO.File]::Delete($signalPath)
        }
        $flagMutator = Start-SynchronizedIndexMutator `
            -ReadyPath $driftReadyPath `
            -ReleasePath $driftReleasePath `
            -SwapPath $flagSwapIndexPath `
            -IndexPath $flagDriftIndexPath `
            -BackupPath $flagBackupIndexPath
        $originalScanner = $scanner
        try {
            $scanner = $instrumentedScanner
            $flagDriftResult = Invoke-Scanner -ScanPath $flagDriftRoot
            if (-not $flagMutator.WaitForExit(20000)) {
                $flagMutator.Kill()
                [void]$flagMutator.WaitForExit(5000)
                Add-Failure 'Expected the bounded flag mutator to exit.'
            } elseif ($flagMutator.ExitCode -ne 0) {
                Add-Failure 'Expected the atomic flags-only mutation to succeed.'
            }
        }
        finally {
            $scanner = $originalScanner
            $flagMutator.Dispose()
        }
        [IO.File]::Copy(
            $normalFlagIndexTemplate,
            $flagDriftIndexPath,
            $true
        )
        if ($flagDriftResult.ExitCode -ne 2 -or
            $flagDriftResult.Output -notmatch
            'integrity: git-index-drift') {
            Add-Failure 'Expected a flags-only index mutation to be caught by the final raw debug comparison.'
        }

        # A tracked local marker configuration is itself a publication leak
        # boundary, regardless of whether its contents look sensitive.
        $trackedLocalRoot = New-CheckedGitFixture -Name 'tracked-local-marker'
        Set-Content `
            -LiteralPath (Join-Path $trackedLocalRoot '.private-markers.local') `
            -Value 'synthetic-local-only-rule' `
            -Encoding UTF8
        [void](Invoke-CheckedFixtureGit `
            -FixtureRoot $trackedLocalRoot `
            -Arguments @('add', '-f', '--', '.private-markers.local') `
            -Context 'Force-add local marker configuration')
        $trackedLocalResult = Invoke-Scanner -ScanPath $trackedLocalRoot
        if ($trackedLocalResult.ExitCode -ne 2 -or
            $trackedLocalResult.Output -notmatch
            'integrity: git-index-local-marker') {
            Add-Failure "Expected tracked local marker configuration to fail closed. Output: $($trackedLocalResult.Output.Trim())"
        }

        # Intent-to-add entries carry CE_INTENT_TO_ADD even though current Git
        # exposes the normal empty-blob OID. Reject both the present `.A` and
        # missing `.D` worktree states from the direct extended flag.
        $intentRoot = New-CheckedGitFixture -Name 'intent-to-add'
        Set-Content `
            -LiteralPath (Join-Path $intentRoot 'intent.md') `
            -Value 'synthetic clean content' `
            -Encoding UTF8
        [void](Invoke-CheckedFixtureGit `
            -FixtureRoot $intentRoot `
            -Arguments @('add', '--intent-to-add', '--', 'intent.md') `
            -Context 'Create intent-to-add entry')
        $intentResult = Invoke-Scanner -ScanPath $intentRoot
        if ($intentResult.ExitCode -ne 2 -or
            $intentResult.Output -notmatch
            'integrity: git-index-intent-to-add') {
            Add-Failure "Expected intent-to-add index entry to fail closed. Output: $($intentResult.Output.Trim())"
        }
        [IO.File]::Delete((Join-Path $intentRoot 'intent.md'))
        $missingIntentResult = Invoke-Scanner -ScanPath $intentRoot
        if ($missingIntentResult.ExitCode -ne 2 -or
            $missingIntentResult.Output -notmatch
            'integrity: git-index-intent-to-add') {
            Add-Failure "Expected missing intent-to-add index entry to fail closed. Output: $($missingIntentResult.Output.Trim())"
        }

        # A genuinely staged empty file has the same blob OID but not the
        # extended flag, so the direct flag parser must not reject it.
        $stagedEmptyRoot = New-CheckedGitFixture -Name 'staged-empty'
        [IO.File]::WriteAllBytes(
            (Join-Path $stagedEmptyRoot 'empty.md'),
            [byte[]]@()
        )
        [void](Invoke-CheckedFixtureGit `
            -FixtureRoot $stagedEmptyRoot `
            -Arguments @('add', '--', 'empty.md') `
            -Context 'Stage genuine empty file')
        $stagedEmptyResult = Invoke-Scanner -ScanPath $stagedEmptyRoot
        if ($stagedEmptyResult.ExitCode -ne 0) {
            Add-Failure "Expected a genuine staged empty file to pass. Output: $($stagedEmptyResult.Output.Trim())"
        }

        # A gitlink has no text blob at the path and may hide a nested external
        # repository. A synthetic info-only cache entry avoids any network.
        $gitlinkRoot = New-CheckedGitFixture -Name 'gitlink'
        $syntheticCommitOid = ('1' * 40)
        [void](Invoke-CheckedFixtureGit `
            -FixtureRoot $gitlinkRoot `
            -Arguments @(
                'update-index',
                '--add',
                '--info-only',
                '--cacheinfo',
                "160000,$syntheticCommitOid,vendor"
            ) `
            -Context 'Create synthetic gitlink entry')
        $gitlinkResult = Invoke-Scanner -ScanPath $gitlinkRoot
        if ($gitlinkResult.ExitCode -ne 2 -or
            $gitlinkResult.Output -notmatch 'integrity: git-index-gitlink') {
            Add-Failure "Expected gitlink index entry to fail closed. Output: $($gitlinkResult.Output.Trim())"
        }

        # Index-mode symlinks are scanned from their raw immutable blob only
        # when no worktree link exists, so no external target is followed.
        $indexLinkRoot = New-CheckedGitFixture -Name 'index-symlink'
        $linkSource = Join-Path $indexLinkRoot 'link-source.bin'
        $linkMarker = ('g' + 'hp_') + 'synthetic_link_target'
        [IO.File]::WriteAllText(
            $linkSource,
            "synthetic/$linkMarker",
            [Text.UTF8Encoding]::new($false)
        )
        $linkHashResult = Invoke-CheckedFixtureGit `
            -FixtureRoot $indexLinkRoot `
            -Arguments @('hash-object', '-w', '--', 'link-source.bin') `
            -Context 'Create synthetic symlink blob'
        $linkOid = [Text.Encoding]::ASCII.GetString(
            $linkHashResult.StdoutBytes
        ).Trim()
        if ($linkOid -notmatch '^[0-9a-f]{40,64}$') {
            Add-Failure 'Expected a valid object ID for the synthetic symlink blob.'
        } else {
            [void](Invoke-CheckedFixtureGit `
                -FixtureRoot $indexLinkRoot `
                -Arguments @(
                    'update-index',
                    '--add',
                    '--cacheinfo',
                    "120000,$linkOid,synthetic-link.md"
                ) `
                -Context 'Create synthetic index symlink')
            $indexLinkResult = Invoke-Scanner -ScanPath $indexLinkRoot
            if ($indexLinkResult.ExitCode -eq 0 -or
                $indexLinkResult.Output -notmatch
                'synthetic-link\.md \[index symlink; worktree missing\]') {
                Add-Failure "Expected missing worktree symlink to scan its index blob. Output: $($indexLinkResult.Output.Trim())"
            }
        }

        # A reparse/symlink directory in a tracked worktree path must be
        # rejected before its external leaf is opened.
        $reparseRoot = New-CheckedGitFixture -Name 'reparse-ancestor'
        $trackedDirectory = Join-Path $reparseRoot 'linked'
        New-Item -ItemType Directory -Path $trackedDirectory | Out-Null
        Set-Content `
            -LiteralPath (Join-Path $trackedDirectory 'leak.md') `
            -Value 'synthetic clean content' `
            -Encoding UTF8
        [void](Invoke-CheckedFixtureGit `
            -FixtureRoot $reparseRoot `
            -Arguments @('add', '--', 'linked/leak.md') `
            -Context 'Stage reparse ancestor fixture')
        $externalDirectory = Join-Path $tempRoot 'reparse-external-target'
        Move-Item `
            -LiteralPath $trackedDirectory `
            -Destination $externalDirectory
        $externalMarker = ('g' + 'hp_') + 'synthetic_external_target'
        Set-Content `
            -LiteralPath (Join-Path $externalDirectory 'leak.md') `
            -Value "external marker: $externalMarker" `
            -Encoding UTF8
        try {
            if ($runtimeIsWindows) {
                New-Item `
                    -ItemType Junction `
                    -Path $trackedDirectory `
                    -Target $externalDirectory |
                    Out-Null
            } else {
                New-Item `
                    -ItemType SymbolicLink `
                    -Path $trackedDirectory `
                    -Target $externalDirectory |
                    Out-Null
            }
            $reparseResult = Invoke-Scanner -ScanPath $reparseRoot
            if ($reparseResult.ExitCode -ne 2 -or
                $reparseResult.Output -notmatch
                'integrity: worktree-reparse-path' -or
                $reparseResult.Output.Contains($externalMarker)) {
                Add-Failure "Expected a reparse ancestor to fail before external content is read. Output: $($reparseResult.Output.Trim())"
            }
        }
        catch {
            Add-Failure 'Expected the synthetic reparse ancestor fixture to be creatable.'
        }

        # Replace refs can redirect cat-file away from the exact staged object.
        # The hermetic child environment must force the original marker blob.
        $replaceRoot = New-CheckedGitFixture -Name 'replace-object'
        $replacePath = Join-Path $replaceRoot 'replace.md'
        $replaceMarker = ('g' + 'hp_') + 'synthetic_replace_original'
        Set-Content `
            -LiteralPath $replacePath `
            -Value "original marker: $replaceMarker" `
            -Encoding UTF8
        [void](Invoke-CheckedFixtureGit `
            -FixtureRoot $replaceRoot `
            -Arguments @('add', '--', 'replace.md') `
            -Context 'Stage replace-ref marker')
        $originalOidResult = Invoke-CheckedFixtureGit `
            -FixtureRoot $replaceRoot `
            -Arguments @('rev-parse', ':replace.md') `
            -Context 'Resolve original marker object'
        $originalOid = [Text.Encoding]::ASCII.GetString(
            $originalOidResult.StdoutBytes
        ).Trim()
        $cleanBlobPath = Join-Path $replaceRoot 'clean-source.bin'
        [IO.File]::WriteAllText(
            $cleanBlobPath,
            'synthetic clean replacement',
            [Text.UTF8Encoding]::new($false)
        )
        $cleanOidResult = Invoke-CheckedFixtureGit `
            -FixtureRoot $replaceRoot `
            -Arguments @('hash-object', '-w', '--', 'clean-source.bin') `
            -Context 'Create clean replacement object'
        $cleanOid = [Text.Encoding]::ASCII.GetString(
            $cleanOidResult.StdoutBytes
        ).Trim()
        if ($originalOid -notmatch '^[0-9a-f]{40,64}$' -or
            $cleanOid -notmatch '^[0-9a-f]{40,64}$') {
            Add-Failure 'Expected valid object IDs for the replace-ref regression.'
        } else {
            $replaceRefs = Join-Path $replaceRoot '.git/refs/replace'
            New-Item -ItemType Directory -Path $replaceRefs -Force | Out-Null
            [IO.File]::WriteAllText(
                (Join-Path $replaceRefs $originalOid),
                "$cleanOid`n",
                [Text.UTF8Encoding]::new($false)
            )
            Remove-Item -LiteralPath $replacePath -Force
            $replaceResult = Invoke-Scanner -ScanPath $replaceRoot
            if ($replaceResult.ExitCode -eq 0 -or
                $replaceResult.Output -notmatch
                'replace\.md \[index; worktree missing\]') {
                Add-Failure "Expected replace refs to be disabled while scanning the original index blob. Output: $($replaceResult.Output.Trim())"
            }
        }

        # A corrupted index must stop at the Git boundary. Do not treat a
        # failed ls-files parse as an empty repository.
        $corruptRoot = New-CheckedGitFixture -Name 'corrupt-index'
        Set-Content `
            -LiteralPath (Join-Path $corruptRoot 'tracked.md') `
            -Value 'synthetic clean content' `
            -Encoding UTF8
        [void](Invoke-CheckedFixtureGit `
            -FixtureRoot $corruptRoot `
            -Arguments @('add', '--', 'tracked.md') `
            -Context 'Stage corrupt-index fixture')
        [IO.File]::WriteAllBytes(
            (Join-Path $corruptRoot '.git/index'),
            [byte[]](1, 2, 3, 4, 5, 6, 7)
        )
        $corruptResult = Invoke-Scanner -ScanPath $corruptRoot
        if ($corruptResult.ExitCode -ne 2 -or
            $corruptResult.Output -notmatch 'integrity: git-index-list') {
            Add-Failure "Expected a corrupt index to fail closed. Output: $($corruptResult.Output.Trim())"
        }

        # Build an actual unmerged index so stages 1-3 cannot be mistaken for a
        # normal stage-0 path.
        $conflictRoot = New-CheckedGitFixture -Name 'unmerged-index'
        $conflictPath = Join-Path $conflictRoot 'conflict.md'
        $syntheticEmail = 'synthetic' + '@example.invalid'
        Set-Content -LiteralPath $conflictPath -Value 'base' -Encoding UTF8
        [void](Invoke-CheckedFixtureGit `
            -FixtureRoot $conflictRoot `
            -Arguments @('add', '--', 'conflict.md') `
            -Context 'Stage conflict base')
        [void](Invoke-CheckedFixtureGit `
            -FixtureRoot $conflictRoot `
            -Arguments @(
                '-c',
                'user.name=Synthetic',
                '-c',
                "user.email=$syntheticEmail",
                'commit',
                '--quiet',
                '-m',
                'base'
            ) `
            -Context 'Commit conflict base')
        $branchResult = Invoke-CheckedFixtureGit `
            -FixtureRoot $conflictRoot `
            -Arguments @('branch', '--show-current') `
            -Context 'Resolve default branch'
        $defaultBranch = [Text.Encoding]::UTF8.GetString(
            $branchResult.StdoutBytes
        ).Trim()
        [void](Invoke-CheckedFixtureGit `
            -FixtureRoot $conflictRoot `
            -Arguments @('checkout', '--quiet', '-b', 'synthetic-side') `
            -Context 'Create conflict side branch')
        Set-Content -LiteralPath $conflictPath -Value 'side' -Encoding UTF8
        [void](Invoke-CheckedFixtureGit `
            -FixtureRoot $conflictRoot `
            -Arguments @('add', '--', 'conflict.md') `
            -Context 'Stage conflict side')
        [void](Invoke-CheckedFixtureGit `
            -FixtureRoot $conflictRoot `
            -Arguments @(
                '-c',
                'user.name=Synthetic',
                '-c',
                "user.email=$syntheticEmail",
                'commit',
                '--quiet',
                '-m',
                'side'
            ) `
            -Context 'Commit conflict side')
        [void](Invoke-CheckedFixtureGit `
            -FixtureRoot $conflictRoot `
            -Arguments @('checkout', '--quiet', $defaultBranch) `
            -Context 'Return to default branch')
        Set-Content -LiteralPath $conflictPath -Value 'main' -Encoding UTF8
        [void](Invoke-CheckedFixtureGit `
            -FixtureRoot $conflictRoot `
            -Arguments @('add', '--', 'conflict.md') `
            -Context 'Stage conflict main')
        [void](Invoke-CheckedFixtureGit `
            -FixtureRoot $conflictRoot `
            -Arguments @(
                '-c',
                'user.name=Synthetic',
                '-c',
                "user.email=$syntheticEmail",
                'commit',
                '--quiet',
                '-m',
                'main'
            ) `
            -Context 'Commit conflict main')
        $mergeResult = Invoke-IsolatedGit `
            -GitPath $gitCommand.Source `
            -WorkingDirectory $conflictRoot `
            -IsolationRoot $gitIsolationRoot `
            -Arguments @(
                '-c',
                'user.name=Synthetic',
                '-c',
                "user.email=$syntheticEmail",
                'merge',
                '--no-edit',
                'synthetic-side'
            ) `
            -InheritedEnvironment $adversarialEnvironment
        if ($mergeResult.ExitCode -eq 0 -or
            -not (Test-BoundedResultHealthy -Result $mergeResult)) {
            Add-Failure "Expected the synthetic branch merge to produce an unmerged index. Output: $($mergeResult.Output.Trim())"
        } else {
            $unmergedResult = Invoke-CheckedFixtureGit `
                -FixtureRoot $conflictRoot `
                -Arguments @('ls-files', '--unmerged', '--') `
                -Context 'Inspect synthetic unmerged index'
            if ($unmergedResult.StdoutBytes.Length -eq 0) {
                Add-Failure "Expected merge failure to leave unmerged index stages. Merge output: $($mergeResult.Output.Trim())"
            } else {
                $conflictResult = Invoke-Scanner -ScanPath $conflictRoot
                if ($conflictResult.ExitCode -ne 2 -or
                    $conflictResult.Output -notmatch
                    'integrity: git-index-conflict') {
                    Add-Failure "Expected an unmerged index to fail closed. Output: $($conflictResult.Output.Trim())"
                }
            }
        }

        if (-not $runtimeIsWindows) {
            # POSIX permits control characters in file names. Findings must
            # escape them so a path cannot forge extra CI log lines.
            $controlRoot = New-CheckedGitFixture -Name 'control-path'
            $controlName = 'control' + [char]10 + 'name.md'
            $controlMarker = ('g' + 'hp_') + 'synthetic_control_path'
            Set-Content `
                -LiteralPath (Join-Path $controlRoot $controlName) `
                -Value "synthetic marker: $controlMarker" `
                -Encoding UTF8
            [void](Invoke-CheckedFixtureGit `
                -FixtureRoot $controlRoot `
                -Arguments @('add', '-A') `
                -Context 'Stage control-character path')
            $controlResult = Invoke-Scanner -ScanPath $controlRoot
            if ($controlResult.ExitCode -eq 0 -or
                $controlResult.Output -notmatch
                'control\\u000aname\.md') {
                Add-Failure "Expected control characters in displayed paths to be escaped. Output: $($controlResult.Output.Trim())"
            }

            # Feed three malformed ls-files byte streams through the public
            # entrypoint. The fake executable is a local synthetic fixture;
            # no repository content or external command is consulted.
            $fakeGitDirectory = Join-Path $tempRoot 'fake-git-bin'
            $fakeGitRoot = Join-Path $tempRoot 'fake-git-root'
            New-Item -ItemType Directory -Path $fakeGitDirectory | Out-Null
            New-Item -ItemType Directory -Path $fakeGitRoot | Out-Null
            $fakeGitPath = Join-Path $fakeGitDirectory 'git'
            $fakeGitScript = @'
#!/bin/sh
mode=
if [ -f .fake-git-mode ]; then
  IFS= read -r mode < .fake-git-mode
fi
case "$*" in
  *"rev-parse --show-toplevel"*)
    printf '%s\n' "$PWD"
    ;;
  *"ls-files -z --stage --debug"*)
    case "$mode" in
      header)
        printf 'bad-header\tfile.md\0  ctime: 0:0\n  mtime: 0:0\n  dev: 0\tino: 0\n  uid: 0\tgid: 0\n  size: 0\tflags: 0\n'
        ;;
      path)
        printf '100644 1111111111111111111111111111111111111111 0\t../escape.md\0  ctime: 0:0\n  mtime: 0:0\n  dev: 0\tino: 0\n  uid: 0\tgid: 0\n  size: 0\tflags: 0\n'
        ;;
    esac
    ;;
  *"ls-files -z --stage"*)
    case "$mode" in
      nul)
        printf '100644 1111111111111111111111111111111111111111 0\tfile.md'
        ;;
      header)
        printf 'bad-header\tfile.md\0'
        ;;
      path)
        printf '100644 1111111111111111111111111111111111111111 0\t../escape.md\0'
        ;;
    esac
    ;;
  *)
    exit 1
    ;;
esac
'@
            [IO.File]::WriteAllText(
                $fakeGitPath,
                $fakeGitScript,
                [Text.UTF8Encoding]::new($false)
            )
            $fakeChmodResult = Invoke-PrivateMarkerBoundedProcess `
                -FileName $chmodCommand.Source `
                -Arguments @('+x', $fakeGitPath) `
                -IsolationRoot (Join-Path $tempRoot 'fake-git-chmod') `
                -TimeoutMilliseconds 10000
            if ($fakeChmodResult.ExitCode -ne 0 -or
                -not (Test-BoundedResultHealthy -Result $fakeChmodResult)) {
                Add-Failure 'Expected the synthetic fake Git fixture to be executable.'
            } else {
                $fakePath = $fakeGitDirectory +
                    [IO.Path]::PathSeparator +
                    $scannerDefaultPath
                foreach ($malformedCase in @(
                    @{
                        Mode = 'nul'
                        Reason = 'git-index-nul'
                    },
                    @{
                        Mode = 'header'
                        Reason = 'git-index-header'
                    },
                    @{
                        Mode = 'path'
                        Reason = 'git-index-path'
                    }
                )) {
                    [IO.File]::WriteAllText(
                        (Join-Path $fakeGitRoot '.fake-git-mode'),
                        $malformedCase.Mode,
                        [Text.UTF8Encoding]::new($false)
                    )
                    $malformedResult = Invoke-Scanner `
                        -ScanPath $fakeGitRoot `
                        -InheritedEnvironment @{
                            PATH = $fakePath
                        }
                    if ($malformedResult.ExitCode -ne 2 -or
                        $malformedResult.Output -notmatch
                        ("integrity: " +
                            [regex]::Escape($malformedCase.Reason))) {
                        Add-Failure "Expected malformed $($malformedCase.Mode) index output to fail closed. Output: $($malformedResult.Output.Trim())"
                    }
                }
            }
        }
    }
}
finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}

if ($failures.Count -gt 0) {
    Write-Host 'Private marker scan self-test failed:'
    foreach ($failure in $failures) {
        Write-Host "- $failure"
    }
    exit 1
}

Write-Host 'Private marker scan self-test passed.'
exit 0
