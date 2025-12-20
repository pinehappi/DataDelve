--!strict

local SelectionService = game:GetService("Selection")
local ScriptEditorService = game:GetService("ScriptEditorService")

local Types = require(script.Parent.Types)
local ViewerTypes = require(script.Parent.Parent.Viewers.Types)
local UIMessages = require(script.Parent.Parent.UIMessages)
local Theme = require(script.Parent.Parent.Theme)
local Tooltip = require(script.Parent.Parent.Tooltip)
local PopupHelper = require(script.Parent.Parent.PopupHelper)
local rfmt = require(script.Parent.Parent.Parent.rfmt)
local DeserializerState = require(script.Parent.Parent.Parent.DeserializerState)
local ModalState = require(script.Parent.Parent.ModalState)

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
	_cleanupEditor: (Deserializer) -> (),

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
	_editor: (DeserializerState.Editor & { viewer: any? })?,

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

	self._originalValue = buf
	self._editor = nil

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
	self._uiMessages:error(message)
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

	local deserializer, err = DeserializerState.tryLoadDeserializer(module)
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
	self:_cleanupEditor()

	self._deserializerName = name
	self._deserializer = deserializer
	self._styleStates.deserializer.label.Text = `Deserializer: {name}`

	self._frame.Container.Error.Visible = false
	self._frame.Container.Content.Visible = true

	if deserializer.type == "function" then
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

		-- circular dependency...
		local Tree = require(script.Parent.Parent.Viewers.Tree) :: any

		local container = Instance.new("Frame")
		container.BackgroundTransparency = 1
		container.Size = UDim2.fromScale(1, 1)
		container.Parent = self._frame.Container.Content

		local viewer = Tree.new(self._theme, self._uiMessages, container, {
			data = value,
			readOnly = false,
			showKeyInfo = false,
			inputReceiver = self._inputReceiver,
			modalState = ModalState.new(),
		})

		local connection = viewer.historyChanged:Connect(function()
			self._historyChanged:Fire()
		end)

		self._editor = {
			object = container :: any,
			getValue = function()
				local result = viewer:getValue()
				if result.kind == "success" then
					return deserializer.serialize(result.value)
				end

				return nil :: any
			end,
			cleanup = function()
				viewer:destroy()
			end,
			viewer = viewer :: any,
		}
	elseif deserializer.type == "editor" then
		local editor: DeserializerState.Editor
		local success, err = pcall(function()
			local gotEditor: any = deserializer.createEditor(buf or self:getValue())

			if typeof(gotEditor) ~= "table" then
				error("Deserializer error: expected `createEditor` to return a table.", 0)
			end

			if typeof(gotEditor.object) ~= "Instance" then
				error("Deserializer error: expected editor to contain `object` key of type Instance.", 0)
			end

			if typeof(gotEditor.getValue) ~= "function" then
				error("Deserializer error: expected editor to contain `getValue` key of type `() -> buffer?`.", 0)
			end

			if gotEditor.cleanup and typeof(gotEditor.cleanup) ~= "function" then
				error("Deserializer error: expected editor to contain `getValue` key of type `() -> buffer?`.", 0)
			end

			editor = gotEditor
		end)

		-- TODO: the error might belong to the serializer of the previous editor. Need a better way to separate the error in `createEditor` and `getValue`
		if not success then
			self:_setError(`Deserializer error: {err}`)
			return
		end

		editor.object.Parent = self._frame.Container.Content
		self._editor = editor :: any
	end

	self._historyChanged:Fire()
end

function Deserializer._cleanupEditor(self: Deserializer)
	if self._editor and self._editor.cleanup then
		self._editor.cleanup()
		self._editor.object:Destroy()
	end
	self._editor = nil
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
	if self._editor then
		local buf: buffer?
		local success, err = pcall(function()
			buf = self._editor.getValue()
		end)

		if not success then
			self._uiMessages:error(err)
			return self._originalValue
		end

		return buf or self._originalValue
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
	if self._editor and self._editor.viewer then
		return self._editor.viewer:canUndo()
	else
		return false
	end
end

function Deserializer.canRedo(self: Deserializer)
	if self._editor and self._editor.viewer then
		return self._editor.viewer:canRedo()
	else
		return false
	end
end

function Deserializer.undo(self: Deserializer)
	if self._editor and self._editor.viewer then
		self._editor.viewer:undo()
	end
end

function Deserializer.redo(self: Deserializer)
	if self._editor and self._editor.viewer then
		self._editor.viewer:redo()
	end
end

function Deserializer.destroy(self: Deserializer)
	self:_cleanupEditor()

	for _, v in self._styleStates do
		(v :: any):destroy()
	end

	self._helpTooltipDestructor()

	self:_closeHelpPopup()

	self._historyChanged:Destroy()
	self._frame:Destroy()
end

return Deserializer
