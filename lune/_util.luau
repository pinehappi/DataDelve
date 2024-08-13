--> Utility used in other Lune scripts.

local stdio = require("@lune/stdio")
local process = require("@lune/process")

--[=[
	@return {string} -- Arguments
	@return {[string]: boolean} -- Flags
]=]
local function processArgs(allowedFlags: { string }): ({ string }, { [string]: boolean })
	local args = {}
	local flags = {}
	for _, arg in process.args do
		if arg:sub(1, 1) == "-" then
			if arg:sub(2, 2) ~= "-" then
				error("Only long flags are allowed.")
			else
				local flagName = arg:sub(3)
				if not table.find(allowedFlags, flagName) then
					error(`Unknown flag: {flagName}`)
				end

				flags[flagName] = true
			end
		else
			table.insert(args, arg)
		end
	end

	return args, flags
end

local function parsePath(path: string): (string, string, string)
	local split = path:split("/")
	local split2 = split[#split]:split(".")
	local name, extension, parentPath = split2[1], table.concat(split2, ".", 2), table.concat(split, "/", 1, #split - 1)
	return name, extension, parentPath
end

local function bold(text: string): string
	return `\x1B[1m{text}\x1B[0m`
end

local function dim(text: string): string
	return `\x1B[2m{text}\x1B[0m`
end

-- Call ok() or fail() or skip() after this to replace the pending status
local function pending()
	return `{dim("... ")}\b\b\b\b`
end

local function ok()
	stdio.write("\x1B[32mOK  \x1B[0m")
end

local function fail()
	stdio.write("\x1B[31mFAIL\x1b[0m")
end

local function skip()
	stdio.write("\x1B[33mSKIP\x1b[0m")
end

return {
	processArgs = processArgs,
	parsePath = parsePath,
	bold = bold,
	dim = dim,
	pending = pending,
	ok = ok,
	fail = fail,
	skip = skip,
}
