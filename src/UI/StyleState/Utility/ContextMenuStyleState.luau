-- TODO: should auto-follow theme when using.createMenu

local TweenService = game:GetService("TweenService")

local StyleStateHelper = require(script.Parent.Parent.StyleStateHelper)
local PopupHelper = require(script.Parent.Parent.Parent.PopupHelper)

local ContextMenuStyleState = {}
ContextMenuStyleState.__index = ContextMenuStyleState

ContextMenuStyleState.SEPARATOR = newproxy()

export type Options = { string | { icon: string, text: string } }
export type ContextMenuOptions = {
	options: Options
}

-- For convenience
function ContextMenuStyleState.prompt(theme, container: GuiObject, position: Vector2, options: ContextMenuOptions)
	local contextMenu, modal = ContextMenuStyleState.createMenu(theme, container, position, options)

	local option = contextMenu.selected:Wait()

	modal:destroy()
	contextMenu:destroy(true)
	
	return option
end

function ContextMenuStyleState.createMenu(theme, container: GuiObject, position: Vector2, options: ContextMenuOptions)
	local frame = script.ContextMenu:Clone()
	frame.Parent = container
	frame.Position = UDim2.fromOffset(position.X, position.Y)
	
	local styleState = ContextMenuStyleState.from(theme, frame, options)
	
	local modal = PopupHelper.modal(frame, container, {
		zIndex = 20
	})
	modal.cancelled:Connect(function()
		styleState:selectOption(nil)
	end)
	
	PopupHelper.clamp(frame, container, {
		boundaryDistance = 5,
		tryPivot = true,
	})
	
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
		separator.Size = UDim2.fromOffset(self.frame.AbsoluteSize.X - (script.ContextMenu.UIPadding.PaddingLeft.Offset + script.ContextMenu.UIPadding.PaddingRight.Offset), 1)
	end
end

function ContextMenuStyleState:selectOption(option: string?)
	self._selected:Fire(option)
end

function ContextMenuStyleState:update(speed: StyleStateHelper.TransitionSpeed?)
	local tweenInfo = StyleStateHelper.getTweenInfoForSpeed(speed)
	TweenService:Create(self.frame, tweenInfo, {
		BackgroundColor3 = self.theme.colors.button.secondary.body.default
	}):Play()
	TweenService:Create(self.frame.UIStroke, tweenInfo, {
		Color = self.theme.colors.button.secondary.outline.default
	}):Play()
	for _, separator in self._separators do
		StyleStateHelper.tween(separator, tweenInfo, {
			BackgroundColor3 = self.theme.colors.button.secondary.outline.default
		})
	end
	for _, button in self._buttons do
		local hovering = (self._hoveringOption == button.Name)
		StyleStateHelper.tween(button, tweenInfo, {
			BackgroundTransparency = if hovering then 0.5 else 1,
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

function ContextMenuStyleState:destroy(completely: boolean)
	self._selected:Destroy()
	for _, button in self._buttons do
		button:Destroy()
	end
	if completely then
		self.frame:Destroy()
	end
end

return ContextMenuStyleState