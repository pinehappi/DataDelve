local TweenService = game:GetService("TweenService")
local StyleStateHelper = require(script.Parent.StyleStateHelper)
local ButtonStyleState = require(script.Parent.ButtonStyleState)

local TabsStyleState = {}
TabsStyleState.__index = TabsStyleState

function TabsStyleState.from(theme, frame: Frame)
	local buttons = {}
	for _, v in frame:GetChildren() do
		if v:IsA("GuiButton") then
			buttons[v.Name] = v
		end
	end

	local self = setmetatable({
		theme = theme,
		frame = frame,

		buttons = buttons,
		buttonStyleStates = {},

		selecting = nil,
		_selectingStyleState = nil,

		selectBar = script.SelectBar:Clone(),
	}, TabsStyleState)

	for _, button in buttons do
		local styleState = ButtonStyleState.from(self.theme, button, {
			style = "dormant",
		})
		self.buttonStyleStates[button.Name] = styleState

		local fakeBar = nil

		button.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseMovement then
				if (not fakeBar) and not styleState.selecting then
					fakeBar = self.selectBar:Clone()
					fakeBar.BackgroundTransparency = 0.75
					fakeBar.Parent = button
				end
			end
		end)

		button.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseMovement then
				if fakeBar then
					fakeBar:Destroy()
					fakeBar = nil
				end
			end
		end)

		button.Activated:Connect(function()
			self:select(button.Name)
		end)
	end

	self._selectingChanged = Instance.new("BindableEvent")
	self.selectingChanged = self._selectingChanged.Event

	self:update("instant")
	return self
end

function TabsStyleState:select(name: string)
	if self.selecting == name then
		return
	end

	local lastSelectedStyleState = self._selectingStyleState
	if lastSelectedStyleState then
		lastSelectedStyleState:setSelecting(false):update()
	end

	local styleState = self.buttonStyleStates[name]
	self.selecting = name
	self._selectingStyleState = styleState

	styleState:setSelecting(true):update()
	self._selectingChanged:Fire(name)

	-- Style select bar
	self.selectBar.BackgroundTransparency = 1
	self.selectBar.Parent = self.buttons[name]
	TweenService:Create(self.selectBar, StyleStateHelper.getTweenInfoForSpeed("fast"), {
		BackgroundTransparency = 0,
	}):Play()
end

function TabsStyleState:update(speed: StyleStateHelper.TransitionSpeed?)
	TweenService:Create(self.selectBar, StyleStateHelper.getTweenInfoForSpeed(speed), {
		BackgroundColor3 = self.theme.colors.mainAccent,
	}):Play()
	for _, button in self.buttonStyleStates do
		button:update(speed)
	end
end

function TabsStyleState:destroy(completely: boolean)
	self.SelectBar:Destroy()
	for _, button in self.buttons do
		button:destroy(completely)
	end
	if completely then
		self.frame:Destroy()
	end
end

return TabsStyleState
