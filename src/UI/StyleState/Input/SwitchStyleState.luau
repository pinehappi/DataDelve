--!strict
-- Same as Checkbox, just styled differently

local TweenService = game:GetService("TweenService")
local StyleStateHelper = require(script.Parent.Parent.StyleStateHelper)
local ButtonStyleState = require(script.Parent.Parent.ButtonStyleState)

local SwitchStyleState = {}
SwitchStyleState.__index = SwitchStyleState

type SwitchOptions = {
	default: boolean?,
}
function SwitchStyleState.from(theme, switch: TextButton & { Circle: GuiObject }, options: SwitchOptions?)
	local options: SwitchOptions = options or {}

	local self = setmetatable({
		value = options.default or false,
		switch = switch,
		theme = theme,

		buttonStyleState = ButtonStyleState.from(theme, switch, {
			style = "secondary",
		}),
	}, SwitchStyleState)

	self._toggled = Instance.new("BindableEvent")
	self.toggled = self._toggled.Event

	self._clickedConnection = self.switch.Activated:Connect(function()
		self:setValue(not self.value)
	end)

	self:_updateCircle("instant")
	self:update("instant")
	return self
end

function SwitchStyleState:_getCircleColor()
	return if self.value
		then self.theme.colors.button.primary.text.select
		else self.theme.colors.button.secondary.text.default
end

function SwitchStyleState:_updateCircle(speed: StyleStateHelper.TransitionSpeed)
	local tweenInfo = StyleStateHelper.getTweenInfoForSpeed(speed)
	if self.value then
		self.buttonStyleState.style = "primary"
	else
		self.buttonStyleState.style = "secondary"
	end
	StyleStateHelper.tween(self.switch.Circle, tweenInfo, {
		BackgroundColor3 = self:_getCircleColor(),
		Position = if self.value then UDim2.fromScale(1, 0) else UDim2.fromScale(0, 0),
		AnchorPoint = if self.value then Vector2.new(1, 0) else Vector2.new(0, 0),
	})
end

function SwitchStyleState:update(speed: StyleStateHelper.TransitionSpeed)
	local tweenInfo = StyleStateHelper.getTweenInfoForSpeed(speed)
	self.buttonStyleState:update(speed)
	StyleStateHelper.tween(self.switch.Circle, tweenInfo, {
		BackgroundColor3 = self:_getCircleColor(),
	})
end

function SwitchStyleState:setValue(value)
	local lastValue = self.value
	self.value = value
	self:_updateCircle("veryFast")
	self.buttonStyleState:update("veryFast")

	if self.value ~= lastValue then
		self._toggled:Fire(self.value)
	end
end

function SwitchStyleState:destroy(completely: boolean)
	self.buttonStyleState:destroy(completely)
	self._clickedConnection:Disconnect()
	self._toggled:Destroy()
	if completely then
		-- it will be destroyed by the button style state
	end
end

return SwitchStyleState
