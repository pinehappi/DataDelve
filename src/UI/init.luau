local rfmt = require(script.Parent.rfmt)

local Types = require(script.Parent.Types)
local Theme = require(script.Theme)

local PopupHelper = require(script.PopupHelper)
local Tooltip = require(script.Tooltip)

local Assets = script.Assets
local StyleState = script.StyleState

local StyleStateWrapper = require(StyleState.StyleStateWrapper)
local StyleStateHelper = require(StyleState.StyleStateHelper)

local BackgroundStyleState = require(StyleState.BackgroundStyleState)
local BreadcrumbsStyleState = require(StyleState.BreadcrumbsStyleState)
local ButtonStyleState = require(StyleState.ButtonStyleState)
local SeparatorStyleState = require(StyleState.SeparatorStyleState)
local LabelStyleState = require(StyleState.LabelStyleState)
local LoadMoreListStyleState = require(StyleState.LoadMoreListStyleState)
local TabsStyleState = require(StyleState.TabsStyleState)

local CheckboxStyleState = require(StyleState.Input.CheckboxStyleState)
local TextBoxStyleState = require(StyleState.Input.TextBoxStyleState)
local ShortcutsTextBoxStyleState = require(StyleState.Input.ShortcutsTextBoxStyleState)

local SkeletonStyleState = require(StyleState.Utility.SkeletonStyleState)
local ContextMenuStyleState = require(StyleState.Utility.ContextMenuStyleState)

local OrderedDataStoreView = require(script.OrderedDataStoreView)
local SettingsView = require(script.SettingsView)
local VersionsView = require(script.VersionsView)

local UI = {}
UI.__index = UI

