# NOTE: Keep this file saved as UTF-8 WITH BOM. It contains a Japanese
# heading literal (the templates/ja checks below), and Windows PowerShell 5.1
# parses BOM-less .ps1 files as ANSI — the misread multi-byte bytes can
# swallow an adjacent quote and break parsing ("The string is missing the
# terminator"). The BOM makes 5.1 parse the file as UTF-8.
[CmdletBinding()]
param(
    [string]$Path = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptRoot = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($scriptRoot)) {
    $scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
}

if ([string]::IsNullOrWhiteSpace($Path)) {
    $Path = Split-Path -Parent $scriptRoot
}

$root = (Resolve-Path -LiteralPath $Path).Path
$failures = New-Object System.Collections.Generic.List[string]

function Add-Failure {
    param([string]$Message)
    $failures.Add($Message) | Out-Null
}

function Get-RepoFilePath {
    param([string]$RelativePath)
    return Join-Path $root $RelativePath
}

function Assert-FileExists {
    param([string]$RelativePath)

    $filePath = Get-RepoFilePath -RelativePath $RelativePath
    if (-not (Test-Path -LiteralPath $filePath -PathType Leaf)) {
        Add-Failure "Missing required file: $RelativePath"
    }
}

function Assert-FileContains {
    param(
        [string]$RelativePath,
        [string]$Pattern,
        [string]$Description
    )

    $filePath = Get-RepoFilePath -RelativePath $RelativePath
    if (-not (Test-Path -LiteralPath $filePath -PathType Leaf)) {
        Add-Failure "Cannot inspect missing file: $RelativePath ($Description)"
        return
    }

    # Explicit UTF-8: Windows PowerShell 5.1 otherwise decodes BOM-less UTF-8
    # as the ANSI code page and garbles the Japanese template headings.
    $content = Get-Content -LiteralPath $filePath -Raw -Encoding UTF8
    if ($content -notmatch $Pattern) {
        Add-Failure "$RelativePath is missing: $Description"
    }
}

function Test-WorkflowExternalUsesPolicy {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Source
    )

    $violations = New-Object System.Collections.Generic.List[object]
    $lines = @($Source -split '\r?\n')
    for ($lineIndex = 0; $lineIndex -lt $lines.Count; $lineIndex++) {
        $line = $lines[$lineIndex]
        $trimmed = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($trimmed) -or
            $trimmed.StartsWith('#', [StringComparison]::Ordinal)) {
            continue
        }

        # YAML explicit keys, escaped/multiline double-quoted scalars, and
        # anchor/alias mapping keys can hide a semantic `uses` key from a
        # lexical validator. This repository does not need those forms, so
        # reject their indicators broadly rather than guessing at decoded,
        # folded, flow-style, or aliased YAML.
        if ($line -match '^\s*(?:-\s*)?\?\s+' -or
            $line -match '"[^"]*\\' -or
            $line -match (
                '(?:^|[\s\[\]\{\},:?-])&[^\s\[\]\{\},]+'
            ) -or
            $line -match (
                '(?:^|[\s\[\]\{\},:?-])' +
                '\*[^\s\[\]\{\},:]+\s*:'
            )) {
            $violations.Add([pscustomobject]@{
                Line = $lineIndex + 1
                Reason = 'non-canonical, escaped, or aliased workflow mapping'
            }) | Out-Null
            continue
        }

        # Fail closed on every active uses word, including quoted keys and
        # split/explicit forms. Inline flow mappings and unrelated executable
        # text containing a standalone `uses` word are deliberately rejected
        # because a regex-only validator cannot safely recover YAML semantics.
        $usesToken = [regex]::Match(
            $line,
            '(?i)(?:^|[\s?{,])(?:"uses"|''uses''|uses)(?=\s|:|$)'
        )
        if (-not $usesToken.Success) {
            continue
        }

        $canonicalUse = [regex]::Match(
            $line,
            '^\s*(?:-\s*)?uses\s*:\s*(?:"(?<double>[^"\s#]+)"|''(?<single>[^''\s#]+)''|(?<bare>[^\s#]+))(?:[ \t]+#.*)?[ \t]*$'
        )
        if (-not $canonicalUse.Success) {
            $violations.Add([pscustomobject]@{
                Line = $lineIndex + 1
                Reason = 'non-canonical uses syntax'
            }) | Out-Null
            continue
        }

        $reference = @(
            $canonicalUse.Groups['double'].Value,
            $canonicalUse.Groups['single'].Value,
            $canonicalUse.Groups['bare'].Value
        ) | Where-Object { -not [string]::IsNullOrEmpty($_) } |
            Select-Object -First 1
        if ([string]::IsNullOrWhiteSpace($reference)) {
            $violations.Add([pscustomobject]@{
                Line = $lineIndex + 1
                Reason = 'empty uses reference'
            }) | Out-Null
            continue
        }

        # Repository-local actions are already immutable with the checked-out
        # commit. Every other action must name an owner/repository path and one
        # exact lowercase Git object ID, not a tag, branch, expression, or
        # abbreviated revision.
        if ($reference.StartsWith('./', [StringComparison]::Ordinal)) {
            continue
        }
        if ($reference -cnotmatch (
            '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+' +
            '(?:/[A-Za-z0-9_.-]+)*@[0-9a-f]{40}$'
        )) {
            $violations.Add([pscustomobject]@{
                Line = $lineIndex + 1
                Reason = 'external uses reference is not pinned to a full lowercase commit SHA'
            }) | Out-Null
        }
    }

    return [pscustomobject]@{
        IsValid = $violations.Count -eq 0
        Violations = @($violations | ForEach-Object { $_ })
    }
}

