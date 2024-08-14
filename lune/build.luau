--> Builds the plugin file. Run with `lune run build` to get help on how to use this.

local datetime = require("@lune/datetime")
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local stdio = require("@lune/stdio")
local task = require("@lune/task")

local util = require("./_util")
local processArgs, parsePath, bold, dim, pending, ok, fail =
	util.processArgs, util.parsePath, util.bold, util.dim, util.pending, util.ok, util.fail

local args, flags = processArgs({ "release", "fastMode" })

type BuildType = "dev" | "release"

local function help()
	print(
		`Builds the plugin from the contents of this directory into an .rbxm.\n`
			.. `Do not specify the file extension in the output file name. It is automatically added. The output file will be placed in the {bold(
				"build"
			)} directory.`
	)
	print("")
	print(`{bold("Usage:")} lune run build [output file name]`)
	print("")
	print(`{bold("Options:")}`)
	print(
		`  {bold("--release")}   Whether to build for release. In release mode, tests will not be added to the output, and the canary flag will be set to false`
	)
	print(`  {bold("--fastMode")}  Sync without artifical delays that improve the viewing experience.`)
end

-- Build

local function buildSourceInstance(path: string, parent: roblox.Instance): LuaSourceContainer
	local name, extension = parsePath(path)
	local source = fs.readFile(path)
	local script = nil
	if extension == "server.luau" then
		script = roblox.Instance.new("Script")
	elseif extension == "luau" then
		script = roblox.Instance.new("ModuleScript")
	else
		error(`Unknown file extension: {extension}`)
	end
	script.Source = source
	script.Name = name

	script.Parent = parent

	return script
end

local function buildSourceDirectory(path: string, parent: roblox.Instance): LuaSourceContainer | Folder
	local name, _ = parsePath(path)
	local hasInit = false
	local folder = nil

	-- Check if it has init file
	for _, childPath in fs.readDir(path) do
		childPath = `{path}/{childPath}`

		local childName, _, _ = parsePath(childPath)
		if childName == "init" then
			local script = buildSourceInstance(childPath, parent)
			script.Name = name
			script.Parent = parent
			folder = script
			hasInit = true
			break
		end
	end

	if not hasInit then
		folder = roblox.Instance.new("Folder")
		folder.Name = name
		folder.Parent = parent
	end

	for _, childPath in fs.readDir(path) do
		childPath = `{path}/{childPath}`

		local metadata = fs.metadata(childPath)
		local childName, _, _ = parsePath(childPath)
		if childName == "init" then
			continue
		end
		if metadata.kind == "dir" then
			buildSourceDirectory(childPath, folder)
		elseif metadata.kind == "file" then
			buildSourceInstance(childPath, folder)
		else
			error(`Unexpected file: {childPath}`)
		end
	end

	return folder
end

local function buildAssetDirectory(path: string, parent: roblox.Instance, isRoot: boolean)
	local name, _ = parsePath(path)
	local folder = nil
	if not isRoot then
		folder = parent:FindFirstChild(name) or roblox.Instance.new("Folder")
		folder.Name = name
		folder.Parent = parent
	else
		folder = parent
	end

	for _, childPath in fs.readDir(path) do
		childPath = `{path}/{childPath}`

		local metadata = fs.metadata(childPath)
		local childName, childExtension, _ = parsePath(childPath)
		if metadata.kind == "dir" then
			buildAssetDirectory(childPath, folder, false)
		elseif metadata.kind == "file" then
			if childExtension ~= "rbxmx" then
				error(`Unexpected file: {childPath}`)
			end

			local model = roblox.deserializeModel(fs.readFile(childPath))[1]
			model.Name = childName
			model.Parent = folder
		else
			error(`Unexpected file: {childPath}`)
		end
	end
end

local function build(outputFile: string, buildType: BuildType)
	local outputFilePath = `build/{outputFile}.rbxm`
	local start = datetime.now().unixTimestampMillis

	stdio.write(`Making build directory  {pending()}`)
	fs.writeDir("build")
	ok()
	stdio.write("\n")

	print(`Starting {buildType} build...`)

	local root = roblox.Instance.new("Folder")
	root.Name = if buildType == "dev" then "DataDelve Canary" else "DataDelve"

	local success: boolean, err: string?

	stdio.write(`Building {bold("src/")}  {pending()}`)
	success, err = pcall(function()
		local src = buildSourceDirectory("src", root)
		for _, child in src:GetChildren() do
			child.Parent = root
		end
		src:Destroy()
	end)
	if not success then
		fail()
	else
		ok()
		stdio.write("\n")

		if not flags.fastMode then
			task.wait(math.random() * 0.3)
		end

		if buildType == "dev" then
			stdio.write(`Building {bold("tests/")}  {pending()}`)
			success, err = pcall(function()
				buildSourceDirectory("tests", root)
			end)
		end

		if not success then
			fail()
		else
			ok()
			stdio.write("\n")

			if not flags.fastMode then
				task.wait(math.random() * 0.3)
			end

			if not flags.fastMode then
				task.wait(math.random() * 0.3)
			end

			stdio.write(`Building {bold("assets/")}  {pending()}`)

			success, err = pcall(function()
				buildAssetDirectory("assets", root, true)
			end)

			if not success then
				fail()
			else
				ok()
				stdio.write("\n")

				if not flags.fastMode then
					task.wait(math.random() * 0.3)
				end

				stdio.write(`Adding flags  {pending()}`)

				local isCanaryRelease = roblox.Instance.new("BoolValue")
				isCanaryRelease.Name = "IsCanaryRelease"
				isCanaryRelease.Value = (buildType ~= "release")
				isCanaryRelease.Parent = root

				ok()
				stdio.write("\n")

				if not flags.fastMode then
					task.wait(math.random() * 0.3)
				end

				stdio.write(`Writing to {bold(outputFilePath)}  {pending()}`)
				success, err = pcall(function()
					fs.writeFile(outputFilePath, roblox.serializeModel({ root }))
				end)
				if not success then
					fail()
				else
					ok()
				end
			end
		end
	end

	stdio.write("\n")

	local elapsed = datetime.now().unixTimestampMillis - start
	local mode = if flags.fastMode then "fast mode" else "enjoyable mode"
	stdio.write(`Build status  `)
	if err then
		fail()
	else
		ok()
	end

	stdio.write(dim(`({elapsed}ms {mode})`))

	if err then
		stdio.write("\n\n")
		error(err)
	else
		stdio.write("\n")
	end
end

-- Main

if #args == 0 then
	help()
elseif #args == 1 then
	build(args[1], if flags.release then "release" else "dev")
else
	print(`Invalid usage. Run {bold("lune run build")} for help.`)
end
