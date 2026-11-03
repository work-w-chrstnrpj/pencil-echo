#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Validate AI project template structure, formatting, and generated adapter consistency.
.DESCRIPTION
    Checks canonical role metadata, skill frontmatter, generated adapter formatting,
    presence of curated skills, and absence of removed granular skills.
    Exits nonzero on any failure.
#>

$ErrorActionPreference = "Stop"
$Root = (Resolve-Path (Join-Path -Path $PSScriptRoot -ChildPath "..")).Path
$exitCode = 0

function Get-RelativePath {
    param([string]$BasePath, [string]$TargetPath)
    if ($TargetPath.StartsWith($BasePath, [StringComparison]::OrdinalIgnoreCase)) {
        $result = $TargetPath.Substring($BasePath.Length).TrimStart("\", "/")
        return $result
    }
    return $TargetPath
}

function Join-Relative {
    param([string[]]$Parts)
    $path = $Root
    foreach ($p in $Parts) {
        $path = Join-Path -Path $path -ChildPath $p
    }
    return $path
}

function Write-Fail {
    param([string]$Message)
    Write-Host "[FAIL] $Message" -ForegroundColor Red
    $script:exitCode = 1
}

function Write-Pass {
    param([string]$Message)
    Write-Host "[PASS] $Message" -ForegroundColor Green
}

function Write-Skip {
    param([string]$Message)
    Write-Host "[SKIP] $Message" -ForegroundColor Yellow
}

# --- 1. Validate role metadata ---
Write-Host "`n=== Role Metadata ===" -ForegroundColor Cyan

$rolePath = Join-Relative @(".agents", "roles")
$roleFiles = Get-ChildItem -Path $rolePath -Filter "*.md" | Where-Object { $_.Name -ne "README.md" }
if ($roleFiles.Count -eq 0) {
    Write-Fail "No role files found in .agents/roles/"
} else {
    Write-Pass "Found $($roleFiles.Count) role files"
}

foreach ($file in $roleFiles) {
    $content = Get-Content -Raw $file.FullName
    $nameMatch = [regex]::Match($content, "(?m)^- \*\*Name:\*\*\s+.+$")
    $roleMatch = [regex]::Match($content, "(?m)^- \*\*Role:\*\*\s+.+$")
    $descMatch = [regex]::Match($content, "(?m)^- \*\*Description:\*\*\s+.+$")

    $relative = Get-RelativePath -BasePath $Root -TargetPath $file.FullName
    $errors = @()
    if (-not $nameMatch.Success) { $errors += "- **Name:**" }
    if (-not $roleMatch.Success) { $errors += "- **Role:**" }
    if (-not $descMatch.Success) { $errors += "- **Description:**" }

    if ($errors.Count -gt 0) {
        Write-Fail ("${relative}: missing metadata fields: " + ($errors -join ', '))
    } else {
        Write-Pass ("${relative}: metadata parseable")
    }

    if ($content.Split("`n").Count -lt 30) {
        Write-Fail ("${relative}: fewer than 30 lines (possible compression)")
    }

    if ($content -match "(?m)^## Allowed Skills") {
        Write-Fail ("${relative}: still uses deprecated Allowed Skills section")
    } elseif ($content -match "(?m)^## Reusable Skills") {
        Write-Pass ("${relative}: has Reusable Skills section")
    } else {
        Write-Fail ("${relative}: missing Reusable Skills section")
    }

    if ($content -match "(?m)^## Embedded Capability Playbooks") {
        Write-Pass ("${relative}: has Embedded Capability Playbooks section")
    } else {
        Write-Fail ("${relative}: missing Embedded Capability Playbooks section")
    }
}

# --- 2. Validate skill frontmatter ---
Write-Host "`n=== Skill Frontmatter ===" -ForegroundColor Cyan

$expectedSkills = @(
    "ask-repo-question", "investigate-issue", "plan-code-change", "execute-code-change",
    "code-review", "use-context-tools", "write-automated-test-cases", "create-manual-test-cases",
    "execute-manual-test-cases", "update-docs", "release-check", "generate-rca", "sync-ai-adapters"
)

$skillPath = Join-Relative @(".agents", "skills")
$skillDirs = Get-ChildItem -Path $skillPath -Directory
$actualSkills = $skillDirs | ForEach-Object { $_.Name } | Sort-Object
$missingSkills = $expectedSkills | Where-Object { $_ -notin $actualSkills }
$extraSkills = $actualSkills | Where-Object { $_ -notin $expectedSkills }

if ($missingSkills.Count -gt 0) {
    Write-Fail ("Missing curated skills: " + ($missingSkills -join ', '))
} elseif ($extraSkills.Count -gt 0) {
    Write-Fail ("Unexpected skill folders: " + ($extraSkills -join ', '))
} else {
    Write-Pass "Curated standalone skill set intact ($($expectedSkills.Count) skills)"
}
$granularSkills = @(
    "api-design", "api-testing", "auth-implementation", "database-change",
    "database-schema-design", "deployment", "frontend-implementation",
    "responsive-design", "state-management", "technical-writing",
    "workflow-orchestration"
)

foreach ($dir in $skillDirs) {
    $skillFilePath = Join-Path -Path $dir.FullName -ChildPath "SKILL.md"
    $relativeName = $dir.Name

    if (-not (Test-Path $skillFilePath)) {
        Write-Fail (".agents/skills/${relativeName}: SKILL.md missing")
        continue
    }

    $content = Get-Content -Raw $skillFilePath
    $fmMatch = [regex]::Match($content, "(?s)^---\s*\r?\n(.*?)\r?\n---\s*\r?\n")

    if (-not $fmMatch.Success) {
        Write-Fail (".agents/skills/${relativeName}/SKILL.md: invalid or missing frontmatter")
        continue
    }

    if ($content -match "^--- name:") {
        Write-Fail (".agents/skills/${relativeName}/SKILL.md: compressed one-line frontmatter")
        continue
    }

    $fm = $fmMatch.Groups[1].Value
    if ($fm -notmatch "(?m)^name:\s*\S") {
        Write-Fail (".agents/skills/${relativeName}/SKILL.md: frontmatter missing 'name:'")
    } elseif ($fm -notmatch "(?m)^description:\s*\S") {
        Write-Fail (".agents/skills/${relativeName}/SKILL.md: frontmatter missing 'description:'")
    } else {
        Write-Pass (".agents/skills/${relativeName}/SKILL.md: valid frontmatter")
    }
}

# --- 3. Check no granular skills exist ---
Write-Host "`n=== Granular Skill Check ===" -ForegroundColor Cyan
$foundGranular = @()
foreach ($skill in $granularSkills) {
    $checkPath = Join-Relative @(".agents", "skills", $skill)
    if (Test-Path $checkPath) {
        $foundGranular += $skill
    }
}

if ($foundGranular.Count -gt 0) {
    Write-Fail ("Granular skill folders exist: " + ($foundGranular -join ', '))
} else {
    Write-Pass "No granular skill folders detected"
}

# --- 4. Validate skill references in routing maps ---
Write-Host "`n=== Skill Reference Routing ===" -ForegroundColor Cyan

$skillReferenceFiles = @(
    (Join-Relative @(".ai", "maps", "agent-map.md"))
    (Join-Relative @(".ai", "prompt-recipes.md"))
)

foreach ($referenceFile in $skillReferenceFiles) {
    if (-not (Test-Path $referenceFile)) {
        $relative = Get-RelativePath -BasePath $Root -TargetPath $referenceFile
        Write-Fail ("${relative}: not found")
        continue
    }

    $content = Get-Content -Raw $referenceFile
    $relative = Get-RelativePath -BasePath $Root -TargetPath $referenceFile
    $backtickSkills = [regex]::Matches($content, '`([^`]+)`') |
        ForEach-Object { $_.Groups[1].Value } |
        Where-Object { $_ -match '^[a-z][a-z0-9]+(-[a-z0-9]+)+$' }
    $proseSkills = [regex]::Matches($content, '\b([a-z][a-z0-9]+(-[a-z0-9]+)+)\s+skill\b') |
        ForEach-Object { $_.Groups[1].Value }
    $referencedSkills = @($backtickSkills) + @($proseSkills)
    $referencedSkills = $referencedSkills | Sort-Object -Unique

    $unknownSkills = $referencedSkills | Where-Object { $_ -notin $expectedSkills }

    if ($unknownSkills.Count -gt 0) {
        Write-Fail ("${relative}: references unknown skills: " + ($unknownSkills -join ', '))
    } else {
        Write-Pass ("${relative}: skill references match curated skill set")
    }
}

# --- 5. Validate generated adapter frontmatter ---
Write-Host "`n=== Generated Adapter Frontmatter ===" -ForegroundColor Cyan

$generatedDirs = @(".claude", ".cursor", ".github", ".opencode", ".windsurf")

foreach ($dir in $generatedDirs) {
    $basePath = Join-Relative @($dir)
    if (-not (Test-Path $basePath)) {
        Write-Skip ("${dir}: directory not found")
        continue
    }

    $files = Get-ChildItem -Path $basePath -Recurse -File -Include "*.md", "*.mdc" | Where-Object { $_.DirectoryName -notmatch 'node_modules' }
    foreach ($file in $files) {
        $content = Get-Content -Raw $file.FullName
        if ($content -match "^--- name:") {
            $relative = Get-RelativePath -BasePath $Root -TargetPath $file.FullName
            Write-Fail ("${relative}: compressed one-line frontmatter")
        }
    }
    Write-Pass ("${dir}: no compressed frontmatter found")
}

# --- 6. Validate generated source notices ---
Write-Host "`n=== Generated Source Notices ===" -ForegroundColor Cyan

foreach ($dir in $generatedDirs) {
    $basePath = Join-Relative @($dir)
    if (-not (Test-Path $basePath)) {
        continue
    }

    $agentDir = Join-Path -Path $basePath -ChildPath "agents"
    $rulesDir = Join-Path -Path $basePath -ChildPath "rules"

    $checkDirs = @()
    if (Test-Path $agentDir) { $checkDirs += $agentDir }
    if (Test-Path $rulesDir) { $checkDirs += $rulesDir }

    foreach ($cd in $checkDirs) {
        $files = Get-ChildItem -Path $cd -Recurse -File -Include "*.md", "*.mdc"
        foreach ($file in $files) {
            if ($file.Name -eq "README.md") { continue }
            $content = Get-Content -Raw $file.FullName
            $relative = Get-RelativePath -BasePath $Root -TargetPath $file.FullName
            if ($content -match '(Generated from|<!-- Generated from)[^\r\n]*\.agents') {
                Write-Pass ("${relative}: has source notice")
            } else {
                Write-Fail ("${relative}: missing source notice")
            }
        }
    }
}

# --- 7. Validate overlay permissions in OpenCode ---
Write-Host "`n=== OpenCode Overlay Permissions ===" -ForegroundColor Cyan

$opencodeAgentDir = Join-Relative @(".opencode", "agents")
if (Test-Path $opencodeAgentDir) {
    foreach ($overlay in @("coach.md", "mentor.md")) {
        $opPath = Join-Path -Path $opencodeAgentDir -ChildPath $overlay
        if (Test-Path $opPath) {
            $content = Get-Content -Raw $opPath
            if ($content -match "edit: deny") {
                Write-Pass (".opencode/agents/${overlay}: edit denied")
            } else {
                Write-Fail (".opencode/agents/${overlay}: missing edit: deny")
            }
        }
    }
}

# --- 8. Validate overlays ---
Write-Host "`n=== Overlays ===" -ForegroundColor Cyan

$overlayFiles = @("README.md", "mentor.md", "coach.md")
foreach ($overlay in $overlayFiles) {
    $overlayPath = Join-Relative @(".agents", "overlays", $overlay)
    if (-not (Test-Path $overlayPath)) {
        Write-Fail (".agents/overlays/${overlay}: missing")
        continue
    }

    $content = Get-Content -Raw $overlayPath
    $lineCount = $content.Split("`n").Count
    if ($lineCount -lt 10) {
        Write-Fail (".agents/overlays/${overlay}: only ${lineCount} lines (possible compression)")
    } elseif ($content -match "(?m)^# ") {
        Write-Pass (".agents/overlays/${overlay}: readable Markdown (${lineCount} lines)")
    } else {
        Write-Fail (".agents/overlays/${overlay}: missing heading structure")
    }
}

# --- 9. Validate AGENTS.md structure ---
Write-Host "`n=== AGENTS.md ===" -ForegroundColor Cyan

$agentsMd = Join-Relative @("AGENTS.md")
if (Test-Path $agentsMd) {
    $content = Get-Content -Raw $agentsMd
    $lineCount = $content.Split("`n").Count
    if ($lineCount -gt 40) {
        Write-Pass ("AGENTS.md: ${lineCount} lines (adequate)")
    } else {
        Write-Fail ("AGENTS.md: only ${lineCount} lines (may be compressed)")
    }

    if ($content -match "(?m)^## ") {
        Write-Pass "AGENTS.md: has heading structure"
    } else {
        Write-Fail "AGENTS.md: missing heading structure"
    }
} else {
    Write-Fail "AGENTS.md not found"
}

# --- 10. Validate script file formatting ---
Write-Host "`n=== Script Files ===" -ForegroundColor Cyan

$scriptsToCheck = @("sync-ai-adapters.ps1", "generate-ai-adapters.ps1", "validate-ai-template.ps1")
foreach ($script in $scriptsToCheck) {
    $scriptPath = Join-Relative @("scripts", $script)
    if (Test-Path $scriptPath) {
        $content = Get-Content -Raw $scriptPath
        $lineCount = $content.Split("`n").Count
        if ($lineCount -gt 5) {
            Write-Pass ("scripts/${script}: ${lineCount} lines")
        } else {
            Write-Fail ("scripts/${script}: fewer than 5 lines (may be compressed)")
        }
    }
}

# --- Summary ---
Write-Host "`n========================================" -ForegroundColor Cyan
if ($exitCode -eq 0) {
    Write-Host "Validation PASSED" -ForegroundColor Green
} else {
    Write-Host "Validation FAILED with ${exitCode} error(s)" -ForegroundColor Red
}
Write-Host "========================================" -ForegroundColor Cyan

exit $exitCode
