--!strict

type App = {
	new: (id: string) -> App,

	toggleEnabled: (App) -> (),
	getEnabled: (App) -> boolean,
	enabledChanged: RBXScriptSignal,
}

local IS_CANARY = script.Parent.IsCanaryRelease.Value

local RunService = game:GetService("RunService")

local App = require(script.Parent.App) :: App
local ClientFallbackApp = require(script.Parent.ClientFalbackApp) :: App

local History = require(script.Parent.History).global
local Settings = require(script.Parent.Settings)
local Theme = require(script.Parent.UI.Theme)

local globalApp: App
local appName = if IS_CANARY then "DataDelve Canary" else "DataDelve"

local function initSettings()
	History:load(plugin)
	Settings.load(plugin)
	Theme.global:setPreset(Settings.data.themePreset)
	Theme.global:setAccent(Settings.data.themeAccent)

	Settings.changed:Connect(function(key, value)
		if key == "themePreset" then
			Theme.global:setPreset(value)
		elseif key == "themeAccent" then
			Theme.global:setAccent(value)
		end
	end)
end

local function initApp()
	-- Use the ClientFallbackApp when play testing as a client because it does not
	-- have access to the DataStore APIs.
	if RunService:IsRunning() and RunService:IsClient() then
		globalApp = ClientFallbackApp.new(appName)
	else
		globalApp = App.new(appName)
	end
end

local function initPluginToolbar()
	local toolbar: PluginToolbar = plugin:CreateToolbar(appName)
	local pluginButton: PluginToolbarButton = toolbar:CreateButton(
		appName,
		"easy interface for datastores",
		if IS_CANARY then "rbxassetid://18476887048" else "rbxassetid://18476917665"
	)
	pluginButton.ClickableWhenViewportHidden = true

	plugin.Unloading:Connect(function()
		History:save(plugin)
		Settings.save(plugin)
	end)

	pluginButton.Click:Connect(function()
		globalApp:toggleEnabled()
	end)
	globalApp.enabledChanged:Connect(function(enabled: boolean)
		pluginButton:SetActive(enabled)
	end)
	pluginButton:SetActive(globalApp:getEnabled())
end

local function init()
	initSettings()
	initApp()
	initPluginToolbar()
end

init()
