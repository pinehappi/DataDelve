--!strict

local MAIN_SETTINGS_KEY = "DataDelveSetting alpha 1"

export type SettingsData = {
	themePreset: string,
	themeAccent: string,
	allScopes: boolean,
	hideGameName: boolean,
	highlightColors: "Default" | "Script Editor",
	listDeletedKeys: boolean,
	automaticallyList: boolean,
}

local Settings = {}

local changed = Instance.new("BindableEvent")
Settings.changed = changed.Event

local defaultSettings = {
	themePreset = "studio",
	themeAccent = "neutral",
	allScopes = false,
	hideGameName = false,
	highlightColors = "Default",
	listDeletedKeys = false,
	automaticallyList = true,
}

local function fillWithDefaults(a, defaults)
	for key, default in defaults do
		if a[key] == nil then
			a[key] = default
		end
	end
end

function Settings.load(plugin: Plugin)
	Settings.data = plugin:GetSetting(MAIN_SETTINGS_KEY) or {}
	fillWithDefaults(Settings.data, defaultSettings)
end

function Settings.save(plugin: Plugin)
	plugin:SetSetting(MAIN_SETTINGS_KEY, Settings.data)
end

function Settings.set(setting: string, value: any)
	Settings.data[setting] = value
	changed:Fire(setting, value)
end

function Settings.get(setting: string)
	return Settings.data[setting]
end

return Settings
