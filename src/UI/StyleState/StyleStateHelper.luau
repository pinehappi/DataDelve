export type TransitionSpeed = "fast" | "slow" | "instant" | "veryFast" | "superDuperFast" | nil
export type StyleState = {
	from: (theme: any, object: GuiObject, ...any) -> StyleState,

	update: (StyleState, TransitionSpeed) -> (),
	destroy: (StyleState, completely: boolean?) -> (),
}

local TweenService = game:GetService("TweenService")

local StyleStateHelper = {}

StyleStateHelper.superDuperFastTween = TweenInfo.new(0.05, Enum.EasingStyle.Sine)
StyleStateHelper.veryFastTween = TweenInfo.new(0.2, Enum.EasingStyle.Quad)
StyleStateHelper.fastTween = TweenInfo.new(0.35, Enum.EasingStyle.Sine)
StyleStateHelper.slowTween = TweenInfo.new(0.5, Enum.EasingStyle.Quad)
StyleStateHelper.instantTween = TweenInfo.new(0, Enum.EasingStyle.Linear)

function StyleStateHelper.getTweenInfoForSpeed(speed: TransitionSpeed)
	local tweenInfo = StyleStateHelper.fastTween
	if speed == "slow" then
		tweenInfo = StyleStateHelper.slowTween
	elseif speed == "instant" then
		tweenInfo = StyleStateHelper.instantTween
	elseif speed == "veryFast" then
		tweenInfo = StyleStateHelper.veryFastTween
	elseif speed == "superDuperFast" then
		tweenInfo = StyleStateHelper.superDuperFastTween
	end

	return tweenInfo
end

-- Updates a table that contains style states or more tables that contain style states
type StyleStateTable = {
	[string]: StyleState | StyleStateTable,
}
function StyleStateHelper.update(t: StyleStateTable, speed: TransitionSpeed)
	for _, styleState in t do
		if styleState.update then
			styleState:update(speed)
		else
			StyleStateHelper.update(styleState)
		end
	end
end

function StyleStateHelper.destroy(t: StyleStateTable, completely: boolean?)
	for _, styleState in t do
		if styleState.update then
			styleState:destroy(completely)
		else
			StyleStateHelper.destroy(styleState)
		end
	end
end

-- TODO: handle race conditions
function StyleStateHelper.tween(object: Instance, info: TweenInfo, props: { [string]: unknown })
	if info.Time == 0 then
		for prop, val in props do
			object[prop] = val
		end
	else
		TweenService:Create(object, info, props):Play()
	end
end

return StyleStateHelper
