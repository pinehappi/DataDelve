--!strict

local DESCENDING_ICON = "rbxassetid://17650920474"
local ASCENDING_ICON = "rbxassetid://17650919434"

local rfmt = require(script.Parent.Parent.rfmt)

local StyleState = script.Parent.StyleState
local Assets = script.Parent.Assets

local Settings = require(script.Parent.Parent.Settings)
local Theme = require(script.Parent.Theme)
local UIMessages = require(script.Parent.UIMessages)
local PopupHelper = require(script.Parent.PopupHelper)
local Validators = require(script.Parent.Parent.Validators)
local Tooltip = require(script.Parent.Tooltip)

local StyleStateHelper = require(StyleState.StyleStateHelper)
local TextBoxStyleState = require(StyleState.Input.TextBoxStyleState)
local ShortcutsTextBoxStyleState = require(StyleState.Input.ShortcutsTextBoxStyleState)
local ButtonStyleState = require(StyleState.ButtonStyleState)
local LabelStyleState = require(StyleState.LabelStyleState)
local LoadMoreListStyleState = require(StyleState.LoadMoreListStyleState)
local SeparatorStyleState = require(StyleState.SeparatorStyleState)
local ContextMenuStyleState = require(StyleState.Utility.ContextMenuStyleState)
local ConfirmDialogStyleState = require(StyleState.Utility.ConfirmDialogStyleState)

local OrderedDataStoreKeyStyleState = require(script.OrderedDataStoreKeyStyleState)

local constrainTextBoxStyleState = require(script.Parent.Utilities.constrainTextBoxStyleState)
local createTabSwitchGroup = require(script.Parent.Utilities.createTabSwitchGroup)
local getHighlightColors = require(script.Parent.Utilities.getHighlightColors)
local promptKeyValueForm = require(script.Parent.Utilities.promptKeyValueForm)

local OrderedDataStoreView = {}
OrderedDataStoreView.__index = OrderedDataStoreView

