--!strict

-- Stuff for deserialization with buffers.

local plugin = script:FindFirstAncestorOfClass("Plugin")

local DESERIALIZATION_KEY = "DataDelve_Deserialization"

type PlaceSettings = {
	-- path to the default deserializer
	defaultDeserializer: { string }?,
}

type DeserializationSettings = {
	[--[[placeId:]]string]: PlaceSettings,
}

export type FunctionDeserializer = {
	type: "function",
	deserialize: (buf: buffer) -> unknown,
	serialize: (data: unknown) -> buffer,
}
export type Editor = {
	object: GuiObject,
	getValue: () -> buffer?,
	cleanup: (() -> ())?,
}
export type EditorDeserializer = {
	type: "editor",
	createEditor: (buf: buffer) -> Editor,
}
export type Deserializer = FunctionDeserializer | EditorDeserializer

local DeserializeState = {}

local placeSettings: PlaceSettings
do
	local got = plugin:GetSetting(DESERIALIZATION_KEY)
	if got then
		placeSettings = got[tostring(game.PlaceId)]
	end

	if not placeSettings then
		placeSettings = {
			defaultDeserializer = nil,
		}
	end
end

local function getPath(instance: Instance): { string }
	local path = {}
	local current: Instance? = instance
	while current and current ~= game do
		table.insert(path, 1, current.Name)
		current = current.Parent
	end
	return path
end

local function takePath(path: { string }): Instance?
	local current = game
	for _, name in path do
		current = current:FindFirstChild(name)
		if not current then
			break
		end
	end
	return current
end

function DeserializeState.getDefaultDeserializerScript(): Instance?
	if placeSettings.defaultDeserializer then
		return takePath(placeSettings.defaultDeserializer)
	end
	return nil
end

-- returns modules script or error message if none
function DeserializeState.getDefaultDeserializer(): ({ name: string, deserializer: Deserializer }?, string?)
	if placeSettings.defaultDeserializer then
		local name = table.concat(placeSettings.defaultDeserializer, ".")
		local got = takePath(placeSettings.defaultDeserializer)
		if got and got:IsA("ModuleScript") then
			local deserializer, err = DeserializeState.tryLoadDeserializer(got)
			if err then
				return nil, `Invalid value for {name}. {err}`
			end

			return {
				name = name,
				deserializer = deserializer :: Deserializer,
			}, nil
		elseif got then
			return nil, `{name} is not a ModuleScript.`
		else
			return nil, `{name} was not found.`
		end
	end
	return nil, nil
end

function DeserializeState.trySetDefaultDeserializer(module: ModuleScript)
	if not module:IsDescendantOf(game) then
		return
	end

	local gotKey = plugin:GetSetting(DESERIALIZATION_KEY)
	local newKey: DeserializationSettings
	local newSettings: PlaceSettings = {
		defaultDeserializer = getPath(module),
	}

	if gotKey then
		gotKey[tostring(game.PlaceId)] = newSettings
		newKey = gotKey
	else
		newKey = {
			[tostring(game.PlaceId)] = newSettings,
		}
	end

	placeSettings = newSettings
	plugin:SetSetting(DESERIALIZATION_KEY, newKey)
end

function DeserializeState.tryLoadDeserializer(module: ModuleScript): (Deserializer?, string?)
	local success, result = pcall(function()
		return require(module) :: any
	end)
	if not success then
		return nil, `Error while requiring: {result}`
	end

	if typeof(result) ~= "table" then
		return nil, "Must return a table."
	end

	local createEditor = result.createEditor or result.CreateEditor
	if createEditor then
		if typeof(createEditor) ~= "function" then
			return nil, "`getEditor` must be a function."
		end

		return {
			type = "editor",
			createEditor = createEditor,
		}
	end

	local got: FunctionDeserializer = {
		type = "function",
		deserialize = result.deserialize or result.Deserialize,
		serialize = result.serialize or result.Serialize,
	}

	if typeof(got.deserialize) ~= "function" then
		return nil, "Must have function named `deserialize` that takes a single buffer argument and returns a value."
	elseif typeof(got.serialize) ~= "function" then
		return nil, "Must have function named `serialize` that takes a single buffer argument and returns a buffer."
	end

	return got, nil
end

return DeserializeState
