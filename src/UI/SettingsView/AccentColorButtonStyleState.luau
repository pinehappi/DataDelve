local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent.Parent.Theme)

local StyleStateHelper = require(script.Parent.Parent.StyleState.StyleStateHelper)
local ButtonStyleState = require(script.Parent.Parent.StyleState.ButtonStyleState)

local AccentColorButtonStyleState = setmetatable({}, { __index = ButtonStyleState })
AccentColorButtonStyleState.__index = AccentColorButtonStyleState

function AccentColorButtonStyleState.from(...)
	local self = setmetatable(ButtonStyleState.from(...), AccentColorButtonStyleState)

	self:update("instant")
	return self
end

function AccentColorButtonStyleState:update(speed: StyleStateHelper.TransitionSpeed)
	local tween = StyleStateHelper.getTweenInfoForSpeed(speed)
	local state = if self.disabled
		then "disable"
		elseif self.selecting then "select"
		elseif self._pressing then "press"
		elseif self._hovering then "hover"
		else "default"

	local color = if state == "disable"
		then Color3.new(0.5, 0.5, 0.5)
		else Theme.getAccentColor(self.theme.preset, self.button.Name)
	TweenService:Create(self.button, tween, {
		BackgroundColor3 = color,
	}):Play()
	TweenService:Create(self.button.Outline.UIStroke, tween, {
		Color = color,
		Thickness = if self.disabled
			then 0
			elseif self.selecting then 2
			elseif self._pressing then 2
			elseif self._hovering then 1
			else 0,
	}):Play()
end

return AccentColorButtonStyleState
