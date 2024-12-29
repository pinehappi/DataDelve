-- Handles bread crumbs
-- If the breadcrumbs is too long for the window, it will switch into a dropdown

local TweenService = game:GetService("TweenService")

local StyleStateHelper = require(script.Parent.StyleStateHelper)
local ButtonStyleState = require(script.Parent.ButtonStyleState)
local SelectStyleState = require(script.Parent.Input.SelectStyleState)

local BreadcrumbsStyleState = {}
BreadcrumbsStyleState.__index = BreadcrumbsStyleState

export type BreadcrumbsLayout = "breadcrumbs" | "dropdown"

type Crumb = {
	styleState: ButtonStyleState.ButtonStyleState,
	category: string,
	name: string,

	unselectedIcon: string,
	selectedIcon: string,
}

function BreadcrumbsStyleState.from(theme, frame: Frame & { UIListLayout: UIListLayout })
	local self = setmetatable({
		theme = theme,
		frame = frame,

		disabled = false,

		layout = "breadcrumbs" :: BreadcrumbsLayout,
		_lastContentSizeX = 0,
		_selectStyleState = nil, -- Only used for "dropdown" layout

		crumbs = {},
		currentCrumbIndex = nil,
		_pointers = {}, -- Unused pointers are parented to nil and destroyed when the StyleState is destroyed

		_connections = {},
	}, BreadcrumbsStyleState)

	self._crumbChanged = Instance.new("BindableEvent")
	self.crumbChanged = self._crumbChanged.Event

	task.defer(function()
		self._lastContentSizeX = frame.UIListLayout.AbsoluteContentSize.X

		local function updateLayout()
			if not frame.Visible then
				return
			end

			if self.layout == "breadcrumbs" then
				self._lastContentSizeX = frame.UIListLayout.AbsoluteContentSize.X
			end

			if frame.AbsoluteSize.X + 20 < self._lastContentSizeX then
				self:_setLayout("dropdown")
			else
				self:_setLayout("breadcrumbs")
			end
		end

		table.insert(
			self._connections,
			frame.UIListLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(updateLayout)
		)
		table.insert(self._connections, frame:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateLayout))
		table.insert(self._connections, frame:GetPropertyChangedSignal("Visible"):Connect(updateLayout))
	end)

	self:update("instant")
	return self
end

function BreadcrumbsStyleState:update(speed: StyleStateHelper.TransitionSpeed?)
	if self._selectStyleState then
		self._selectStyleState:update(speed)
	end

	if self.layout ~= "breadcrumbs" then
		speed = "instant"
	end

	for _, crumb in self.crumbs do
		crumb.styleState:update(speed)
	end

	local tweenInfo = StyleStateHelper.getTweenInfoForSpeed(speed)
	for _, pointer in self._pointers do
		TweenService:Create(pointer, tweenInfo, {
			ImageColor3 = self.theme.colors.text,
		}):Play()
	end
end

function BreadcrumbsStyleState:jumpTo(crumbIndex: number)
	local lastCrumb = self.crumbs[self.currentCrumbIndex]
	if lastCrumb then
		lastCrumb.styleState.button.TextLabel.FontFace = Font.new(
			script.Crumb.TextLabel.FontFace.Family,
			Enum.FontWeight.Regular,
			script.Crumb.TextLabel.FontFace.Style
		)
		lastCrumb.styleState.button.Icon.Image = lastCrumb.unselectedIcon
	end

	local currentCrumb = self.crumbs[crumbIndex]
	self.currentCrumbIndex = crumbIndex
	currentCrumb.styleState.button.TextLabel.FontFace =
		Font.new(script.Crumb.TextLabel.FontFace.Family, Enum.FontWeight.Bold, script.Crumb.TextLabel.FontFace.Style)
	currentCrumb.styleState.button.Icon.Image = currentCrumb.selectedIcon

	if self._selectStyleState then
		self._selectStyleState:setSelection(currentCrumb.name, {
			index = crumbIndex,
			silently = true,
		})
	end

	self._crumbChanged:Fire(currentCrumb)
end

-- Icon can be an image id or a table with the image ids for the selected and unselected states
function BreadcrumbsStyleState:addCrumb(
	icon: string | { selected: string, unselected: string },
	category: string,
	name: string
)
	local index = nil
	local button = script.Crumb:Clone()
	local styleState = ButtonStyleState.from(self.theme, button, {
		style = "transparent",
	})

	local unselectedIcon: string
	local selectedIcon: string
	if typeof(icon) == "table" then
		unselectedIcon = icon.unselected
		selectedIcon = icon.selected
	else
		unselectedIcon = icon
		selectedIcon = icon
	end

	local crumb: Crumb = {
		styleState = styleState,
		category = category,
		name = name,
		unselectedIcon = unselectedIcon,
		selectedIcon = selectedIcon,

		hovering = false,
		selecting = false,
	}

	button.Icon.Image = unselectedIcon
	button.TextLabel.Text = name

	button.Activated:Connect(function()
		self:jumpTo(index)
	end)

	if self.currentCrumbIndex then
		-- Destroy crumbs that come after
		for i = self.currentCrumbIndex + 1, #self.crumbs do
			self:_cleanupCrumb(self.crumbs[i])
			self.crumbs[i] = nil
		end
	end

	if self.layout == "breadcrumbs" then
		button.Parent = self.frame
	end
	table.insert(self.crumbs, crumb)
	index = #self.crumbs

	self:_tryUpdateSelect()

	self:jumpTo(index)
	self:_updatePointers()
