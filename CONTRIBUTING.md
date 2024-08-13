See the first part of the [architecture overview](ARCHITECTURE.md) for how to start working on this plugin. 

Try to include a little comment at the top of each script you add about what it does.

# Coding Style

Before commiting, please make sure to run StyLua for consistent formatting. If you are using Rokit, this is how you can do it:
```bash
# Install the tools first (only need to do this once)
rokit install
# Run the formatter
stylua .
```

## Strict

Make sure all your scripts are `--!strict` unless you have a good reason not to. You may see that a lot of the codebase is not `--!strict` at the moment. Do not follow my lead.

## Naming Convention
Generally same as the Roblox Lua Style Guide: https://roblox.github.io/lua-style-guide/#naming.
Only difference is capitalize the whole acronym (JSON instead of Json).

## Writing classes
I use this style for most of the codebase:
```luau
--!strict
local Class = {}
Class.__index = Class

function Class.new(...)
    local self = setmetatable({
        ...
    }, Class)

    return self
end

export type Class = typeof(Class.new({} :: any))
return Class
```
This doesn't typecheck well, though. You can use this style since it's less boilerplate, but for more important classes, use this one: https://luau-lang.org/typecheck#adding-types-for-faux-object-oriented-programs (I just found out about this).

# Other Contributing Guide
Everything in this contributing guide should more or less apply to DataDelve as well (except the commit message part): https://github.com/jessesquires/.github/blob/main/CONTRIBUTING.md

# Addendum

Make sure to have fun! This isn't a super serious project and all contributions are welcome. If you're making a big contribution/adding a new feature, raise an issue for it first though. 😉