local rfmt = require(script.Parent.rfmt)

local Types = require(script.Parent.Types)
local Theme = require(script.Theme)
local Validators = require(script.Parent.Validators)

local PopupHelper = require(script.PopupHelper)
local Tooltip = require(script.Tooltip)

local Assets = script.Assets
local StyleState = script.StyleState

local StyleStateWrapper = require(StyleState.StyleStateWrapper)
local StyleStateHelper = require(StyleState.StyleStateHelper)

local BackgroundStyleState = require(StyleState.BackgroundStyleState)
local ScrollingFrameStyleState = require(StyleState.ScrollingFrameStyleState)
local BreadcrumbsStyleState = require(StyleState.BreadcrumbsStyleState)
local ButtonStyleState = require(StyleState.ButtonStyleState)
local SeparatorStyleState = require(StyleState.SeparatorStyleState)
local LabelStyleState = require(StyleState.LabelStyleState)
local LoadMoreListStyleState = require(StyleState.LoadMoreListStyleState)
local TabsStyleState = require(StyleState.TabsStyleState)

local CheckboxStyleState = require(StyleState.Input.CheckboxStyleState)
local ShortcutsTextBoxStyleState = require(StyleState.Input.ShortcutsTextBoxStyleState)

local SkeletonStyleState = require(StyleState.Utility.SkeletonStyleState)
local ContextMenuStyleState = require(StyleState.Utility.ContextMenuStyleState)

local OrderedDataStoreView = require(script.Views.OrderedDataStoreView)
local SettingsView = require(script.Views.SettingsView)
local EditKeyView = require(script.Views.EditKeyView)

local createTabSwitchGroup = require(script.Utilities.createTabSwitchGroup)
local showShadowOnScroll = require(script.Utilities.showShadowOnScroll)

local UI = {}
UI.__index = UI

