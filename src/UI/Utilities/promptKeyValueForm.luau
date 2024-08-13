local Assets = script.Parent.Parent.Assets
local StyleState = script.Parent.Parent.StyleState

local StyleStateWrapper = require(StyleState.StyleStateWrapper)
local TextBoxStyleState = require(StyleState.Input.TextBoxStyleState)
local ShortcutsTextBoxStyleState = require(StyleState.Input.ShortcutsTextBoxStyleState)
local ButtonStyleState = require(StyleState.ButtonStyleState)
local BackgroundStyleState = require(StyleState.BackgroundStyleState)
local LabelStyleState = require(StyleState.LabelStyleState)

local Validators = require(script.Parent.Parent.Parent.Validators)
local JSONHelper = require(script.Parent.Parent.Parent.JSONHelper)
local PopupHelper = require(script.Parent.Parent.PopupHelper)

export type Options = {
	position: Vector2?,
	anchorPoint: Vector2?,
	title: string,

	includeKey: boolean,
	includeValue: boolean,

	yesText: string?,
	noText: string?,

	constraint: "userId" | "orderedDataStore" | "rename" | "renameAllScopes" | nil,
}
return function(theme, gui, options: Options): { key: string, value: JSONHelper.JSONValue }?
	local frame = Assets.KeyValueForm:Clone()
	frame.Title.Text = options.title

	local wrapper = StyleStateWrapper.new(theme, {
		title = LabelStyleState.from(theme, frame.Title),
		background = BackgroundStyleState.from(theme, frame, {
			style = "popup",
		}),

		keyLabel = LabelStyleState.from(theme, frame.Form.Key.Title),
		keyTextBox = if options.constraint == "rename" or options.constraint == "renameAllScopes"
			then ShortcutsTextBoxStyleState.from(theme, frame.Form.Key.TextBox)
			else TextBoxStyleState.from(theme, frame.Form.Key.TextBox),

		valueLabel = LabelStyleState.from(theme, frame.Form.Value.Title),
		valueTextBox = TextBoxStyleState.from(theme, frame.Form.Value.TextBox),

		insert = ButtonStyleState.from(theme, frame.Form.Buttons.Insert, {
			style = "primary",
		}),
		cancel = ButtonStyleState.from(theme, frame.Form.Buttons.Cancel, {
			style = "secondary",
		}),
	})

	wrapper.styleStates.insert.button.TextLabel.Text = options.yesText or "Insert"
	wrapper.styleStates.cancel.button.TextLabel.Text = options.noText or "Cancel"

	local keyTextBoxStyleState = wrapper.styleStates.keyTextBox
	local valueTextBoxStyleState = wrapper.styleStates.valueTextBox
	local function updateDisabled(instant)
		local disabled = (options.includeKey and keyTextBoxStyleState.textBox.Text == "")
			or (options.includeValue and valueTextBoxStyleState.textBox.Text == "")
			or keyTextBoxStyleState.error
			or valueTextBoxStyleState.error

		wrapper.styleStates.insert:setDisabled(disabled):update(if instant then "instant" else nil)
	end

	keyTextBoxStyleState.textBox:GetPropertyChangedSignal("Text"):Connect(function()
		if keyTextBoxStyleState.textBox.Text == "" then
			keyTextBoxStyleState:setError(nil):update("veryFast")
			updateDisabled()
			return
		end

		local validator = if options.constraint == "orderedDataStore"
			then Validators.dataStoreKey
			elseif options.constraint == "renameAllScopes" then Validators.allScopesKey
			elseif options.constraint == "rename" then Validators.dataStoreKey
			else Validators.empty
		local valid, err = validator(keyTextBoxStyleState.textBox.Text)
		if valid then
			keyTextBoxStyleState:setError(nil):update("veryFast")
		else
			keyTextBoxStyleState:setError(err):update("veryFast")
		end

		updateDisabled()
	end)
	valueTextBoxStyleState.textBox:GetPropertyChangedSignal("Text"):Connect(function()
		-- Syntax highlighting
		local valueType = JSONHelper.parseInputString(valueTextBoxStyleState.textBox.Text, "")
		valueTextBoxStyleState:overrideTextColor(theme.colors.syntaxHighlight[valueType]):update("veryFast")

		-- Validate
		if valueTextBoxStyleState.textBox.Text == "" then
			valueTextBoxStyleState:setError(nil):update("veryFast")
			updateDisabled()
			return
		end

		local validator = if options.constraint == "orderedDataStore"
			then Validators.orderedDataStoreValue
			elseif options.constraint == "userId" then Validators.userId
			else Validators.empty

		local valid, err = validator(valueTextBoxStyleState.textBox.Text)
		if valid then
			valueTextBoxStyleState:setError(nil):update("veryFast")
		else
			valueTextBoxStyleState:setError(err):update("veryFast")
		end

		updateDisabled()
	end)

	if not options.includeKey then
		frame.Form.Key.Visible = false
	end
	if not options.includeValue then
		frame.Form.Value.Visible = false
	end

	local position = options.position or gui:GetRelativeMousePosition()
	frame.Position = UDim2.fromOffset(position.X, position.Y)
	frame.AnchorPoint = options.anchorPoint or frame.AnchorPoint
	frame.Parent = gui

	if options.includeKey then
		keyTextBoxStyleState.textBox:CaptureFocus()
	else
		valueTextBoxStyleState.textBox:CaptureFocus()
	end

	PopupHelper.clamp(frame, gui)
	local modal = PopupHelper.modal(frame, gui)

	local status = nil

	modal.cancelled:Connect(function()
		status = "cancel"
	end)
	wrapper.styleStates.cancel.button.Activated:Connect(function()
		status = "cancel"
	end)
	local function onFocusLost(entered: boolean)
		if entered then
			if wrapper.styleStates.insert.button.Active then
				status = "insert"
			end
		end
	end
	keyTextBoxStyleState.textBox.FocusLost:Connect(onFocusLost)
	valueTextBoxStyleState.textBox.FocusLost:Connect(onFocusLost)
	wrapper.styleStates.insert.button.Activated:Connect(function()
		status = "insert"
	end)

	updateDisabled(true)

	while status == nil do
		task.wait()
	end

	modal:destroy()
	wrapper:destroy()
	frame:Destroy()

	if status == "insert" then
		local type, value = JSONHelper.parseInputString(valueTextBoxStyleState.textBox.Text)
		return {
			key = keyTextBoxStyleState:getText(function(err)
				-- TODO: have the error display in the plugin gui!!! need to pass in uimessages
				warn(err)
			end),
			value = value,
			type = type,
		}
	else
		return nil
	end
end
