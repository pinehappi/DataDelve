--!strict
local TweenService = game:GetService("TweenService")
local StyleStateHelper = require(script.Parent.StyleStateHelper)

local ScrollingFrame = {}
ScrollingFrame.__index = ScrollingFrame

function ScrollingFrame.from(theme, scrollingFrame: ScrollingFrame)
	local self = setmetatable({
		scrollingFrame = scrollingFrame,
		theme = theme,
	}, ScrollingFrame)

	self:update("instant")
	return self
end

function ScrollingFrame:update(speed: StyleStateHelper.TransitionSpeed)
	local tweenInfo = StyleStateHelper.getTweenInfoForSpeed(speed)

	TweenService:Create(self.scrollingFrame, tweenInfo, {
		ScrollBarImageColor3 = (self :: any).theme.colors.scrollbar,
	}):Play()
end

function ScrollingFrame:destroy(completely: boolean)
	if completely then
		self.scrollingFrame:Destroy()
	end
end

return ScrollingFrame
