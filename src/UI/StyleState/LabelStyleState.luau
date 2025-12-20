local TweenService = game:GetService("TweenService")
local StyleStateHelper = require(script.Parent.StyleStateHelper)

local LabelStyleState = {}
LabelStyleState.__index = LabelStyleState

export type LabelStyleStateFromOptions = {
	style: "text" | "error" | nil,
	emphasis: "normal" | "light" | nil,
}
function LabelStyleState.from(theme, label: GuiLabel, options: LabelStyleStateFromOptions?)
	options = options or {}
	assert(options)

	local self = setmetatable({
		label = label,
		theme = theme,
		style = options.style or "text",
		emphasis = options.emphasis or "normal",

		overridenColor = nil :: Color3?,
	}, LabelStyleState)

	self:update("instant")
	return self
end

-- Convenience function goes through all descendants and returns a dictionary
-- with all textlabel and imagelabel descendants as LabelStyleStates and the key as the name of the labels.
-- Will error if there are duplicate label names.
function LabelStyleState.fromDescendants(theme, ancestor: GuiObject, options: LabelStyleStateFromOptions?)
	local styleStates = {}
	for _, descendant in ancestor:GetDescendants() do
		if
			(not descendant.Parent:IsA("GuiButton"))
			and (descendant:IsA("TextLabel") or descendant:IsA("ImageLabel"))
			and (not descendant:GetAttribute("ExcludeStyleState"))
		then
			assert(not styleStates[descendant.Name], `Duplicate label name: {descendant:GetFullName()}`)
			styleStates[descendant.Name] = LabelStyleState.from(theme, descendant, options)
		end
	end
	return styleStates
end

function LabelStyleState:update(speed: StyleStateHelper.TransitionSpeed)
	local property = if self.label:IsA("ImageLabel") then "ImageColor3" else "TextColor3"
	local tweenInfo = StyleStateHelper.getTweenInfoForSpeed(speed)
	local color = self.overridenColor
		or self.theme.colors[if self.style == "text" then "text" elseif self.style == "error" then "error" else "text"]

	local property2 = if self.label:IsA("ImageLabel") then "ImageTransparency" else "TextTransparency"
	local transparency = if self.emphasis == "normal" then 0 else 0.1

	StyleStateHelper.tween(self.label, tweenInfo, {
		[property] = color,
		[property2] = transparency,
	})
end

function LabelStyleState:overrideColor(color: Color3)
	self.overridenColor = color
	return self
end

function LabelStyleState:destroy(completely: boolean)
	if completely then
		self.label:Destroy()
	end
end

return LabelStyleState
