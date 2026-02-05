--!strict

local StyleStateHelper = require(script.Parent.Parent.StyleStateHelper)
local StyleStateWrapper = require(script.Parent.Parent.StyleStateWrapper)
local PopupHelper = require(script.Parent.Parent.Parent.PopupHelper)

local BackgroundStyleState = require(script.Parent.Parent.BackgroundStyleState)
local ButtonStyleState = require(script.Parent.Parent.ButtonStyleState)
local LabelStyleState = require(script.Parent.Parent.LabelStyleState)

local PopupFormStyleState = {}
PopupFormStyleState.__index = PopupFormStyleState
PopupFormStyleState.template = script.PopupForm
PopupFormStyleState.buttonTemplate = script.ButtonTemplate

export type PopupFormFromOptions = {
	title: string,
	buttons: { { text: string, options: ButtonStyleState.ButtonStyleStateFromOptions? } },
	addContents: (Frame) -> { StyleStateHelper.StyleState } | { [string]: StyleStateHelper.StyleState },
}

-- For convenience
function PopupFormStyleState.createPopup(theme, container: GuiBase2d, position: Vector2, options: PopupFormFromOptions)
	local frame = script.PopupForm:Clone()
	frame.Parent = container
	frame.Position = UDim2.fromOffset(position.X, position.Y)

	local styleState = PopupFormStyleState.from(theme, frame, options)

	local modal = PopupHelper.modal(frame, container, {
		zIndex = 20,
	})
	modal.cancelled:Connect(function()
		styleState._interacted:Fire(nil)
	end)

	PopupHelper.clamp(frame, container)

	return styleState, modal
end

function PopupFormStyleState.from(theme, dialog: typeof(PopupFormStyleState.template), options: PopupFormFromOptions)
	local self = setmetatable({
		theme = theme,
		frame = dialog,
	}, PopupFormStyleState)

	local buttonStyleStates = {}
	for _, buttonInfo in options.buttons do
		local button = script.ButtonTemplate:Clone()
		button.TextLabel.Text = buttonInfo.text
		local styleState = ButtonStyleState.from(theme, button, buttonInfo.options)
		buttonStyleStates[buttonInfo.text] = styleState

		button.Activated:Connect(function()
			self:interact(buttonInfo.text)
		end)

		button.Parent = dialog.Form.Buttons
	end

	self.wrapper = StyleStateWrapper.new(theme, {
		background = BackgroundStyleState.from(theme, dialog, {
			style = "popup",
		}),
		title = LabelStyleState.from(theme, dialog.Title),
		contents = options.addContents(dialog.Form),
		buttons = buttonStyleStates,
	})

	dialog.Title.Text = options.title

	self._interacted = Instance.new("BindableEvent")
	self.interacted = self._interacted.Event

	self:update("instant")
	return self
end

function PopupFormStyleState:interact(clicked: string?)
	self._interacted:Fire(clicked)
end

function PopupFormStyleState:update(speed: StyleStateHelper.TransitionSpeed?)
	self.wrapper:update(speed)
end

function PopupFormStyleState:destroy(completely: boolean)
	self.wrapper:destroy(completely)
	if completely then
		self.frame:Destroy()
	end
end

return PopupFormStyleState