function OrderedDataStoreView.from(
	theme: Theme.Theme,
	uiMessages: UIMessages.UIMessages,
	frame: typeof(Assets.Widget.EditOrderedDataStore)
)
	local self = setmetatable({}, OrderedDataStoreView)
	self.theme = theme
	self.frame = frame
	self.uiMessages = uiMessages
	self.connections = {}
	self.locked = false

	self.activeKey = nil :: string?

	self.order = "descending"
	self._orderChanged = Instance.new("BindableEvent")
	self.orderChanged = self._orderChanged.Event

	self.minValue = nil :: number?
	self.maxValue = nil :: number?

	self._highlightColors = getHighlightColors(self.theme)

	-- Events

	self._listed = Instance.new("BindableEvent")
	self.listed = self._listed.Event

	self._keyQueried = Instance.new("BindableEvent")
	self.keyQueried = self._keyQueried.Event

	self._keyEdited = Instance.new("BindableEvent")
	self.keyEdited = self._keyEdited.Event

	self._keyDeleted = Instance.new("BindableEvent")
	self.keyDeleted = self._keyDeleted.Event

	self._keyAdded = Instance.new("BindableEvent")
	self.keyAdded = self._keyAdded.Event

	self.styleStates = {
		getKey = ShortcutsTextBoxStyleState.from(theme, frame.Key),
		order = ButtonStyleState.from(theme, frame.Order),
		minValue = TextBoxStyleState.from(theme, frame.MinValue),
		maxValue = TextBoxStyleState.from(theme, frame.MaxValue),
		list = ButtonStyleState.from(theme, frame.List, {
			style = "primary",
		}),

		rangeDash = LabelStyleState.from(theme, frame.RangeDash),

		separators = SeparatorStyleState.fromDescendants(theme, frame),

		loadMore = LoadMoreListStyleState.from(theme, frame.Keys.Table, {
			createItemStyleState = function(loadMoreListStyleState, info)
				local key = Assets.OrderedDataStoreKey:Clone()
				local styleState = OrderedDataStoreKeyStyleState.from(theme, self._highlightColors, key)

				key.Name = info.key
				key.Key.Text = info.key
				key.Value.Text = info.value

				local function onRightClick()
					if not key.Key.Active then
						return
					end -- It's disabled

					local gui = frame:FindFirstAncestorWhichIsA("PluginGui")

					local resetSelecting = loadMoreListStyleState:setSelectingStyleState(styleState)
					local option = ContextMenuStyleState.prompt(theme, gui, gui:GetRelativeMousePosition(), {
						options = {
							{ icon = self.theme.icons.insert, text = "Insert" },
							{ icon = self.theme.icons.delete, text = "Delete" },
						},
					})

					if option == "Delete" then
						if
							ConfirmDialogStyleState.confirm(theme, gui, gui:GetRelativeMousePosition(), {
								title = "Delete key?",
								message = "Are you sure you want to do this?",
							})
						then
							if
								ConfirmDialogStyleState.confirm(theme, gui, gui:GetRelativeMousePosition(), {
									title = "Confirm again",
									message = `You are going to delete the key <b>{info.key}</b>. This CANNOT be undone.`,
								})
							then
								self._keyDeleted:Fire(info.key)
							end
						end
					elseif option == "Insert" then
						self:_promptInsert()
					end

					resetSelecting()
				end

				local function toggleSelect()
					if loadMoreListStyleState.selectingStyleState == styleState then
						loadMoreListStyleState:setSelectingStyleState(nil)
					else
						loadMoreListStyleState:setSelectingStyleState(styleState)
					end
				end

				key.Key.Activated:Connect(function(_, count: number)
					count = count % 2
					if count == 0 then
						toggleSelect()
					elseif count == 1 then
						uiMessages:warn("Cannot edit ordered datastore keys at the moment.")
					end
				end)
				key.Value.Activated:Connect(function(_, count: number)
					count = count % 2
					if count == 0 then
						toggleSelect()
					elseif count == 1 then
						local gui = frame:FindFirstAncestorWhichIsA("LayerCollector")
						local textBox = Assets.ModalTextBox:Clone()
						local styleState = TextBoxStyleState.from(theme, textBox)

						styleState
							:overrideTextColor(self._highlightColors.number)
							:overrideBackgroundColor(self._highlightColors.background)
							:update("instant")

						textBox.PlaceholderText = "Value"
						textBox.Text = key.Value.Text
						textBox.Size = UDim2.fromOffset(key.Value.AbsoluteSize.X, key.Value.AbsoluteSize.Y)

						local attachment = PopupHelper.attach(textBox, key.Value, {
							anchor = Vector2.new(0, 0),
							offset = Vector2.new(0, 0),
						})
						local modal = PopupHelper.modal(textBox, gui, {
							includeDropShadow = false,
						})

						local function cleanup()
							modal:destroy()
							attachment:destroy()
							styleState:destroy()
							textBox:Destroy()
						end

						modal.cancelled:Once(cleanup)
						textBox.FocusLost:Connect(function(entered)
							if entered then
								local valid, _ = Validators.integer(textBox.Text)
								if valid then
									self._keyEdited:Fire(info.key, tonumber(textBox.Text))
								else
									uiMessages:error("Value must be an integer!")
								end
							end
							cleanup()
						end)

						-- Weird bug, without this the textbox jitters
						task.delay(0, function()
							textBox:CaptureFocus()
						end)
					end
				end)

				key.Key.MouseButton2Click:Connect(onRightClick)
				key.Value.MouseButton2Click:Connect(onRightClick)

				key.Parent = loadMoreListStyleState.frame
				return styleState
			end,
		}),

		tableLabels = LabelStyleState.fromDescendants(theme, frame.Keys),
	}

	self:_updateHighlightColors({ tween = false })
	self.styleStates.tableLabels.Empty:update("instant")
	self.styleStates.tableLabels.Instructions:update("instant")

	-- Tooltip
	Tooltip.bindButtonGeneric(
		self.theme,
		self.styleStates.order.button,
		"Order\nToggle between highest-to-lowest or lowest-to-highest."
	)
	Tooltip.bindButtonGeneric(
		self.theme,
		self.styleStates.list.button,
		`List Keys\nList all keys in order. Equivalent to a call to {rfmt.code("GetSortedAsync")}.`
	)

	-- Tab switch groups

	createTabSwitchGroup({
		self.styleStates.getKey.textBox,
		self.styleStates.minValue.textBox,
		self.styleStates.maxValue.textBox,
	})

	-- Events

	table.insert(
		self.connections,
		theme.colorsChanged:Connect(function()
			task.wait()

			self:_updateHighlightColors({ tween = false })

			StyleStateHelper.update(self.styleStates)
		end)
	)

	table.insert(
		self.connections,
		Settings.changed:Connect(function(settingName)
			if settingName == "highlightColors" then
				self:_updateHighlightColors({ tween = true })
			end
		end)
	)

	-- UI Events
	-- Click Background
	self.frame.ClickBackground.MouseButton2Click:Connect(function()
		self.styleStates.loadMore:setSelectingStyleState(nil)

		local gui = self.frame:FindFirstAncestorWhichIsA("LayerCollector")
		local option = ContextMenuStyleState.prompt(self.theme, gui, gui:GetRelativeMousePosition(), {
			options = {
				{ icon = self.theme.icons.insert, text = "Insert" },
			},
		})

		if option == "Insert" then
			self:_promptInsert()
		end
	end)

	-- Listing events
	self.styleStates.minValue.textBox.FocusLost:Connect(function(entered: boolean, input: InputObject?)
		if input == nil then
			return
		end

		local number = tonumber(self.styleStates.minValue.textBox.Text)
		if number then
			self.minValue = number
		elseif self.styleStates.minValue.textBox.Text:gsub("%s", "") ~= "" then
			uiMessages:error("Min value must be a number.")
		else
			self.minValue = nil
		end
		self.styleStates.minValue.textBox.Text = if self.minValue then tostring(self.minValue) else ""

		if entered then
			self._listed:Fire()
		end
	end)

	constrainTextBoxStyleState(self.styleStates.minValue, { Validators.integer })

	self.styleStates.maxValue.textBox.FocusLost:Connect(function(entered: boolean, input: InputObject?)
		if input == nil then
			return
		end

		local number = tonumber(self.styleStates.maxValue.textBox.Text)
		if number then
			self.maxValue = number
		elseif self.styleStates.maxValue.textBox.Text:gsub("%s", "") ~= "" then
			uiMessages:error("Max value must be a number.")
		else
			self.maxValue = nil
		end
		self.styleStates.maxValue.textBox.Text = if self.maxValue then tostring(self.maxValue) else ""

		if entered then
			self._listed:Fire()
		end
	end)

	constrainTextBoxStyleState(self.styleStates.maxValue, { Validators.integer })

	self.styleStates.order.button.Activated:Connect(function()
		if self.order == "ascending" then
			self.order = "descending"
			self.styleStates.order.button.ImageLabel.Image = DESCENDING_ICON
			self._orderChanged:Fire()
		elseif self.order == "descending" then
			self.order = "ascending"
			self.styleStates.order.button.ImageLabel.Image = ASCENDING_ICON
			self._orderChanged:Fire()
		end
	end)

	self.styleStates.list.button.Activated:Connect(function()
		self._listed:Fire()
	end)

	self.styleStates.getKey.textBox.FocusLost:Connect(function(entered, input)
		if input == nil then
			return
		end

		if entered then
			local function errorHandler(err: string)
				self.uiMessages:error(err)
			end
			self._keyQueried:Fire(self.styleStates.getKey:getText(errorHandler))
		end
	end)

	constrainTextBoxStyleState(self.styleStates.getKey, { Validators.dataStoreKey })

	return self
