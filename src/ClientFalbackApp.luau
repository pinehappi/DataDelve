-- If the user is play-testing on the client, fallback to this since the plugin won't work
local plugin = script:FindFirstAncestorOfClass("Plugin")

local ClientFallbackApp = {}
ClientFallbackApp.__index = ClientFallbackApp

local Theme = require(script.Parent.UI.Theme).global

local StyleState = script.Parent.UI.StyleState
local BackgroundStyleState = require(StyleState.BackgroundStyleState)
local LabelStyleState = require(StyleState.LabelStyleState)

local WIDGET_INFO = DockWidgetPluginGuiInfo.new(
	Enum.InitialDockState.Float, -- Widget will be initialized in floating panel
	false, -- Widget will be initially enabled
	false, -- Don't override the previous enabled state
	400, -- Default width of the floating window
	250, -- Default height of the floating window
	350, -- Minimum width of the floating window
	230 -- Minimum height of the floating window
)

function ClientFallbackApp.new(id: string)
	local self = setmetatable({
		id = id,
	}, ClientFallbackApp)

	self.widget = plugin:CreateDockWidgetPluginGui(id, WIDGET_INFO)
	self.widget.Title = id
	self.widget.Name = id
	self.widget.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	self.background = script.Background:Clone()
	self.background.Parent = self.widget

	self.styleStates = {
		background = BackgroundStyleState.from(Theme, self.background),
		imageLabel = LabelStyleState.from(Theme, self.background.ImageLabel),
		textLabel = LabelStyleState.from(Theme, self.background.TextLabel),
	}

	-- Enabled
	self._enabledChanged = Instance.new("BindableEvent")
	self.enabledChanged = self._enabledChanged.Event
	self.widget:GetPropertyChangedSignal("Enabled"):Connect(function()
		self._enabledChanged:Fire(self.widget.Enabled)
	end)

	return self
end

function ClientFallbackApp:toggleEnabled()
	self.widget.Enabled = not self.widget.Enabled
end

function ClientFallbackApp:getEnabled()
	return self.widget.Enabled
end

return ClientFallbackApp
