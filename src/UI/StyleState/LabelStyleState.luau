local TweenService = game:GetService("TweenService")
local StyleStateHelper = require(script.Parent.StyleStateHelper)

local LabelStyleState = {}
LabelStyleState.__index = LabelStyleState

export type LabelStyleStateFromOptions = {
	style: "text" | "error" | nil
}
function LabelStyleState.from(theme, label: GuiLabel, options: LabelStyleStateFromOptions?)
	options = options or {}
	
	local self = setmetatable({
		label = label,
		theme = theme,
		style = options.style or "text",
	}, LabelStyleState)
	
	self:update("instant")
	return self
end

-- Convenience function goes through all descendants and returns a table
-- with all textlabel and imagelabel descendants as LabelStyleStates
function LabelStyleState.fromDescendants(theme, ancestor: GuiObject, options: LabelStyleStateFromOptions?)
	local styleStates = {}
	for _, descendant in ancestor:GetDescendants() do
		if descendant:IsA("TextLabel") or descendant:IsA("ImageLabel") then
			table.insert(styleStates, LabelStyleState.from(theme, descendant, options))
		end
	end
	return styleStates
end

function LabelStyleState:update(speed: StyleStateHelper.TransitionSpeed)
	local property = if self.label:IsA("TextLabel") then "TextColor3" else "ImageColor3"
	local tweenInfo = StyleStateHelper.getTweenInfoForSpeed(speed)
	local color =
		if self.style == "text" then "text"
		elseif self.style == "error" then "error"
		else "text"
	
	TweenService:Create(self.label, tweenInfo, {
		[property] = self.theme.colors[color]
	}):Play()
end

function LabelStyleState:destroy(completely: boolean)
	if completely then
		self.label:Destroy()
	end
end

return LabelStyleState