function Assert-WorkflowExternalUsesPolicyRegressions {
    $commit = 'fbc6f3992d24b796d5a048ff273f7fcc4a7b6c09'
    $cases = @(
        [pscustomobject]@{
            Name = 'full-sha'
            Expected = $true
            Source = "steps:`n  - uses: actions/checkout@$commit # v5.1.0"
        },
        [pscustomobject]@{
            Name = 'quoted-full-sha-and-local-action'
            Expected = $true
            Source = (
                "steps:`n" +
                "  - uses: `"owner/action@$commit`"`n" +
                "  - uses: ./.github/actions/local"
            )
        },
        [pscustomobject]@{
            Name = 'comment-only'
            Expected = $true
            Source = "steps:`n  # uses: owner/action@v1"
        },
        [pscustomobject]@{
            Name = 'mutable-tag-after-pinned-reference'
            Expected = $false
            Source = (
                "steps:`n" +
                "  - uses: owner/action@$commit`n" +
                "  - uses: owner/action@v1"
            )
        },
        [pscustomobject]@{
            Name = 'abbreviated-sha'
            Expected = $false
            Source = "steps:`n  - uses: owner/action@fbc6f3992d24"
        },
        [pscustomobject]@{
            Name = 'non-comment-hash-suffix'
            Expected = $false
            Source = "steps:`n  - uses: owner/action@$commit#v1"
        },
        [pscustomobject]@{
            Name = 'dynamic-reference'
            Expected = $false
            Source = 'steps:' + "`n" +
                '  - uses: owner/action@${{ inputs.ref }}'
        },
        [pscustomobject]@{
            Name = 'docker-reference'
            Expected = $false
            Source = "steps:`n  - uses: docker://synthetic:latest"
        },
        [pscustomobject]@{
            Name = 'inline-flow-mapping'
            Expected = $false
            Source = "steps:`n  - { uses: owner/action@$commit }"
        },
        [pscustomobject]@{
            Name = 'quoted-uses-key'
            Expected = $false
            Source = "steps:`n  - `"uses`": owner/action@$commit"
        },
        [pscustomobject]@{
            Name = 'explicit-uses-key'
            Expected = $false
            Source = (
                "steps:`n" +
                "  - ? uses`n" +
                "    : owner/action@$commit"
            )
        },
        [pscustomobject]@{
            Name = 'escaped-uses-key'
            Expected = $false
            Source = (
                'steps:' + "`n" +
                '  - "u\u0073es": owner/action@' + $commit
            )
        },
        [pscustomobject]@{
            Name = 'aliased-escaped-uses-key'
            Expected = $false
            Source = (
                'env:' + "`n" +
                '  KEY: &uses_key "u\u0073es"' + "`n" +
                'jobs:' + "`n" +
                '  validate:' + "`n" +
                '    steps:' + "`n" +
                '      - *uses_key: owner/action@v1'
            )
        },
        [pscustomobject]@{
            Name = 'aliased-plain-uses-key'
            Expected = $false
            Source = (
                "env:`n" +
                "  KEY: &uses_key uses`n" +
                "jobs:`n" +
                "  validate:`n" +
                "    steps:`n" +
                "      - *uses_key: owner/action@$commit"
            )
        },
        [pscustomobject]@{
            Name = 'flow-aliased-folded-uses-key'
            Expected = $false
            Source = (
                "jobs:`n" +
                "  validate:`n" +
                "    strategy:`n" +
                "      matrix:`n" +
                '        key: [&uses_key "u\' + "`n" +
                '          ses"]' + "`n" +
                "    steps: [{*uses_key: owner/action@v1}]"
            )
        },
        [pscustomobject]@{
            Name = 'folded-escaped-uses-key'
            Expected = $false
            Source = (
                "steps:`n" +
                '  - "u\' + "`n" +
                '      ses": owner/action@v1'
            )
        }
    )

    foreach ($case in $cases) {
        $result = Test-WorkflowExternalUsesPolicy -Source $case.Source
        if ($result.IsValid -ne $case.Expected) {
            Add-Failure "Workflow action pin policy regression failed: $($case.Name)."
        }
    }
}

function Assert-AllWorkflowExternalUsesPinned {
    $workflowRoot = Get-RepoFilePath -RelativePath '.github/workflows'
    if (-not (Test-Path -LiteralPath $workflowRoot -PathType Container)) {
        Add-Failure 'Missing required workflow directory: .github/workflows'
        return
    }

    $workflowFiles = @(
        Get-ChildItem -LiteralPath $workflowRoot -File |
            Where-Object { $_.Extension -in @('.yml', '.yaml') }
    )
    if ($workflowFiles.Count -eq 0) {
        Add-Failure 'No YAML workflow files were found under .github/workflows.'
        return
    }

    foreach ($workflowFile in $workflowFiles) {
        $relativePath = '.github/workflows/' + $workflowFile.Name
        $source = Get-Content `
            -LiteralPath $workflowFile.FullName `
            -Raw `
            -Encoding UTF8
        $result = Test-WorkflowExternalUsesPolicy -Source $source
        foreach ($violation in $result.Violations) {
            Add-Failure (
                "$relativePath line $($violation.Line): " +
                $violation.Reason
            )
        }
    }
}

function Test-WindowsPowerShell51WorkflowJobPolicy {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Source
    )

    $violations = New-Object System.Collections.Generic.List[string]
    $jobMatches = [regex]::Matches(
        $Source,
        '(?ms)^  validate-windows-powershell-5-1:\s*\r?\n' +
            '(?<body>.*?)(?=^  (?!#)\S[^\r\n]*?:[^\r\n]*$|\z)'
    )
    if ($jobMatches.Count -ne 1) {
        $violations.Add(
            'expected exactly one validate-windows-powershell-5-1 job'
        ) | Out-Null
    }
    else {
        # Scope every assertion to the PS5.1 job body. Independent global
        # matches can otherwise let the main pwsh matrix mask a missing
        # checkout, timeout, or validation command in the fresh PS5.1 job.
        $body = $jobMatches[0].Groups['body'].Value
        $expectedBody = @'
    name: Validate skill repository (windows-latest, PowerShell 5.1)
    runs-on: windows-latest
    timeout-minutes: 25
    steps:
      - name: Check out repository
        uses: actions/checkout@fbc6f3992d24b796d5a048ff273f7fcc4a7b6c09 # v5.1.0

      - name: Validate OSS readiness
        shell: pwsh
        run: powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File ./scripts/validate-oss-readiness.ps1

      - name: Check whitespace
        shell: pwsh
        run: git diff-tree --check 4b825dc642cb6eb9a060e54bf8d69288fbee4904 HEAD
'@
        $normalizedBody = ($body -replace '\r\n?', "`n").TrimEnd(
            [char[]]@([char]10)
        )
        $normalizedExpectedBody =
            ($expectedBody -replace '\r\n?', "`n").TrimEnd(
                [char[]]@([char]10)
            )
        if (-not [string]::Equals(
                $normalizedBody,
                $normalizedExpectedBody,
                [StringComparison]::Ordinal
            )) {
            $violations.Add(
                'PS5.1 job body does not match the canonical fresh-runner suite'
            ) | Out-Null
        }
        $requirements = @(
            [pscustomobject]@{
                Name = 'windows runner'
                Pattern = '(?m)^    runs-on:\s*windows-latest\s*$'
            },
            [pscustomobject]@{
                Name = '25-minute bound'
                Pattern = '(?m)^    timeout-minutes:\s*25\s*$'
            },
            [pscustomobject]@{
                Name = 'official immutable checkout'
                Pattern = (
                    '(?ms)^      - name: Check out repository\s*\r?\n' +
                    '        uses: actions/checkout@' +
                    'fbc6f3992d24b796d5a048ff273f7fcc4a7b6c09' +
                    '\s+#\s+v5\.1\.0\s*$'
                )
            },
            [pscustomobject]@{
                Name = 'Windows PowerShell 5.1 readiness command'
                Pattern = (
                    '(?ms)^      - name: Validate OSS readiness\s*\r?\n' +
                    '        shell: pwsh\s*\r?\n' +
                    '        run: powershell\.exe -NoProfile -NonInteractive ' +
                    '-ExecutionPolicy Bypass -File ' +
                    '\./scripts/validate-oss-readiness\.ps1\s*$'
                )
            },
            [pscustomobject]@{
                Name = 'committed-tree whitespace command'
                Pattern = (
                    '(?ms)^      - name: Check whitespace\s*\r?\n' +
                    '        shell: pwsh\s*\r?\n' +
                    '        run: git diff-tree --check ' +
                    '4b825dc642cb6eb9a060e54bf8d69288fbee4904 HEAD\s*$'
                )
            }
        )
        foreach ($requirement in $requirements) {
            if ($body -notmatch $requirement.Pattern) {
                $violations.Add(
                    "missing PS5.1 job requirement: $($requirement.Name)"
                ) | Out-Null
            }
        }
    }

    return [pscustomobject]@{
        IsValid = $violations.Count -eq 0
        Violations = @($violations | ForEach-Object { $_ })
    }
}

