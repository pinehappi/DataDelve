-- TODO: should auto-follow theme when using.createDialog

local StyleStateHelper = require(script.Parent.Parent.StyleStateHelper)
local PopupHelper = require(script.Parent.Parent.Parent.PopupHelper)

local BackgroundStyleState = require(script.Parent.Parent.BackgroundStyleState)
local ButtonStyleState = require(script.Parent.Parent.ButtonStyleState)
local LabelStyleState = require(script.Parent.Parent.LabelStyleState)

local ConfirmDialogStyleState = {}
ConfirmDialogStyleState.__index = ConfirmDialogStyleState
ConfirmDialogStyleState.template = script.ConfirmDialog

type ContextMenuOptions = {
	title: string,
	message: string,
	yesText: string?,
	noText: string?,
}

-- For convenience
function ConfirmDialogStyleState.confirm(
	theme,
	container: GuiObject,
	position: Vector2,
	options: ContextMenuOptions
): boolean
	local dialog, modal = ConfirmDialogStyleState.createDialog(theme, container, position, options)

	local confirmed = dialog.interacted:Wait()

	modal:destroy()
	dialog:destroy(true)

	return confirmed
end

function ConfirmDialogStyleState.createDialog(
	theme,
	container: GuiObject,
	position: Vector2,
	options: ContextMenuOptions
)
	local frame = script.ConfirmDialog:Clone()
	frame.Parent = container
	frame.Position = UDim2.fromOffset(position.X, position.Y)

	local styleState = ConfirmDialogStyleState.from(theme, frame, options)

	local modal = PopupHelper.modal(frame, container, {
		zIndex = 20,
	})
	modal.cancelled:Connect(function()
		styleState._interacted:Fire(false)
	end)

	if options.yesText then
		frame.Buttons.Yes.TextLabel.Text = options.yesText
	end
	if options.noText then
		frame.Buttons.No.TextLabel.Text = options.noText
	end

	PopupHelper.clamp(frame, container)

	return styleState, modal
end

function ConfirmDialogStyleState.from(theme, dialog: typeof(script.ConfirmDialog), options: ContextMenuOptions)
	local self = setmetatable({
		theme = theme,
		frame = dialog,
		options = options.options,

		_styleStates = {
			background = BackgroundStyleState.from(theme, dialog, {
				style = "popup",
			}),
			title = LabelStyleState.from(theme, dialog.Title),
			message = LabelStyleState.from(theme, dialog.Message),
			yes = ButtonStyleState.from(theme, dialog.Buttons.Yes, {
				style = "primary",
			}),
			no = ButtonStyleState.from(theme, dialog.Buttons.No, {
				style = "secondary",
			}),
		},
	}, ConfirmDialogStyleState)

	dialog.Title.Text = options.title
	dialog.Message.Text = options.message

	self._interacted = Instance.new("BindableEvent")
	self.interacted = self._interacted.Event

	dialog.Buttons.Yes.Activated:Connect(function()
		self._interacted:Fire(true)
	end)
	dialog.Buttons.No.Activated:Connect(function()
		self._interacted:Fire(false)
	end)

	self:update("instant")
	return self
end

function ConfirmDialogStyleState:interact(confirmed: boolean)
	self._interacted:Fire(confirmed)
end

function ConfirmDialogStyleState:update(speed: StyleStateHelper.TransitionSpeed?)
	for _, styleState in self._styleStates do
		styleState:update(speed)
	end
end

function ConfirmDialogStyleState:destroy(completely: boolean)
	for _, styleState in self._styleStates do
		styleState:destroy(completely)
	end
	if completely then
		self.frame:Destroy()
	end
end

return ConfirmDialogStyleState
