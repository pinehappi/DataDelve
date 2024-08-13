See the first part of the [architecture overview](ARCHITECTURE.md) for how to start working on this plugin. 

# Design Brief

The main audience is scripters, secondary audience is people learning DataStores and people who manage games. 

## Design Goals
From most important to least important.

- Have clean UI that is intuitive to use and understand.
- Reflect the API. The UI should reflect the DataStore API as much as possible since people will be using it as they learn the API. If there is a discrepancy between the UI and DataStore API, tooltips should be used to clear it up.
- Be fast to use. Minimize clicks and let the user stay on the keyboard without having to use their mouse.

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

## Naming Convention
Generally same as the Roblox Lua Style Guide: https://roblox.github.io/lua-style-guide/#naming.
Only difference is capitalize the whole acronym (JSON instead of Json).

# Other Contributing Guide
Everything in this contributing guide should more or less apply to DataDelve as well (except the commit message part): https://github.com/jessesquires/.github/blob/main/CONTRIBUTING.md

# Addendum

Make sure to have fun! This isn't a super serious project and all contributions are welcome. 😉