--!strict

local TextService = game:GetService("TextService")
local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent.Parent.Parent.Theme)
local PopupHelper = require(script.Parent.Parent.Parent.PopupHelper)

local StyleStateHelper = require(script.Parent.Parent.StyleStateHelper)
local BackgroundStyleState = require(script.Parent.Parent.BackgroundStyleState)
local ButtonStyleState = require(script.Parent.Parent.ButtonStyleState)

local DOWN_ARROW_IMAGE = "rbxassetid://17650880752"
local UP_ARROW_IMAGE = "rbxassetid://18557565597"
local SELECT_MENU_OFFSET = 2

local SelectStyleState = {}
SelectStyleState.__index = SelectStyleState

export type Options = { string | { name: string, icon: string } }
export type SelectStyleStateOptions = {
	default: string,
	defaultIndex: number?,
	options: Options,
	buttonStyle: ButtonStyleState.ButtonStyle?,

	fitButton: boolean?, -- default: true. Whether or not the button should fit the options
}

function SelectStyleState.from(
	theme: Theme.Theme,
	button: TextButton & { Selection: TextLabel, Arrow: ImageLabel, Icon: ImageLabel? },
	selectStyleStateOptions: SelectStyleStateOptions -- Required
)
	if selectStyleStateOptions.fitButton == nil then
		selectStyleStateOptions.fitButton = true
	end

	local self = setmetatable({
		options = selectStyleStateOptions.options,
		open = false,

		selection = nil :: string?,
		selectionIndex = nil :: number?,

		fitButton = selectStyleStateOptions.fitButton,

		menu = nil :: any,
		menuStyleStates = {} :: { any },
		menuModal = nil :: any,
		menuAttachment = nil :: any,

		button = button,
		buttonStyleState = ButtonStyleState.from(
			theme,
			button,
			{ style = selectStyleStateOptions.buttonStyle or "input" }
		),

		theme = theme,
	}, SelectStyleState)

	if self.fitButton then
		self:_fitSelectedText()
	end

	self._changed = Instance.new("BindableEvent")
	self.changed = self._changed.Event

	button.Activated:Connect(function()
		self:setOpen(not self.open)
	end)

	self:setSelection(selectStyleStateOptions.default, {
		index = selectStyleStateOptions.defaultIndex,
		silently = true,
	})
	return self
end

function SelectStyleState:setOpen(open: boolean)
	self.open = open
	self.buttonStyleState:setSelecting(open)
	self:update()

	if self.open then
		self:_makeMenu()
	elseif self.menu then
		self:_clearMenu()
	end
end

function SelectStyleState:_clearMenu()
	for _, styleState in self.menuStyleStates do
		styleState:destroy()
	end
	self.menuStyleStates = {}
	self.menuModal:destroy()
	self.menuAttachment:destroy()
	self.menu:Destroy()
	self.menu = nil :: any
	self.menuModal = nil :: any
	self.menuAttachment = nil :: any
end

function SelectStyleState:_makeMenu()
	if self.menu then
		self:_clearMenu()
	end

	self.menu = script.SelectMenu:Clone()
	self.menu.BackgroundColor3 = self.theme.colors.floatingAction.background
	self.menu.UIStroke.Color = self.theme.colors.floatingAction.outline
	if self.fitButton then
		self.menu.Size = UDim2.fromOffset(self.button.AbsoluteSize.X, 0)
	else
		local longestX = 0

		for _, option in self.options do
			local text = if typeof(option) == "string" then option else option.name

			local textBoundsParams = Instance.new("GetTextBoundsParams")
			textBoundsParams.Text = text
			textBoundsParams.Font = self.button.Selection.FontFace
			textBoundsParams.Size = self.button.Selection.TextSize
			textBoundsParams.Width = math.huge

			local textBounds = TextService:GetTextBoundsAsync(textBoundsParams)
			local boundsX = textBounds.X

			if typeof(option) == "table" then
				boundsX += script.SelectOption.ImageLabel.AbsoluteSize.X
				boundsX += script.SelectOption.UIListLayout.Padding.Offset
			end

			longestX = math.max(longestX, boundsX)
		end

		self.menu.Size = UDim2.fromOffset(
			longestX
				+ script.SelectOption.UIPadding.PaddingLeft.Offset
				+ script.SelectOption.UIPadding.PaddingRight.Offset,
			0
		)
	end

	for index, option in self.options do
		local text = if typeof(option) == "string" then option else option.name

		local button = script.SelectOption:Clone()
		button.TextLabel.Text = text
		if typeof(option) == "table" then
			button.ImageLabel.Image = option.icon
		else
			button.ImageLabel:Destroy()
		end

		button.Activated:Connect(function()
			self:setSelection(text, {
				index = index,
			})

			self:setOpen(false)
		end)
		button.Size = UDim2.new(1, 0, 0, self.button.AbsoluteSize.Y)

		button.Parent = self.menu
		table.insert(self.menuStyleStates, ButtonStyleState.from(self.theme, button, { style = "transparent" }))
	end

	local gui = (self.button:FindFirstAncestorWhichIsA("LayerCollector") :: any) :: LayerCollector
	self.menuModal = PopupHelper.modal(self.menu, gui, {
		zIndex = 20,
		passThroughInput = true,
	})
	self.menuAttachment = PopupHelper.attach(self.menu, self.button, {
		anchor = Vector2.new(0, 1),
		offset = Vector2.new(0, 2),
		beforeUpdate = function(options, object, target)
			local height = object.AbsoluteSize.Y
			if target.AbsolutePosition.Y + target.AbsoluteSize.Y + height + SELECT_MENU_OFFSET > gui.AbsoluteSize.Y then
				-- Try flipping it
				if target.AbsolutePosition.Y - height - SELECT_MENU_OFFSET < 0 then
					-- Can't be flipped, just clamp
					local position = target.AbsolutePosition + Vector2.new(0, target.AbsoluteSize.Y)
					object.Position = UDim2.fromOffset(position.X, position.Y)
					PopupHelper.clamp(object, gui)
					return "manual"
				else
					options.anchor = Vector2.new(0, 0)
					object.AnchorPoint = Vector2.new(0, 1)
				end
			else
				options.anchor = Vector2.new(0, 1)
				object.AnchorPoint = Vector2.new(0, 0)
			end
			return nil
		end,
	})

	self.menuModal.cancelled:Connect(function()
		self:setOpen(false)
	end)

	self:_animateMenu()
