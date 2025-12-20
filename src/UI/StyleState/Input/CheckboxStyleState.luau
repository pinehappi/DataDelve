local TweenService = game:GetService("TweenService")
local StyleStateHelper = require(script.Parent.Parent.StyleStateHelper)
local ButtonStyleState = require(script.Parent.Parent.ButtonStyleState)

local CheckboxStyleState = {}
CheckboxStyleState.__index = CheckboxStyleState

export type CheckboxOptions = {
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
	assert(options)

	checkbox.Check:SetAttribute("Exclude", true) -- Exclude it from button theming

	local self = setmetatable({
		value = options.default or false,
		checkbox = checkbox,
		theme = theme,

		_hovering = false,
		_pressing = false,
	}, CheckboxStyleState)

	self._toggled = Instance.new("BindableEvent")
	self.toggled = self._toggled.Event

	self._connections = {
		self.checkbox.Activated:Connect(function()
			self:setValue(not self.value)
		end),
		self.checkbox.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseMovement then
				self._hovering = true
				self:update()
			elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
				self._pressing = true
				self:update()

				local connection: RBXScriptConnection
				connection = input:GetPropertyChangedSignal("UserInputState"):Connect(function()
					if
						input.UserInputState ~= Enum.UserInputState.Begin
						and input.UserInputState ~= Enum.UserInputState.Change
					then
						connection:Disconnect()

						self._pressing = false
						self:update()
					end
				end)
			end
		end),
		self.checkbox.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseMovement then
				self._hovering = false
				self:update()
			end
		end),
	}
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

	local style = if self.value then "primary" else "secondary"
	local state = if self._pressing then "press" elseif self._hovering then "hover" else "default"

	StyleStateHelper.tween(self.checkbox, tweenInfo, {
		BackgroundColor3 = self.theme.colors.button[style].body[state],
	})

	StyleStateHelper.tween(self.checkbox.UIStroke, tweenInfo, {
		Color = self.theme.colors.button[style].outline[state],
	})

	if self.checkbox.Check.Visible then
		StyleStateHelper.tween(self.checkbox.Check, tweenInfo, {
			ImageColor3 = self.theme.colors.button.primary.text.select,
		})
	end
end

function CheckboxStyleState:setValue(value)
	local lastValue = self.value
	self.value = value
	self.checkbox.Check.Visible = value
	self:update()

	if self.value ~= lastValue then
		self._toggled:Fire(self.value)
	end
end

function CheckboxStyleState:destroy(completely: boolean)
	self.buttonStyleState:destroy(completely)

	for _, connection in self._connections do
		connection:Disconnect()
	end

	if self._inputPairClickedConnection then
		self._inputPairClickedConnection:Disconnect()
	end

	self._toggled:Destroy()
	if completely then
		-- it will be destroyed by the button style state
	end
end

return CheckboxStyleState