function UI.new(theme: Theme.Theme, uiMessages)
	local gui = Assets.Widgets.MainApp:Clone()
	local self = setmetatable({
		theme = theme,
		parent = nil,
		gui = gui,
		uiMessages = uiMessages,

		connections = {},

		activeView = nil,
	}, UI)

	self.styleStates = {
		headerBackground = BackgroundStyleState.from(theme, gui.HeaderBackground, { style = "header" }),
		background = BackgroundStyleState.from(theme, gui.Background),
		breadcrumbs = BreadcrumbsStyleState.from(theme, gui.Breadcrumbs),
		breadcrumbsSeparator = SeparatorStyleState.from(theme, gui.BreadcrumbsSeparator),
		settingsButton = ButtonStyleState.from(theme, gui.SettingsButton, {
			style = "dormant",
		}),

		connect = {
			scrollingFrame = ScrollingFrameStyleState.from(theme, gui.ConnectDataStore.Content),
			tabs = TabsStyleState.from(theme, gui.ConnectDataStore.Content.Form.Tabs),

			prefix = ShortcutsTextBoxStyleState.from(theme, gui.ConnectDataStore.Content.Form.Prefix.TextBox),
			listButton = ButtonStyleState.from(theme, gui.ConnectDataStore.Content.Form.Prefix.List, {
				style = "primary",
			}),

			connectButton = ButtonStyleState.from(theme, gui.ConnectDataStore.Content.Form.Connect.Connect, {
				style = "primary",
			}),
			dataStoreNameTitle = LabelStyleState.from(theme, gui.ConnectDataStore.Content.Form.DataStoreName.Title),
			dataStoreNameTextBox = ShortcutsTextBoxStyleState.from(
				theme,
				gui.ConnectDataStore.Content.Form.DataStoreName.TextBox
			),

			dataStoreScopeTitle = LabelStyleState.from(theme, gui.ConnectDataStore.Content.Form.DataStoreScope.Title),
			dataStoreScopeTextBox = ShortcutsTextBoxStyleState.from(
				theme,
				gui.ConnectDataStore.Content.Form.DataStoreScope.TextBox
			),

			orderedDataStoreTitle = LabelStyleState.from(
				theme,
				gui.ConnectDataStore.Content.Form.IsOrderedDataStore.Title
			),
			orderedDataStoreCheckbox = CheckboxStyleState.from(
				theme,
				gui.ConnectDataStore.Content.Form.IsOrderedDataStore.Check
			),

			separators = SeparatorStyleState.fromDescendants(theme, gui.ConnectDataStore),

			loadMore = LoadMoreListStyleState.from(theme, gui.ConnectDataStore.Content.DataStoreList.Table, {
				createItemStyleState = function(loadMoreListStyleState, info: DataStoreInfo)
					local button = Assets.DataStoreRow:Clone()
					button.DataStore.Text = info.DataStoreName
					button.Created.Text = DateTime.fromUnixTimestampMillis(info.CreatedTime)
						:FormatLocalTime("ll LT", "en-us")
					button.Updated.Text = DateTime.fromUnixTimestampMillis(info.UpdatedTime)
						:FormatLocalTime("ll LT", "en-us")

					button.Parent = loadMoreListStyleState.frame

					button.Activated:Connect(function()
						self._dataStoreInfoSelected:Fire(info)
					end)

					return ButtonStyleState.from(theme, button, {
						style = "transparent",
					})
				end,
			}),

			datastoreTableLabels = LabelStyleState.fromDescendants(theme, gui.ConnectDataStore.Content.DataStoreList),
		},
		browse = {
			scrollingFrame = ScrollingFrameStyleState.from(theme, gui.BrowseKeys.Keys),
			key = ShortcutsTextBoxStyleState.from(theme, gui.BrowseKeys.Key),

			separators = SeparatorStyleState.fromDescendants(theme, gui.BrowseKeys),

			prefix = ShortcutsTextBoxStyleState.from(theme, gui.BrowseKeys.Prefix),
			listButton = ButtonStyleState.from(theme, gui.BrowseKeys.List, {
				style = "primary",
			}),
			loadMore = LoadMoreListStyleState.from(theme, gui.BrowseKeys.Keys.Table, {
				createItemStyleState = function(loadMoreListStyleState, info: DataStoreKey)
					local button = Assets.KeyRow:Clone()
					local styleState = ButtonStyleState.from(theme, button, {
						style = "transparent",
					})
					button.Key.Text = info.KeyName

					button.Parent = loadMoreListStyleState.frame

					button.Activated:Connect(function()
						self._keySelected:Fire(info)
					end)

					button.MouseButton2Click:Connect(function()
						local resetSelecting = loadMoreListStyleState:setSelectingStyleState(styleState)
						local option = ContextMenuStyleState.prompt(
							self.theme,
							self.parent,
							self.parent:GetRelativeMousePosition(),
							{
								options = {
									{ icon = self.theme.icons.import, text = "Load" },
									{ icon = self.theme.icons.lookup, text = "Lookup Id" },
									{ icon = self.theme.icons.delete, text = "Delete" },
									ContextMenuStyleState.SEPARATOR,
									{ icon = self.theme.icons.externalLink, text = "Open in New Widget" },
								},
							}
						)
						resetSelecting()

						if option == "Load" then
							self.styleStates.browse.key.textBox.Text = info.KeyName:gsub("@", "\\@")
							self.styleStates.browse.key.textBox:CaptureFocus()
						elseif option == "Lookup Id" then
							self._idLookedUp:Fire(info)
						elseif option == "Delete" then
							self._keyDeleted:Fire(info)
						elseif option == "Open in New Widget" then
							self._keySelected:Fire(info, true)
						end
					end)

					return styleState, info.KeyName
				end,
			}),

			separator = SeparatorStyleState.from(theme, gui.BrowseKeys.Separator),

			datastoreTableLabels = LabelStyleState.fromDescendants(theme, gui.BrowseKeys.Keys),
		},
	}

	-- Views

	Assets.Views.EditKey:Clone().Parent = gui

	self.orderedDataStoreView = OrderedDataStoreView.from(theme, uiMessages, gui.EditOrderedDataStore)
	self.settingsView = SettingsView.from(theme, uiMessages, gui.Settings)

	showShadowOnScroll(gui.BrowseKeys.Keys, gui.BrowseKeys.ScrollShadow)

	-- Extra setting up
	self.styleStates.connect.tabs:select("Connect")
	self:switchConnectTab("connect")

	-- Hack to get AutomaticSize to not mess up since the overlay textlabel messes with that
	-- This also causes the overlay text label to not render when the user has typed a lot of text and is far from its origin
	self.styleStates.connect.dataStoreNameTextBox.overlay:GetPropertyChangedSignal("Size"):Connect(function(size)
		if self.styleStates.connect.dataStoreNameTextBox.overlay.Size.X.Scale ~= 1 then
			self.styleStates.connect.dataStoreNameTextBox.overlay.Size = UDim2.fromScale(1, 1)
		end
	end)
	self.styleStates.connect.dataStoreScopeTextBox.overlay:GetPropertyChangedSignal("Size"):Connect(function(size)
		if self.styleStates.connect.dataStoreScopeTextBox.overlay.Size.X.Scale ~= 1 then
			self.styleStates.connect.dataStoreScopeTextBox.overlay.Size = UDim2.fromScale(1, 1)
		end
	end)

	-- Tab switch groups

	createTabSwitchGroup({
		self.styleStates.connect.dataStoreNameTextBox.textBox,
		self.styleStates.connect.dataStoreScopeTextBox.textBox,
	})

	createTabSwitchGroup({
		self.styleStates.browse.key.textBox,
		self.styleStates.browse.prefix.textBox,
	})

	-- Add tooltips to everything

	Tooltip.bind(self.theme, self.gui.SettingsButton, "Settings", {
		on = self.gui.SettingsButton.ImageLabel,
		offsetAnchor = Vector2.new(1, 1),
		tooltipAnchor = Vector2.new(1, 0),
	})

	Tooltip.bindButtonGeneric(
		self.theme,
		self.gui.ConnectDataStore.Content.Form.Connect.Connect,
		`This is equivalent to a call to {rfmt.code("GetDataStore")}`
	)

	-- MouseButton1 event doesn't trigger on textboxes
	--[[Tooltip.bind(self.gui, self.gui.ConnectDataStore.Content.Form.Prefix.TextBox,
		"Prefix",
		"List only DataStores that begin with a certain prefix.")]]
	Tooltip.bindButtonGeneric(
		self.theme,
		self.gui.ConnectDataStore.Content.Form.Prefix.List,
		`List all DataStores in this game. Does not include OrderedDataStores. This is equivalent to a call to {rfmt.code(
			"ListDataStoresAsync"
		)}.`
	)

	-- MouseButton1 event doesn't trigger on textboxes
	--Tooltip.bind(self.gui, self.gui.BrowseKeys.Key, "Get Key", "Equivalent to a call to GetAsync.")
	Tooltip.bindButtonGeneric(
		self.theme,
		self.gui.BrowseKeys.List,
		`List all keys in the DataStore. Equivalent to a call to {rfmt.code("ListKeysAsync")}.`
	)

	-- Events

	self._dataStoreInfoSelected = Instance.new("BindableEvent")
	self.dataStoreInfoSelected = self._dataStoreInfoSelected.Event

	self._keySelected = Instance.new("BindableEvent")
	self.keySelected = self._keySelected.Event

	self._idLookedUp = Instance.new("BindableEvent")
	self.idLookedUp = self._idLookedUp.Event

	-- Fired when a key is deleted from the list
	self._keyDeleted = Instance.new("BindableEvent")
	self.keyDeleted = self._keyDeleted.Event

	self._connectionRecordSelected = Instance.new("BindableEvent")
	self._connectionRecordDeleted = Instance.new("BindableEvent")
	self._connectionRecordPinChanged = Instance.new("BindableEvent")
	self._connectionRecordLoaded = Instance.new("BindableEvent")
	self.connectionRecordSelected = self._connectionRecordSelected.Event
	self.connectionRecordDeleted = self._connectionRecordDeleted.Event
	self.connectionRecordPinChanged = self._connectionRecordPinChanged.Event
	self.connnectionRecordLoaded = self._connectionRecordLoaded.Event

	self._connectionRecordStyleStates = {}

	table.insert(
		self.connections,
		theme.colorsChanged:Connect(function()
			task.wait()
			StyleStateHelper.update(self.styleStates, "slow")

			for _, connectionRecordStyleStates in self._connectionRecordStyleStates do
				connectionRecordStyleStates:update("slow")
			end
		end)
	)

	return self