function Assert-WindowsPowerShell51WorkflowJobRegressions {
    $commit = 'fbc6f3992d24b796d5a048ff273f7fcc4a7b6c09'
    $valid = @"
jobs:
  validate-windows-powershell-5-1:
    name: Validate skill repository (windows-latest, PowerShell 5.1)
    runs-on: windows-latest
    timeout-minutes: 25
    steps:
      - name: Check out repository
        uses: actions/checkout@$commit # v5.1.0

      - name: Validate OSS readiness
        shell: pwsh
        run: powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File ./scripts/validate-oss-readiness.ps1

      - name: Check whitespace
        shell: pwsh
        run: git diff-tree --check 4b825dc642cb6eb9a060e54bf8d69288fbee4904 HEAD
"@
    $dummy = @"
jobs:
  validate:
    timeout-minutes: 25
    steps:
      - name: Check out repository
        uses: actions/checkout@$commit # v5.1.0
      - name: Validate OSS readiness
        shell: pwsh
        run: powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File ./scripts/validate-oss-readiness.ps1
      - name: Check whitespace
        shell: pwsh
        run: git diff-tree --check 4b825dc642cb6eb9a060e54bf8d69288fbee4904 HEAD
  validate-windows-powershell-5-1:
    runs-on: windows-latest
    steps:
      - name: Dummy
        shell: powershell
        run: Write-Output dummy
"@
    $quotedBorrowedJob = @"
jobs:
  validate-windows-powershell-5-1:
    runs-on: windows-latest
    steps:
      - name: Dummy
        shell: powershell
        run: Write-Output dummy
  "borrowed":
    timeout-minutes: 25
    steps:
      - name: Check out repository
        uses: actions/checkout@$commit # v5.1.0
      - name: Validate OSS readiness
        shell: pwsh
        run: powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File ./scripts/validate-oss-readiness.ps1
      - name: Check whitespace
        shell: pwsh
        run: git diff-tree --check 4b825dc642cb6eb9a060e54bf8d69288fbee4904 HEAD
"@
    $scalarSpoof = @"
jobs:
  validate-windows-powershell-5-1:
    name: |2
      - name: Check out repository
        uses: actions/checkout@$commit # v5.1.0
      - name: Validate OSS readiness
        shell: pwsh
        run: powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File ./scripts/validate-oss-readiness.ps1
      - name: Check whitespace
        shell: pwsh
        run: git diff-tree --check 4b825dc642cb6eb9a060e54bf8d69288fbee4904 HEAD
    runs-on: windows-latest
    timeout-minutes: 25
    steps:
      - name: Dummy
        shell: powershell
        run: Write-Output dummy
"@
    foreach ($case in @(
        [pscustomobject]@{
            Name = 'complete-fresh-ps51-job'
            Source = $valid
            Expected = $true
        },
        [pscustomobject]@{
            Name = 'global-matches-cannot-mask-dummy-ps51-job'
            Source = $dummy
            Expected = $false
        },
        [pscustomobject]@{
            Name = 'quoted-next-job-cannot-lend-ps51-requirements'
            Source = $quotedBorrowedJob
            Expected = $false
        },
        [pscustomobject]@{
            Name = 'scalar-text-cannot-spoof-ps51-steps'
            Source = $scalarSpoof
            Expected = $false
        }
    )) {
        $result = Test-WindowsPowerShell51WorkflowJobPolicy `
            -Source $case.Source
        if ($result.IsValid -ne $case.Expected) {
            Add-Failure "PS5.1 workflow job policy regression failed: $($case.Name)."
        }
    }
}

function Assert-WindowsPowerShell51WorkflowJob {
    $workflowPath = Get-RepoFilePath `
        -RelativePath '.github/workflows/validate.yml'
    $source = Get-Content `
        -LiteralPath $workflowPath `
        -Raw `
        -Encoding UTF8
    $result = Test-WindowsPowerShell51WorkflowJobPolicy -Source $source
    foreach ($violation in $result.Violations) {
        Add-Failure "PS5.1 workflow job: $violation"
    }
}

function Get-CanonicalValidationWorkflowSource {
    # The built-in validation workflow is deliberately small and security
    # sensitive. An exact source contract prevents a valid YAML scalar,
    # duplicate quoted job key, conditional step, or extra field from lending
    # misleading raw lines to the dependency-free lexical checks.
    return @'
name: Validate

on:
  pull_request:
  push:
    branches:
      - main

permissions:
  contents: read

jobs:
  validate:
    name: Validate skill repository (${{ matrix.os }})
    # The scanner supports Windows PowerShell and POSIX PowerShell paths. Run
    # both Linux and macOS because macOS exercises the native libc setsid(2)
    # fallback that commonly has no external setsid executable.
    strategy:
      fail-fast: false
      matrix:
        os:
          - windows-latest
          - ubuntu-latest
          - macos-15
    runs-on: ${{ matrix.os }}
    timeout-minutes: 25
    steps:
      - name: Check out repository
        uses: actions/checkout@fbc6f3992d24b796d5a048ff273f7fcc4a7b6c09 # v5.1.0

      - name: Validate OSS readiness
        shell: pwsh
        run: ./scripts/validate-oss-readiness.ps1

      - name: Test private marker scan
        shell: pwsh
        run: ./scripts/test-scan-private-markers.ps1

      - name: Scan for private markers
        shell: pwsh
        run: ./scripts/scan-private-markers.ps1

      - name: Check whitespace
        shell: pwsh
        # A fresh checkout has no worktree/index diff, so `git diff --check`
        # would be vacuous here. Diff the committed tree against the empty
        # tree (the SHA-1 empty-tree constant) so whitespace errors in
        # committed content actually fail the job (exit 2 on findings).
        run: git diff-tree --check 4b825dc642cb6eb9a060e54bf8d69288fbee4904 HEAD

  validate-windows-powershell-5-1:
    name: Validate skill repository (windows-latest, PowerShell 5.1)
    runs-on: windows-latest
    timeout-minutes: 25
    steps:
      - name: Check out repository
        uses: actions/checkout@fbc6f3992d24b796d5a048ff273f7fcc4a7b6c09 # v5.1.0

      - name: Validate OSS readiness
        shell: pwsh
        run: powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File ./scripts/validate-oss-readiness.ps1

      - name: Check whitespace
        shell: pwsh
        run: git diff-tree --check 4b825dc642cb6eb9a060e54bf8d69288fbee4904 HEAD
'@
}

function Test-CanonicalValidationWorkflowSource {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Source
    )

    $expected = Get-CanonicalValidationWorkflowSource
    $normalizedSource = ($Source -replace '\r\n?', "`n").TrimEnd(
        [char[]]@([char]10)
    )
    $normalizedExpected = ($expected -replace '\r\n?', "`n").TrimEnd(
        [char[]]@([char]10)
    )
    return [string]::Equals(
        $normalizedSource,
        $normalizedExpected,
        [StringComparison]::Ordinal
    )
}

