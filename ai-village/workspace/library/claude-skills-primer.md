# Claude Skills primer

Claude Skills teach Claude how to perform tasks in a repeatable way. They are folders containing instructions, scripts and resources that Claude discovers and loads when relevant.

Skills use progressive disclosure: Claude first scans skill metadata (about 100 tokens each) to find matches, loads the full instructions (under 5k tokens) only when a skill applies, and loads bundled files and scripts only as needed.

Skills are available in the Claude.ai web interface under Settings > Capabilities, in Claude Code, and through the Claude API. Team and Enterprise admins must enable skills organisation-wide first.

Source: the awesome-claude-skills README in this repository.