end

function UI:setParent(parent: LayerCollector)
	self.gui.Parent = parent
	self.parent = parent
end

function UI:setActiveView(view: "game" | "datastore" | "key" | "orderedDatastore" | "settings")
	if self.activeView == "settings" and view ~= "settings" then
		self.settingsView:afterClose()
	elseif self.activeView ~= "settings" and view == "settings" then
		self.settingsView:beforeOpen()
	end

	self.activeView = view
	local frames = {
		game = self.gui.ConnectDataStore,
		orderedDatastore = self.gui.EditOrderedDataStore,
		settings = self.gui.Settings,
		datastore = self.gui.BrowseKeys,
		key = self.gui.EditKey,
	}
	for name, frame in frames do
		frame.Visible = (name == view)
	end

	self:autoFocus()

	if view == "game" then
		-- Window might've resized, so update this if it's too small to do center alignment
		self:_updateConnectCentering()
	end
end

function UI:autoFocus()
	-- Delay to ignore the key press if enter was pressed
	task.delay(0, function()
		if self.parent and self.parent.Enabled then
			if self.activeView == "game" then
				if self.styleStates.connect.tabs:isSelecting("connect") then
					self.styleStates.connect.dataStoreNameTextBox.textBox:CaptureFocus()
				elseif self.styleStates.connect.tabs:isSelecting("list") then
					self.styleStates.connect.prefix.textBox:CaptureFocus()
				end
			elseif self.activeView == "datastore" then
				self.styleStates.browse.key.textBox:CaptureFocus()
			elseif self.activeView == "orderedDatastore" then
				self.orderedDataStoreView.styleStates.getKey.textBox:CaptureFocus()
			end
		end
	end)
