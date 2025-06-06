--!strict

local MAIN_SETTINGS_KEY = "DataDelveSetting alpha 1"

export type SettingsData = {
	themePreset: string,
	themeAccent: string,
	allScopes: boolean,
	hideGameName: boolean,
	highlightColors: "Default" | "Script Editor",
	useAlternatingKeyColors: boolean,
	listDeletedKeys: boolean,
	automaticallyList: boolean,
	clickToOpen: boolean,
}

local defaultSettings: SettingsData = {
	themePreset = "studio",
	themeAccent = "neutral",
	allScopes = false,
	hideGameName = false,
	highlightColors = "Default",
	useAlternatingKeyColors = false,
	listDeletedKeys = false,
	automaticallyList = true,
	clickToOpen = false,
}

local Settings = {}
Settings.data = defaultSettings

local changed = Instance.new("BindableEvent")
Settings.changed = changed.Event

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
