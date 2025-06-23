local TweenService = game:GetService("TweenService")
local StyleStateHelper = require(script.Parent.StyleStateHelper)

local BackgroundStyleState = {}
BackgroundStyleState.__index = BackgroundStyleState

type BackgroundStyleStateOptions = {
	style: "default" | "popup" | "image" | "header",
}
function BackgroundStyleState.from(theme, background: Frame, options: BackgroundStyleStateOptions?)
	options = options or {} :: BackgroundStyleStateOptions
	assert(options)

	options.style = options.style or "default"

	local self = setmetatable({
		background = background,
		stroke = background:FindFirstChildOfClass("UIStroke"),
		theme = theme,

		style = options.style,
	}, BackgroundStyleState)

	self:update("instant")
	return self
end

function BackgroundStyleState:update(speed: StyleStateHelper.TransitionSpeed)
	local tweenInfo = StyleStateHelper.getTweenInfoForSpeed(speed)
	local background = if self.style == "default"
		then "background"
		elseif self.style == "image" then "imageBackground"
		elseif self.style == "header" then "headerBackground"
		else "popupBackground"
	local outline = if self.style == "default"
		then "backgroundOutline"
		elseif self.style == "image" then "imageBackgroundOutline"
		elseif self.style == "header" then "backgroundOutline"
		else "popupBackgroundOutline"

	StyleStateHelper.tween(self.background, tweenInfo, {
		BackgroundColor3 = self.theme.colors[background],
	})
	if self.stroke then
		StyleStateHelper.tween(self.stroke, tweenInfo, {
			Color = self.theme.colors[outline],
		})
	end
end

function BackgroundStyleState:destroy(completely: boolean)
	if completely then
		self.background:Destroy()
	end
end

return BackgroundStyleState
