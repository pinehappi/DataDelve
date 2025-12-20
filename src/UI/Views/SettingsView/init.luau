--!strict

local rfmt = require(script.Parent.Parent.Parent.rfmt)

local StyleState = script.Parent.Parent.StyleState
local Assets = script.Parent.Parent.Assets

local Settings = require(script.Parent.Parent.Parent.Settings)

local Theme = require(script.Parent.Parent.Theme)
local UIMessages = require(script.Parent.Parent.UIMessages)
local Tooltip = require(script.Parent.Parent.Tooltip)

local Tree = require(script.Parent.Parent.Viewers.Tree)

local StyleStateHelper = require(StyleState.StyleStateHelper)
local BackgroundStyleState = require(StyleState.BackgroundStyleState)
local ScrollingFrameStyleState = require(StyleState.ScrollingFrameStyleState)
local ButtonStyleState = require(StyleState.ButtonStyleState)
local LabelStyleState = require(StyleState.LabelStyleState)
local SeparatorStyleState = require(StyleState.SeparatorStyleState)
local SwitchStyleState = require(StyleState.Input.SwitchStyleState)
local SelectStyleState = require(StyleState.Input.SelectStyleState)

local AccentColorButtonStyleState = require(script.AccentColorButtonStyleState)

local SettingsView = {}
SettingsView.__index = SettingsView

local function spinIcon(icon: ImageLabel)
	local start = os.clock()
	local duration = 1
	while true do
		local delta = math.min(duration, os.clock() - start)
		local alpha = delta / duration

		icon.Rotation = 180 * ((alpha - 1) ^ 3 + 1)

		if delta >= duration then
			break
		end

		task.wait()
	end

	icon.Rotation = 0
end

local function rockIcon(icon: ImageLabel)
	local start = os.clock()
	local duration = 1.25
	while true do
		local delta = math.min(duration, os.clock() - start)
		local alpha = delta / duration

		icon.Rotation = 90 * math.sin(4 * math.pi * alpha) * math.pow(10, -alpha)

		if delta >= duration then
			break
		end

		task.wait()
	end

	icon.Rotation = 0
end

local function jumpIcon(icon: ImageLabel)
	local start = os.clock()
	local duration = 0.3
	while true do
		local delta = math.min(duration, os.clock() - start)
		local alpha = delta / duration

		icon.Position = UDim2.new(0.5, 0, 0.5, -5 * (-(2 * alpha - 1) ^ 2 + 1))

		if delta >= duration then
			break
		end

		task.wait()
	end

	icon.Position = UDim2.fromScale(0.5, 0.5)
end

local function bindSettingTooltip(theme: Theme.Theme, setting: any, message: string)
	Tooltip.bind(theme, setting, message, {
		on = setting,
		tooltipAnchor = Vector2.new(0, 0.5),
		offsetAnchor = Vector2.new(1, 0.5),
		offsetOnX = true,
	})
end

