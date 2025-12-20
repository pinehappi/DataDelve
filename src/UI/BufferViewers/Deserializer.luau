--!strict

local SelectionService = game:GetService("Selection")
local ScriptEditorService = game:GetService("ScriptEditorService")

local Types = require(script.Parent.Types)
local UIMessages = require(script.Parent.Parent.UIMessages)
local Theme = require(script.Parent.Parent.Theme)
local Tooltip = require(script.Parent.Parent.Tooltip)
local PopupHelper = require(script.Parent.Parent.PopupHelper)
local rfmt = require(script.Parent.Parent.Parent.rfmt)
local DeserializerState = require(script.Parent.Parent.Parent.DeserializerState)

local StyleState = script.Parent.Parent.StyleState
local Assets = script.Parent.Parent.Assets

local StyleStateWrapper = require(StyleState.StyleStateWrapper)
local LabelStyleState = require(StyleState.LabelStyleState)
local BackgroundStyleState = require(StyleState.BackgroundStyleState)
local ButtonStyleState = require(StyleState.ButtonStyleState)

export type DeserializerFrame = typeof(Assets.Views.DeserializerView)

local function getStyleStates(theme: Theme.Theme, frame: DeserializerFrame)
	return {
		errorLabel = LabelStyleState.from(theme, frame.Container.Error.Message),
		errorIcon = LabelStyleState.from(theme, frame.Container.Error.Icon, { style = "error" }),
		deserializer = LabelStyleState.from(theme, frame.Top.Deserializer),
		useSelection = ButtonStyleState.from(theme, frame.Top.UseSelection),
		help = ButtonStyleState.from(theme, frame.Top.Help, {
			style = "dormant",
		}),
	}
end

export type DeserializerImplementation = {
	__index: DeserializerImplementation,
	from: (buf: buffer, container: Frame, options: Types.BufferViewerFromOptions) -> Deserializer,
	setValue: (Deserializer, buf: buffer) -> (),
	getValue: (Deserializer) -> buffer,
	destroy: (Deserializer) -> (),

	undo: (Deserializer) -> (),
	redo: (Deserializer) -> (),
	canUndo: (Deserializer) -> boolean,
	canRedo: (Deserializer) -> boolean,

	_setError: (Deserializer, message: string) -> (),
	_tryUseSelection: (Deserializer) -> (),
	_setDeserializer: (Deserializer, name: string, DeserializerState.Deserializer, buf: buffer?) -> (),

	_showHelpPopup: (Deserializer) -> (),
	_closeHelpPopup: (Deserializer) -> (),
}

export type DeserializerFields = {
	_historyChanged: BindableEvent,
	historyChanged: RBXScriptSignal,

	_inputReceiver: GuiObject,
	_container: Frame,
	_frame: DeserializerFrame,

	_theme: Theme.Theme,
	_uiMessages: UIMessages.UIMessages,
	_styleStates: typeof(getStyleStates({} :: any, {} :: any)),
	_helpTooltipDestructor: Tooltip.TooltipDestructor,

	_originalValue: buffer,
	_viewer: any,
	_viewerHistoryConnection: RBXScriptConnection?,

	_deserializerName: string?,
	_deserializer: DeserializerState.Deserializer?,

	_helpPopup: any,
	_helpPopupModal: any,
}

export type Deserializer = typeof(setmetatable({} :: DeserializerFields, {} :: DeserializerImplementation))

local Deserializer: DeserializerImplementation = {} :: DeserializerImplementation
Deserializer.__index = Deserializer

function Deserializer.from(buf: buffer, container: Frame, options: Types.BufferViewerFromOptions)
	local self = setmetatable({}, Deserializer)

	self._historyChanged = Instance.new("BindableEvent")
	self.historyChanged = self._historyChanged.Event :: RBXScriptSignal

	self._inputReceiver = options.inputReceiver
	self._theme = options.theme
	self._uiMessages = options.uiMessages
	self._container = container
	self._frame = Assets.Views.DeserializerView:Clone()
	self._frame.Parent = container
	self._styleStates = getStyleStates(options.theme, self._frame)

	self._viewer = nil
	self._originalValue = buf
	self._viewerHistoryConnection = nil

	self._helpTooltipDestructor = Tooltip.bindButtonGeneric(self._theme, self._styleStates.help.button, "Help")

	self._frame.Top.Deserializer.Activated:Connect(function()
		local moduleScript = DeserializerState.getDefaultDeserializerScript()
		if moduleScript and moduleScript:IsA("ModuleScript") then
			SelectionService:Set({ moduleScript })
			ScriptEditorService:OpenScriptDocumentAsync(moduleScript)
		end
	end)

	self._styleStates.useSelection.button.Activated:Connect(function()
		self:_tryUseSelection()
	end)

	self._styleStates.help.button.Activated:Connect(function()
		self:_showHelpPopup()
	end)

	local deserializer, err = DeserializerState.getDefaultDeserializer()
	if err then
		self:_setError(`Error deserializing: {err}`)
	elseif deserializer then
		self:_setDeserializer(deserializer.name, deserializer.deserializer)
	end

	return self
end

function Deserializer._setError(self: Deserializer, message: string)
	self._styleStates.errorLabel.label.Text = message
	self._frame.Container.Error.Visible = true
	self._frame.Container.Content.Visible = false
end

