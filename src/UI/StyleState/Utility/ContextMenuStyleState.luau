-- TODO: should auto-follow theme when using.createMenu

local TweenService = game:GetService("TweenService")

local StyleStateHelper = require(script.Parent.Parent.StyleStateHelper)
local PopupHelper = require(script.Parent.Parent.Parent.PopupHelper)

local TRY_CLOSE_SUBMENU_DELAY = 0.275

local ContextMenuStyleState = {}
ContextMenuStyleState.__index = ContextMenuStyleState

ContextMenuStyleState.SEPARATOR = newproxy()

export type Option = | string | { icon: string, text: string, hotkey: string? } | { icon: string?, options: { Option } }

export type ContextMenuOptions = {
	options: { Option },
	submenuDirection: "left" | "right" | nil, -- default: right
	passThroughInput: boolean?,
}

-- For convenience
function ContextMenuStyleState.prompt(theme, container: GuiBase2d, position: Vector2, options: ContextMenuOptions)
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

function ContextMenuStyleState.createMenu(theme, container: GuiBase2d, options: ContextMenuOptions)
	local frame = script.ContextMenu:Clone()
	frame.Parent = container

	local styleState = ContextMenuStyleState.from(theme, frame, options)

	local modal = PopupHelper.modal(frame, container, {
		zIndex = 20,
		passThroughInput = if options.passThroughInput == nil then false else options.passThroughInput,
		scrimTransparency = if options.passThroughInput or (options.passThroughInput == nil) then 0.8 else 0,
	})
	modal.cancelled:Connect(function()
		styleState:selectOption(nil)
	end)

	return styleState, modal
end

local function optionsHasIcon(options: Options): boolean
	for _, option in options do
		if typeof(option) == "table" and option.icon then
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
		submenuDirection = options.submenuDirection,

		_hasIcons = optionsHasIcon(options.options),
		_subContextMenu = nil,

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
			local hotkey = nil
			local suboptions: { Option }? = nil
			if typeof(option) == "table" then
				text = option.text
				icon = option.icon
				hotkey = option.hotkey
				suboptions = option.options
			end

			local button = script.Option:Clone()
			button.Name = text
			button.TextLabel.Text = text

			if self._hasIcons then
				button.Icon.Visible = true
				button.Icon.Image = icon or ""

				button.UIPadding.PaddingLeft = UDim.new(0, 3)
			end

			if hotkey then
				button.Hotkey.Visible = true
				button.Hotkey.Text = hotkey
			else
				button.Hotkey.Visible = false
			end

			if suboptions then
				script.Arrow:Clone().Parent = button
			end

			table.insert(self._buttons, button)

			button.InputBegan:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseMovement then
					self._hoveringOption = text
					self:update("veryFast")

					if
						suboptions
						and (
							(self._subContextMenu and self._subContextMenu.options ~= suboptions)
							or not self._subContextMenu
						)
					then
						self:_openSub(button, text, suboptions)
					end
				end
			end)

			button.InputEnded:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseMovement then
					if suboptions and self._subContextMenu and self._subContextMenu.options == suboptions then
						task.delay(TRY_CLOSE_SUBMENU_DELAY, function()
							if suboptions and self._subContextMenu and self._subContextMenu.options == suboptions then
								self:_tryCloseSub(button, text, input.Position)
							end
						end)
					else
						if self._hoveringOption == text then
							self._hoveringOption = nil
							self:update("veryFast")
						end
					end
				end
			end)

			if not suboptions then
				button.Activated:Connect(function()
					self:selectOption(text)
				end)
			end

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

-- open sub menu
function ContextMenuStyleState:_openSub(button: GuiObject, buttonText: string, options: { Option })
	self:_closeSub()

	local subframe = script.ContextMenu:Clone()
	subframe.Parent = self.frame.Parent
	subframe.ZIndex = self.frame.ZIndex
	subframe.Position = UDim2.fromOffset(button.AbsolutePosition.X, button.AbsolutePosition.Y)
	if self.submenuDirection == "left" then
		subframe.AnchorPoint = Vector2.new(1, 0)
	else
		subframe.Position += UDim2.fromOffset(button.AbsoluteSize.X, 0)
	end

	subframe.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement then
			task.delay(TRY_CLOSE_SUBMENU_DELAY, function()
				if self._subContextMenu and self._subContextMenu.frame == subframe then
					self:_tryCloseSub(button, buttonText, input.Position)
				end
			end)
		end
	end)

	self._subContextMenu = ContextMenuStyleState.from(self.theme, subframe, {
		options = options,
	})

	self._subContextMenu.selected:Connect(function(option)
		if typeof(option) == "table" then
			table.insert(option, 1, buttonText)
		else
			option = { buttonText, option }
		end

		self:selectOption(option)
	end)

	if self.submenuDirection == "left" then
		self._subContextMenu:animate(-16, 0)
	else
		self._subContextMenu:animate(16, 0)
	end
