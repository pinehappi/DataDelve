-- Utility to send alerts/toasts
-- Layout manually calculated (no AutomaticSize).

local TweenService = game:GetService("TweenService")
local TextService = game:GetService("TextService")

local StyleState = script.Parent.StyleState
local PopupHelper = require(script.Parent.PopupHelper)

local StyleStateWrapper = require(StyleState.StyleStateWrapper)
local BackgroundStyleState = require(StyleState.BackgroundStyleState)
local ButtonStyleState = require(StyleState.ButtonStyleState)
local LabelStyleState = require(StyleState.LabelStyleState)

local FrameTemplate = script.FrameTemplate
local TextLabelTemplate = script.TextLabelTemplate
local IconTemplate = script.IconTemplate
local DropShadowTemplate = script.DropShadowTemplate
local CloseButtonTemplate = script.CloseButtonTemplate

local UIMessages = {}
UIMessages.__index = UIMessages

UIMessages.ERROR_ICON = "rbxassetid://18829614103"
UIMessages.WARNING_ICON = "rbxassetid://18829786614"
UIMessages.SUCCESS_ICON = "rbxassetid://18829818279"

-- Toasts

local MIN_TOAST_X = 100
local MIN_TOAST_Y = 0
local TOAST_PADDING_X = 8
local TOAST_PADDING_Y = 8
local TOAST_PADDING_INBETWEEN = 8
local WINDOW_PADDING_X = 12
local WINDOW_PADDING_Y = 12

function UIMessages.new(theme)
	local gui = script.MessagesContainer:Clone()
	local self = setmetatable({
		theme = theme,
		
		parent = nil,
		gui = gui,
		zIndex = gui.ZIndex,
		
		_toastQueue = {} :: {ToastQueueElement},
	}, UIMessages)
	
	return self
end

function UIMessages:setParent(parent: Instance)
	self.gui.Parent = parent
	self.parent = parent
end

function UIMessages:_getMaxToastWidth(): number
	return math.clamp(math.floor(self.gui.AbsoluteSize.X * 0.4), 200, 500)
end

local function attachDropShadow(object: GuiObject)
	local dropShadow = DropShadowTemplate:Clone()
	dropShadow.ZIndex = object.ZIndex - 1
	
	local function update()
		dropShadow.Position = UDim2.fromOffset(object.AbsolutePosition.X - 15, object.AbsolutePosition.Y - 9)
		dropShadow.Size = UDim2.fromOffset(object.AbsoluteSize.X + 30, object.AbsoluteSize.Y + 26)
	end
	
	update()
	object:GetPropertyChangedSignal("AbsoluteSize"):Connect(update)
	object:GetPropertyChangedSignal("AbsolutePosition"):Connect(update)
	object.Destroying:Connect(function()
		dropShadow:Destroy()
	end)
	
	dropShadow.Parent = object.Parent
end

type ToastQueueElement = {
	frame: typeof(FrameTemplate),
	position: UDim2,
}

local appearTweenInfo = TweenInfo.new(0.1, Enum.EasingStyle.Quart)
local disappearTweenInfo = TweenInfo.new(0.15, Enum.EasingStyle.Sine)

function UIMessages:_pushToastElements(amount: number, tweenInfo: TweenInfo, after: number?)
	after = after or 0
	for i, element: ToastQueueElement in self._toastQueue do
		if i <= after then continue end
		
		element.position -= UDim2.fromOffset(0, amount)
		local tween = TweenService:Create(element.frame, tweenInfo, {
			Position = element.position
		})
		tween:Play()
	end
end

function UIMessages:_removeToastElementAt(index: number)
	local element: ToastQueueElement = self._toastQueue[index]
	local disappearTween = TweenService:Create(element.frame, disappearTweenInfo, {
		Position = element.position + UDim2.fromOffset(element.frame.AbsoluteSize.X + WINDOW_PADDING_X + 4, 0)
	})
	disappearTween:Play()
	
	self:_pushToastElements(-element.frame.AbsoluteSize.Y - TOAST_PADDING_INBETWEEN, disappearTweenInfo, index)
	table.remove(self._toastQueue, index)
	
	disappearTween.Completed:Wait()
	element.frame:Destroy()
end

