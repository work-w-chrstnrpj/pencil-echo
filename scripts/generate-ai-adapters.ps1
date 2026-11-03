#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Compatibility wrapper that syncs all AI adapter targets.
.DESCRIPTION
    Convenience alias for users accustomed to the older script name.
    Delegates to scripts/sync-ai-adapters.ps1 -Target all.
    The main implementation, all target-specific generators, and all
    formatting logic live in scripts/sync-ai-adapters.ps1.
#>

$ErrorActionPreference = "Stop"
& (Join-Path $PSScriptRoot "sync-ai-adapters.ps1") -Target all