function UI.new(theme: Theme.Theme, uiMessages)
	local gui = Assets.Widget:Clone()
	local self = setmetatable({
		theme = theme,
		parent = nil,
		gui = gui,
		uiMessages = uiMessages,
		
		connections = {},
		
		activeView = nil,
	}, UI)
	
	self.styleStates = {
		background = BackgroundStyleState.from(theme, gui.Background),
		breadcrumbs = BreadcrumbsStyleState.from(theme, gui.Breadcrumbs),
		breadcrumbsSeparator = SeparatorStyleState.from(theme, gui.BreadcrumbsSeparator),
		settingsButton = ButtonStyleState.from(theme, gui.SettingsButton, {
			style = "dormant"
		}),
		
		connect = {
			tabs = TabsStyleState.from(theme, gui.ConnectDataStore.Content.Form.Tabs),

			prefix = ShortcutsTextBoxStyleState.from(theme, gui.ConnectDataStore.Content.Form.Prefix.TextBox),
			listButton = ButtonStyleState.from(theme, gui.ConnectDataStore.Content.Form.Prefix.List, {
				style = "primary"
			}),

			connectButton = ButtonStyleState.from(theme, gui.ConnectDataStore.Content.Form.Connect.Connect, {
				style = "primary"
			}),
			dataStoreNameTitle = LabelStyleState.from(theme, gui.ConnectDataStore.Content.Form.DataStoreName.Title),
			dataStoreNameTextBox = ShortcutsTextBoxStyleState.from(theme, gui.ConnectDataStore.Content.Form.DataStoreName.TextBox),

			dataStoreScopeTitle = LabelStyleState.from(theme, gui.ConnectDataStore.Content.Form.DataStoreScope.Title),
			dataStoreScopeTextBox = ShortcutsTextBoxStyleState.from(theme, gui.ConnectDataStore.Content.Form.DataStoreScope.TextBox),

			orderedDataStoreTitle = LabelStyleState.from(theme, gui.ConnectDataStore.Content.Form.IsOrderedDataStore.Title),
			orderedDataStoreCheckbox = CheckboxStyleState.from(theme, gui.ConnectDataStore.Content.Form.IsOrderedDataStore.Check),

			separators = SeparatorStyleState.fromDescendants(theme, gui.ConnectDataStore),

			loadMore = LoadMoreListStyleState.from(theme, gui.ConnectDataStore.Content.DataStoreList.Table, {
				createItemStyleState = function(loadMoreListStyleState, info: DataStoreInfo)
					local button = Assets.DataStoreRow:Clone()
					button.DataStore.Text = info.DataStoreName
					button.Created.Text = DateTime.fromUnixTimestampMillis(info.CreatedTime):FormatLocalTime("ll LT", "en-us")
					button.Updated.Text = DateTime.fromUnixTimestampMillis(info.UpdatedTime):FormatLocalTime("ll LT", "en-us")
					
					button.Parent = loadMoreListStyleState.frame
					
					button.Activated:Connect(function()
						self._dataStoreInfoSelected:Fire(info)
					end)
					
					return ButtonStyleState.from(theme, button, {
						style = "transparent"
					})
				end,
			}),
			
			datastoreTableLabels = LabelStyleState.fromDescendants(theme, gui.ConnectDataStore.Content.DataStoreList),
			historyTableLabels = LabelStyleState.fromDescendants(theme, gui.ConnectDataStore.Content.History)
		},
		browse = {
			key = ShortcutsTextBoxStyleState.from(theme, gui.BrowseKeys.Key),
			
			separators = SeparatorStyleState.fromDescendants(theme, gui.BrowseKeys),
			
			prefix = ShortcutsTextBoxStyleState.from(theme, gui.BrowseKeys.Prefix),
			listButton = ButtonStyleState.from(theme, gui.BrowseKeys.List, {
				style = "primary"
			}),
			loadMore = LoadMoreListStyleState.from(theme, gui.BrowseKeys.Keys.Table, {
				createItemStyleState = function(loadMoreListStyleState, info: DataStoreKey)
					local button = Assets.KeyRow:Clone()
					local styleState = ButtonStyleState.from(theme, button, {
						style = "transparent"
					})
					button.Key.Text = info.KeyName

					button.Parent = loadMoreListStyleState.frame

					button.Activated:Connect(function()
						self._keySelected:Fire(info)
					end)
					
					button.MouseButton2Click:Connect(function()
						loadMoreListStyleState:setSelectingStyleState(styleState)
						local option = ContextMenuStyleState.prompt(self.theme, self.parent, self.parent:GetRelativeMousePosition(), {
							options = {
								{ icon=self.theme.icons.import, text="Load" },
								{ icon=self.theme.icons.lookup, text="Lookup Id" },
							}
						})
						loadMoreListStyleState:setSelectingStyleState(nil)

						if option == "Load" then
							self.styleStates.browse.key.textBox.Text = info.KeyName:gsub("@", "\\@")
							self.styleStates.browse.key.textBox:CaptureFocus()
						elseif option == "Lookup Id" then
							self._idLookedUp:Fire(info.KeyName)
						end
					end)

					return styleState
				end,
			}),
			
			separator = SeparatorStyleState.from(theme, gui.BrowseKeys.Separator),
			
			datastoreTableLabels = LabelStyleState.fromDescendants(theme, gui.BrowseKeys.Keys)
		},
		edit = {
			delete = ButtonStyleState.from(theme, gui.EditKey.Delete, {
				style = "secondary",
			}),
			save = ButtonStyleState.from(theme, gui.EditKey.Save, {
				style = "primary",
			}),
			refresh = ButtonStyleState.from(theme, gui.EditKey.Refresh, {
				style = "secondary",
			}),
			more = ButtonStyleState.from(theme, gui.EditKey.More, {
				style = "transparent"
			}),
			
			versions = ButtonStyleState.from(theme, gui.EditKey.Versions, {
				style = "secondary"
			})
		},
	}
	
	self.orderedDataStoreView = OrderedDataStoreView.from(theme, uiMessages, gui.EditOrderedDataStore)
	self.settingsView = SettingsView.from(theme, uiMessages, gui.Settings)
	self.versionsView = VersionsView.from(theme, uiMessages, gui.Versions)
	
	self.styleStates.edit.save:setDisabled(true):update()
	
	self.styleStates.connect.tabs:select("Connect")
	self:switchConnectTab("connect")
	
	self._dataStoreInfoSelected = Instance.new("BindableEvent")
	self.dataStoreInfoSelected = self._dataStoreInfoSelected.Event
	 
	self._keySelected = Instance.new("BindableEvent")
	self.keySelected = self._keySelected.Event
	
	self._idLookedUp = Instance.new("BindableEvent")
	self.idLookedUp = self._idLookedUp.Event
	
	self._connectionRecordSelected = Instance.new("BindableEvent")
	self._connectionRecordDeleted = Instance.new("BindableEvent")
	self._connectionRecordPinChanged = Instance.new("BindableEvent")
	self._connectionRecordLoaded = Instance.new("BindableEvent")
	self.connectionRecordSelected = self._connectionRecordSelected.Event
	self.connectionRecordDeleted = self._connectionRecordDeleted.Event
	self.connectionRecordPinChanged = self._connectionRecordPinChanged.Event
	self.connnectionRecordLoaded = self._connectionRecordLoaded.Event
		
	self._connectionRecordStyleStates = {}
	
	table.insert(self.connections, theme.colorsChanged:Connect(function()
		task.wait()
		StyleStateHelper.update(self.styleStates)
		
		for _, connectionRecordStyleStates in self._connectionRecordStyleStates do
			connectionRecordStyleStates:update("slow")
		end
	end))
	
	-- Add tooltips to everything
	
	Tooltip.bind(self.theme, self.gui.SettingsButton, "Settings", {
		on = self.gui.SettingsButton.ImageLabel,
		offsetAnchor = Vector2.new(1, 1),
		tooltipAnchor = Vector2.new(1, 0),
	})
	
	Tooltip.bindButtonGeneric(self.theme, self.gui.ConnectDataStore.Content.Form.Connect.Connect, `This is equivalent to a call to {rfmt.code("GetDataStore")}`)
	
	-- MouseButton1 event doesn't trigger on textboxes
	--[[Tooltip.bind(self.gui, self.gui.ConnectDataStore.Content.Form.Prefix.TextBox,
		"Prefix",
		"List only DataStores that begin with a certain prefix.")]]
	Tooltip.bindButtonGeneric(
		self.theme,
		self.gui.ConnectDataStore.Content.Form.Prefix.List,
		`List all DataStores in this game. Does not include OrderedDataStores. This is equivalent to a call to {rfmt.code("ListDataStoresAsync")}.`
	)
	
	-- MouseButton1 event doesn't trigger on textboxes
	--Tooltip.bind(self.gui, self.gui.BrowseKeys.Key, "Get Key", "Equivalent to a call to GetAsync.")
	Tooltip.bindButtonGeneric(self.theme, self.gui.BrowseKeys.List, `List all keys in the DataStore. Equivalent to a call to {rfmt.code("ListKeysAsync")}.`)
	
	Tooltip.bindButtonGeneric(self.theme, self.gui.EditKey.Versions, `Equivalent to {rfmt.code("ListVersionsAsync")}.`)
	Tooltip.bindButtonGeneric(self.theme, self.gui.EditKey.Save, `Save\nEquivalent to {rfmt.code("UpdateAsync")}.`)
	Tooltip.bindButtonGeneric(self.theme, self.gui.EditKey.Refresh, `Refresh\nEquivalent to {rfmt.code("GetAsync")}.`)
	Tooltip.bindButtonGeneric(self.theme, self.gui.EditKey.Delete, `Delete\nEquivalent to {rfmt.code("RemoveAsync")}.`)
	
	
	return self