function Assert-CanonicalValidationWorkflowSourceRegressions {
    $canonical = Get-CanonicalValidationWorkflowSource
    if (-not (Test-CanonicalValidationWorkflowSource -Source $canonical)) {
        Add-Failure 'Canonical validation workflow rejected its own source.'
    }
    $withoutMacOS = $canonical -replace (
        '(?m)^\s{10}- macos-15\r?\n'
    ), ''
    if (Test-CanonicalValidationWorkflowSource -Source $withoutMacOS) {
        Add-Failure (
            'Canonical validation workflow accepted a missing macOS runner.'
        )
    }
    if (Test-CanonicalValidationWorkflowSource -Source (
            $canonical + "`n# unexpected workflow mutation"
        )) {
        Add-Failure 'Canonical validation workflow accepted an extra mutation.'
    }
}

function Assert-CanonicalValidationWorkflowSource {
    $workflowPath = Get-RepoFilePath `
        -RelativePath '.github/workflows/validate.yml'
    $source = Get-Content `
        -LiteralPath $workflowPath `
        -Raw `
        -Encoding UTF8
    if (-not (Test-CanonicalValidationWorkflowSource -Source $source)) {
        Add-Failure (
            '.github/workflows/validate.yml does not match the reviewed ' +
            'canonical workflow source.'
        )
    }
}

function Test-TemplateSectionContract {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Source,
        [Parameter(Mandatory = $true)]
        [string]$ExpectedTitle,
        [Parameter(Mandatory = $true)]
        [string[]]$ExpectedSections
    )

    if ([string]::IsNullOrEmpty($Source) -or
        [string]::IsNullOrEmpty($ExpectedTitle) -or
        $ExpectedSections.Count -eq 0 -or
        $Source -match "`r(?!`n)") {
        return $false
    }

    $seenExpectedSections = New-Object 'System.Collections.Generic.HashSet[string]' (
        [StringComparer]::Ordinal
    )
    foreach ($expectedSection in $ExpectedSections) {
        if ([string]::IsNullOrEmpty($expectedSection) -or
            -not $seenExpectedSections.Add($expectedSection)) {
            return $false
        }
    }

    $lines = @($Source -split '\r?\n')
    if ($lines.Count -eq 0) {
        return $false
    }

    $firstLine = $lines[0].TrimStart([char]0xFEFF)
    if (-not [string]::Equals(
        $firstLine,
        "# $ExpectedTitle",
        [StringComparison]::Ordinal
    )) {
        return $false
    }

    $actualSections = New-Object System.Collections.Generic.List[string]
    $inFence = $false
    $fenceCharacter = ''
    $minimumFenceLength = 0

    for ($lineIndex = 1; $lineIndex -lt $lines.Count; $lineIndex++) {
        $line = $lines[$lineIndex]

        if ($inFence) {
            $closingPattern = (
                '^[ ]{0,3}' +
                [Regex]::Escape($fenceCharacter) +
                "{$minimumFenceLength,}[ `t]*$"
            )
            if ($line -match $closingPattern) {
                $inFence = $false
                $fenceCharacter = ''
                $minimumFenceLength = 0
            }
            continue
        }

        if ($line -match '^[ ]{0,3}(`{3,}|~{3,})(.*)$') {
            $fence = $Matches[1]
            $fenceInfo = $Matches[2]
            if ($fence.StartsWith('`', [StringComparison]::Ordinal) -and
                $fenceInfo.IndexOf('`', [StringComparison]::Ordinal) -ge 0) {
                return $false
            }
            $inFence = $true
            $fenceCharacter = $fence.Substring(0, 1)
            $minimumFenceLength = $fence.Length
            continue
        }

        # Raw HTML headings and Setext syntax would create unreviewed peers
        # without appearing in the pinned ATX schema. Bundled templates
        # intentionally use ATX headings only, so fail closed on either form.
        if ($line -match '(?i)</?h[12](?:[ \t\x0C/>]|$)') {
            return $false
        }
        if ($line -match '^[ ]{0,3}(?:=+|-+)[ \t]*$') {
            return $false
        }

        # CommonMark permits up to three leading spaces and empty ATX
        # headings. Detect those semantic headings before enforcing this
        # repository's stricter reviewed spelling.
        if ($line -match '^[ ]{0,3}(#{1,6})(?:[ \t]+.*)?[ \t]*$') {
            $headingLevel = $Matches[1].Length
            if ($headingLevel -eq 1) {
                # A second top-level title changes the document identity.
                return $false
            }
            if ($headingLevel -eq 2) {
                if ($line -notmatch '^##[ \t]+(.+?)[ \t]*$') {
                    return $false
                }
                $actualSections.Add($Matches[1]) | Out-Null
            }
        }
    }

    if ($inFence -or $actualSections.Count -ne $ExpectedSections.Count) {
        return $false
    }

    for ($sectionIndex = 0;
        $sectionIndex -lt $ExpectedSections.Count;
        $sectionIndex++) {
        if (-not [string]::Equals(
            $actualSections[$sectionIndex],
            $ExpectedSections[$sectionIndex],
            [StringComparison]::Ordinal
        )) {
            return $false
        }
    }

    return $true
}

