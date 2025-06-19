See the first part of the [architecture overview](ARCHITECTURE.md) for how to start working on this plugin. 

# Commits & Pull Requests

- If you're making a big contribution/adding a new feature, raise an issue for it first.
- When making a change to the UI, provide a screenshot or video as well.

# Coding Style

Before commiting, please make sure to run StyLua for consistent formatting. If you are using Rokit, this is how you can do it:
```bash
# Install the tools first (only need to do this once)
rokit install
# Run the formatter
stylua .
```

## Strict

Make sure all your scripts are `--!strict` unless you have a good reason not to. You may see that a lot of the codebase is not `--!strict` at the moment. Do not follow my lead. 😔