end

function OrderedDataStoreView:_updateHighlightColors(options: { tween: boolean })
	self._highlightColors = getHighlightColors(self.theme)
	self.frame.ClickBackground.BackgroundColor3 = self._highlightColors.background

	if options.tween then
		self.styleStates.tableLabels.Empty:overrideColor(self._highlightColors.plain):update()
		self.styleStates.tableLabels.Instructions:overrideColor(self._highlightColors.plain):update()
	else
		self.styleStates.tableLabels.Empty:overrideColor(self._highlightColors.plain)
		self.styleStates.tableLabels.Instructions:overrideColor(self._highlightColors.plain)
	end

	for _, styleState in self.styleStates.loadMore.itemStyleStates do
		styleState:setHighlightColors(self._highlightColors)
		if options.tween then
			styleState:update()
		end
	end
end

function OrderedDataStoreView:setLocked(locked: boolean)
	self.locked = locked

	self.styleStates.order:setDisabled(locked):update()
	self.styleStates.getKey:setDisabled(locked):update()
	self.styleStates.minValue:setDisabled(locked):update()
	self.styleStates.maxValue:setDisabled(locked):update()
	self.styleStates.list:setDisabled(locked):update()

	for _, styleState in self.styleStates.loadMore.itemStyleStates do
		styleState:setDisabled(locked):update()
	end