end

function ContextMenuStyleState:_closeSub()
	if self._subContextMenu then
		self._subContextMenu:destroy(true)
		self._subContextMenu = nil
	end
end

-- try to close submenu if mouse is not in safe zone
-- `button` parameter is the button the submenu belongs to
function ContextMenuStyleState:_tryCloseSub(button: TextButton, buttonText: string, position: Vector2)
	if self._subContextMenu then
		local shouldStayOpen = false

		if
			position.X > self._subContextMenu.frame.AbsolutePosition.X
			and position.X < self._subContextMenu.frame.AbsolutePosition.X + self._subContextMenu.frame.AbsoluteSize.X
			and position.Y > self._subContextMenu.frame.AbsolutePosition.Y
			and position.Y
				< self._subContextMenu.frame.AbsolutePosition.Y + self._subContextMenu.frame.AbsoluteSize.Y
		then
			shouldStayOpen = true
		end

		if not shouldStayOpen then
			if
				position.X > button.AbsolutePosition.X - 1
				and position.X < button.AbsolutePosition.X + button.AbsoluteSize.X + 1
				and position.Y > button.AbsolutePosition.Y
				and position.Y < button.AbsolutePosition.Y + button.AbsoluteSize.Y
			then
				shouldStayOpen = true
			end
		end

		if not shouldStayOpen then
			self:_closeSub()

			if self._hoveringOption == buttonText then
				self._hoveringOption = nil
				self:update("veryFast")
			end
		end
	end
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

-- `option` could be an array if it is coming from a submenu.
-- In that case it will be {"option", "submenuOption", ...}
function ContextMenuStyleState:selectOption(option: string | { string } | nil)
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
			BackgroundColor3 = self.theme.colors.button.transparent.baseColor,
		})
		StyleStateHelper.tween(button.TextLabel, tweenInfo, {
			TextColor3 = self.theme.colors.text,
		})
		StyleStateHelper.tween(button.Hotkey, tweenInfo, {
			TextColor3 = if hovering then self.theme.colors.text else self.theme.colors.disabledText,
		})
		if self._hasIcons then
			StyleStateHelper.tween(button.Icon, tweenInfo, {
				ImageColor3 = self.theme.colors.text,
			})
		end

		local arrow = button:FindFirstChild("Arrow")
		if arrow then
			StyleStateHelper.tween(button.Arrow.ImageLabel, tweenInfo, {
				ImageColor3 = self.theme.colors.text,
			})
		end
	end
end

-- Assumes ContextMenu is parented directly to the GUI
function ContextMenuStyleState:animate(xOffset: number?, yOffset: number?)
	local originalPosition = self.frame.Position
	local originalAnchor = self.frame.AnchorPoint
	local originalParent = self.frame.Parent

	local targetX = self.frame.AbsolutePosition.X - 2
	local targetY = self.frame.AbsolutePosition.Y - 2
	local startX = targetX - (xOffset or 0)
	local startY = targetY - (yOffset or 16)

	local canvasGroup = Instance.new("CanvasGroup")
	canvasGroup.BackgroundTransparency = 1
	canvasGroup.Size = UDim2.fromOffset(4 + self.frame.AbsoluteSize.X, 4 + self.frame.AbsoluteSize.Y)
	canvasGroup.Position = UDim2.fromOffset(targetX, startY)

	self.frame.Position = UDim2.fromOffset(2, 2)
	self.frame.AnchorPoint = Vector2.new(0, 0)
	self.frame.Size = UDim2.fromOffset(self.frame.AbsoluteSize.X, self.frame.AbsoluteSize.Y)
	self.frame.Parent = canvasGroup
	canvasGroup.ZIndex = self.frame.ZIndex
	canvasGroup.Parent = originalParent

	local start = os.clock()
	while self.frame and self._selected do
		local delta = os.clock() - start
		local a = math.min(delta / 0.1, 1)
		a = TweenService:GetValue(a, Enum.EasingStyle.Cubic, Enum.EasingDirection.Out)

		canvasGroup.Position = UDim2.fromOffset(startX + a * (targetX - startX), startY + a * (targetY - startY))
		canvasGroup.GroupTransparency = 1 - a

		if a >= 1 then
			break
		end

		task.wait()
	end

	if self.frame and self.frame.Parent then
		self.frame.Position = originalPosition
		self.frame.AnchorPoint = originalAnchor
		self.frame.Parent = originalParent
	end

	canvasGroup:Destroy()
end

function ContextMenuStyleState:destroy(completely: boolean)
	self:_closeSub()
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
