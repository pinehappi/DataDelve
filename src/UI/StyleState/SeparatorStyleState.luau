local TweenService = game:GetService("TweenService")
local StyleStateHelper = require(script.Parent.StyleStateHelper)

local SeparatorStyleState = {}
SeparatorStyleState.__index = SeparatorStyleState

function SeparatorStyleState.from(theme, separator: Frame)
	local self = setmetatable({
		separator = separator,
		theme = theme,
	}, SeparatorStyleState)

	self:update("instant")
	return self
end

-- Convenience function goes through all descendants and returns a table
-- with all frames with Separator in their name as a SeparatorStyleState
function SeparatorStyleState.fromDescendants(theme, ancestor: GuiObject)
	local styleStates = {}
	for _, descendant in ancestor:GetDescendants() do
		if descendant:IsA("Frame") and descendant.Name:find("Separator") then
			table.insert(styleStates, SeparatorStyleState.from(theme, descendant))
		end
	end
	return styleStates
end

function SeparatorStyleState:update(speed: StyleStateHelper.TransitionSpeed)
	TweenService:Create(self.separator, StyleStateHelper.getTweenInfoForSpeed(speed), {
		BackgroundColor3 = self.theme.colors.separator,
	}):Play()
end

function SeparatorStyleState:destroy(completely: boolean)
	if completely then
		self.separator:Destroy()
	end
end

return SeparatorStyleState
