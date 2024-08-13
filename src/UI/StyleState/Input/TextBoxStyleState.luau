local TweenService = game:GetService("TweenService")

local PopupHelper = require(script.Parent.Parent.Parent.PopupHelper)
local StyleStateHelper = require(script.Parent.Parent.StyleStateHelper)

local TextBoxStyleState = {}
TextBoxStyleState.__index = TextBoxStyleState

function TextBoxStyleState.from(theme: any, textBox: TextBox & { UIStroke: UIStroke })
	local self = setmetatable({
		textBox = textBox,
		stroke = textBox.UIStroke,
		theme = theme,
		
		overridenBackgroundColor3 = nil :: Color3?,
		overriddenTextColor = nil :: Color3?,
		
		disabled = false,
		_pressing = false,
		_hovering = false,
		
		error = nil :: string?,
		_errorPopup = nil :: typeof(script.ErrorPopup)?,
	}, TextBoxStyleState)
	
	self._errorChanged = Instance.new("BindableEvent")
	self.errorChanged = self._errorChanged.Event
	
	self._beganConnection = textBox.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			self._pressing = true
			self:update()

			local connection = nil
			connection = input:GetPropertyChangedSignal("UserInputState"):Connect(function()
				if input.UserInputState == Enum.UserInputState.End or input.UserInputState == Enum.UserInputState.Cancel then
					self._pressing = false
					connection:Disconnect()
					self:update()
				end
			end)
		elseif input.UserInputType == Enum.UserInputType.MouseMovement then
			self._hovering = true
			self:update()
		end
	end)

	self._endedConnection = textBox.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement then
			self._hovering = false
			self:update()
		end
	end)
	
	self._focusedConnection = textBox.Focused:Connect(function()
		self:update()
		
		if self.error then
			if not self._errorPopup then
				self:_makeErrorPopup()
			end
		end
	end)
	
	self._focusLostConnection = textBox.FocusLost:Connect(function()
		self:update()
		if self._errorPopup then
			self:_deleteErrorPopup()
		end
	end)

	self:update("instant")
	return self
end

function TextBoxStyleState:update(speed: StyleStateHelper.TransitionSpeed?)
	local state = 
		if self.disabled then "disable"
		elseif self.textBox:IsFocused() then "select"
		elseif self._pressing then "press"
		elseif self._hovering then "hover"
		else "default"

	local tweenInfo = StyleStateHelper.getTweenInfoForSpeed(speed)
	
	StyleStateHelper.tween(self.textBox, tweenInfo, {
		BackgroundColor3 = self.overridenBackgroundColor or self.theme.colors.button.input.body[state],
		TextColor3 = self.overriddenTextColor or self.theme.colors.button.input.text[state],
		PlaceholderColor3 = self.theme.colors.button.input.text.default:lerp(self.theme.colors.button.input.body.default, 0.5),
	})
	StyleStateHelper.tween(self.stroke, tweenInfo, {
		Color =
			if self.error then self.theme.colors.error
			else self.theme.colors.button.input.outline[state]
	})
end

function TextBoxStyleState:setDisabled(disabled: boolean)
	self.disabled = disabled
	self.textBox.TextEditable = not disabled
	
	return self
end

function TextBoxStyleState:overrideTextColor(color: Color3)
	self.overriddenTextColor = color
	return self
end

function TextBoxStyleState:overrideBackgroundColor(color: Color3)
	self.overridenBackgroundColor = color
	return self
end

function TextBoxStyleState:_deleteErrorPopup()
	if self._errorPopup then
		self._errorPopup:destroy(true)
		self._errorPopup = nil
	end
end

function TextBoxStyleState:_makeErrorPopup()
	if self.error then
		local popupFrame = script.ErrorPopup:Clone()
		popupFrame.Text = self.error
		popupFrame.ZIndex = 100
		popupFrame.Parent = self.textBox:FindFirstAncestorWhichIsA("LayerCollector")
		self._errorPopup = PopupHelper.attach(
			popupFrame,
			self.textBox,
			{
				anchor = Vector2.new(0.5, 1),
				offset = Vector2.new(0, 6),
			}
		)
	end
end

function TextBoxStyleState:setError(err: string?)
	local lastError = self.error
	self.error = err
	
	if lastError ~= err then
		self._errorChanged:Fire(err)
		self:_deleteErrorPopup()
		self:_makeErrorPopup()
	end
	
	return self
end

export type GetTextErrorHandler = (string) -> ()
function TextBoxStyleState:getText(_: GetTextErrorHandler): string
	return self.textBox.Text
end

function TextBoxStyleState:destroy(completely: boolean)
	self._beganConnection:Disconnect()
	self._endedConnection:Disconnect()
	self._focusedConnection:Disconnect()
	self._focusLostConnection:Disconnect()
	
	if self._errorPopup then
		self._errorPopup:destroy(true)
	end
	
	if completely then
		self.textBox:Destroy()
	end
end

export type TextBoxStyleState = typeof(TextBoxStyleState.from({} :: any, {} :: any))
return TextBoxStyleState