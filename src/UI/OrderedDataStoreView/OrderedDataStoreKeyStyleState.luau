local TweenService = game:GetService("TweenService")

local StyleStateHelper = require(script.Parent.Parent.StyleState.StyleStateHelper)

local OrderedDataStoreKeyStyleState = {}
OrderedDataStoreKeyStyleState.__index = OrderedDataStoreKeyStyleState

function OrderedDataStoreKeyStyleState.from(theme, highlightColors, frame)
	local self = setmetatable({
		theme = theme,
		frame = frame,

		_highlightColors = highlightColors,

		selecting = false,
		_disabled = false,
		_hovering = false,

		_connections = {},
	}, OrderedDataStoreKeyStyleState)

	table.insert(
		self._connections,
		frame.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseMovement then
				self._hovering = true
				self:update()
			end
		end)
	)
	table.insert(
		self._connections,
		frame.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseMovement then
				self._hovering = false
				self:update()
			end
		end)
	)

	self:update("instant")
	return self
end

function OrderedDataStoreKeyStyleState:setSelecting(selecting: boolean)
	self.selecting = selecting
	return self
end

function OrderedDataStoreKeyStyleState:setDisabled(disabled: boolean)
	self._disabled = disabled
	self.frame.Key.Active = not disabled
	self.frame.Value.Active = not disabled
	return self
end

function OrderedDataStoreKeyStyleState:setHighlightColors(colors)
	self._highlightColors = colors
	return self
end

function OrderedDataStoreKeyStyleState:update(_)
	-- Since there can be 100s at at time, no tween

	if self._disabled then
		self.frame.BackgroundColor3 = self._highlightColors.background
		self.frame.Key.TextColor3 = self.theme.colors.disabledText
		self.frame.Value.TextColor3 = self.theme.colors.disabledText
	else
		self.frame.BackgroundColor3 = if self.selecting
			then self._highlightColors.selectBackground
			elseif self._hovering then self._highlightColors.hoverBackground
			else self._highlightColors.background
		self.frame.Key.TextColor3 = self._highlightColors.key
		self.frame.Value.TextColor3 = self._highlightColors.number
	end
end

function OrderedDataStoreKeyStyleState:destroy(completely: boolean)
	if completely then
		self.frame:Destroy()
	end
	for _, connection in self._connections do
		connection:Disconnect()
	end
end

return OrderedDataStoreKeyStyleState