function Assert-TemplateSectionContractRegressions {
    $expectedSections = @(
        'Canonical scope of this document',
        'Current position',
        'Next step'
    )
    $validSource = @(
        '# HANDOFF — <project>',
        '',
        '## Canonical scope of this document',
        '',
        'Owned scope.',
        '',
        '## Current position',
        '',
        '### Detail',
        '',
        'Current state.',
        '',
        '## Next step',
        '',
        '1. Continue.'
    ) -join "`n"

    if (-not (Test-TemplateSectionContract `
        -Source $validSource `
        -ExpectedTitle 'HANDOFF — <project>' `
        -ExpectedSections $expectedSections)) {
        Add-Failure 'Template section contract rejected the valid regression fixture.'
    }
    if (-not (Test-TemplateSectionContract `
        -Source $validSource.Replace("`n", "`r`n") `
        -ExpectedTitle 'HANDOFF — <project>' `
        -ExpectedSections $expectedSections)) {
        Add-Failure 'Template section contract rejected the CRLF regression fixture.'
    }

    $mutations = @(
        @{
            Name = 'missing required section'
            Source = $validSource.Replace(
                "## Current position`n`n### Detail`n`nCurrent state.`n`n",
                ''
            )
        },
        @{
            Name = 'reordered required sections'
            Source = $validSource.Replace(
                "## Current position`n`n### Detail`n`nCurrent state.`n`n## Next step",
                "## Next step`n`n1. Continue.`n`n## Current position"
            )
        },
        @{
            Name = 'duplicate required section'
            Source = $validSource + "`n## Next step`n"
        },
        @{
            Name = 'wrong required heading level'
            Source = $validSource.Replace('## Current position', '### Current position')
        },
        @{
            Name = 'required heading inside a fenced block'
            Source = $validSource.Replace(
                '## Current position',
                '```text' + "`n## Current position`n" + '```'
            )
        },
        @{
            Name = 'unexpected peer section'
            Source = $validSource.Replace(
                '## Next step',
                "## Unreviewed section`n`nUnexpected.`n`n## Next step"
            )
        },
        @{
            Name = 'wrong document title'
            Source = $validSource.Replace(
                '# HANDOFF — <project>',
                '# TASKS — <project>'
            )
        },
        @{
            Name = 'mixed bare carriage return'
            Source = $validSource.Replace("`n", "`r`n") + "`r"
        },
        @{
            Name = 'unclosed fenced block'
            Source = $validSource.Replace(
                'Current state.',
                '```text' + "`nCurrent state."
            )
        },
        @{
            Name = 'indented unexpected peer section'
            Source = $validSource.Replace(
                '## Next step',
                " ## Unexpected peer`n`n## Next step"
            )
        },
        @{
            Name = 'indented additional title'
            Source = $validSource.Replace(
                '## Next step',
                " # Unexpected title`n`n## Next step"
            )
        },
        @{
            Name = 'setext level-two section'
            Source = $validSource.Replace(
                '## Next step',
                "Unexpected peer`n---`n`n## Next step"
            )
        },
        @{
            Name = 'setext level-one title'
            Source = $validSource.Replace(
                '## Next step',
                "Unexpected title`n===`n`n## Next step"
            )
        },
        @{
            Name = 'empty ATX peer section'
            Source = $validSource.Replace(
                '## Next step',
                "##`n`n## Next step"
            )
        },
        @{
            Name = 'empty additional ATX title'
            Source = $validSource.Replace(
                '## Next step',
                "#`n`n## Next step"
            )
        },
        @{
            Name = 'invalid backtick fence hiding a peer section'
            Source = $validSource.Replace(
                'Current state.',
                '```foo`bar' + "`n## Unexpected peer`n" + '```'
            )
        },
        @{
            Name = 'raw HTML level-two section'
            Source = $validSource.Replace(
                '## Next step',
                '<h2 class="peer">Unexpected peer</h2>' + "`n`n## Next step"
            )
        },
        @{
            Name = 'uppercase raw HTML level-one title'
            Source = $validSource.Replace(
                '## Next step',
                '<H1 data-kind="peer">Unexpected title</H1>' + "`n`n## Next step"
            )
        },
        @{
            Name = 'form-feed raw HTML level-two section'
            Source = $validSource.Replace(
                '## Next step',
                (
                    '<h2' +
                    [char]0x0C +
                    'class="peer">Unexpected peer' +
                    "`n`n## Next step"
                )
            )
        }
    )

    if ($mutations.Count -ne 19) {
        Add-Failure 'Template section contract regression set is incomplete.'
    }
    foreach ($mutation in $mutations) {
        if ([string]::Equals(
            $mutation.Source,
            $validSource,
            [StringComparison]::Ordinal
        )) {
            Add-Failure (
                'Template section contract mutation did not change source: ' +
                $mutation.Name
            )
            continue
        }
        if (Test-TemplateSectionContract `
            -Source $mutation.Source `
            -ExpectedTitle 'HANDOFF — <project>' `
            -ExpectedSections $expectedSections) {
            Add-Failure (
                'Template section contract accepted mutation: ' +
                $mutation.Name
            )
        }
    }
}

function Assert-TemplateSectionContract {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RelativePath,
        [Parameter(Mandatory = $true)]
        [string]$ExpectedTitle,
        [Parameter(Mandatory = $true)]
        [string[]]$ExpectedSections
    )

    $filePath = Get-RepoFilePath -RelativePath $RelativePath
    if (-not (Test-Path -LiteralPath $filePath -PathType Leaf)) {
        Add-Failure "Cannot inspect missing template: $RelativePath"
        return
    }

    $source = Get-Content -LiteralPath $filePath -Raw -Encoding UTF8
    if (-not (Test-TemplateSectionContract `
        -Source $source `
        -ExpectedTitle $ExpectedTitle `
        -ExpectedSections $ExpectedSections)) {
        Add-Failure (
            "$RelativePath does not match its reviewed title and ordered " +
            'level-two section contract.'
        )
    }
}

function ConvertTo-NormalizedLfText {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Source
    )

    return $Source.Replace("`r`n", "`n").Replace("`r", "`n")
}

function ConvertFrom-StrictUtf8Bytes {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [byte[]]$Bytes
    )

    # Strip at most one physical UTF-8 BOM before strict decoding. Any second
    # BOM decodes to U+FEFF content and therefore remains digest-significant.
    $offset = 0
    if ($Bytes.Length -ge 3 -and
        $Bytes[0] -eq 0xEF -and
        $Bytes[1] -eq 0xBB -and
        $Bytes[2] -eq 0xBF) {
        $offset = 3
    }

    $strictUtf8 = [Text.UTF8Encoding]::new($false, $true)
    return $strictUtf8.GetString(
        $Bytes,
        $offset,
        $Bytes.Length - $offset
    )
}

