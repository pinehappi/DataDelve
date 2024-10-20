local TweenService = game:GetService("TweenService")
local StyleStateHelper = require(script.Parent.Parent.StyleStateHelper)
local ButtonStyleState = require(script.Parent.Parent.ButtonStyleState)

local CheckboxStyleState = {}
CheckboxStyleState.__index = CheckboxStyleState

type CheckboxOptions = {
	default: boolean?,

	-- The inputPair will also be used to process clicks.
	-- Useful if you have a label next to the checkbox that you want to be clickable.
	inputPair: GuiButton?,
}
function CheckboxStyleState.from(
	theme,
	checkbox: TextButton & { UIStroke: UIStroke, Check: ImageLabel },
	options: CheckboxOptions?
)
	options = options or {}
	checkbox.Check:SetAttribute("Exclude", true) -- Exclude it from button theming

	local self = setmetatable({
		value = options.default or false,
		checkbox = checkbox,
		theme = theme,

		buttonStyleState = ButtonStyleState.from(theme, checkbox, {
			style = "input",
		}),
	}, CheckboxStyleState)

	self._toggled = Instance.new("BindableEvent")
	self.toggled = self._toggled.Event

	self._clickedConnection = self.checkbox.Activated:Connect(function()
		self:setValue(not self.value)
	end)
	self.checkbox.Check.Visible = self.value

	if options.inputPair then
		self._inputPairClickedConnection = options.inputPair.Activated:Connect(function()
			self:setValue(not self.value)
		end)
	end

	self:update("instant")
	return self
end

function CheckboxStyleState:update(speed: StyleStateHelper.TransitionSpeed)
	local tweenInfo = StyleStateHelper.getTweenInfoForSpeed(speed)
	self.buttonStyleState:update(speed)
	if self.checkbox.Check.Visible then
		TweenService:Create(self.checkbox.Check, tweenInfo, {
			ImageColor3 = self.theme.colors.mainAccent,
		}):Play()
	end
end

function CheckboxStyleState:setValue(value)
	local lastValue = self.value
	self.value = value
	self.checkbox.Check.Visible = value
	if value then
		self.checkbox.Check.ImageColor3 = self.theme.colors.mainAccent
	end

	if self.value ~= lastValue then
		self._toggled:Fire(self.value)
	end
end

function CheckboxStyleState:destroy(completely: boolean)
	self.buttonStyleState:destroy(completely)
	self._clickedConnection:Disconnect()

	if self._inputPairClickedConnection then
		self._inputPairClickedConnection:Disconnect()
	end

	self._toggled:Destroy()
	if completely then
		-- it will be destroyed by the button style state
	end
end

return CheckboxStyleState
