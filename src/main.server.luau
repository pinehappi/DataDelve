type App = {
	new: (id: string) -> App,
	
	toggleEnabled: (App) -> (),
	getEnabled: (App) -> boolean,
	enabledChanged: RBXScriptSignal,
}

local IS_CANARY = script.Parent.IsCanaryRelease.Value

local RunService = game:GetService("RunService")

local App: App = require(script.Parent.App)
local ClientFallbackApp: App = require(script.Parent.ClientFalbackApp)

local History = require(script.Parent.History).global
local Settings = require(script.Parent.Settings)
local Theme = require(script.Parent.UI.Theme)

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

local appName =
	if IS_CANARY then "DataDelve Canary"
	else "DataDelve"

local app
if RunService:IsRunning() and RunService:IsClient() then
	app = ClientFallbackApp.new(appName)
else
	app = App.new(appName)
end

local toolbar: PluginToolbar = plugin:CreateToolbar(appName)

local pluginButton: PluginToolbarButton = toolbar:CreateButton(
	appName,
	"easy interface for datastores",
	if IS_CANARY
		then "rbxassetid://18476887048"
		else "rbxassetid://18476917665"
)
pluginButton.ClickableWhenViewportHidden = true

plugin.Unloading:Connect(function()
	History:save(plugin)
	Settings.save(plugin)
end)

pluginButton.Click:Connect(function()
	app:toggleEnabled()
end)
app.enabledChanged:Connect(function(enabled: boolean)
	pluginButton:SetActive(enabled)
end)
pluginButton:SetActive(app:getEnabled())