function SettingsView.from(theme: Theme.Theme, uiMessages: UIMessages.UIMessages, frame: typeof(Assets.Widget.Settings))
	local accentColorButtonStyleStates = {}
	for _, row in frame.Content.Accent.Buttons:GetChildren() do
		if row:IsA("Frame") then
			for _, button in row:GetChildren() do
				if button:IsA("TextButton") then
					accentColorButtonStyleStates[button.Name] = AccentColorButtonStyleState.from(theme, button)
				end
			end
		end
	end

	local settingLabels = {}
	for _, child in frame.Content:GetChildren() do
		local title = child:FindFirstChild("Title")
		if title then
			settingLabels[child.Name .. "Title"] = LabelStyleState.from(theme, title)
		elseif child:IsA("TextLabel") then
			settingLabels[child.Name] = LabelStyleState.from(theme, child)
		end

		local description = child:FindFirstChild("Description")
		if description then
			settingLabels[child.Name .. "Description"] =
				LabelStyleState.from(theme, description, { emphasis = "light" })
		end
	end

	local self = setmetatable({
		theme = theme,
		frame = frame,
		styleStates = {
			scrollbar = ScrollingFrameStyleState.from(theme, frame.Content),
			headerBackground = BackgroundStyleState.from(theme, frame.HeaderBackground, { style = "header" }),
			title = LabelStyleState.from(theme, frame.Title),
			presetButtons = {
				dark = ButtonStyleState.from(theme, frame.Content.Preset.Buttons.dark),
				light = ButtonStyleState.from(theme, frame.Content.Preset.Buttons.light),
				studio = ButtonStyleState.from(theme, frame.Content.Preset.Buttons.studio),
			},
			accentColorButtons = accentColorButtonStyleStates,
			highlightColorsSelect = SelectStyleState.from(theme, frame.Content.HighlightColors.Select, {
				default = Settings.get("highlightColors"),
				options = {
					"Default",
					"Script Editor",
				},
			}),
			hideGameNameSwitch = SwitchStyleState.from(theme, frame.Content.HideGameName.Switch, {
				default = Settings.get("hideGameName"),
			}),
			listDeletedKeysSwitch = SwitchStyleState.from(theme, frame.Content.ListDeletedKeys.Switch, {
				default = Settings.get("listDeletedKeys"),
			}),
			automaticallyListSwitch = SwitchStyleState.from(theme, frame.Content.AutomaticallyList.Switch, {
				default = Settings.get("automaticallyList"),
			}),
			clickToOpenSwitch = SwitchStyleState.from(theme, frame.Content.ClickToOpen.Switch, {
				default = Settings.get("clickToOpen"),
			}),
			useAlternatingKeysSwitch = SwitchStyleState.from(theme, frame.Content.UseAlternatingKeyColors.Switch, {
				default = Settings.get("useAlternatingKeyColors"),
			}),

			settingLabels = settingLabels,
			separators = SeparatorStyleState.fromDescendants(theme, frame),
		},

		connections = {},

		_tree = nil,
	}, SettingsView)

	self:loadFrom(Settings.data)

	-- Events

	table.insert(
		self.connections,
		Settings.changed:Connect(function(key, value)
			if key == "themePreset" then
				self:_updatePresetButtons(value)
				self:_updateAccentButtons(Settings.data.themeAccent)
				if value == "dark" then
					rockIcon(self.styleStates.presetButtons.dark.button.ImageHolder.ImageLabel)
				elseif value == "light" then
					spinIcon(self.styleStates.presetButtons.light.button.ImageHolder.ImageLabel)
				elseif value == "studio" then
					jumpIcon(self.styleStates.presetButtons.studio.button.ImageHolder.ImageLabel)
				end
			elseif key == "themeAccent" then
				self:_updateAccentButtons(value)
			end
		end)
	)

	table.insert(
		self.connections,
		theme.colorsChanged:Connect(function()
			task.wait()
			StyleStateHelper.update(self.styleStates :: any, "slow") -- TODO: why is this a warning without :: any
		end)
	)

	-- UI Events
	for _, button: any in self.styleStates.presetButtons do
		button.button.Activated:Connect(function()
			if Settings.data.themePreset ~= button.button.Name then
				Settings.set("themePreset", button.button.Name)
			end
		end)
	end

	for _, button: any in self.styleStates.accentColorButtons do
		button.button.Activated:Connect(function()
			if Settings.data.themeAccent ~= button.button.Name then
				Settings.set("themeAccent", button.button.Name)
			end
		end)
	end

	self.styleStates.highlightColorsSelect.changed:Connect(function(value)
		Settings.set("highlightColors", value)
	end)

	self.styleStates.hideGameNameSwitch.toggled:Connect(function(value)
		Settings.set("hideGameName", value)
	end)

	self.styleStates.useAlternatingKeysSwitch.toggled:Connect(function(value)
		Settings.set("useAlternatingKeyColors", value)
	end)

	self.styleStates.listDeletedKeysSwitch.toggled:Connect(function(value)
		Settings.set("listDeletedKeys", value)
	end)

	self.styleStates.automaticallyListSwitch.toggled:Connect(function(value)
		Settings.set("automaticallyList", value)
	end)

	self.styleStates.clickToOpenSwitch.toggled:Connect(function(value)
		Settings.set("clickToOpen", value)
	end)

	return self
end

function SettingsView:loadFrom(data: Settings.SettingsData)
	self:_updatePresetButtons(data.themePreset)
	self:_updateAccentButtons(data.themeAccent)
end

function SettingsView:_updatePresetButtons(selecting: string)
	for _, button: any in self.styleStates.presetButtons do
		button:setSelecting(button.button.Name == selecting):update()
	end
end

function SettingsView:_updateAccentButtons(selecting: string)
	for _, button: any in self.styleStates.accentColorButtons do
		if Settings.data.themePreset == "studio" then
			button:setSelecting(false)
			button:setDisabled(true)
			button:update()
		else
			button:setDisabled(false)
			button:setSelecting(button.button.Name == selecting):update()
		end
	end
end

function SettingsView:beforeOpen()
	self = self :: any
	if self._tree then
		self._tree:destroy()
	end

	self._tree = Tree.new(self.theme, self.uiMessages, self.frame.Content.TreePreview, {
		data = {
			number = 100,
			string = "preview",
			bool = true,
			buffer = buffer.create(2),
			null = nil,
			object = {
				number = 100,
				string = "preview",
				bool = true,
				null = nil,
				{
					nested = "object",
				},
			},
			array = {
				100 :: any,
				"preview" :: any,
				true :: any,
				nil :: any,
				{
					"nested",
					"array",
				},
			},
		},
		readOnly = true,
		allOpen = true,
	})
end

function SettingsView:afterClose()
	self = self :: any

	if self._tree then
		self._tree:destroy()
		self._tree = nil
	end
end

function SettingsView:destroy()
	for _, connection in self.connections do
		connection:Disconnect()
	end
end

return SettingsView