function Deserializer._tryUseSelection(self: Deserializer)
	local selection = SelectionService:Get()
	if #selection == 0 then
		self._uiMessages:error("Select a ModuleScript.")
		return
	elseif #selection > 1 then
		self._uiMessages:error("Select exactly on ModuleScript.")
		return
	end

	local module = selection[1]
	if not module:IsA("ModuleScript") then
		self._uiMessages:error("Select a ModuleScript.")
		return
	end

	local deserializer, err = DeserializerState.tryGetDeserializer(module)
	if err then
		self._uiMessages:error(err)
		return
	end

	DeserializerState.trySetDefaultDeserializer(module)

	self:_setDeserializer(module:GetFullName(), deserializer :: DeserializerState.Deserializer)
end

local function hasMixedTable(t: unknown): boolean
	if typeof(t) ~= "table" then
		return false
	else
		local hasNumeric = false
		local hasNonNumeric = false

		for k in t :: any do
			if type(k) == "number" then
				hasNumeric = true
			else
				hasNonNumeric = true
			end

			if hasNumeric and hasNonNumeric then
				return true
			end
		end

		for _, v in t :: any do
			if hasMixedTable(v) then
				return true
			end
		end

		return false
	end
end

function Deserializer._setDeserializer(
	self: Deserializer,
	name: string,
	deserializer: DeserializerState.Deserializer,
	buf: buffer?
)
	if self._viewer then
		self._viewer:destroy()
		self._viewer = nil

		self._frame.Container.Content.Visible = false
		self._frame.Container.Error.Visible = true
	end

	if self._viewerHistoryConnection then
		self._viewerHistoryConnection:Disconnect()
	end

	self._deserializerName = name
	self._deserializer = deserializer
	self._styleStates.deserializer.label.Text = `Deserializer: {name}`

	local value: unknown
	local success, err = pcall(function()
		value = deserializer.deserialize(buf or self:getValue())
	end)

	if not success then
		self:_setError(`Deserializer error: {err}`)
		return
	end

	if hasMixedTable(value) then
		self:_setError("Deserializer error: Mixed tables are not allowed!")
		return
	end

	local Tree = require(script.Parent.Parent.Viewers.Tree) :: any
	self._viewer = Tree.new(self._theme, self._uiMessages, self._frame.Container.Content, {
		data = value,
		readOnly = false,
		showKeyInfo = false,
		inputReceiver = self._inputReceiver,
	})

	self._viewer.historyChanged:Connect(function()
		self._historyChanged:Fire()
	end)
	self._historyChanged:Fire()
end

function Deserializer._showHelpPopup(self: Deserializer)
	self:_closeHelpPopup()

	local popup = Assets.Views.DeserializerHelpPopup:Clone()
	local wrapper = StyleStateWrapper.new(self._theme, {
		background = BackgroundStyleState.from(self._theme, popup),
		close = ButtonStyleState.from(self._theme, popup["Escape Layout"].Close),
		paragraphs = LabelStyleState.fromDescendants(self._theme, popup.Content),
		title = LabelStyleState.from(self._theme, popup.Title),
	})

	local modal = PopupHelper.modal(popup, self._container:FindFirstAncestorWhichIsA("LayerCollector") :: any)

	wrapper.styleStates.close.button.Activated:Connect(function()
		self:_closeHelpPopup()
	end)

	modal.cancelled:Connect(function()
		self:_closeHelpPopup()
	end)

	self._helpPopup = wrapper
	self._helpPopupModal = modal
end

function Deserializer._closeHelpPopup(self: Deserializer)
	if self._helpPopup then
		self._helpPopup:destroy(true)
	end
	if self._helpPopupModal then
		self._helpPopupModal:destroy()
	end

	self._helpPopup = nil
	self._helpPopupModal = nil
end

function Deserializer.getValue(self: Deserializer): buffer
	if self._viewer and self._deserializer then
		local buf: buffer
		local success, err = pcall(function()
			local viewerValue = self._viewer:getValue()
			buf = self._deserializer.serialize(viewerValue)
		end)

		if not success then
			warn(err)
			return self._originalValue
		end

		return buf
	else
		return self._originalValue
	end
end

function Deserializer.setValue(self: Deserializer, buf: buffer)
	if self._deserializerName and self._deserializer then
		self._originalValue = buf
		self:_setDeserializer(self._deserializerName, self._deserializer, buf)
	else
		self._originalValue = buf
	end
end

function Deserializer.canUndo(self: Deserializer)
	if self._viewer then
		return self._viewer:canUndo()
	else
		return false
	end
end

function Deserializer.canRedo(self: Deserializer)
	if self._viewer then
		return self._viewer:canRedo()
	else
		return false
	end
end

function Deserializer.undo(self: Deserializer)
	if self._viewer then
		self._viewer:undo()
	end
end

function Deserializer.redo(self: Deserializer)
	if self._viewer then
		self._viewer:redo()
	end
end

function Deserializer.destroy(self: Deserializer)
	if self._viewer then
		self._viewer:destroy()
	end

	if self._viewerHistoryConnection then
		self._viewerHistoryConnection:Disconnect()
	end

	for _, v in self._styleStates do
		(v :: any):destroy()
	end

	self._helpTooltipDestructor()

	self:_closeHelpPopup()

	self._historyChanged:Destroy()
	self._frame:Destroy()
end

return Deserializer