function Get-NormalizedUtf8Sha256 {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Source
    )

    $normalizedSource = ConvertTo-NormalizedLfText -Source $Source
    $sha256 = [Security.Cryptography.SHA256]::Create()
    try {
        $digest = $sha256.ComputeHash(
            [Text.Encoding]::UTF8.GetBytes($normalizedSource)
        )
        return [BitConverter]::ToString($digest).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $sha256.Dispose()
    }
}

function Get-NormalizedUtf8Sha256FromBytes {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [byte[]]$Bytes
    )

    $source = ConvertFrom-StrictUtf8Bytes -Bytes $Bytes
    return Get-NormalizedUtf8Sha256 -Source $source
}

function Test-SkillTranslationDigestMarker {
    param(
        [Parameter(Mandatory = $true)]
        [string]$CanonicalSource,
        [Parameter(Mandatory = $true)]
        [string]$TranslationSource
    )

    $expectedDigest = Get-NormalizedUtf8Sha256 -Source $CanonicalSource
    $normalizedTranslation = ConvertTo-NormalizedLfText `
        -Source $TranslationSource
    if ([Regex]::Matches(
        $normalizedTranslation,
        'canonical-en-sha256',
        [Text.RegularExpressions.RegexOptions]::IgnoreCase
    ).Count -ne 1) {
        return $false
    }
    $markerPattern = (
        '(?m)^<!-- canonical-en-sha256: ([0-9a-f]{64}); ' +
        'normalization: utf8-lf -->$'
    )
    $markerMatches = [Regex]::Matches(
        $normalizedTranslation,
        $markerPattern
    )
    if ($markerMatches.Count -ne 1) {
        return $false
    }

    # Keep the acknowledgement visible at the top of the translated document
    # instead of allowing a stale marker to survive unnoticed in history text.
    $expectedPrefix = (
        "# Agent Handoff Docs（日本語完全版）`n`n" +
        "<!-- canonical-en-sha256: $expectedDigest; " +
        "normalization: utf8-lf -->`n"
    )
    if (-not $normalizedTranslation.StartsWith(
        $expectedPrefix,
        [StringComparison]::Ordinal
    )) {
        return $false
    }

    return [string]::Equals(
        $markerMatches[0].Groups[1].Value,
        $expectedDigest,
        [StringComparison]::Ordinal
    )
}

function Assert-SkillTranslationDigestRegressions {
    $canonicalSource = "First line.`nSecond line.`n"
    $canonicalBytes = [Text.Encoding]::UTF8.GetBytes($canonicalSource)
    $utf8Bom = [byte[]](0xEF, 0xBB, 0xBF)
    $oneBomBytes = [byte[]]($utf8Bom + $canonicalBytes)
    $twoBomBytes = [byte[]]($utf8Bom + $utf8Bom + $canonicalBytes)
    $digest = Get-NormalizedUtf8Sha256FromBytes -Bytes $canonicalBytes
    $oneBomDigest = Get-NormalizedUtf8Sha256FromBytes -Bytes $oneBomBytes
    $twoBomDigest = Get-NormalizedUtf8Sha256FromBytes -Bytes $twoBomBytes
    if (-not [string]::Equals(
        $digest,
        $oneBomDigest,
        [StringComparison]::Ordinal
    ) -or [string]::Equals(
        $digest,
        $twoBomDigest,
        [StringComparison]::Ordinal
    )) {
        Add-Failure (
            'Skill translation digest must ignore exactly one physical BOM ' +
            'and retain a second BOM as content.'
        )
    }

    $invalidUtf8Rejected = $false
    try {
        Get-NormalizedUtf8Sha256FromBytes `
            -Bytes ([byte[]](0xC3, 0x28)) | Out-Null
    }
    catch [Text.DecoderFallbackException] {
        $invalidUtf8Rejected = $true
    }
    if (-not $invalidUtf8Rejected) {
        Add-Failure 'Skill translation digest accepted invalid UTF-8 bytes.'
    }

    $validTranslation = (
        "# Agent Handoff Docs（日本語完全版）`n`n" +
        "<!-- canonical-en-sha256: $digest; normalization: utf8-lf -->`n`n" +
        "Translated body.`n"
    )

    $equivalentCanonicalSources = @(
        $canonicalSource,
        $canonicalSource.Replace("`n", "`r`n")
    )
    foreach ($equivalentSource in $equivalentCanonicalSources) {
        if (-not (Test-SkillTranslationDigestMarker `
            -CanonicalSource $equivalentSource `
            -TranslationSource $validTranslation)) {
            Add-Failure (
                'Skill translation digest rejected an equivalent UTF-8/LF ' +
                'canonical source.'
            )
        }
    }

    $mutations = @(
        @{
            Name = 'changed canonical source'
            Canonical = $canonicalSource + 'Changed.'
            Translation = $validTranslation
        },
        @{
            Name = 'uppercase digest'
            Canonical = $canonicalSource
            Translation = $validTranslation.Replace(
                $digest,
                $digest.ToUpperInvariant()
            )
        },
        @{
            Name = 'duplicate digest marker'
            Canonical = $canonicalSource
            Translation = (
                $validTranslation +
                "<!-- canonical-en-sha256: $digest; " +
                "normalization: utf8-lf -->`n"
            )
        },
        @{
            Name = 'digest marker displaced from document header'
            Canonical = $canonicalSource
            Translation = $validTranslation.Replace(
                "`n<!-- canonical-en-sha256:",
                "`nIntro.`n`n<!-- canonical-en-sha256:"
            )
        },
        @{
            Name = 'unreviewed normalization label'
            Canonical = $canonicalSource
            Translation = $validTranslation.Replace('utf8-lf', 'raw-bytes')
        },
        @{
            Name = 'case-variant duplicate marker'
            Canonical = $canonicalSource
            Translation = (
                $validTranslation +
                "<!-- CANONICAL-EN-SHA256: $digest; " +
                "normalization: utf8-lf -->`n"
            )
        },
        @{
            Name = 'leading U+FEFF content'
            Canonical = [char]0xFEFF + $canonicalSource
            Translation = $validTranslation
        }
    )

    if ($mutations.Count -ne 7) {
        Add-Failure 'Skill translation digest regression set is incomplete.'
    }
    foreach ($mutation in $mutations) {
        if (Test-SkillTranslationDigestMarker `
            -CanonicalSource $mutation.Canonical `
            -TranslationSource $mutation.Translation) {
            Add-Failure (
                'Skill translation digest accepted mutation: ' +
                $mutation.Name
            )
        }
    }
}

