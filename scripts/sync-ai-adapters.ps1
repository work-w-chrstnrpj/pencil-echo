param(
    [ValidateSet(
        "all",
        "claude",
        "codex",
        "cursor",
        "copilot",
        "opencode",
        "aider",
        "cline",
        "kilo",
        "windsurf",
        "antigravity",
        "openhands",
        "gemini"
    )]
    [string[]]$Target = @("all"),

    [switch]$Clean
)

$ErrorActionPreference = "Stop"
$Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path

function Join-RepoPath {
    param([Parameter(Mandatory = $true, Position = 0, ValueFromRemainingArguments = $true)][string[]]$Parts)

    $path = $Parts[0]
    for ($i = 1; $i -lt $Parts.Length; $i++) {
        $path = Join-Path $path $Parts[$i]
    }
    return $path
}

function Write-Utf8NoBom {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Content
    )

    $directory = Split-Path -Parent $Path
    if ($directory -and -not (Test-Path $directory)) {
        New-Item -ItemType Directory -Path $directory | Out-Null
    }

    $encoding = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($Path, $Content, $encoding)
}

function Quote-Yaml {
    param([Parameter(Mandatory = $true)][string]$Value)
    return "'" + ($Value -replace "'", "''") + "'"
}

function Quote-Toml {
    param([Parameter(Mandatory = $true)][string]$Value)
    $escaped = $Value.Replace('\', '\\').Replace('"', '\"')
    return '"' + $escaped + '"'
}

function Get-RoleMetadata {
    param([Parameter(Mandatory = $true)][System.IO.FileInfo]$File)

    $content = Get-Content -Raw $File.FullName
    $nameMatch = [regex]::Match($content, "(?m)^- \*\*Name:\*\*\s*(.+?)\s*$")
    $roleMatch = [regex]::Match($content, "(?m)^- \*\*Role:\*\*\s*(.+?)\s*$")
    $descriptionMatch = [regex]::Match($content, "(?m)^- \*\*Description:\*\*\s*(.+?)\s*$")

    if (-not $nameMatch.Success -or -not $descriptionMatch.Success) {
        throw "Role metadata missing in $($File.FullName)"
    }

    $title = if ($roleMatch.Success) { $roleMatch.Groups[1].Value.Trim() } else { $nameMatch.Groups[1].Value.Trim() }

    return [pscustomobject]@{
        Name = $nameMatch.Groups[1].Value.Trim()
        Title = $title
        Description = $descriptionMatch.Groups[1].Value.Trim()
        FileName = $File.Name
        Content = $content.Trim()
    }
}

function Get-OverlayMetadata {
    param([Parameter(Mandatory = $true)][System.IO.FileInfo]$File)

    $content = Get-Content -Raw $File.FullName
    $name = [System.IO.Path]::GetFileNameWithoutExtension($File.Name)
    $title = ($content -split "`n" | Where-Object { $_ -match "^# " } | Select-Object -First 1) -replace "^#\s*", ""

    return [pscustomobject]@{
        Name = $name
        Title = if ($title) { $title.Trim() } else { $name }
        Description = "Overlay: $($name). Changes response style, not work ownership."
        FileName = $File.Name
        Content = $content.Trim()
    }
}

function Get-SkillMetadata {
    param([Parameter(Mandatory = $true)][System.IO.DirectoryInfo]$Directory)

    $skillPath = Join-Path $Directory.FullName "SKILL.md"
    $content = Get-Content -Raw $skillPath
    $frontmatterMatch = [regex]::Match($content, "(?s)^---\s*\r?\n(.*?)\r?\n---")

    if (-not $frontmatterMatch.Success) {
        throw "Skill frontmatter missing in $skillPath"
    }

    $metadata = @{}
    foreach ($line in ($frontmatterMatch.Groups[1].Value -split "\r?\n")) {
        $match = [regex]::Match($line, "^\s*([^:#]+):\s*(.*?)\s*$")
        if ($match.Success) {
            $metadata[$match.Groups[1].Value.Trim()] = $match.Groups[2].Value.Trim().Trim('"').Trim("'")
        }
    }

    if (-not $metadata.ContainsKey("name")) {
        $metadata["name"] = $Directory.Name
    }
    if (-not $metadata.ContainsKey("description")) {
        throw "Skill description missing in $skillPath"
    }

    return [pscustomobject]@{
        Name = $metadata["name"]
        Description = $metadata["description"]
        Directory = $Directory
    }
}

function Copy-SkillDirectory {
    param(
        [Parameter(Mandatory = $true)][System.IO.DirectoryInfo]$Source,
        [Parameter(Mandatory = $true)][string]$Destination
    )

    if (-not (Test-Path $Destination)) {
        New-Item -ItemType Directory -Path $Destination | Out-Null
    }

    Get-ChildItem -Path $Source.FullName -Recurse -File | ForEach-Object {
        $relative = $_.FullName.Substring($Source.FullName.Length).TrimStart("\", "/")
        $target = Join-Path $Destination $relative
        $targetDirectory = Split-Path -Parent $target
        if ($targetDirectory -and -not (Test-Path $targetDirectory)) {
            New-Item -ItemType Directory -Path $targetDirectory | Out-Null
        }
        Copy-Item -LiteralPath $_.FullName -Destination $target -Force
    }
}

function Remove-StaleSkillAdapters {
    param(
        [Parameter(Mandatory = $true)][string]$SkillRoot,
        [Parameter(Mandatory = $true)][string[]]$KeepNames
    )

    if (-not $Clean -or -not (Test-Path $SkillRoot)) {
        return
    }

    Get-ChildItem -Path $SkillRoot -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        if ($KeepNames -notcontains $_.Name) {
            Remove-Item -LiteralPath $_.FullName -Recurse -Force
        }
    }
}

function New-AdapterBody {
    param(
        [Parameter(Mandatory = $true)][string]$CanonicalPath,
        [Parameter(Mandatory = $true)][string]$Content
    )

    return @(
        "<!-- Generated from $CanonicalPath. Do not edit directly. Edit the canonical source, then run ``scripts/sync-ai-adapters.ps1``. -->"
        ""
        $Content
    ) -join "`n"
}

function Write-ClaudeAgent {
    param(
        [Parameter(Mandatory = $true)][object]$Item,
        [Parameter(Mandatory = $true)][string]$CanonicalPath,
        [Parameter(Mandatory = $true)][string]$OutputName
    )

    $body = New-AdapterBody -CanonicalPath $CanonicalPath -Content $Item.Content
    $content = @(
        "---"
        "name: $($Item.Name)"
        "description: $(Quote-Yaml $Item.Description)"
        "tools:"
        "  - Read"
        "  - Glob"
        "  - Grep"
        "  - Edit"
        "  - MultiEdit"
        "  - Bash"
        "---"
        ""
        $body
        ""
    ) -join "`n"

    Write-Utf8NoBom -Path (Join-RepoPath $Root ".claude" "agents" "$OutputName.md") -Content $content
}

function Write-OpenCodeAgent {
    param(
        [Parameter(Mandatory = $true)][object]$Item,
        [Parameter(Mandatory = $true)][string]$CanonicalPath,
        [Parameter(Mandatory = $true)][string]$OutputName,
        [string]$Mode = "subagent",
        [string]$EditPermission = "allow"
    )

    $body = New-AdapterBody -CanonicalPath $CanonicalPath -Content $Item.Content
    $content = @(
        "---"
        "name: $($Item.Name)"
        "description: $(Quote-Yaml $Item.Description)"
        "mode: $Mode"
        "permission:"
        "  edit: $EditPermission"
        "  bash: ask"
        "---"
        ""
        $body
        ""
    ) -join "`n"

    Write-Utf8NoBom -Path (Join-RepoPath $Root ".opencode" "agents" "$OutputName.md") -Content $content
}

function Write-CodexAgent {
    param([Parameter(Mandatory = $true)][object]$Role)

    $canonicalPath = ".agents/roles/$($Role.FileName)"
    $instructions = New-AdapterBody -CanonicalPath $canonicalPath -Content $Role.Content
    if ($instructions.Contains("'''")) {
        throw "Cannot write TOML literal string for $($Role.Name); canonical role contains triple single quotes."
    }

    $content = @(
        "name = $(Quote-Toml $Role.Name)"
        "description = $(Quote-Toml $Role.Description)"
        ""
        "developer_instructions = '''"
        $instructions
        "'''"
        ""
    ) -join "`n"

    Write-Utf8NoBom -Path (Join-RepoPath $Root ".codex" "agents" "$($Role.Name).toml") -Content $content
}

function Write-CursorRule {
    param(
        [Parameter(Mandatory = $true)][object]$Item,
        [Parameter(Mandatory = $true)][string]$CanonicalPath,
        [Parameter(Mandatory = $true)][string]$OutputName
    )

    $body = New-AdapterBody -CanonicalPath $CanonicalPath -Content $Item.Content
    $content = @(
        "---"
        "description: $(Quote-Yaml $Item.Description)"
        "alwaysApply: false"
        "---"
        ""
        $body
        ""
    ) -join "`n"

    Write-Utf8NoBom -Path (Join-RepoPath $Root ".cursor" "rules" "$OutputName.mdc") -Content $content
}

function Write-GitHubCopilotAgent {
    param([Parameter(Mandatory = $true)][object]$Role)

    $canonicalPath = ".agents/roles/$($Role.FileName)"
    $body = New-AdapterBody -CanonicalPath $canonicalPath -Content $Role.Content
    $content = @(
        "---"
        "name: $(Quote-Yaml $Role.Title)"
        "description: $(Quote-Yaml $Role.Description)"
        "tools:"
        "  - read"
        "  - edit"
        "  - terminal"
        "  - search"
        "---"
        ""
        $body
        ""
    ) -join "`n"

    Write-Utf8NoBom -Path (Join-RepoPath $Root ".github" "agents" "$($Role.Name).agent.md") -Content $content
}

function Sync-SkillAdapters {
    param([Parameter(Mandatory = $true)][string[]]$TargetRoots)

    $keepNames = $skills | ForEach-Object { $_.Name }

    foreach ($targetRoot in $TargetRoots) {
        Remove-StaleSkillAdapters -SkillRoot $targetRoot -KeepNames $keepNames
        foreach ($skill in $skills) {
            Copy-SkillDirectory -Source $skill.Directory -Destination (Join-Path $targetRoot $skill.Name)
        }
    }
}

function Sync-Claude {
    foreach ($role in $roles) {
        Write-ClaudeAgent -Item $role -CanonicalPath ".agents/roles/$($role.FileName)" -OutputName $role.Name
    }
    foreach ($overlay in $overlays) {
        Write-ClaudeAgent -Item $overlay -CanonicalPath ".agents/overlays/$($overlay.FileName)" -OutputName $overlay.Name
    }

    $claudeMd = @(
        "# Claude Code Project Instructions"
        ""
        "Generated adapter summary. Canonical sources live in ``AGENTS.md`` and ``.agents/``."
        ""
        "Read ``AGENTS.md`` first. Use roles from ``.agents/roles/``. Use standalone skills from ``.agents/skills/``. Overlays: Mentor and Coach in ``.agents/overlays/``."
        ""
        "Regenerate adapters: ``pwsh scripts/sync-ai-adapters.ps1 -Target claude``"
        ""
    ) -join "`n"
    Write-Utf8NoBom -Path (Join-RepoPath $Root "CLAUDE.md") -Content $claudeMd
    Sync-SkillAdapters -TargetRoots @((Join-RepoPath $Root ".claude" "skills"))
}

function Sync-Gemini {
    $geminiMd = @(
        "# Google Gemini Project Instructions"
        ""
        "Generated adapter summary. Canonical sources live in ``AGENTS.md`` and ``.agents/``."
        ""
        "Read ``AGENTS.md`` first. Use roles from ``.agents/roles/``. Use standalone skills from ``.agents/skills/``. Overlays: Mentor and Coach in ``.agents/overlays/``."
        ""
        "Regenerate adapters: ``pwsh scripts/sync-ai-adapters.ps1 -Target gemini``"
        ""
    ) -join "`n"
    Write-Utf8NoBom -Path (Join-RepoPath $Root "GEMINI.md") -Content $geminiMd
}

function Sync-Codex {
    foreach ($role in $roles) {
        Write-CodexAgent -Role $role
    }
}

function Sync-Cursor {
    foreach ($role in $roles) {
        Write-CursorRule -Item $role -CanonicalPath ".agents/roles/$($role.FileName)" -OutputName $role.Name
    }
    foreach ($overlay in $overlays) {
        Write-CursorRule -Item $overlay -CanonicalPath ".agents/overlays/$($overlay.FileName)" -OutputName $overlay.Name
    }
    Sync-SkillAdapters -TargetRoots @((Join-RepoPath $Root ".cursor" "skills"))
}

function Sync-Copilot {
    foreach ($role in $roles) {
        Write-GitHubCopilotAgent -Role $role
    }

    $copilotInstructions = @(
        "# GitHub Copilot Instructions"
        ""
        "Generated from canonical sources. Read ``AGENTS.md`` and ``.agents/README.md`` first."
        ""
        "Roles: ``.agents/roles/``. Skills: ``.agents/skills/``. Overlays: ``.agents/overlays/``."
        ""
        "Regenerate: ``pwsh scripts/sync-ai-adapters.ps1 -Target copilot``"
        ""
    ) -join "`n"
    Write-Utf8NoBom -Path (Join-RepoPath $Root ".github" "copilot-instructions.md") -Content $copilotInstructions
    Sync-SkillAdapters -TargetRoots @((Join-RepoPath $Root ".github" "skills"))
}

function Sync-OpenCode {
    foreach ($role in $roles) {
        Write-OpenCodeAgent -Item $role -CanonicalPath ".agents/roles/$($role.FileName)" -OutputName $role.Name
    }
    foreach ($overlay in $overlays) {
        Write-OpenCodeAgent -Item $overlay -CanonicalPath ".agents/overlays/$($overlay.FileName)" -OutputName $overlay.Name -Mode "primary" -EditPermission "deny"
    }

    $opencodeJson = @(
        '{',
        '  "$schema": "https://opencode.ai/config.json",',
        '  "instructions": [',
        '    "AGENTS.md",',
        '    ".agents/README.md",',
        '    ".agents/overlays/README.md",',
        '    ".agents/tools/context-policy.md",',
        '    ".agents/tools/verification-policy.md",',
        '    ".agents/tools/adapter-generation-policy.md"',
        '  ]',
        '}'
    ) -join "`n"

    Write-Utf8NoBom -Path (Join-RepoPath $Root "opencode.json") -Content $opencodeJson
    Sync-SkillAdapters -TargetRoots @((Join-RepoPath $Root ".opencode" "skills"))
}

function Sync-Aider {
    $conventions = @(
        "# Project Conventions"
        ""
        "Generated summary for Aider. Canonical sources: ``AGENTS.md`` and ``.agents/``."
        ""
        "## Operating Rules"
        ""
        "- Exact source files are truth; maps and indexes are navigation only."
        "- Update canonical ``.agents/`` files first, then run ``scripts/sync-ai-adapters.ps1``."
        "- Never claim verification passed unless it actually ran."
        "- Ask approval before destructive, production, secret, or migration operations."
        ""
        "## Canonical AI Structure"
        ""
        "- Roles: ``.agents/roles/``"
        "- Skills: ``.agents/skills/`` (reusable workflows only)"
        "- Overlays: ``.agents/overlays/`` (Mentor, Coach)"
        "- Workflows: ``.agents/workflows/``"
        "- Tool policies: ``.agents/tools/``"
        ""
        "See ``.agents/tools/verification-policy.md`` and ``.agents/tools/adapter-generation-policy.md``."
        ""
    ) -join "`n"
    Write-Utf8NoBom -Path (Join-RepoPath $Root "CONVENTIONS.md") -Content $conventions

    $aiderConfig = @(
        "# Generic project-level Aider config."
        "# Replace placeholder commands per project."
        ""
        "map-tokens: 4096"
        "map-refresh: auto"
        ""
        "read:"
        "  - AGENTS.md"
        "  - CONVENTIONS.md"
        "  - .agents/tools/context-policy.md"
        ""
        "auto-commits: false"
        "dirty-commits: false"
        "show-diffs: true"
        ""
        "lint-cmd: `"<project-lint-command>`""
        "test-cmd: `"<project-test-command>`""
        ""
        "auto-lint: true"
        "auto-test: false"
        ""
        "analytics: false"
        ""
    ) -join "`n"
    Write-Utf8NoBom -Path (Join-RepoPath $Root ".aider.conf.yml") -Content $aiderConfig
}

function Sync-Cline {
    $clineRules = @(
        "# Cline Rules"
        ""
        "Generated from ``AGENTS.md``. Edit canonical sources, then run ``scripts/sync-ai-adapters.ps1 -Target cline``."
        ""
        "- Read ``AGENTS.md`` and ``.agents/README.md`` first."
        "- Use the smallest relevant role from ``.agents/roles/``."
        "- Use standalone skills from ``.agents/skills/`` only when a reusable workflow is needed."
        "- Overlays Mentor/Coach change style, not ownership."
        "- Exact source files are truth."
        ""
    ) -join "`n"
    Write-Utf8NoBom -Path (Join-RepoPath $Root ".clinerules" "project.md") -Content $clineRules
}

function Sync-Kilo {
    $kiloRule = @(
        "# Kilo Code Rules"
        ""
        "Generated from ``AGENTS.md``. Canonical AI assets live in ``.agents/``."
        ""
        "Read ``AGENTS.md`` first. Use roles, skills, overlays, and workflows from ``.agents/``."
        ""
    ) -join "`n"
    Write-Utf8NoBom -Path (Join-RepoPath $Root ".kilo" "rules" "project.md") -Content $kiloRule

    $kiloJson = @(
        '{',
        '  "rules": [',
        '    ".kilo/rules/project.md"',
        '  ]',
        '}'
    ) -join "`n"
    Write-Utf8NoBom -Path (Join-RepoPath $Root "kilo.jsonc") -Content $kiloJson
}

function Sync-Windsurf {
    foreach ($role in $roles) {
        $summary = @(
            "# $($role.Title)"
            ""
            "Generated from ``.agents/roles/$($role.FileName)``. Use the canonical role for full guidance."
            ""
            $role.Description
            ""
        ) -join "`n"
        Write-Utf8NoBom -Path (Join-RepoPath $Root ".windsurf" "rules" "$($role.Name).md") -Content $summary
    }

    $workflowRoot = Join-RepoPath $Root ".agents" "workflows"
    $windsurfWorkflowRoot = Join-RepoPath $Root ".windsurf" "workflows"
    $keepWorkflows = Get-ChildItem -Path $workflowRoot -Filter "*.md" |
        Where-Object { $_.Name -ne "README.md" } |
        ForEach-Object { $_.Name }

    if (Test-Path $windsurfWorkflowRoot) {
        Get-ChildItem -Path $windsurfWorkflowRoot -Filter "*.md" | ForEach-Object {
            if ($keepWorkflows -notcontains $_.Name) {
                Remove-Item -LiteralPath $_.FullName -Force
            }
        }
    }

    Get-ChildItem -Path $workflowRoot -Filter "*.md" |
        Where-Object { $_.Name -ne "README.md" } |
        ForEach-Object {
            $workflowContent = Get-Content -Raw $_.FullName
            $dest = Join-RepoPath $Root ".windsurf" "workflows" $_.Name
            $body = @(
                "# Workflow Adapter: $($_.BaseName)"
                ""
                "Generated from ``.agents/workflows/$($_.Name)``."
                ""
                $workflowContent.Trim()
                ""
            ) -join "`n"
            Write-Utf8NoBom -Path $dest -Content $body
        }

    Sync-SkillAdapters -TargetRoots @((Join-RepoPath $Root ".windsurf" "skills"))
}

function Sync-Antigravity {
    $note = @(
        "# Antigravity Adapter Note"
        ""
        "Antigravity uses canonical sources directly:"
        ""
        "- ``AGENTS.md``"
        "- ``.agents/skills/<skill>/SKILL.md``"
        "- ``.agents/roles/`` for role prompts when needed"
        ""
        "No extra Antigravity-specific duplication is required unless the project confirms a supported format."
        ""
    ) -join "`n"
    Write-Utf8NoBom -Path (Join-RepoPath $Root ".agents" "tools" "antigravity-adapter-note.md") -Content $note
}

function Sync-OpenHands {
    $note = @(
        "# OpenHands Adapter Note"
        ""
        "OpenHands should start with ``AGENTS.md`` and canonical ``.agents/`` sources."
        ""
        "Do not invent complex OpenHands adapter formats without confirmed support in the project."
        ""
    ) -join "`n"
    Write-Utf8NoBom -Path (Join-RepoPath $Root ".openhands" "README.md") -Content $note
}

$roleRoot = Join-RepoPath $Root ".agents" "roles"
$skillRoot = Join-RepoPath $Root ".agents" "skills"
$overlayRoot = Join-RepoPath $Root ".agents" "overlays"

$roles = Get-ChildItem -Path $roleRoot -Filter "*.md" | Where-Object { $_.Name -ne "README.md" } | Sort-Object Name | ForEach-Object { Get-RoleMetadata -File $_ }
$skills = Get-ChildItem -Path $skillRoot -Directory | Where-Object {
    Test-Path (Join-Path $_.FullName "SKILL.md")
} | Sort-Object Name | ForEach-Object { Get-SkillMetadata -Directory $_ }
$overlays = Get-ChildItem -Path $overlayRoot -Filter "*.md" | Where-Object { $_.Name -ne "README.md" } | Sort-Object Name | ForEach-Object { Get-OverlayMetadata -File $_ }

$allTargets = @("claude", "codex", "cursor", "copilot", "opencode", "aider", "cline", "kilo", "windsurf", "antigravity", "openhands", "gemini")
$selected = if ($Target -contains "all") { $allTargets } else { $Target }

$generated = @()

foreach ($t in $selected) {
    switch ($t) {
        "claude" { Sync-Claude; $generated += "claude" }
        "codex" { Sync-Codex; $generated += "codex" }
        "cursor" { Sync-Cursor; $generated += "cursor" }
        "copilot" { Sync-Copilot; $generated += "copilot" }
        "opencode" { Sync-OpenCode; $generated += "opencode" }
        "aider" { Sync-Aider; $generated += "aider" }
        "cline" { Sync-Cline; $generated += "cline" }
        "kilo" { Sync-Kilo; $generated += "kilo" }
        "windsurf" { Sync-Windsurf; $generated += "windsurf" }
        "antigravity" { Sync-Antigravity; $generated += "antigravity" }
        "openhands" { Sync-OpenHands; $generated += "openhands" }
        "gemini" { Sync-Gemini; $generated += "gemini" }
        default { throw "Unsupported target: $t" }
    }
}

Write-Host "Synced targets: $($generated -join ', ')"
Write-Host "Roles: $($roles.Count)"
Write-Host "Skills: $($skills.Count)"
Write-Host "Overlays: $($overlays.Count)"
