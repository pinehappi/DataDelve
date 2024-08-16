-- TODO: should auto-follow theme when using.createMenu

local TweenService = game:GetService("TweenService")

local StyleStateHelper = require(script.Parent.Parent.StyleStateHelper)
local PopupHelper = require(script.Parent.Parent.Parent.PopupHelper)

local ContextMenuStyleState = {}
ContextMenuStyleState.__index = ContextMenuStyleState

ContextMenuStyleState.SEPARATOR = newproxy()

export type Options = { string | { icon: string, text: string } }
export type ContextMenuOptions = {
	options: Options,
}

-- For convenience
function ContextMenuStyleState.prompt(theme, container: GuiObject, position: Vector2, options: ContextMenuOptions)
	local contextMenu, modal = ContextMenuStyleState.createMenu(theme, container, options)
	contextMenu.frame.Position = UDim2.fromOffset(position.X, position.Y)
	PopupHelper.clamp(contextMenu.frame, container, {
		tryPivot = true,
	})

	local option = contextMenu.selected:Wait()

	modal:destroy()
	contextMenu:destroy(true)

	return option
end

function ContextMenuStyleState.createMenu(theme, container: GuiObject, options: ContextMenuOptions)
	local frame = script.ContextMenu:Clone()
	frame.Parent = container

	local styleState = ContextMenuStyleState.from(theme, frame, options)

	local modal = PopupHelper.modal(frame, container, {
		zIndex = 20,
		passThroughInput = true,
	})
	modal.cancelled:Connect(function()
		styleState:selectOption(nil)
	end)

	return styleState, modal
end

local function optionsHasIcon(options: Options): boolean
	for _, option in options do
		if typeof(option) == "table" then
			return true
		end
	end
	return false
end

function ContextMenuStyleState.from(theme, contextMenu: typeof(script.ContextMenu), options: ContextMenuOptions)
	local self = setmetatable({
		theme = theme,
		frame = contextMenu,
		options = options.options,

		_hasIcons = optionsHasIcon(options.options),

		_buttons = table.create(#options.options),
		_separators = table.create(1),
		_hoveringOption = nil,
	}, ContextMenuStyleState)

	local lastInserted: "option" | "separator" | nil = nil
	for i, option in options.options do
		if option == ContextMenuStyleState.SEPARATOR then
			if lastInserted == "option" then
				local separator = script.Separator:Clone()
				table.insert(self._separators, separator)
				separator.Parent = self.frame

				lastInserted = "separator"
			end
		else
			local icon = ""
			local text = option
			if typeof(option) == "table" then
				text = option.text
				icon = option.icon
			end

			local button = script.Option:Clone()
			button.Name = text
			button.TextLabel.Text = text

			if self._hasIcons then
				button.Icon.Visible = true
				button.Icon.Image = icon

				button.UIPadding.PaddingLeft = UDim.new(0, 3)
			end

			table.insert(self._buttons, button)

			button.InputBegan:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseMovement then
					self._hoveringOption = text
					self:update("veryFast")
				end
			end)
			button.InputEnded:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseMovement then
					if self._hoveringOption == text then
						self._hoveringOption = nil
						self:update("veryFast")
					end
				end
			end)
			button.Activated:Connect(function()
				self:selectOption(text)
			end)

			button.Parent = self.frame

			lastInserted = "option"
		end
	end

	self._selected = Instance.new("BindableEvent")
	self.selected = self._selected.Event

	self:_updateSeparatorSizes()
	contextMenu:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		self:_updateSeparatorSizes()
	end)

	self:update("instant")
	return self
end

-- Can't use scale because AutomaticSize will expand it all the way
function ContextMenuStyleState:_updateSeparatorSizes()
	for _, separator in self._separators do
		separator.Size = UDim2.fromOffset(
			self.frame.AbsoluteSize.X
				- (script.ContextMenu.UIPadding.PaddingLeft.Offset + script.ContextMenu.UIPadding.PaddingRight.Offset),
			1
		)
	end
end

function ContextMenuStyleState:selectOption(option: string?)
	self._selected:Fire(option)
end

function ContextMenuStyleState:update(speed: StyleStateHelper.TransitionSpeed?)
	local tweenInfo = StyleStateHelper.getTweenInfoForSpeed(speed)
	StyleStateHelper.tween(self.frame, tweenInfo, {
		BackgroundColor3 = self.theme.colors.floatingAction.background,
	})
	StyleStateHelper.tween(self.frame.UIStroke, tweenInfo, {
		Color = self.theme.colors.floatingAction.outline,
	})
	for _, separator in self._separators do
		StyleStateHelper.tween(separator, tweenInfo, {
			BackgroundColor3 = self.theme.colors.separator,
		})
	end
	for _, button in self._buttons do
		local hovering = (self._hoveringOption == button.Name)
		StyleStateHelper.tween(button, tweenInfo, {
			BackgroundTransparency = if hovering then self.theme.colors.button.transparent.press else 1,
			BackgroundColor3 = self.theme.colors.mainAccent,
		})
		StyleStateHelper.tween(button.TextLabel, tweenInfo, {
			TextColor3 = self.theme.colors.text,
		})
		if self._hasIcons then
			StyleStateHelper.tween(button.Icon, tweenInfo, {
				ImageColor3 = self.theme.colors.text,
			})
		end
	end
end

-- Assumes ContextMenu is parented directly to the GUI
function ContextMenuStyleState:animate()
	local originalPosition = self.frame.Position
	local originalAnchor = self.frame.AnchorPoint
	local originalParent = self.frame.Parent

	local targetX = self.frame.AbsolutePosition.X - 2
	local targetY = self.frame.AbsolutePosition.Y - 2
	local startY = targetY - 8

	local canvasGroup = Instance.new("CanvasGroup")
	canvasGroup.BackgroundTransparency = 1
	canvasGroup.Size = UDim2.fromOffset(4 + self.frame.AbsoluteSize.X, 4 + self.frame.AbsoluteSize.Y)
	canvasGroup.Position = UDim2.fromOffset(targetX, startY)

	self.frame.Position = UDim2.fromOffset(2, 2)
	self.frame.AnchorPoint = Vector2.new(0, 0)
	self.frame.Parent = canvasGroup
	canvasGroup.ZIndex = self.frame.ZIndex
	canvasGroup.Parent = originalParent

	local start = os.clock()
	while self.frame and self._selected do
		local delta = os.clock() - start
		local a = math.min(delta / 0.1, 1)
		a = TweenService:GetValue(a, Enum.EasingStyle.Cubic, Enum.EasingDirection.Out)

		canvasGroup.Position = UDim2.fromOffset(targetX, startY + a * (targetY - startY))
		canvasGroup.GroupTransparency = 1 - a

		if a >= 1 then
			break
		end

		task.wait()
	end

	if self.frame then
		self.frame.Position = originalPosition
		self.frame.AnchorPoint = originalAnchor
		self.frame.Parent = originalParent
	end

	canvasGroup:Destroy()
end

function ContextMenuStyleState:destroy(completely: boolean)
	self._selected:Destroy()
	self._selected = nil

	for _, button in self._buttons do
		button:Destroy()
	end
	self._buttons = nil

	if completely then
		self.frame:Destroy()
		self.frame = nil
	end
end

return ContextMenuStyleState