export type ToastOptions = {
	text: string,
	icon: string?,
	iconColor: Color3?,
	duration: number?,
}
function UIMessages:toast(options: ToastOptions?)
	options = options or {}
	
	local frame = FrameTemplate:Clone()
	frame.BackgroundColor3 = self.theme.colors.message.background
	frame.UIStroke.Color = self.theme.colors.message.outline
	
	local boundsX, boundsY = MIN_TOAST_X, MIN_TOAST_Y
	
	local function updateBounds(newX: number, newY: number)
		boundsX, boundsY = math.max(boundsX, newX), math.max(boundsY, newY)
	end
	
	local icon: ImageLabel?
	if options.icon then
		icon = IconTemplate:Clone()
		icon.Image = options.icon
		icon.ImageColor3 = options.iconColor or self.theme.colors.message.text
		
		updateBounds(icon.AbsoluteSize.X, icon.AbsoluteSize.Y)
	end
	
	local getTextBoundParams = Instance.new("GetTextBoundsParams")
	getTextBoundParams.Text = options.text
	getTextBoundParams.Font = TextLabelTemplate.FontFace
	getTextBoundParams.Size = TextLabelTemplate.TextSize
	getTextBoundParams.Width = self:_getMaxToastWidth()
	getTextBoundParams.RichText = true
	
	local textBounds = TextService:GetTextBoundsAsync(getTextBoundParams)
	
	updateBounds(textBounds.X, textBounds.Y)
	
	local textLabel = TextLabelTemplate:Clone()
	textLabel.TextColor3 = self.theme.colors.message.text
	textLabel.Size = UDim2.fromOffset(math.floor(textBounds.X + 1), math.floor(textBounds.Y + 1))
	textLabel.Text = options.text
	
	local closeButton = CloseButtonTemplate:Clone()
	closeButton.ImageLabel.ImageColor3 = self.theme.colors.message.text
	closeButton.Visible = false
	
	-- Placing
	
	local placeX = TOAST_PADDING_X
	if icon then
		icon.Position = UDim2.fromOffset(placeX, math.floor(boundsY/2 - icon.AbsoluteSize.Y/2) + TOAST_PADDING_Y)
		icon.Parent = frame
		placeX += 10 + icon.AbsoluteSize.X
		boundsX += 10 + icon.AbsoluteSize.X
	end
	
	textLabel.Position = UDim2.fromOffset(placeX, math.floor(boundsY/2 - textBounds.Y/2) + TOAST_PADDING_Y)
	textLabel.Parent = frame
	
	closeButton.AnchorPoint = Vector2.new(1, 0.5)
	closeButton.Position = UDim2.new(1, 0, 0.5, 0)
	closeButton.Size += UDim2.fromOffset(TOAST_PADDING_X, 0)
	closeButton.Parent = frame
	
	frame.Size = UDim2.fromOffset(boundsX + 2*TOAST_PADDING_X + CloseButtonTemplate.AbsoluteSize.X, boundsY + 2*TOAST_PADDING_Y)
	frame.Position = UDim2.new(1, -WINDOW_PADDING_X, 1, boundsY + 2*TOAST_PADDING_Y + 4)
	frame.Parent = self.gui
	attachDropShadow(frame)
	
	-- Animate in
	self:_pushToastElements(frame.AbsoluteSize.Y + TOAST_PADDING_INBETWEEN, appearTweenInfo)
	
	local element: ToastQueueElement = {
		frame = frame,
		position = UDim2.new(1, -WINDOW_PADDING_X, 1, -WINDOW_PADDING_Y),
	}
	
	local appearTween = TweenService:Create(frame, appearTweenInfo, {
		Position = element.position
	})
	
	appearTween:Play()
	table.insert(self._toastQueue, 1, element)
	
	-- Disappearing
	
	local function disappear()
		local index = table.find(self._toastQueue, element)
		if index then
			self:_removeToastElementAt(index)
		end
	end
	
	frame.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement then
			closeButton.Visible = true
		end
	end)
	frame.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement then
			closeButton.Visible = false
		end
	end)
	
	closeButton.Activated:Connect(disappear)
	task.delay(options.duration or 5, disappear)
end

function UIMessages:success(message: string, options: AlertOptions)
	self:toast({
		icon = UIMessages.SUCCESS_ICON,
		iconColor = self.theme.colors.success,
		text = message,
	})
end

function UIMessages:error(message: string, options: AlertOptions)
	self:toast({
		icon = UIMessages.ERROR_ICON,
		iconColor = self.theme.colors.error,
		text = message,
	})
end

function UIMessages:warn(message: string, options: AlertOptions)
	self:toast({
		icon = UIMessages.WARNING_ICON,
		iconColor = self.theme.colors.warn,
		text = message,
	})
end

-- Error alerts

function UIMessages:errorAlert(message: string)
	local frame = script.ErrorAlert:Clone()
	local wrapper = StyleStateWrapper.new(self.theme, {
		background = BackgroundStyleState.from(self.theme, frame, {
			style = "popup",
		}),
		message = LabelStyleState.from(self.theme, frame.Content.Message),
		ok = ButtonStyleState.from(self.theme, frame.Content.Ok, {
			style = "secondary",
		}),
		icon = LabelStyleState.from(self.theme, frame.Icon, {
			style = "error",
		})
	})
	
	wrapper.styleStates.message.label.Text = message
	
	local modal = PopupHelper.modal(frame, self.parent)
	local lockEvent = Instance.new("BindableEvent")
	
	modal.cancelled:Once(function()
		lockEvent:Fire()
	end)
	
	wrapper.styleStates.ok.button.Activated:Connect(function()
		lockEvent:Fire()
	end)
	
	lockEvent.Event:Wait()
	
	modal:destroy()
	frame:Destroy()
end

-- This will choose to create a toast or alert depending on the severity of the error.
local alertableErrors = {
	["103"] = true, ["104"] = true, ["105"] = true,
	["301"] = true, ["302"] = true, ["303"] = true, ["304"] = true, ["305"] = true, ["306"] = true,
	["401"] = true, ["402"] = true, ["403"] = true, ["404"] = true,
	["501"] = true, ["502"] = true, ["503"] = true, ["504"] = true, ["505"] = true, ["509"] = true, ["513"] = true,
	
}
-- TODO: special for 403 API access not enabled
function UIMessages:reportDataStoreError(message: string)
	local code = message:sub(1, 3)
	if alertableErrors[code] then
		self:errorAlert(message)
	else
		self:error(message)
	end
end

export type UIMessages = typeof(UIMessages.new())
return UIMessages