end

function UI:setParent(parent: LayerCollectorer)
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
		key = self.gui.EditKey
	}
	for name, frame in frames do
		frame.Visible = (name == view)
	end
	
	self:autoFocus()
end

function UI:autoFocus()
	-- Delay to ignore the key press if enter was pressed
	task.delay(0, function()
		if self.parent and self.parent.Enabled then
			if self.activeView == "game" then
				if self.styleStates.connect.tabs.selecting:lower() == "connect" then
					self.styleStates.connect.dataStoreNameTextBox.textBox:CaptureFocus()
				elseif self.styleStates.connect.tabs.selecting:lower() == "list" then
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
		self.styleStates.settingsButton.button.Position = UDim2.new(1, -12, 0, 10)
	end
end

function UI:showBreadcrumbs()
	if self.gui.Breadcrumbs.Visible then return end
	
	self.gui.Breadcrumbs.Visible = true
	self.gui.BreadcrumbsSeparator.Visible = true
	
	self:updateSettingsButtonPosition()
	
	for _, frame in {"BrowseKeys", "ConnectDataStore", "EditKey", "EditOrderedDataStore"} do
		self.gui[frame].Size = UDim2.new(1, 0, 1, -34)
		self.gui[frame].Position = UDim2.fromOffset(0, 34)
	end
end

function UI:hideBreadcrumbs()
	if not self.gui.Breadcrumbs.Visible then return end

	self.gui.Breadcrumbs.Visible = false
	self.gui.BreadcrumbsSeparator.Visible = false
	
	self:updateSettingsButtonPosition()
	
	for _, frame in {"BrowseKeys", "ConnectDataStore", "EditKey"} do
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
	if self.gui.ConnectDataStore.Content.History.Visible then
		self.gui.ConnectDataStore.Content.UIListLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
		self.gui.ConnectDataStore.Content.UIListLayout.VerticalAlignment = Enum.VerticalAlignment.Top
	else
		if
			self.gui.ConnectDataStore.Content.DataStoreList.Visible
			and self.gui.ConnectDataStore.Content.DataStoreList.Table.Visible
			and self.styleStates.connect.tabs.selecting == "list"
		then
			self.gui.ConnectDataStore.Content.UIListLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
			self.gui.ConnectDataStore.Content.UIListLayout.VerticalAlignment = Enum.VerticalAlignment.Top
		else
			self.gui.ConnectDataStore.Content.UIListLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
			self.gui.ConnectDataStore.Content.UIListLayout.VerticalAlignment = Enum.VerticalAlignment.Center
		end
	end
end

function UI:switchConnectTab(tab: "connect" | "list")
	local connectVisible = (tab == "connect")
	
	self.gui.ConnectDataStore.Content.Form.Connect.Visible = connectVisible
	self.gui.ConnectDataStore.Content.Form.DataStoreName.Visible = connectVisible
	self.gui.ConnectDataStore.Content.Form.DataStoreScope.Visible = connectVisible
	self.gui.ConnectDataStore.Content.Form.IsOrderedDataStore.Visible = connectVisible
	
	self.gui.ConnectDataStore.Content.Form.Prefix.Visible = not connectVisible
	self.gui.ConnectDataStore.Content.DataStoreList.Visible = not connectVisible
	self:_updateConnectCentering()
end

local function updateConnectionRowPinVisual(row, theme, pinned: boolean)
	if pinned then
		if not row:FindFirstChild("ConnectionRowPinIcon") then
			local icon = Assets.ConnectionRowPinIcon:Clone()
			icon.Parent = row
			icon.ImageColor3 = theme.colors.text
		end
		row.DataStore.Position = UDim2.new(0, 20, 0, 0)
		row.DataStore.Size = UDim2.new(0.5, -20, 1, 0)
	else
		local icon = row:FindFirstChild("ConnectionRowPinIcon")
		if icon then
			icon:Destroy()
		end
		row.DataStore.Position = UDim2.new(0, 0, 0, 0)
		row.DataStore.Size = UDim2.new(0.5, 0, 1, 0)
	end
end

function UI:updateConnectionsHistory(records: {Types.DataStoreConnectionRecord})
	local isVisible = (#records > 0)
	self.gui.ConnectDataStore.Content.Separator.Visible = isVisible
	self.gui.ConnectDataStore.Content.History.Visible = isVisible
	
	self:_updateConnectCentering()
	
	for _, v in self._connectionRecordStyleStates do
		v:destroy(true)
	end
	self._connectionRecordStyleStates = {}
	
	for _, record in records do
		local row = Assets.ConnectionRow:Clone()
		if record.connection.scope and record.connection.scope ~= "" then
			row.DataStore.Text = `{record.connection.scope}/{record.connection.name}`
		else
			row.DataStore.Text = record.connection.name
		end
		row.ConnectionType.Text =
			if record.connection.allScopes then "AllScopes"
			elseif record.connection.isOrdered then "Ordered"
			else "Normal"
		row.LastAccess.Text = DateTime.fromUnixTimestamp(record.lastAccess):FormatUniversalTime("ll LT", "en-us")
		row.LayoutOrder =
			if record.pinned then 0
			else 1
		updateConnectionRowPinVisual(row, self.theme, record.pinned)
		row.Parent = self.gui.ConnectDataStore.Content.History.Table
		
		local styleState = ButtonStyleState.from(self.theme, row, {
			style = "transparent"
		})
		
		table.insert(self._connectionRecordStyleStates, styleState)
		
		row.Activated:Connect(function()
			self._connectionRecordSelected:Fire(record)
		end)
		row.MouseButton2Click:Connect(function()
			styleState:setSelecting(true):update()
			local option = ContextMenuStyleState.prompt(self.theme, self.parent, self.parent:GetRelativeMousePosition(), {
				options = {
					if record.pinned then { icon=self.theme.icons.unpin, text="Unpin" }
						else { icon=self.theme.icons.pin, text="Pin" },
					{ icon=self.theme.icons.import, text="Load" },
					{ icon=self.theme.icons.delete, text="Delete" },
				}
			})
			styleState:setSelecting(false):update()
			
			if option == "Delete" then
				self._connectionRecordDeleted:Fire(record)
			elseif option == "Load" then
				self._connectionRecordLoaded:Fire(record)
			elseif option == "Pin" then
				self._connectionRecordPinChanged:Fire(record, true)
			elseif option == "Unpin" then
				self._connectionRecordPinChanged:Fire(record, false)
			end
		end)
	end
end

-- Returns a style state that starts off with a skeleton
-- Call :populate on this styleState to populate it with info
-- Call :abort to delete the styleState
-- Automatically handles destruction on the UI side
function UI:createUserCard()
	local card = Assets.UserCard:Clone()
	local skeletonStyleState = SkeletonStyleState.from(self.theme, card)
	local styleState = StyleStateWrapper.new(self.theme, {
		background = BackgroundStyleState.from(self.theme, card, {
			style = "popup"
		}),
		imageBackground = BackgroundStyleState.from(self.theme, card.ImageLabel, {
			style = "image"
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
	
	local modal = PopupHelper.modal(card, self.gui)
	
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
	
	function styleState:populate(thumbnailUrl: string, info: {
		Id: number,
		Username: string,
		DisplayName: string,
		HasVerifiedBadge: boolean,
	})
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

local KEY_MAX_SIZE = 4_194_304
local METADATA_MAX_SIZE = 299
function UI:createDataUsageCard(keyUsage: number, metadataUsage: number)
	local card = Assets.DataUsageCard:Clone()
	
	local function updateBarColor(speed: StyleStateHelper.TransitionSpeed)
		StyleStateHelper.tween(card.KeyBar, StyleStateHelper.getTweenInfoForSpeed(speed), {
			BackgroundColor3 = self.theme.colors.button.secondary.body.default,
		})
		StyleStateHelper.tween(card.KeyBar.UIStroke, StyleStateHelper.getTweenInfoForSpeed(speed), {
			Color = self.theme.colors.button.secondary.outline.default,
		})
		StyleStateHelper.tween(card.KeyBar.Clipper.Fill, StyleStateHelper.getTweenInfoForSpeed(speed), {
			BackgroundColor3 = self.theme.colors.mainAccent,
		})
		
		StyleStateHelper.tween(card.MetadataBar, StyleStateHelper.getTweenInfoForSpeed(speed), {
			BackgroundColor3 = self.theme.colors.button.secondary.body.default,
		})
		StyleStateHelper.tween(card.MetadataBar.UIStroke, StyleStateHelper.getTweenInfoForSpeed(speed), {
			Color = self.theme.colors.button.secondary.outline.default,
		})
		StyleStateHelper.tween(card.MetadataBar.Clipper.Fill, StyleStateHelper.getTweenInfoForSpeed(speed), {
			BackgroundColor3 = self.theme.colors.mainAccent,
		})
	end
	
	updateBarColor("instant")
	
	local wrapper = StyleStateWrapper.new(self.theme, {
		background = BackgroundStyleState.from(self.theme, card, { style="popup" }),
		mainTitle = LabelStyleState.from(self.theme, card.MainTitle),
		dataLabel = LabelStyleState.from(self.theme, card.KeyLabel, { style=if keyUsage > KEY_MAX_SIZE then "error" else "text" }),
		metadataTitle = LabelStyleState.from(self.theme, card.MetadataTitle),
		metadataLabel = LabelStyleState.from(self.theme, card.MetadataLabel, { style=if metadataUsage > METADATA_MAX_SIZE then "error" else "text" }),
	}, {
		onThemeChange = function()
			updateBarColor("slow")
		end,
	})
	
	local function updateBar(usage: number, max: number, label, bar)
		if usage == 0 then
			bar.Clipper.Size = UDim2.fromScale(0, 1)
		else
			local percentage = math.min(1, usage / max)
			local tweenInfo = TweenInfo.new(1.5, Enum.EasingStyle.Quart)
			bar.Clipper.Size = UDim2.fromScale(0, 1)
			bar.Clipper.Fill.Size = UDim2.fromScale(0, 1)
			StyleStateHelper.tween(bar.Clipper, tweenInfo, {
				Size = UDim2.fromScale(percentage, 1)
			})
			StyleStateHelper.tween(bar.Clipper.Fill, tweenInfo, {
				Size = UDim2.fromScale(1 / percentage, 1)
			})
		end
		
		label.Text =
			`{tostring(usage):reverse():gsub("(%d%d%d)", "%1,"):gsub(",$", ""):reverse()}/{tostring(max):reverse():gsub("(%d%d%d)", "%1,"):gsub(",$", ""):reverse()} bytes`
	end
	
	updateBar(keyUsage, KEY_MAX_SIZE, wrapper.styleStates.dataLabel.label, card.KeyBar)
	updateBar(metadataUsage, METADATA_MAX_SIZE, wrapper.styleStates.metadataLabel.label, card.MetadataBar)
	
	local modal = PopupHelper.modal(card, self.gui)
	
	local function cleanup()
		modal:destroy()
		wrapper:destroy()
		card:Destroy()
	end
	
	modal.cancelled:Once(cleanup)
	
	return card
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