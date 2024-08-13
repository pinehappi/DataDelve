--> Syncs this directory with a plugin file. Run with `lune run sync` to get help on how to use this.
-- NOTE: At the moment, this creates many extra directories. These do not appear in the repository, but they're still there.

local datetime = require("@lune/datetime")
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local stdio = require("@lune/stdio")
local task = require("@lune/task")

local util = require("./_util")
local processArgs, parsePath, bold, dim, pending, ok, fail, skip =
	util.processArgs, util.parsePath, util.bold, util.dim, util.pending, util.ok, util.fail, util.skip

local args, flags = processArgs({ "fastMode" })

local function help()
	print("Syncs this project directory with a .rbxm of the plugin. Prints fancy tree to look cool.")
	print("")
	print(`{bold("Usage:")} lune run sync [plugin file]`)
	print("")
	print(`{bold("Options:")}`)
	print(`  {bold("--fastMode")}  Sync without artifical delays that improve the viewing experience.`)
end

-- Syncing

type PathInfo = {
	sourcePath: string, -- Used for scripts
	assetPath: string, -- Used for gui assets
}

local syncInstance: (instance: roblox.Instance, path: PathInfo) -> ()
local syncSourceContainer: (container: LuaSourceContainer, path: PathInfo, force: boolean) -> ()
local sync: (filePath: string) -> ()

local function doesInstanceHaveScriptsInside(instance: roblox.Instance): boolean
	for _, child in instance:GetChildren() do
		if child:IsA("LuaSourceContainer") then
			return true
		end
	end
	return false
end