end

function UI:updateSettingsButtonPosition()
	if self.gui.Settings.Visible or self.gui.Breadcrumbs.Visible then
		self.styleStates.settingsButton.button.Parent = self.gui
		self.styleStates.settingsButton.button.Position = UDim2.new(1, -4, 0, 3)
	else
		self.styleStates.settingsButton.button.Parent =
			self.gui.ConnectDataStore.Content["Put settings button here when breadcrumbs is disabled"]
		self.styleStates.settingsButton.button.Position = UDim2.new(1, -2, 0, 6)
	end
end

local BODY_FRAMES = { "BrowseKeys", "ConnectDataStore", "EditKey", "EditOrderedDataStore" }
function UI:showBreadcrumbs()
	if self.gui.Breadcrumbs.Visible then
		return
	end

	self.gui.Breadcrumbs.Visible = true
	self.gui.HeaderBackground.Visible = true
	self.gui.BreadcrumbsSeparator.Visible = true

	self:updateSettingsButtonPosition()

	for _, frame in BODY_FRAMES do
		self.gui[frame].Size = UDim2.new(1, 0, 1, -34)
		self.gui[frame].Position = UDim2.fromOffset(0, 34)
	end
end

function UI:hideBreadcrumbs()
	if not self.gui.Breadcrumbs.Visible then
		return
	end

	self.gui.Breadcrumbs.Visible = false
	self.gui.HeaderBackground.Visible = false
	self.gui.BreadcrumbsSeparator.Visible = false

	self:updateSettingsButtonPosition()

	for _, frame in BODY_FRAMES do
		self.gui[frame].Size = UDim2.new(1, 0, 1, 0)
		self.gui[frame].Position = UDim2.fromOffset(0, 0)
	end
end

function UI:updateBreadcrumbsVisibility()
	if #self.styleStates.breadcrumbs.crumbs > 1 then
		self:showBreadcrumbs()
	else
		self:hideBreadcrumbs()
	end
end

