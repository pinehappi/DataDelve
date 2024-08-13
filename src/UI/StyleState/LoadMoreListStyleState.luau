-- Provide a `createItemStyleState(...)` function.
-- Other consumers of the StyleState can then call `:add(...)` which will use the `createItemStyleState` to add a StyleState into the list.
-- `Pages` does this when a new page is loaded.
-- 
-- StyleStates produced from `createItemStyleState` can have method `setSelecting(bool)` to make them
-- eligible for the `setSelectingStyleState` method of this object.

local TweenService = game:GetService("TweenService")
local StyleStateHelper = require(script.Parent.StyleStateHelper)
local ButtonStyleState = require(script.Parent.ButtonStyleState)

local LoadMoreListStyleState = {}
LoadMoreListStyleState.__index = LoadMoreListStyleState

type LoadMoreList = Frame & {
	LoadMore: TextButton,
	LoadMorePadding: GuiObject,
}

type LoadMoreListOptions = {
	createItemStyleState: (parent: LoadMoreListStyleState, ...any) -> StyleStateHelper.StyleState
}

function LoadMoreListStyleState.from(theme, frame: LoadMoreList, options: LoadMoreListOptions)
	local self = setmetatable({
		theme = theme,
		frame = frame,
		
		buttonStyleState = ButtonStyleState.from(theme, frame.LoadMore, {
			style = "secondary"
		}),
		
		itemStyleStates = {},
		selectingStyleState = nil,
		options = options
	}, LoadMoreListStyleState)
	
	return self
end

function LoadMoreListStyleState:add(...)
	local itemStyleState = self.options.createItemStyleState(self, ...)
	table.insert(self.itemStyleStates, itemStyleState)
end

function LoadMoreListStyleState:clear()
	for _, styleState in self.itemStyleStates do
		styleState:destroy(true)
	end
	
	if self.selectingStyleState then
		self.selectingStyleState = nil
	end
	
	self.itemStyleStates = {}
end

function LoadMoreListStyleState:setLoadMoreVisible(visible: boolean)
	self.frame.LoadMorePadding.Visible = visible
	self.frame.LoadMore.Visible = visible
end

function LoadMoreListStyleState:setSelectingStyleState(styleState)
	if self.selectingStyleState then
		self.selectingStyleState:setSelecting(false):update()
	end
	self.selectingStyleState = styleState
	
	if styleState then
		styleState:setSelecting(true):update()
	end
end

function LoadMoreListStyleState:update(speed: StyleStateHelper.TransitionSpeed?)
	for _, styleState in self.itemStyleStates do
		styleState:update(speed)
	end
	self.buttonStyleState:update(speed)
end

function LoadMoreListStyleState:destroy(completely: boolean)
	self:clear()
	if completely then
		self.frame:Destroy()
	end
end

return LoadMoreListStyleState