function syncSourceContainer(container: LuaSourceContainer, path: PathInfo, force: boolean)
	if (#container:GetChildren() > 0) and not force then
		fs.writeDir(path.assetPath)

		local hasScripts = doesInstanceHaveScriptsInside((container :: any) :: roblox.Instance)

		if hasScripts then
			fs.writeDir(path.sourcePath)
			syncSourceContainer(container, {
				sourcePath = `{path.sourcePath}/init`,
				assetPath = path.assetPath,
			}, true)
		else
			syncSourceContainer(container, path, true)
		end

		for _, child in container:GetChildren() do
			syncInstance(child, path)
		end
	elseif container:IsA("Script") then
		fs.writeFile(`{path.sourcePath}.server.luau`, container.Source)
		ok()
	elseif container:IsA("ModuleScript") then
		fs.writeFile(`{path.sourcePath}.luau`, container.Source)
		ok()
	else
		fail()
		error(`Invalid source container: {container}`)
	end
end

function syncInstance(instance: roblox.Instance, path: PathInfo)
	local newSourcePath = `{path.sourcePath}/{instance.Name}`
	local newAssetPath = `{path.assetPath}/{instance.Name}`
	local depth = #(newSourcePath:split("/"))
	stdio.write(`\n┠{("──"):rep(depth - 1)} {instance.Name}  {pending()}`)

	if not flags.fastMode then
		task.wait(0.1 * math.random()) -- To enjoy the view
	end

	if instance:IsA("Folder") then
		local hasScripts = doesInstanceHaveScriptsInside(instance)
		if hasScripts then
			fs.writeDir(newSourcePath)
		end
		fs.writeDir(newAssetPath)
		ok()
		for _, child in instance:GetChildren() do
			syncInstance(child, {
				sourcePath = newSourcePath,
				assetPath = newAssetPath,
			})
		end
	elseif instance:IsA("Script") then
		local script = (instance :: any) :: Script
		syncSourceContainer(script, {
			sourcePath = newSourcePath,
			assetPath = newAssetPath,
		}, false)
	elseif instance:IsA("ModuleScript") then
		local script = (instance :: any) :: ModuleScript
		syncSourceContainer(script, {
			sourcePath = newSourcePath,
			assetPath = newAssetPath,
		}, false)
	elseif instance:IsA("LocalScript") then
		error(`Use a Script instead of LocalScript: {instance}`)
	elseif instance:IsA("BoolValue") and instance.Name == "IsCanaryRelease" then
		skip()
	elseif instance:IsA("GuiBase2d") or instance:IsA("UIBase") then
		local model = roblox.serializeModel({ instance }, true)
		fs.writeFile(`{newAssetPath}.rbxmx`, model)
		ok()
	else
		error(`Unknown instance: {instance}`)
	end
end

local function deleteFile(path: string)
	print(`Pruned {path}`)
	fs.removeFile(path)
end

local function deleteDirectory(path: string)
	print(`Pruned {path}`)
	for _, item in fs.readDir(path) do
		local childPath = `{path}/{item}`
		local childMetadata = fs.metadata(childPath)
		if childMetadata.kind == "dir" then
			deleteDirectory(childPath)
		elseif childMetadata.kind == "file" then
			deleteFile(childPath)
		else
			error(`Unknown file: {childPath}`)
		end
	end
	fs.removeDir(path)
end

type SourceSyncType = "script" | "folder" | "scriptWithScripts"
type AssetSyncType = "asset" | "folder"

local function getSourceFileSyncType(path: string): SourceSyncType
	local metadata = fs.metadata(path)
	if metadata.kind == "dir" then
		if fs.isFile(`{path}/init.luau`) or fs.isFile(`{path}/init.server.luau`) then
			return "scriptWithScripts"
		else
			return "folder"
		end
	elseif metadata.kind == "file" then
		return "script"
	else
		error(`Unknown file: {path}`)
	end
end

local function getSourceInstanceSyncType(instance: roblox.Instance): SourceSyncType
	if instance:IsA("ModuleScript") or instance:IsA("Script") then
		if doesInstanceHaveScriptsInside(instance) then
			return "scriptWithScripts"
		else
			return "script"
		end
	elseif instance:IsA("Folder") then
		return "folder"
	else
		error(`Unexpected instance: {instance:GetFullName()}`)
	end
end

local function pruneSource(instance: roblox.Instance?, path: string)
	local metadata = fs.metadata(path)
	if instance == nil then
		if metadata.kind == "dir" then
			deleteDirectory(path)
		else
			deleteFile(path)
		end
		return
	end

	if metadata.kind == "dir" then
		if getSourceInstanceSyncType(instance) ~= getSourceFileSyncType(path) then
			deleteDirectory(path)
		else
			for _, item in fs.readDir(path) do
				if item == "init.luau" or item == "init.server.luau" then
					continue
				end

				local name, _, _ = parsePath(item)
				pruneSource(instance:FindFirstChild(name), `{path}/{item}`)
			end
		end
	elseif metadata.kind == "file" then
		if getSourceInstanceSyncType(instance) ~= "script" then
			deleteFile(path)
		end
	else
		error(`Unknown file: {instance}`)
	end
end

local function getAssetFileSyncType(path: string): AssetSyncType
	local metadata = fs.metadata(path)
	if metadata.kind == "dir" then
		return "folder"
	elseif metadata.kind == "file" then
		return "asset"
	else
		error(`Unknown file: {path}`)
	end
end

local function getAssetInstanceSyncType(instance: roblox.Instance): AssetSyncType
	if instance:IsA("Folder") then
		return "folder"
	else
		if instance:IsA("LuaSourceContainer") and #instance:GetChildren() > 0 then
			return "folder"
		else
			return "asset"
		end
	end
end

local function pruneAssets(instance: roblox.Instance?, path: string)
	local metadata = fs.metadata(path)
	local shouldDelete = (instance == nil) or (getAssetInstanceSyncType(instance) ~= getAssetFileSyncType(path))
	if shouldDelete then
		if metadata.kind == "dir" then
			deleteDirectory(path)
		else
			deleteFile(path)
		end
		return
	end

	if metadata.kind == "dir" then
		for _, item in fs.readDir(path) do
			local name, _, _ = parsePath(item)
			pruneAssets((instance :: roblox.Instance):FindFirstChild(name), `{path}/{item}`)
		end
	elseif metadata.kind == "file" then
		-- Ignore
	else
		error(`Unknown file: {instance}`)
	end
end

-- Removes folders/files that were deleted from the plugin file
local function prune(instance: roblox.Instance, path: PathInfo)
	pruneSource(instance, path.sourcePath)
	pruneAssets(instance, path.assetPath)
end

function sync(filePath: string)
	local start = datetime.now().unixTimestampMillis

	local success, err = pcall(function()
		stdio.write(`Loading plugin file  {pending()}`)

		local pluginFile, plugin
		local loadSuccess, loadError = pcall(function()
			pluginFile = fs.readFile(filePath)
			plugin = roblox.deserializeModel(pluginFile)[1]
		end)
		if not loadSuccess then
			fail()
			if tostring(loadError):find("No such file") then
				error(`Could not find plugin file. Did you put the right path?`)
			else
				error(loadError)
			end
		else
			ok()
			stdio.write("\n")
		end

		if not plugin:FindFirstChild("tests") then
			error(`Where is the tests folder in your .rbxm? Did you try to sync with a release build?`)
		end

		stdio.write(`Starting pruning...\n`)

		prune(plugin, {
			sourcePath = "src",
			assetPath = "assets",
		})
		prune(plugin.tests, {
			sourcePath = "tests",
			assetPath = "assets/tests",
		})

		stdio.write(`Prune finished.\n`)

		stdio.write("Starting sync...\n")

		if not flags.fastMode then
			task.wait(0.5 * math.random())
		end

		stdio.write("\x1B[1A") -- Goes back one line

		stdio.write("Sync started    ")

		syncInstance(plugin.tests, {
			sourcePath = ".",
			assetPath = "assets",
		})

		for _, child in plugin:GetChildren() do
			if child.Name ~= "tests" then
				syncInstance(child, {
					sourcePath = "src",
					assetPath = "assets",
				})
			end
		end
	end)

	stdio.write("\n\nSync status  ")
	if success then
		ok()

		local elapsed = datetime.now().unixTimestampMillis - start
		local mode = if flags.fastMode then "fast mode" else "enjoyable mode"
		stdio.write(dim(`({math.floor(elapsed)}ms {mode})`))
		stdio.write("\n")
	else
		fail()
		stdio.write("\n\n")
		error(err)
	end
end

-- Main

if #args == 0 then
	help()
elseif #args == 1 then
	sync(args[1])
else
	print("Provide a single argument of the path to the plugin file.")
end
