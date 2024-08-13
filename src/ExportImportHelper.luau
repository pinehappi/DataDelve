local plugin = script:FindFirstAncestorWhichIsA("Plugin")

local SelectionService = game:GetService("Selection")
local StudioService = game:GetService("StudioService")
local HttpService = game:GetService("HttpService")

local ScriptEditorService = game:GetService("ScriptEditorService")
local RunService = game:GetService("RunService")

local STRING_PROPERTY_SIZE_LIMIT = 200_000

local ExportImportHelper = {}

-- Returns if the export went through
-- Optionally returns an error message
function ExportImportHelper.export(fileName: string, value: any): (boolean, string?)
	if RunService:IsRunning() then
		return false, "Cannot export while game is running."
	end
	
	local originalSelection = SelectionService:Get()
	
	local json = HttpService:JSONEncode(value)
	local moduleScript = Instance.new("ModuleScript")
	
	moduleScript.Archivable = false
	moduleScript.Name = "DataDelve Export"
	
	-- Write to source
	local success, err = pcall(function()
		if #json > STRING_PROPERTY_SIZE_LIMIT then
			for i = 1, (math.ceil(#json / STRING_PROPERTY_SIZE_LIMIT)) do
				local slice = json:sub((i - 1) * STRING_PROPERTY_SIZE_LIMIT + 1, i * STRING_PROPERTY_SIZE_LIMIT)
				ScriptEditorService:UpdateSourceAsync(moduleScript, function(old)
					if i == 1 then
						return slice
					else
						return old .. slice
					end
				end)
			end
		else
			ScriptEditorService:UpdateSourceAsync(moduleScript, function()
				return json
			end)
		end
	end)
	
	if not success then
		if err:find("denied") then
			return false, "Script injection permissions is required to export to JSON (a script must be created for export)."
		else
			return false, err
		end
	end
	
	-- Prompt export
	
	moduleScript.Parent = game:GetService("TweenService")
	
	SelectionService:Set({moduleScript})
	local exported = plugin:PromptSaveSelection(`{fileName}_json`)
	
	SelectionService:Set(originalSelection)
	moduleScript:Destroy()
	return exported
end

-- Returns if the user selected a valid JSON file
-- The second return is either the JSON value or error message
function ExportImportHelper.import(): (boolean, (string | unknown)?)
	local file = StudioService:PromptImportFile({"json"})
	if file then
		local contents = file:GetBinaryContents()
		local json: unknown?
		local success, err = pcall(function()
			json = HttpService:JSONDecode(contents)
		end)
		
		if not success then
			return false, "Failed to parse JSON."
		else
			return true, json
		end
	else
		return false, "No file selected for import."
	end
end

return ExportImportHelper