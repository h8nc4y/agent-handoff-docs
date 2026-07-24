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
    'LICENSE',
    'README.md',
    'SECURITY.md',
    'SKILL.md',
    'docs/SKILL.ja.md',
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
Assert-FileContains -RelativePath 'README.md' -Pattern 'templates/en' -Description 'English template directory documented'
Assert-FileContains -RelativePath 'README.md' -Pattern 'templates/ja' -Description 'Japanese template directory documented'
Assert-FileContains -RelativePath '.gitignore' -Pattern '\.private-markers\.local' -Description 'ignore local private marker files'
Assert-FileContains -RelativePath 'CONTRIBUTING.md' -Pattern '(?im)no token|never.*token|secret' -Description 'secret-safe contribution guidance'
Assert-FileContains -RelativePath 'SECURITY.md' -Pattern '(?im)do not.*public|private|security' -Description 'private vulnerability reporting guidance'
Assert-FileContains -RelativePath '.github/workflows/validate.yml' -Pattern 'validate-oss-readiness\.ps1' -Description 'OSS readiness validation in CI'
Assert-FileContains -RelativePath '.github/workflows/validate.yml' -Pattern 'scan-private-markers\.ps1' -Description 'private marker scan in CI'
Assert-FileContains -RelativePath '.github/workflows/validate.yml' -Pattern 'test-scan-private-markers\.ps1' -Description 'private marker scan self-test in CI'
Assert-FileContains -RelativePath '.github/workflows/validate.yml' -Pattern 'windows-latest' -Description 'Windows validation runner in CI'
Assert-FileContains -RelativePath '.github/workflows/validate.yml' -Pattern 'ubuntu-latest' -Description 'Ubuntu validation runner in CI'
Assert-FileContains -RelativePath '.github/workflows/validate.yml' -Pattern 'timeout-minutes:\s*25' -Description 'bounded CI validation job'
Assert-FileContains -RelativePath '.github/workflows/validate.yml' -Pattern 'shell:\s*powershell' -Description 'Windows PowerShell 5.1 validation in CI'

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
