# Claude Adapters

Claude-compatible adapters are generated from canonical files in `.agents/`.

- Agents: `.claude/agents/*.md`
- Skills: `.claude/skills/<skill>/SKILL.md`

Edit `.agents/roles/` or `.agents/skills/`, then run `scripts/generate-ai-adapters.ps1`. Do not make Claude-only edits unless the tool format itself requires them.
