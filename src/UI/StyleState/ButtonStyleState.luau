local StyleStateHelper = require(script.Parent.StyleStateHelper)

local ButtonStyleState = {}
ButtonStyleState.__index = ButtonStyleState

export type ButtonStyle = "primary" | "secondary" | "transparent" | "dormant" | "input"
export type ButtonStyleStateFromOptions = {
	style: ButtonStyle | nil,
}
function ButtonStyleState.from(theme, button: TextButton, options: ButtonStyleStateFromOptions?)
	options = options or {}

	local self = setmetatable({
		theme = theme,
		button = button,
		style = options.style or "secondary",

		disabled = false,
		selecting = false,
		_pressing = false,
		_hovering = false,

		disabledMessage = nil,
	}, ButtonStyleState)

	-- These will have their colors updated based on the state
	self._textLabels = {}
	self._imageLabels = {}
	self._strokes = {}
	self:_findStyleableChildren()

	self._beganConnection = button.InputBegan:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.Touch
			or input.UserInputType == Enum.UserInputType.MouseButton1
		then
			self._pressing = true
			self:update("veryFast")

			local connection = nil
			connection = input:GetPropertyChangedSignal("UserInputState"):Connect(function()
				if
					input.UserInputState == Enum.UserInputState.End
					or input.UserInputState == Enum.UserInputState.Cancel
				then
					self._pressing = false
					connection:Disconnect()
					self:update("veryFast")
				end
			end)
		elseif input.UserInputType == Enum.UserInputType.MouseMovement then
			self._hovering = true
			self:update(if self.style == "transparent" then "superDuperFast" else nil)
		end
	end)

	self._endedConnection = button.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement then
			self._hovering = false
			self:update(if self.style == "transparent" then "superDuperFast" else nil)
		end
	end)

	self:update("instant")
	return self
end

function ButtonStyleState:update(speed: StyleStateHelper.TransitionSpeed?)
	local tweenInfo = StyleStateHelper.getTweenInfoForSpeed(speed)
	local state = if self.disabled
		then "disable"
		elseif self.selecting then "select"
		elseif self._pressing then "press"
		elseif self._hovering then "hover"
		else "default"

	if self.style == "transparent" then
		StyleStateHelper.tween(self.button, tweenInfo, {
			BackgroundColor3 = self.theme.colors.button.transparent.baseColor,
			BackgroundTransparency = self.theme.colors.button.transparent[state],
		})

		local color = if self.disabled then self.theme.colors.disabledText else self.theme.colors.text
		self:_updateChildren(tweenInfo, {
			textLabels = color,
			imageLabels = color,
		})
	elseif self.style == "dormant" then
		self:_updateChildren(tweenInfo, {
			textLabels = self.theme.colors.button.dormant[state],
			imageLabels = self.theme.colors.button.dormant[state],
		})
	else
		self:_updateChildren(tweenInfo, {
			body = self.theme.colors.button[self.style].body[state],
			textLabels = self.theme.colors.button[self.style].text[state],
			imageLabels = self.theme.colors.button[self.style].text[state],
			strokes = self.theme.colors.button[self.style].outline[state],
		})
	end
end

function ButtonStyleState:setSelecting(selecting: boolean)
	self.selecting = selecting
	return self
end

function ButtonStyleState:setDisabled(disabled: boolean, disabledMessage: string?)
	self.disabled = disabled
	self.disabledMessage = disabledMessage
	self.button.Active = not disabled

	return self
end

function ButtonStyleState:destroy(completely: boolean)
	self._beganConnection:Disconnect()
	self._endedConnection:Disconnect()

	if completely then
		self.button:Destroy()
	end
end

-- Private
function ButtonStyleState:_findStyleableChildren()
	for _, label in self.button:GetDescendants() do
		if label:IsA("TextLabel") and (not label:GetAttribute("Exclude")) then
			table.insert(self._textLabels, label)
		end
	end
	for _, label in self.button:GetDescendants() do
		if label:IsA("ImageLabel") and (not label:GetAttribute("Exclude")) then
			table.insert(self._imageLabels, label)
		end
	end
	for _, stroke in self.button:GetDescendants() do
		if stroke:IsA("UIStroke") and (not stroke:GetAttribute("Exclude")) then
			table.insert(self._strokes, stroke)
		end
	end
end

function ButtonStyleState:_updateChildren(
	tweenInfo: TweenInfo,
	colors: {
		body: Color3?,
		textLabels: Color3?,
		imageLabels: Color3?,
		strokes: Color3?,
	}
)
	if colors.body then
		if self.button.BackgroundColor3 ~= colors.body then
			StyleStateHelper.tween(self.button, tweenInfo, { BackgroundColor3 = colors.body })
		end
	end

	if colors.textLabels then
		if self.button:IsA("TextButton") and self.button.TextTransparency < 1 then
			StyleStateHelper.tween(self.button, tweenInfo, { TextColor3 = colors.textLabels })
		elseif self.button:IsA("ImageButton") and self.button.ImageTransparency < 1 then
			StyleStateHelper.tween(self.button, tweenInfo, { ImageColor3 = colors.textLabels })
		end

		for _, label in self._textLabels do
			if label.TextColor3 ~= colors.textLabels then
				StyleStateHelper.tween(label, tweenInfo, { TextColor3 = colors.textLabels })
			end
		end
	end

	if colors.imageLabels then
		for _, label in self._imageLabels do
			if label.ImageColor3 ~= colors.imageLabels then
				StyleStateHelper.tween(label, tweenInfo, { ImageColor3 = colors.imageLabels })
			end
		end
	end

	if colors.strokes then
		for _, stroke in self._strokes do
			if stroke.Color ~= colors.strokes then
				StyleStateHelper.tween(stroke, tweenInfo, { Color = colors.strokes })
			end
		end
	end
end

return ButtonStyleState