end

function BreadcrumbsStyleState:popCrumb(options: { silently: boolean? }?)
	options = options or {}
	assert(options)

	local crumb = table.remove(self.crumbs)
	self:_cleanupCrumb(crumb)
	
	local ptr = table.remove(self._pointers)
	if ptr then ptr:Destroy() end

	if not options.silently then
		if self.currentCrumbIndex > #self.crumbs then
			self:jumpTo(#self.crumbs)
		end
	end

	self:_tryUpdateSelect()
	return crumb
end

function BreadcrumbsStyleState:renameCrumbSafe(index: number, name: string)
	local crumb = self.crumbs[index]
	if crumb then
		crumb.name = name
		crumb.styleState.button.TextLabel.Text = name
	end

	self:_tryUpdateSelect()
end

function BreadcrumbsStyleState:setCrumbNameVisibleSafe(index: number, visible: boolean)
	local crumb = self.crumbs[index]
	if crumb then
		crumb.styleState.button.TextLabel.Visible = visible

		-- AutomaticSize does not shrink it enough for some reason
		-- So manually set the size

		if visible then
			crumb.styleState.button.AutomaticSize = Enum.AutomaticSize.X
			crumb.styleState.button.Size = script.Crumb.Size
			crumb.styleState.button.SizeConstraint = Enum.SizeConstraint.RelativeXY
		else
			crumb.styleState.button.AutomaticSize = Enum.AutomaticSize.None
			crumb.styleState.button.Size = UDim2.new(script.Crumb.Size.Y, script.Crumb.Size.Y)
			crumb.styleState.button.SizeConstraint = Enum.SizeConstraint.RelativeYY
		end
	end
end

function BreadcrumbsStyleState:getCurrentCrumb()
	return self.crumbs[self.currentCrumbIndex]
end

function BreadcrumbsStyleState:setDisabled(disabled: boolean)
	self.disabled = disabled
	for _, crumb in self.crumbs do
		crumb.styleState:setDisabled(disabled)
	end

	return self
end

function BreadcrumbsStyleState:destroy(completely: boolean)
	for _, crumb in self.crumbs do
		self:_cleanupCrumb(crumb)
	end
	for _, pointer in self._pointers do
		pointer:Destroy()
	end
	for _, connection in self._connections do
		connection:Disconnect()
	end

	if completely then
		self.frame:Destroy()
	end
end

-- Private

function BreadcrumbsStyleState:_cleanupCrumb(crumb: Crumb)
	crumb.styleState:destroy(true)
end

function BreadcrumbsStyleState:_updatePointers()
	-- Delete unused pointers
	for i = #self.crumbs, #self._pointers do
		self._pointers[i]:Destroy()
		self._pointers[i] = nil
	end

	for i, crumb in self.crumbs do
		crumb.styleState.button.LayoutOrder = 2 * i
		if i > 1 then
			local pointer = self._pointers[i - 1]
			if not pointer then
				pointer = script.Pointer:Clone()
				table.insert(self._pointers, pointer)
			end
			pointer.LayoutOrder = 2 * i - 1
			pointer.ImageColor3 = self.theme.colors.text

			if self.layout == "breadcrumbs" then
				pointer.Parent = self.frame
			end
		end
	end
end

function BreadcrumbsStyleState:_getSelectOptions(): SelectStyleState.Options
	local options = {}
	for _, crumb in self.crumbs do
		table.insert(options, { name = crumb.name, icon = crumb.unselectedIcon })
	end
	return options
end

function BreadcrumbsStyleState:_tryUpdateSelect()
	if self._selectStyleState then
		self._selectStyleState:changeOptions(self:_getSelectOptions())
	end
end

function BreadcrumbsStyleState:_resetLayout()
	if self.layout == "breadcrumbs" then
		-- Hide everything
		for _, crumb in self.crumbs do
			crumb.styleState.button.Parent = nil
		end
		for _, pointer in self._pointers do
			pointer.Parent = nil
		end
	elseif self.layout == "dropdown" then
		-- Destroy the big button
		self._selectStyleState:destroy(true)
		self._selectStyleState = nil
	end
end

function BreadcrumbsStyleState:_setLayout(layout: BreadcrumbsLayout)
	if layout ~= self.layout then
		self:_resetLayout()
		self.layout = layout

		if layout == "breadcrumbs" then
			for _, crumb in self.crumbs do
				crumb.styleState.button.Parent = self.frame
			end
			for _, pointer in self._pointers do
				pointer.Parent = self.frame
			end
		elseif layout == "dropdown" then
			local button = script.DropdownCrumb:Clone()
			self._selectStyleState = SelectStyleState.from(self.theme, button, {
				default = self.crumbs[self.currentCrumbIndex].name,
				defaultIndex = self.currentCrumbIndex,
				options = self:_getSelectOptions(),
				buttonStyle = "transparent",
				fitButton = false,
			})
			self._selectStyleState.changed:Connect(function(_, index)
				self:jumpTo(index)
			end)
			button.Parent = self.frame
		end
	end
end

return BreadcrumbsStyleState