function Assert-SkillTranslationDigest {
    $canonicalPath = Get-RepoFilePath -RelativePath 'SKILL.md'
    $translationPath = Get-RepoFilePath -RelativePath 'docs/SKILL.ja.md'
    if (-not (Test-Path -LiteralPath $canonicalPath -PathType Leaf) -or
        -not (Test-Path -LiteralPath $translationPath -PathType Leaf)) {
        return
    }

    try {
        $canonicalBytes = [IO.File]::ReadAllBytes($canonicalPath)
        $translationBytes = [IO.File]::ReadAllBytes($translationPath)
        $canonicalSource = ConvertFrom-StrictUtf8Bytes -Bytes $canonicalBytes
        $translationSource = ConvertFrom-StrictUtf8Bytes -Bytes $translationBytes
    }
    catch [Text.DecoderFallbackException] {
        Add-Failure (
            'SKILL.md and docs/SKILL.ja.md must be strict UTF-8 for the ' +
            'translation digest contract.'
        )
        return
    }
    if (-not (Test-SkillTranslationDigestMarker `
        -CanonicalSource $canonicalSource `
        -TranslationSource $translationSource)) {
        $expectedDigest = Get-NormalizedUtf8Sha256FromBytes `
            -Bytes $canonicalBytes
        Add-Failure (
            'docs/SKILL.ja.md must acknowledge the reviewed SKILL.md ' +
            "digest: $expectedDigest"
        )
    }
}

function Test-SkillFrontmatter {
    $skillPath = Get-RepoFilePath -RelativePath 'SKILL.md'
    if (-not (Test-Path -LiteralPath $skillPath -PathType Leaf)) {
        return
    }

    $lines = Get-Content -LiteralPath $skillPath -Encoding UTF8
    if ($lines.Count -lt 4 -or $lines[0] -ne '---') {
        Add-Failure 'SKILL.md must start with YAML frontmatter.'
        return
    }

    $closingIndex = -1
    for ($index = 1; $index -lt $lines.Count; $index++) {
        if ($lines[$index] -eq '---') {
            $closingIndex = $index
            break
        }
    }

    if ($closingIndex -lt 0) {
        Add-Failure 'SKILL.md frontmatter must be closed with --- before content.'
        return
    }

    $frontmatter = $lines[1..($closingIndex - 1)] -join "`n"
    if ($frontmatter -notmatch '(?m)^name:\s*agent-handoff-docs\s*$') {
        Add-Failure 'SKILL.md frontmatter must declare name: agent-handoff-docs.'
    }
    if ($frontmatter -notmatch '(?m)^description:\s*\S') {
        Add-Failure 'SKILL.md frontmatter must include a non-empty description.'
    }
    if ($frontmatter.Length -gt 1024) {
        Add-Failure 'SKILL.md frontmatter must stay under 1024 characters.'
    }
}

$requiredFiles = @(
    '.editorconfig',
    '.gitattributes',
    '.gitignore',
    '.github/ISSUE_TEMPLATE/bug_report.yml',
    '.github/ISSUE_TEMPLATE/config.yml',
    '.github/pull_request_template.md',
    '.github/workflows/validate.yml',
    'CHANGELOG.md',
    'CODE_OF_CONDUCT.md',
    'CONTRIBUTING.md',
    'HANDOFF.md',
    'LICENSE',
    'README.md',
    'SECURITY.md',
    'SKILL.md',
    'docs/SKILL.ja.md',
    'docs/security-boundary-contract.md',
    'examples/canonical-scope-declarations.md',
    'examples/do-not-reread-entries.md',
    'examples/full-scan-verification-commands.md',
    'templates/en/START_HERE.md',
    'templates/en/REQUIREMENTS.md',
    'templates/en/HANDOFF.md',
    'templates/en/TASKS.md',
    'templates/ja/START_HERE.md',
    'templates/ja/REQUIREMENTS.md',
    'templates/ja/HANDOFF.md',
    'templates/ja/TASKS.md',
    'scripts/private-marker-process.ps1',
    'scripts/scan-private-markers.ps1',
    'scripts/test-scan-private-markers.ps1',
    'scripts/validate-oss-readiness.ps1'
)

foreach ($requiredFile in $requiredFiles) {
    Assert-FileExists -RelativePath $requiredFile
}

Assert-FileContains -RelativePath 'README.md' -Pattern '(?im)^##\s+Install' -Description 'installation instructions'
Assert-FileContains -RelativePath 'README.md' -Pattern '(?im)^##\s+Validation' -Description 'validation instructions'
Assert-FileContains -RelativePath 'README.md' -Pattern '(?im)^##\s+Contributing' -Description 'contribution guidance'
Assert-FileContains -RelativePath 'README.md' -Pattern '(?im)^##\s+Security' -Description 'security reporting guidance'
Assert-FileContains -RelativePath 'README.md' -Pattern 'CONTRIBUTING\.md' -Description 'link to CONTRIBUTING.md'
Assert-FileContains -RelativePath 'README.md' -Pattern 'SECURITY\.md' -Description 'link to SECURITY.md'
Assert-FileContains -RelativePath 'README.md' -Pattern 'docs/SKILL\.ja\.md' -Description 'link to the Japanese skill version'
Assert-FileContains -RelativePath 'README.md' -Pattern 'docs/security-boundary-contract\.md' -Description 'link to the security boundary contract'
Assert-FileContains -RelativePath 'README.md' -Pattern 'templates/en' -Description 'English template directory documented'
Assert-FileContains -RelativePath 'README.md' -Pattern 'templates/ja' -Description 'Japanese template directory documented'
Assert-FileContains -RelativePath '.gitignore' -Pattern '\.private-markers\.local' -Description 'ignore local private marker files'
Assert-FileContains -RelativePath 'CONTRIBUTING.md' -Pattern '(?im)no token|never.*token|secret' -Description 'secret-safe contribution guidance'
Assert-FileContains -RelativePath 'SECURITY.md' -Pattern '(?im)do not.*public|private|security' -Description 'private vulnerability reporting guidance'
Assert-FileContains -RelativePath 'SECURITY.md' -Pattern 'docs/security-boundary-contract\.md' -Description 'security boundary contract reference'
Assert-FileContains -RelativePath '.github/workflows/validate.yml' -Pattern 'validate-oss-readiness\.ps1' -Description 'OSS readiness validation in CI'
Assert-FileContains -RelativePath '.github/workflows/validate.yml' -Pattern 'scan-private-markers\.ps1' -Description 'private marker scan in CI'
Assert-FileContains -RelativePath '.github/workflows/validate.yml' -Pattern 'test-scan-private-markers\.ps1' -Description 'private marker scan self-test in CI'
Assert-FileContains -RelativePath '.github/workflows/validate.yml' -Pattern 'windows-latest' -Description 'Windows validation runner in CI'
Assert-FileContains -RelativePath '.github/workflows/validate.yml' -Pattern 'ubuntu-latest' -Description 'Ubuntu validation runner in CI'
Assert-FileContains -RelativePath '.github/workflows/validate.yml' -Pattern 'macos-15' -Description 'macOS validation runner in CI'
Assert-FileContains -RelativePath '.github/workflows/validate.yml' -Pattern 'validate-windows-powershell-5-1:' -Description 'independent Windows PowerShell 5.1 validation job'
Assert-FileContains -RelativePath '.github/workflows/validate.yml' -Pattern 'timeout-minutes:\s*25' -Description 'bounded CI validation jobs'
Assert-FileContains -RelativePath '.github/workflows/validate.yml' -Pattern '(?m)^\s*uses:\s*actions/checkout@fbc6f3992d24b796d5a048ff273f7fcc4a7b6c09\s+#\s+v5\.1\.0\s*$' -Description 'official immutable checkout action revision'
Assert-FileContains -RelativePath '.github/workflows/validate.yml' -Pattern 'powershell\.exe\s+-NoProfile\s+-NonInteractive\s+-ExecutionPolicy\s+Bypass\s+-File\s+\./scripts/validate-oss-readiness\.ps1' -Description 'explicit Windows PowerShell 5.1 readiness validation in CI'
Assert-FileContains -RelativePath 'scripts/test-scan-private-markers.ps1' -Pattern '-ForceNativePosixSessionGate:\(-not \$runtimeIsWindows\)' -Description 'forced native POSIX session gate fixture'
Assert-FileContains -RelativePath 'scripts/test-scan-private-markers.ps1' -Pattern 'POSIX native session gate evidence: forced libc setsid\(2\)' -Description 'native POSIX session gate CI evidence marker'
Assert-FileContains -RelativePath 'scripts/test-scan-private-markers.ps1' -Pattern '\(-not \$runtimeIsWindows -and\s+\$detachedResult\.ExitCode -ne 0\)' -Description 'native POSIX detached-command exit validation'
Assert-FileContains -RelativePath 'scripts/test-scan-private-markers.ps1' -Pattern '\(-not \$runtimeIsWindows -and\s+\$raceResult\.ExitCode -ne 0\)' -Description 'native POSIX immediate-race exit validation'
Assert-FileContains -RelativePath 'scripts/test-scan-private-markers.ps1' -Pattern 'Test-NativePosixSessionEvidenceReady' -Description 'native POSIX evidence eligibility regression'
Assert-FileContains -RelativePath 'scripts/private-marker-process.ps1' -Pattern 'DescendantPipeCleanupRequested' -Description 'descendant pipe cleanup evidence shape'
Assert-FileContains -RelativePath 'scripts/test-scan-private-markers.ps1' -Pattern 'reject a result without descendant pipe cleanup' -Description 'non-pipe-leak evidence regression'
Assert-FileContains -RelativePath 'scripts/test-scan-private-markers.ps1' -Pattern '\$tempRoot = Resolve-PhysicalDirectoryPath' -Description 'physical canonical fixture temp root'
Assert-FileContains -RelativePath 'scripts/test-scan-private-markers.ps1' -Pattern 'physical temp-root alias regression' -Description 'physical temp-root alias regression'
Assert-WorkflowExternalUsesPolicyRegressions
Assert-AllWorkflowExternalUsesPinned
Assert-WindowsPowerShell51WorkflowJobRegressions
Assert-WindowsPowerShell51WorkflowJob
Assert-CanonicalValidationWorkflowSourceRegressions
Assert-CanonicalValidationWorkflowSource
Assert-TemplateSectionContractRegressions
Assert-SkillTranslationDigestRegressions
Assert-SkillTranslationDigest

# These are the reviewed schemas of the bundled source templates, not a rule
# for downstream repositories that copy and customize them. Exact H1/H2
# contracts keep the English and Japanese entry points from drifting while
# still allowing subordinate headings inside each section.
$templateContracts = @(
    @{
        Path = 'templates/en/START_HERE.md'
        Title = 'START_HERE — <project>'
        Sections = @(
            'Canonical scope of this document',
            'What this repository is',
            'Reading order (canonical documents)',
            'Verification commands',
            'Hard gates (never cross without approval)',
            'Next step'
        )
    },
    @{
        Path = 'templates/en/REQUIREMENTS.md'
        Title = 'REQUIREMENTS — <project>'
        Sections = @(
            'Canonical scope of this document',
            'Purpose and background',
            'Functional requirements',
            'Non-functional requirements',
            'Non-goals',
            'Acceptance criteria',
            'Unverified checklist',
            'Open questions'
        )
    },
    @{
        Path = 'templates/en/HANDOFF.md'
        Title = 'HANDOFF — <project>'
        Sections = @(
            'Canonical scope of this document',
            'Traps before you touch anything',
            'Current goal and success metric',
            'Current position',
            'Key files',
            'Recent decisions',
            'Commands already run',
            'Known issues',
            'Do not re-read',
            'Next step'
        )
    },
    @{
        Path = 'templates/en/TASKS.md'
        Title = 'TASKS — <project>'
        Sections = @(
            'Canonical scope of this document',
            'Ledger',
            'Latest verification run',
            'History (one line per period)'
        )
    },
    @{
        Path = 'templates/ja/START_HERE.md'
        Title = 'START_HERE — <project>'
        Sections = @(
            'この資料の正本責務',
            'このリポジトリは何か',
            '読み順（正本）',
            '検証コマンド',
            '主要ゲート（承認なしに越えない境界）',
            '次の一手'
        )
    },
    @{
        Path = 'templates/ja/REQUIREMENTS.md'
        Title = 'REQUIREMENTS（要件定義書）— <project>'
        Sections = @(
            'この資料の正本責務',
            '目的・背景',
            '機能要件',
            '非機能要件',
            '非スコープ（やらないこと）',
            '受け入れ基準',
            '未検証チェックリスト',
            '未決事項'
        )
    },
    @{
        Path = 'templates/ja/HANDOFF.md'
        Title = 'HANDOFF（引き継ぎ）— <project>'
        Sections = @(
            'この資料の正本責務',
            '触る前に知るべき罠',
            '現在のゴールと成功指標',
            '現在地',
            'Key files',
            '直近の決定',
            '実行済みコマンド',
            '既知の問題',
            'Do not re-read（再読不要）',
            '次の一手'
        )
    },
    @{
        Path = 'templates/ja/TASKS.md'
        Title = 'TASKS（タスク台帳）— <project>'
        Sections = @(
            'この資料の正本責務',
            '台帳',
            '直近の検証実行',
            '履歴（期間ごとに1行）'
        )
    }
)
foreach ($contract in $templateContracts) {
    Assert-TemplateSectionContract `
        -RelativePath $contract.Path `
        -ExpectedTitle $contract.Title `
        -ExpectedSections $contract.Sections
}

Test-SkillFrontmatter

if ($failures.Count -gt 0) {
    Write-Host 'OSS readiness validation failed:'
    foreach ($failure in $failures) {
        Write-Host "- $failure"
    }
    exit 1
}

Write-Host "OSS readiness validation passed for $root"
exit 0
