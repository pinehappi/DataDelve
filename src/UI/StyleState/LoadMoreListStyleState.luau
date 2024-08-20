-- Provide a `createItemStyleState(...)` function.
-- Other consumers of the StyleState can then call `:add(...)` which will use the `createItemStyleState` to add a StyleState into the list.
-- `Pages` does this when a new page is loaded.
--
-- StyleStates produced from `createItemStyleState` can have method `setSelecting(bool)` to make them
-- eligible for the `setSelectingStyleState` method of this object
--
-- `createItemStyleState` can optionally return a second return which is a key.
-- You can then access the StyleState created using loadMoreListStyleState.itemStyleStates[key]
-- When multiple items with the same key are added, a warning will be emitted.
-- If no key is specified, the item will be inserted in the array section of itemStyleStates sequentially.

local StyleStateHelper = require(script.Parent.StyleStateHelper)
local ButtonStyleState = require(script.Parent.ButtonStyleState)

local LoadMoreListStyleState = {}
LoadMoreListStyleState.__index = LoadMoreListStyleState

type LoadMoreList = Frame & {
	LoadMore: TextButton,
	LoadMorePadding: GuiObject,
}

type LoadMoreListOptions = {
	createItemStyleState: (parent: LoadMoreListStyleState, ...any) -> (StyleStateHelper.StyleState, unknown?),
}

function LoadMoreListStyleState.from(theme, frame: LoadMoreList, options: LoadMoreListOptions)
	local self = setmetatable({
		theme = theme,
		frame = frame,

		buttonStyleState = ButtonStyleState.from(theme, frame.LoadMore, {
			style = "secondary",
		}),

		itemStyleStates = {},
		selectingStyleState = nil,
		selectingId = 0,
		options = options,
	}, LoadMoreListStyleState)

	return self
end

function LoadMoreListStyleState:add(...)
	local itemStyleState, key = self.options.createItemStyleState(self, ...)
	if key then
		if self.itemStyleStates[key] then
			warn(`Duplicate key ({self.frame:GetFullName()}): {key}`)
		end
		self.itemStyleStates[key] = itemStyleState
	else
		table.insert(self.itemStyleStates, itemStyleState)
	end
end

function LoadMoreListStyleState:tryRemove(key: string?): boolean
	local styleState = self.itemStyleStates[key]
	if styleState then
		styleState:destroy(true)
		self.itemStyleStates[key] = nil
	end
end

function LoadMoreListStyleState:isEmpty(): boolean
	return not next(self.itemStyleStates)
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

-- Returns a function that lets you reset the selection (only if the styleState was not nil)
function LoadMoreListStyleState:setSelectingStyleState(styleState)
	if self.selectingStyleState then
		self.selectingStyleState:setSelecting(false):update()
	end
	self.selectingStyleState = styleState

	if styleState then
		styleState:setSelecting(true):update()

		self.selectingId += 1
		local id = self.selectingId
		return function()
			if self.selectingStyleState == styleState and self.selectingId == id then
				self:setSelectingStyleState(nil)
			end
		end
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
