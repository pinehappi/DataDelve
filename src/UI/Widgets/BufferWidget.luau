--!strict

local plugin = script:FindFirstAncestorOfClass("Plugin")
local StudioService = game:GetService("StudioService")

local Settings = require(script.Parent.Parent.Parent.Settings)
local UIMessages = require(script.Parent.Parent.UIMessages)
local Theme = require(script.Parent.Parent.Theme)

local Types = require(script.Parent.Parent.BufferViewers.Types)
local HexViewer = require(script.Parent.Parent.BufferViewers.Hex)
local DeserializerViewer = require(script.Parent.Parent.BufferViewers.Deserializer)

local Assets = script.Parent.Parent.Assets
local StyleState = script.Parent.Parent.StyleState
local StyleStateWrapper = require(StyleState.StyleStateWrapper)
local BackgroundStyleState = require(StyleState.BackgroundStyleState)
local ButtonStyleState = require(StyleState.ButtonStyleState)
local SelectStyleState = require(StyleState.Input.SelectStyleState)

local WIDGET_INFO = DockWidgetPluginGuiInfo.new(
	Enum.InitialDockState.Float, -- Widget will be initialized in floating panel
	true, -- Widget will be initially enabled
	true, -- Override the previous enabled state
	832, -- Default width of the floating window
	300, -- Default height of the floating window
	400, -- Minimum width of the floating window
	150 -- Minimum height of the floating window
)

local BufferWidget = {}
BufferWidget.__index = BufferWidget

function BufferWidget.new(theme: Theme.Theme, name: string, b: buffer)
	local self = setmetatable({}, BufferWidget)
	self.dead = false
	self.id = tostring(b)

	self.theme = theme
	self.widget = plugin:CreateDockWidgetPluginGui(self.id, WIDGET_INFO) :: PluginGui & typeof(Assets.HexEditorWidget)
	self.widget.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	self.widget.Title = `"{name}" buffer`
	self.widget.Name = "DataDelve HexEditor"

	self.uiMessages = UIMessages.new(self.theme)
	self.uiMessages:setParent(self.widget)

	-- Set up UI

	for _, item in Assets.Widgets.HexEditorWidget:GetChildren() do
		item:Clone().Parent = self.widget
	end
	self.wrapper = StyleStateWrapper.new(theme, {
		background = BackgroundStyleState.from(theme, self.widget.Background),
		mode = SelectStyleState.from(theme, self.widget.Content.LeftTop.Mode, {
			default = Settings.get("bufferViewerMode"),
			options = {
				{ icon = self.theme.icons.hex, name = "Hex" },
				{ icon = self.theme.icons.script, name = "Deserializer" },
			},
			fitButton = false,
		}),
		undo = ButtonStyleState.from(theme, self.widget.Content.LeftTop.History.Undo, { style = "dormant" }),
		redo = ButtonStyleState.from(theme, self.widget.Content.LeftTop.History.Redo, { style = "dormant" }),
		loadFile = ButtonStyleState.from(theme, self.widget.Content.LeftTop.LoadFile, { style = "secondary" }),

		commit = ButtonStyleState.from(theme, self.widget.Content.RightTop.Commit, { style = "primary" }),
		cancel = ButtonStyleState.from(theme, self.widget.Content.RightTop.Cancel, { style = "secondary" }),
	})

	-- Events

	-- Parameters:
	--	submitted: boolean
	--		If the user submitted or cancelled. True is submitted.
	-- NOTE: this is fired with false when the widget is destroyed
	self._interacted = Instance.new("BindableEvent")
	self.interacted = self._interacted.Event

	-- UI Events

	self._viewer = nil :: Types.BufferViewer?
	self._viewerConnections = {} :: { RBXScriptConnection }

	self._mode = self.wrapper.styleStates.mode.selection
	self:_setMode(self._mode, b)
	self.wrapper.styleStates.mode.changed:Connect(function(mode)
		self:_setMode(mode, self:getFreshBuffer())
	end)

	self.wrapper.styleStates.undo.button.Activated:Connect(function()
		assert(self._viewer, "how no viewer?")
		if self._viewer:canUndo() then
			self._viewer:undo()
		end
	end)
	self.wrapper.styleStates.redo.button.Activated:Connect(function()
		assert(self._viewer, "how no viewer?")
		if self._viewer:canRedo() then
			self._viewer:redo()
		end
	end)

	self.wrapper.styleStates.loadFile.button.Activated:Connect(function()
		assert(self._viewer, "how??")

		local file: File = StudioService:PromptImportFile()
		if file then
			self._viewer:setValue(buffer.fromstring(file:GetBinaryContents()))
		else
			self.uiMessages:warn("No file selected.")
		end
	end)

	self.wrapper.styleStates.cancel.button.Activated:Connect(function()
		self._interacted:Fire(false)
	end)
	self.wrapper.styleStates.commit.button.Activated:Connect(function()
		self._interacted:Fire(true)
	end)

	self.widget.Destroying:Connect(function()
		(self :: any):destroy()
	end)
	self.widget:GetPropertyChangedSignal("Enabled"):Connect(function()
		if not self.widget.Enabled then
			(self :: any):destroy()
		end
	end)

	return self
end

function BufferWidget:_updateUndoRedoButtons(speed: string?)
	self.wrapper.styleStates.undo:setDisabled(not self._viewer:canUndo()):update(speed)
	self.wrapper.styleStates.redo:setDisabled(not self._viewer:canRedo()):update(speed)
end

function BufferWidget:_cleanupViewer()
	if self._viewer then
		self._viewer:destroy()
		for _, v in self._viewerConnections do
			v:Disconnect()
		end
	end
end

function BufferWidget:_setMode(mode: Types.BufferViewerMode, buf: buffer)
	self:_cleanupViewer()

	local viewer: Types.BufferViewer
	if mode == "Hex" then
		viewer = (HexViewer :: any) :: Types.BufferViewer
	elseif mode == "Deserializer" then
		viewer = (DeserializerViewer :: any) :: Types.BufferViewer
	end

	Settings.set("bufferViewerMode", mode)

	self._mode = mode
	self._viewer = viewer.from(buf, self.widget.Content.EditorContainer, {
		uiMessages = self.uiMessages,
		theme = self.theme,
		inputReceiver = self.widget.InputReceiver,
		widget = self.widget,
	}) :: Types.BufferViewer

	local selfAny = self :: any
	selfAny:_updateUndoRedoButtons("instant")
	self._viewerConnections = {
		selfAny._viewer.historyChanged:Connect(function()
			selfAny:_updateUndoRedoButtons()
		end),
	}
end

function BufferWidget:getFreshBuffer()
	assert(self._viewer, "how?!?!")
	return self._viewer:getValue()
end

function BufferWidget:destroy()
	if self.dead then
		return
	end
	self.dead = true

	self._interacted:Fire(false)

	self:_cleanupViewer()
	self.wrapper:destroy(true)
	self.widget:Destroy()
end

export type BufferWidget = typeof(BufferWidget.new({} :: any, "", buffer.create(0)))
return BufferWidget
