# RC Toolkit Plugin Development

## Plugin-Dev Skills — Use First

This is a Claude Code plugin project. Before writing or modifying any plugin component, **always invoke the relevant `plugin-dev:*` skill first**. These skills contain authoritative guidance on structure, conventions, and best practices that must be followed.

Match the skill to what you're working on:

- **Creating/scaffolding a plugin** → `/plugin-dev:plugin-structure`
- **Adding or modifying a slash command** → `/plugin-dev:command-development`
- **Adding or modifying a skill** → `/plugin-dev:skill-development`
- **Adding or modifying an agent** → `/plugin-dev:agent-development`
- **Adding or modifying a hook** → `/plugin-dev:hook-development`
- **Configuring plugin settings or state** → `/plugin-dev:plugin-settings`
- **Integrating an MCP server** → `/plugin-dev:mcp-integration`

If a task spans multiple component types, invoke each relevant skill before starting work on that component.

Do **not** guess at plugin conventions — the skills define them. Use the skill, read the output, then implement accordingly.

**This is non-negotiable.** Do not skip this step even if you think you already understand the conventions from reading existing files. The skill invocation is a hard requirement, not a suggestion. Reading existing commands for reference is fine, but the skill must still be invoked and its guidance followed.