end

-- "empty" used when GetSortedAsync returns empty page
-- "notEmpty" when there's stuff in the page
-- "notFound" when queried key not found
function OrderedDataStoreView:setKeysState(state: "empty" | "notEmpty" | "notFound")
	local empty = (state == "empty") or (state == "notFound")
	self.frame.Keys.Table.Visible = not empty
	self.frame.Keys.Empty.Visible = empty
	self.frame.Keys.Instructions.Visible = false

	if state == "notFound" then
		self.frame.Keys.Empty.Text = "Key not found."
	else
		self.frame.Keys.Empty.Text = "No keys found."
	end
end

function OrderedDataStoreView:addKey(key: string, value: number)
	self:setKeysState("notEmpty")

	-- When the user inserts when they haven't listed or the list is empty, the load more button will appear. Make sure it doesn't
	if self.styleStates.loadMore:isEmpty() then
		self.styleStates.loadMore:setLoadMoreVisible(false)
	end
	self.styleStates.loadMore:add({ key = key, value = value })
end

function OrderedDataStoreView:updateKey(key: string, value: number)
	local frame = self.styleStates.loadMore.frame:FindFirstChild(key)
	if frame then
		frame.Value.Text = value
	end
end

function OrderedDataStoreView:deleteKey(key: string)
	local frame = self.styleStates.loadMore.frame:FindFirstChild(key)
	if frame then
		frame:Destroy()

		for i, v in self.styleStates.loadMore.itemStyleStates do
			if v.frame == frame then
				v:destroy()
				table.remove(self.styleStates.loadMore.itemStyleStates, i)
				break
			end
		end
	end
end

-- When setting activeKey to nil, should also list keys.
-- activeKey is the key that they got using the `Get Key` input
function OrderedDataStoreView:setActiveKey(key: string?, value: number?)
	if key then
		self.styleStates.loadMore:clear()
		self.styleStates.loadMore:setLoadMoreVisible(false)
		if value then
			self.styleStates.loadMore:add({ key = key, value = value })
		else
			self:setKeysState("notFound")
		end
	end
	self.activeKey = key
end

function OrderedDataStoreView:_promptInsert()
	local result = promptKeyValueForm(self.theme, self.frame:FindFirstAncestorWhichIsA("PluginGui"), {
		title = "Insert Key",
		includeKey = true,
		includeValue = true,
		constraint = "orderedDataStore",
	})
	if result then
		self._keyAdded:Fire(result.key, result.value)
	end
end

function OrderedDataStoreView:reset()
	self.order = "descending"
	self.styleStates.order.button.ImageLabel.Image = DESCENDING_ICON
	self.styleStates.loadMore:clear()

	self.styleStates.getKey.textBox.Text = ""
	self.styleStates.minValue.textBox.Text = ""
	self.styleStates.maxValue.textBox.Text = ""

	self.activeKey = nil
	self.minValue = nil
	self.maxValue = nil

	self.frame.Keys.Instructions.Visible = true
	self.frame.Keys.Table.Visible = false
	self.frame.Keys.Empty.Visible = false
end

function OrderedDataStoreView:destroy()
	for _, connection in self.connections do
		connection:Disconnect()
	end
end

return OrderedDataStoreView