end

function SelectStyleState:_animateMenu()
	local menu = self.menu
	local menuAttachment = self.menuAttachment

	local start = os.clock()
	local startOffset = -8
	while (self.menu and self.menu == menu) and (self.menuAttachment and self.menuAttachment == menuAttachment) do
		local delta = os.clock() - start
		local a = math.min(delta / 0.1, 1)
		a = TweenService:GetValue(a, Enum.EasingStyle.Cubic, Enum.EasingDirection.Out)

		self.menu.GroupTransparency = 1 - a
		self.menu.UIStroke.Transparency = 1 - a
		self.menuAttachment.options.offset = Vector2.new(0, startOffset + a * (SELECT_MENU_OFFSET - startOffset))
		self.menuAttachment:updatePosition()

		if a >= 1 then
			break
		end

		task.wait()
	end
end

-- Makes sure the Selection TextLabel can always fit the biggest option
function SelectStyleState:_fitSelectedText()
	local longestX = self.button.Selection.TextBounds.X
	if longestX ~= longestX then -- It's nan
		longestX = 0
	end

	for _, option in self.options do
		local text = if typeof(option) == "string" then option else option.name

		local textBoundsParams = Instance.new("GetTextBoundsParams")
		textBoundsParams.Text = text
		textBoundsParams.Font = self.button.Selection.FontFace
		textBoundsParams.Size = self.button.Selection.TextSize
		textBoundsParams.Width = math.huge

		local bounds = TextService:GetTextBoundsAsync(textBoundsParams)
		longestX = math.max(longestX, bounds.X)
	end

	self.button.Selection.Size =
		UDim2.new(0, longestX, self.button.Selection.Size.Y.Scale, self.button.Selection.Size.Y.Offset)
end

function SelectStyleState:changeOptions(options: Options)
	self.options = options
	if self.fitButton then
		self:_fitSelectedText()
	end

	if self.menu then
		-- Reset the menu
		self:_makeMenu()
	end
end

function SelectStyleState:_calculateSelectionIndex(): number?
	for index, option in self.options do
		if typeof(option) == "table" and option.name == self.selection then
			return index
		elseif option == self.selection then
			return index
		end
	end
	return nil
end

export type SetSelectionOptions = {
	silently: boolean?,
	index: number?,
}
-- An index should be provided in case two options have the same name
function SelectStyleState:setSelection(selection: string, options: SetSelectionOptions?)
	local options: SetSelectionOptions = options or {}

	self.selection = selection
	self.selectionIndex = options.index or self:_calculateSelectionIndex()
	self.button.Selection.Text = selection

	-- Set image if possible
	local icon = self.button:FindFirstChild("Icon") :: ImageLabel
	if icon then
		local imageId = nil
		local option = self.options[self.selectionIndex or 1]

		if option and typeof(option) == "table" and option.icon then
			icon.Image = option.icon
		else
			icon.Image = ""
		end
	end

	if not options.silently then
		self._changed:Fire(selection, self.selectionIndex)
	end
end

function SelectStyleState:update(...)
	self.button.Arrow.Image = if self.open then UP_ARROW_IMAGE else DOWN_ARROW_IMAGE
	self.buttonStyleState:update(...)

	if self.menu then
		local tweenInfo = StyleStateHelper.getTweenInfoForSpeed(...)
		StyleStateHelper.tween(self.menu, tweenInfo, {
			BackgroundColor3 = self.theme.colors.floatingAction.background,
		})
		StyleStateHelper.tween(self.menu.UIStroke, tweenInfo, {
			Color = self.theme.colors.floatingAction.outline,
		})
		for _, styleStates in self.menuStyleStates do
			styleStates:update(...)
		end
	end
end

function SelectStyleState:destroy(completely: boolean)
	self.buttonStyleState:destroy()
	self._changed:Destroy()
	if self.menu then
		self:_clearMenu()
	end

	if completely then
		self.button:Destroy()
	end
end

return SelectStyleState
