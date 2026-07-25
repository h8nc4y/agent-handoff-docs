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
Assert-FileContains -RelativePath '.github/workflows/validate.yml' -Pattern 'timeout-minutes:\s*40' -Description 'bounded CI validation job'
Assert-FileContains -RelativePath '.github/workflows/validate.yml' -Pattern '(?m)^\s*uses:\s*actions/checkout@fbc6f3992d24b796d5a048ff273f7fcc4a7b6c09\s+#\s+v5\.1\.0\s*$' -Description 'official immutable checkout action revision'
Assert-FileContains -RelativePath '.github/workflows/validate.yml' -Pattern 'shell:\s*powershell' -Description 'Windows PowerShell 5.1 validation in CI'
Assert-WorkflowExternalUsesPolicyRegressions
Assert-AllWorkflowExternalUsesPinned

# The whole framework hangs on the canonical-scope declaration, so every
# bundled template must reserve it as a heading. English templates carry the
# English heading; Japanese templates carry the Japanese one.
$englishTemplates = @(
    'templates/en/START_HERE.md',
    'templates/en/REQUIREMENTS.md',
    'templates/en/HANDOFF.md',
    'templates/en/TASKS.md'
)
foreach ($template in $englishTemplates) {
    Assert-FileContains -RelativePath $template -Pattern '(?im)^##\s+Canonical scope of this document' -Description 'canonical-scope declaration heading'
}

$japaneseTemplates = @(
    'templates/ja/START_HERE.md',
    'templates/ja/REQUIREMENTS.md',
    'templates/ja/HANDOFF.md',
    'templates/ja/TASKS.md'
)
foreach ($template in $japaneseTemplates) {
    Assert-FileContains -RelativePath $template -Pattern '(?m)^##\s+この資料の正本責務' -Description 'canonical-scope declaration heading (Japanese)'
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