function UI:_updateConnectCentering()
	if
		(
			self.gui.ConnectDataStore.Content.DataStoreList.Visible
			and self.gui.ConnectDataStore.Content.DataStoreList.Table.Visible
			and self.styleStates.connect.tabs:isSelecting("list")
		) or (self.styleStates.connect.tabs:isSelecting("history"))
	then
		self.gui.ConnectDataStore.Content.UIListLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
		self.gui.ConnectDataStore.Content.UIListLayout.VerticalAlignment = Enum.VerticalAlignment.Top
	else
		self.gui.ConnectDataStore.Content.UIListLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		self.gui.ConnectDataStore.Content.UIListLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	end

	-- Gui too small for center aligment
	if self.gui.AbsoluteSize.X <= 360 then
		self.gui.ConnectDataStore.Content.UIListLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	end
end

function UI:switchConnectTab(tab: "connect" | "list" | "history")
	local connectVisible = (tab == "connect")
	local listVisible = (tab == "list")
	local historyVisible = (tab == "history")

	self.gui.ConnectDataStore.Content.Form.Connect.Visible = connectVisible
	self.gui.ConnectDataStore.Content.Form.DataStoreName.Visible = connectVisible
	self.gui.ConnectDataStore.Content.Form.DataStoreScope.Visible = connectVisible
	self.gui.ConnectDataStore.Content.Form.IsOrderedDataStore.Visible = connectVisible

	self.gui.ConnectDataStore.Content.Form.Prefix.Visible = listVisible
	self.gui.ConnectDataStore.Content.DataStoreList.Visible = listVisible

	self.gui.ConnectDataStore.Content.History.Visible = historyVisible

	self:_updateConnectCentering()
end

function UI:updateHistoryTabVisible(visible: boolean)
	self.styleStates.connect.tabs.frame.History.Visible = visible
	if not visible then
		if self.styleStates.connect.tabs:isSelecting("history") then
			self.styleStates.connect.tabs:select("Connect")
		end
	end
end

-- Returns a style state that starts off with a skeleton
-- Call :populate on this styleState to populate it with info
-- Call :abort to delete the styleState
-- Automatically handles destruction on the UI side
function UI:createUserCard()
	local card = Assets.Cards.UserCard:Clone()
	local skeletonStyleState = SkeletonStyleState.from(self.theme, card)
	local styleState = StyleStateWrapper.new(self.theme, {
		background = BackgroundStyleState.from(self.theme, card, {
			style = "popup",
		}),
		imageBackground = BackgroundStyleState.from(self.theme, card.ImageLabel, {
			style = "image",
		}),
		username = LabelStyleState.from(self.theme, card.Frame.Username),
		id = LabelStyleState.from(self.theme, card.Frame.Id),
		displayName = LabelStyleState.from(self.theme, card.Frame.DisplayName),
		verifiedBadge = LabelStyleState.from(self.theme, card.Frame.VerifiedBadge),
		skeletonStyleState = skeletonStyleState,
	})
	task.defer(function()
		skeletonStyleState:update("instant")
		skeletonStyleState:animate()
	end)

	local modal = PopupHelper.modal(card, self.gui.Parent)

	local function cleanup()
		if card.Parent then
			modal:destroy()
			styleState:destroy()
			skeletonStyleState:destroy()
			card:Destroy()
		end
	end

	modal.cancelled:Once(cleanup)

	function styleState:abort()
		cleanup()
	end

	function styleState:populate(
		thumbnailUrl: string,
		info: {
			Id: number,
			Username: string,
			DisplayName: string,
			HasVerifiedBadge: boolean,
		}
	)
		if card.Parent then
			skeletonStyleState:destroy()
			styleState.styleStates.imageBackground:update("instant")
			card.ImageLabel.Image = thumbnailUrl
			card.Frame.Username.Text = `@{info.Username}`
			card.Frame.Id.Text = `User Id: {info.Id}`
			card.Frame.DisplayName.Text = `Display Name: {info.DisplayName}`
			card.Frame.VerifiedBadge.Text = `Has Verified Badge: {info.HasVerifiedBadge}`
		end
	end

	return styleState
end

function UI:destroy()
	for _, connection in self.connections do
		connection:Disconnect()
	end
	for _, styleStates in self._connectionRecordStyleStates do
		styleStates:destroy(true)
	end
	self._connectionRecordStyleStates = nil

	self.settingsView:destroy()
	self.orderedDataStoreView:destroy()
end

export type UI = typeof(UI.new(Theme.global))
return UI
