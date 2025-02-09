local plugin = script:FindFirstAncestorWhichIsA("Plugin")

local Players = game:GetService("Players")
local ContentProvider = game:GetService("ContentProvider")
local UserService = game:GetService("UserService")
local MarketplaceService = game:GetService("MarketplaceService")
local HttpService = game:GetService("HttpService")

-- For crumbs
local GAME_ICON = { selected = "rbxassetid://18745845370", unselected = "rbxassetid://17650835923" }
local DATASTORE_ICON = { selected = "rbxassetid://18745840750", unselected = "rbxassetid://17650834077" }
local ORDERED_DATASTORE_ICON = { selected = "rbxassetid://18745847447", unselected = "rbxassetid://18467184552" }
local ALL_SCOPES_DATASTORE_ICON = { selected = "rbxassetid://18807229788", unselected = "rbxassetid://18807231111" }
local KEY_ICON = { selected = "rbxassetid://18745602938", unselected = "rbxassetid://17650831214" }

local rfmt = require(script.Parent.rfmt)
local Types = require(script.Parent.Types)

local Settings = require(script.Parent.Settings)
local Session = require(script.Parent.Session)
local History = require(script.Parent.History).global

local Tree = require(script.Parent.UI.Viewers.Tree)

local Validators = require(script.Parent.Validators)
local PopupHelper = require(script.Parent.UI.PopupHelper)
local Transactor = require(script.Parent.Transactor)

local StyleStateHelper = require(script.Parent.UI.StyleState.StyleStateHelper)
local LoadingBarStyleState = require(script.Parent.UI.StyleState.Utility.LoadingBarStyleState)
local ConfirmDialogStyleState = require(script.Parent.UI.StyleState.Utility.ConfirmDialogStyleState)
local ContextMenuStyleState = require(script.Parent.UI.StyleState.Utility.ContextMenuStyleState)

local SingleKeyWidget = require(script.Parent.UI.SingleKeyWidget)
local EditKeyView = require(script.Parent.UI.EditKeyView)

local Theme = require(script.Parent.UI.Theme).global
local UI = require(script.Parent.UI)
local UIMessages = require(script.Parent.UI.UIMessages)
local ExportImportHelper = require(script.Parent.ExportImportHelper)

local constraintTextBoxStyleState = require(script.Parent.UI.Utilities.constrainTextBoxStyleState)
local disableFrameWhenModalAppears = require(script.Parent.UI.Utilities.disableFrameWhenModalAppears)

local SETTINGS_TWEEN_INFO = TweenInfo.new(0.2, Enum.EasingStyle.Cubic)
local WIDGET_INFO = DockWidgetPluginGuiInfo.new(
	Enum.InitialDockState.Float, -- Widget will be initialized in floating panel
	false, -- Widget will be initially enabled
	false, -- Don't override the previous enabled state
	400, -- Default width of the floating window
	250, -- Default height of the floating window
	350, -- Minimum width of the floating window
	230 -- Minimum height of the floating window
)

local gameName = game.Name
local gameNameDiscovered = Instance.new("BindableEvent")
task.spawn(function()
	pcall(function()
		local discoveredName = MarketplaceService:GetProductInfo(game.PlaceId).Name
		if discoveredName then
			gameName = discoveredName
			gameNameDiscovered:Fire()
		end
	end)
end)

local App = {}
App.__index = App

function App.new(id: string)
	local uiMessages = UIMessages.new(Theme)
	local self = setmetatable({
		id = id,
		session = Session.new(),
		ui = UI.new(Theme, uiMessages),
		uiMessages = uiMessages,

		editKeyView = nil,
		viewer = nil,

		connections = {},

		_keyTransactor = Transactor.new(),

		_isListingKey = false,
		_isGettingKey = false,
		_isUpdatingKey = false,
	}, App)

	self.widget = plugin:CreateDockWidgetPluginGui(id, WIDGET_INFO)
	self.widget.Title = id
	self.widget.Name = id
	self.widget.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	self.ui:setParent(self.widget)
	self.uiMessages:setParent(self.widget)

	-- Breadcrumbs

	self.ui.styleStates.breadcrumbs.crumbChanged:Connect(function(crumb)
		self.ui:setActiveView(crumb.category)
		self.ui:updateBreadcrumbsVisibility()
	end)

	self.ui:hideBreadcrumbs()

	-- Connect form

	self:_updateConnectButton()
	self.ui.gui.ConnectDataStore.Content.Form.DataStoreName.TextBox:GetPropertyChangedSignal("Text"):Connect(function()
		self:_updateConnectButton()
	end)

	self.ui.styleStates.connect.dataStoreNameTextBox.textBox.FocusLost:Connect(function(entered, input)
		if input == nil then
			return
		end

		if entered then
			self:_submitConnectForm()
		end
	end)
	self.ui.styleStates.connect.dataStoreScopeTextBox.textBox.FocusLost:Connect(function(entered, input)
		if input == nil then
			return
		end

		if entered then
			self:_submitConnectForm()
		end
	end)

	constraintTextBoxStyleState(self.ui.styleStates.connect.dataStoreNameTextBox, { Validators.dataStoreName })
	constraintTextBoxStyleState(self.ui.styleStates.connect.dataStoreScopeTextBox, { Validators.dataStoreScope })

	self.ui.styleStates.connect.dataStoreNameTextBox.errorChanged:Connect(function()
		self:_updateConnectButton()
	end)
	self.ui.styleStates.connect.dataStoreScopeTextBox.errorChanged:Connect(function()
		self:_updateConnectButton()
	end)

	self.ui.gui.ConnectDataStore.Content.Form.Connect.Connect.Activated:Connect(function()
		self:_submitConnectForm()
	end)

	-- History

	self.ui:updateConnectionsHistory(History.connectionRecords)

	table.insert(self.connections, {
		History.connectionsChanged:Connect(function()
			self.ui:updateConnectionsHistory(History.connectionRecords)
		end),
	})

	self.ui.connectionRecordSelected:Connect(function(record: Types.DataStoreConnectionRecord)
		self:tryConnect(record.connection)
	end)
	self.ui.connectionRecordDeleted:Connect(function(record: Types.DataStoreConnectionRecord)
		History:removeConnectionRecord(record.connection)
	end)
	self.ui.connectionRecordPinChanged:Connect(function(record: Types.DataStoreConnectionRecord, pinned: boolean)
		if pinned then
			History:pinConnectionRecord(record.connection)
			self.uiMessages:success("Pinned connection.")
		else
			History:unpinConnectionRecord(record.connection)
			self.uiMessages:success("Unpinned connection.")
		end
	end)
	self.ui.connnectionRecordLoaded:Connect(function(record: Types.DataStoreConnectionRecord)
		self.ui.styleStates.connect.orderedDataStoreCheckbox:setValue(record.connection.isOrdered)
		self.ui.styleStates.connect.dataStoreNameTextBox.textBox.Text = record.connection.name
		self.ui.styleStates.connect.dataStoreScopeTextBox.textBox.Text = record.connection.scope or ""
		self.ui.styleStates.connect.tabs:select("Connect")
		self.ui.gui.ConnectDataStore.Content.CanvasPosition = Vector2.new(0, 0)
		self.uiMessages:success("Loaded connection.")
	end)

	-- DataStore listing

	self.ui.gui.ConnectDataStore.Content.DataStoreList.Table.LoadMore.Activated:Connect(function()
		if self.session.dataStorePages then
			if not self.session.dataStorePages.isFinished then
				local loadingBar = LoadingBarStyleState.from(
					Theme,
					self.ui.gui.ConnectDataStore.Content.DataStoreList.Table.LoadingBar
				)
				self.ui.gui.ConnectDataStore.Content.DataStoreList.Table.LoadingBar.Visible = true
				task.spawn(loadingBar.animate, loadingBar)

				self.ui.styleStates.connect.loadMore.buttonStyleState:setDisabled(true):update()
				local _, err = self.session.dataStorePages:increment()

				self.ui.styleStates.connect.loadMore.buttonStyleState:setDisabled(false):update()
				self.ui.gui.ConnectDataStore.Content.DataStoreList.Table.LoadingBar.Visible = false
				loadingBar:destroy()

				if err then
					self.uiMessages:reportDataStoreError(err)
					return
				end
			end
		end
	end)

	self.ui.dataStoreInfoSelected:Connect(function(info: DataStoreInfo)
		self:tryConnect({
			name = info.DataStoreName,
			scope = nil,
			isOrdered = false,
		})
	end)

	self.ui.gui.ConnectDataStore.Content.Form.Prefix.List.Activated:Connect(function()
		self:tryListDataStores()
	end)

	self.ui.gui.ConnectDataStore.Content.Form.Prefix.TextBox.FocusLost:Connect(function(enterPressed, input)
		if input == nil then
			return
		end
		if enterPressed then
			self:tryListDataStores()
		end
	end)

	-- Key Getting

	self.ui.styleStates.browse.key.textBox:GetPropertyChangedSignal("Text"):Connect(function()
		local text = self.ui.styleStates.browse.key.textBox.Text
		if #text == 0 then
			self.ui.styleStates.browse.key:setError(nil):update("veryFast")
		else
			local validator = if self.session.connection.allScopes
				then Validators.allScopesKey
				else Validators.dataStoreKey
			local valid, err = validator(text)
			if valid then
				self.ui.styleStates.browse.key:setError(nil):update("veryFast")
			else
				self.ui.styleStates.browse.key:setError(err):update("veryFast")
			end
		end
	end)

	self.ui.styleStates.browse.key.textBox.FocusLost:Connect(function(enterPressed, input)
		if input == nil then
			return
		end
		if not enterPressed then
			return
		end
		if not self.session then
			self.uiMessages:error("How are you on this page???")
			return
		end
		if self.ui.styleStates.browse.key.textBox.Text == "" then
			return
		end

		local loadingBar = LoadingBarStyleState.from(Theme, self.ui.styleStates.browse.key.textBox.LoadingBar)
		loadingBar.container.Visible = true
		self.ui.styleStates.browse.key:setDisabled(true):update()
		task.spawn(loadingBar.animate, loadingBar)

		local keyName = self.ui.styleStates.browse.key:getText(function(err: string)
			self.uiMessages:error(err)
		end)

		local success, err = self:_trySwapEditKeyView(keyName)

		loadingBar.container.Visible = false
		loadingBar:destroy()
		self.ui.styleStates.browse.key:setDisabled(false):update()

		if err then
			self.uiMessages:reportDataStoreError(err)
			return
		else
			self.ui.styleStates.browse.key.textBox.Text = ""
		end
	end)

	-- Key browsing

	self.ui.gui.BrowseKeys.Keys.Table.LoadMore.Activated:Connect(function()
		if self.session.keyPages then
			if not self.session.keyPages.isFinished then
				local loadingBar = LoadingBarStyleState.from(Theme, self.ui.gui.BrowseKeys.Keys.Table.LoadingBar)
				loadingBar.container.Visible = true
				task.spawn(loadingBar.animate, loadingBar)

				self.ui.styleStates.browse.loadMore.buttonStyleState:setDisabled(true):update()
				local _, err = self.session.keyPages:increment()

				self.ui.styleStates.browse.loadMore.buttonStyleState:setDisabled(false):update()
				loadingBar.container.Visible = false
				loadingBar:destroy()

				if err then
					self.uiMessages:reportDataStoreError(err)
					return
				end
			end
		end
	end)

	self.ui.gui.BrowseKeys.List.Activated:Connect(function()
		self:tryListKeys()
	end)

	self.ui.gui.BrowseKeys.Prefix.FocusLost:Connect(function(enterPressed, input)
		if input == nil then
			return
		end

		if enterPressed then
			self:tryListKeys()
		end
	end)

	self.ui.keySelected:Connect(function(key: DataStoreKey, openInNewWidget: boolean)
		if openInNewWidget then
			local forkedSession = self.session:fork()
			local widget, err = SingleKeyWidget.new({
				session = forkedSession,
				theme = Theme,
				keyName = key.KeyName,
			})

			if widget then
				widget.deleted:Connect(function()
					self:_onKeyDeleted(key.KeyName, forkedSession.connection)
				end)
			else
				self.uiMessages:reportDataStoreError(err)
			end
		else
			local success, err = self:_trySwapEditKeyView(key.KeyName)
			if not success then
				self.uiMessages:reportDataStoreError(err)
				return
			end
		end
	end)

	self.ui.idLookedUp:Connect(function(key: DataStoreKey)
		local id = tonumber(key.KeyName:match("%d+"))
		if not id then
			self.uiMessages:error("Invalid Id.")
			return
		end

		self:_tryLookupId(id)
	end)

	self.ui.keyDeleted:Connect(function(key: DataStoreKey)
		if self.session.currentKey == key.KeyName or self._keyTransactor.locked then
			return
		end

		local popupPosition = self.widget:GetRelativeMousePosition()
		local confirmed = ConfirmDialogStyleState.confirm(Theme, self.widget, popupPosition, {
			title = "Delete key?",
			message = "Are you sure you want to do this?",
		})

		if confirmed then
			if self.session.currentKey == key.KeyName and self._keyTransactor.locked then
				return
			end

			local confirmedAgain = ConfirmDialogStyleState.confirm(Theme, self.widget, popupPosition, {
				title = "Confirm again",
				message = `You are going to delete the key <b>{key.KeyName}</b>.`,
			})

			if confirmedAgain then
				local styleState = self.ui.styleStates.browse.loadMore:get(key.KeyName)
				styleState:setDisabled(true):update()

				local success, err = self.session:tryDeleteKey(key.KeyName)

				if not success then
					self.uiMessages:reportDataStoreError(err)
					styleState:setDisabled(false):update()
					return
				else
					self:_onKeyDeleted(key.KeyName, self.session.connection)
					self.uiMessages:success(`Deleted <b>{key.KeyName}</b>.`)
				end
			end
		end
	end)

	-- Ordered data store

	self.ui.orderedDataStoreView.listed:Connect(function()
		self:_tryListOrderedKeys()
	end)

	self.ui.orderedDataStoreView.orderChanged:Connect(function()
		self:_tryListOrderedKeys()
	end)

	self.ui.orderedDataStoreView.keyEdited:Connect(function(key, value)
		self:_wrapOrderedDataStoreOperation(function()
			local success, err = self.session:trySetOrderedKey(key, value)

			if not success then
				self.uiMessages:reportDataStoreError(err)
				task.wait()
			else
				self.ui.orderedDataStoreView:updateKey(key, value)
			end
		end)
	end)

	self.ui.orderedDataStoreView.keyAdded:Connect(function(key, value)
		self:_wrapOrderedDataStoreOperation(function()
			local success, err = self.session:trySetOrderedKey(key, value)

			if not success then
				self.uiMessages:reportDataStoreError(err)
				task.wait()
			else
				self.ui.orderedDataStoreView:addKey(key, value)
				self.uiMessages:success(`Key <b>{key}</b> added!`)
			end
		end)
	end)

	self.ui.orderedDataStoreView.keyDeleted:Connect(function(key)
		self:_wrapOrderedDataStoreOperation(function()
			local success, err = self.session:tryRemoveOrderedKey(key)
			if not success then
				self.uiMessages:reportDataStoreError(err)
				task.wait()
			else
				self.ui.orderedDataStoreView:deleteKey(key)
				self.uiMessages:success(`Key <b>{key}</b> deleted!`)
			end
		end)
	end)

	self.ui.orderedDataStoreView.keyQueried:Connect(function(key)
		self:_wrapOrderedDataStoreOperation(function()
			local value, err = self.session:tryGetOrderedKey(key)
			if err then
				self.uiMessages:reportDataStoreError(err)
				task.wait()
			else
				self.ui.orderedDataStoreView:setActiveKey(key, value)
			end
		end)
	end)

	self.ui.orderedDataStoreView.styleStates.loadMore.buttonStyleState.button.Activated:Connect(function()
		if self.session.keyPages then
			if not self.session.keyPages.isFinished then
				self:_wrapOrderedDataStoreOperation(function()
					local _, err = self.session.keyPages:increment()
					if err then
						self.uiMessages:reportDataStoreError(err)
					end
				end)
			end
		end
	end)

	-- Settings
	self.ui.styleStates.settingsButton.button.Activated:Connect(function()
		if self.ui.styleStates.settingsButton.selecting then
			self.ui.styleStates.settingsButton:setSelecting(false):update()
			StyleStateHelper.tween(self.ui.styleStates.settingsButton.button, SETTINGS_TWEEN_INFO, {
				Rotation = 0,
			})

			self.ui:updateBreadcrumbsVisibility()
			self.ui:setActiveView(self.ui.styleStates.breadcrumbs:getCurrentCrumb().category)
		else
			self.ui.styleStates.settingsButton:setSelecting(true):update()
			StyleStateHelper.tween(self.ui.styleStates.settingsButton.button, SETTINGS_TWEEN_INFO, {
				Rotation = 30,
			})

			self.ui.styleStates.breadcrumbs.frame.Visible = false
			self.ui:setActiveView("settings")
		end
		self.ui:updateSettingsButtonPosition()
	end)

	table.insert(
		self.connections,
		Settings.changed:Connect(function(name: string, value: any)
			if name == "allScopes" then
				self:_updateAllScopes()
			elseif name == "hideGameName" then
				self.ui.styleStates.breadcrumbs:setCrumbNameVisibleSafe(1, not value)
			end
		end)
	)
	self.ui.styleStates.connect.orderedDataStoreCheckbox.toggled:Connect(function()
		self:_updateAllScopes()
	end)
	self.ui.styleStates.connect.tabs.selectingChanged:Connect(function(tab)
		self.ui:switchConnectTab(tab:lower())
		self.ui:autoFocus()
		self:_updateAllScopes()

		if Settings.get("automaticallyList") then
			if tab:lower() == "list" then
				if not self.session.dataStorePages then
					self:tryListDataStores()
				end
			end
		end
	end)
	self:_updateAllScopes()

	table.insert(
		self.connections,
		gameNameDiscovered.Event:Connect(function()
			self.ui.styleStates.breadcrumbs:renameCrumbSafe(1, gameName)
		end)
	)

	table.insert(
		self.connections,
		self._keyTransactor.lockedChanged:Connect(function(locked: boolean)
			self.ui.styleStates.breadcrumbs:setDisabled(locked):update()
		end)
	)

	-- Enabled
	self._enabledChanged = Instance.new("BindableEvent")
	self.enabledChanged = self._enabledChanged.Event
	self.widget:GetPropertyChangedSignal("Enabled"):Connect(function()
		self._enabledChanged:Fire(self.widget.Enabled)
	end)

	-- Init
	disableFrameWhenModalAppears(self.widget, { self.ui.gui })
	self.ui.styleStates.breadcrumbs:addCrumb(GAME_ICON, "game", gameName)
	self.ui.styleStates.breadcrumbs:setCrumbNameVisibleSafe(1, not Settings.get("hideGameName")) -- Hide the crumb name for the game if the setting says to
	task.defer(self.ui.updateSettingsButtonPosition, self.ui)

	return self
end

function App._updateConnectButton(self: App)
	local disabled = (self.ui.styleStates.connect.dataStoreNameTextBox.textBox.Text == "")
		or self.ui.styleStates.connect.dataStoreNameTextBox.error
		or self.ui.styleStates.connect.dataStoreScopeTextBox.error

	self.ui.styleStates.connect.connectButton:setDisabled(disabled):update()
end

function App.tryConnect(self: App, connection: Types.DataStoreConnection)
	if self._isListingKey then
		self.uiMessages:error(
			`Cannot connect to another DataStore while a {rfmt.code("ListKeysAsync")} request is being made.`
		)
		return
	end

	if Settings.get("allScopes") and not connection.isOrdered then
		(connection :: any).allScopes = true;
		(connection :: any).scope = "" -- Has to be to work
	end

	local success, err = self.session:tryConnect(connection)
	if not success then
		self.uiMessages:reportDataStoreError(err)
		return
	end

	History:addConnection(connection)

	local crumbName = connection.name
	if connection.scope and connection.scope ~= "" then
		crumbName = `{connection.scope}/{connection.name}`
	end

	-- Reset ui
	if connection.isOrdered then
		self.ui.orderedDataStoreView:reset()
	else
		self.ui.gui.BrowseKeys.Keys.Empty.Visible = false
		self.ui.gui.BrowseKeys.Keys.Table.Visible = false
		self.ui.gui.BrowseKeys.Keys.Instructions.Visible = true
		self.ui.styleStates.browse.key.textBox.Text = ""
		self.ui.styleStates.browse.prefix.textBox.Text = ""
	end

	self.ui.styleStates.breadcrumbs:addCrumb(
		if connection.allScopes
			then ALL_SCOPES_DATASTORE_ICON
			elseif connection.isOrdered then ORDERED_DATASTORE_ICON
			else DATASTORE_ICON,
		if connection.isOrdered then "orderedDatastore" else "datastore",
		crumbName
	)

	if Settings.get("automaticallyList") then
		if connection.isOrdered then
			if (not self.session.keyPages) and (self.session:hasBudgetFor("listOrdered")) then
				self:_tryListOrderedKeys()
			end
		else
			if (not self.session.keyPages) and (self.session:hasBudgetFor("list")) then
				self:tryListKeys()
			end
		end
	end
end

function App._submitConnectForm(self: App)
	local dataStoreName = self.ui.styleStates.connect.dataStoreNameTextBox:getText(function(err: string)
		self.uiMessages:error(err)
	end)
	local dataStoreScope = self.ui.styleStates.connect.dataStoreScopeTextBox:getText(function(err: string)
		self.uiMessages:error(err)
	end)
	if dataStoreName == "" then
		self.uiMessages:error("PUT A NAME!")
		return
	end
	if dataStoreScope == "" then
		dataStoreScope = nil
	end

	local isOrdered = self.ui.styleStates.connect.orderedDataStoreCheckbox.value

	self.ui.gui.ConnectDataStore.Content.Form.DataStoreName.TextBox.Text = ""
	self.ui.gui.ConnectDataStore.Content.Form.DataStoreScope.TextBox.Text = ""
	self.ui.styleStates.connect.orderedDataStoreCheckbox:setValue(false)

	self:tryConnect({
		name = dataStoreName,
		scope = dataStoreScope,
		isOrdered = isOrdered,
	})
end

function App.listDataStores(self: App, prefix: string?)
	local loadingBar =
		LoadingBarStyleState.from(Theme, self.ui.gui.ConnectDataStore.Content.Form.Prefix.TextBox.LoadingBar)
	loadingBar.container.Visible = true
	task.spawn(loadingBar.animate, loadingBar)
	self.ui.styleStates.connect.prefix:setDisabled(true):update()
	self.ui.styleStates.connect.listButton:setDisabled(true):update()

	local success, err = self.session:tryCreateDataStorePages(prefix)

	loadingBar.container.Visible = false
	loadingBar:destroy()
	self.ui.styleStates.connect.prefix:setDisabled(false):update()
	self.ui.styleStates.connect.listButton:setDisabled(false):update()

	if not success then
		self.uiMessages:reportDataStoreError(err)
		return
	end

	self.ui.styleStates.connect.loadMore:clear()
	self.session.dataStorePages:syncWithLoadMoreListStyleState(self.ui.styleStates.connect.loadMore)

	local empty = self.session.dataStorePages:isEmpty()
	self.ui.gui.ConnectDataStore.Content.DataStoreList.Table.Visible = not empty
	self.ui.gui.ConnectDataStore.Content.DataStoreList.Empty.Visible = empty
	self.ui.gui.ConnectDataStore.Content.DataStoreList.Instructions.Visible = false

	if not empty then
		self.ui.gui.ConnectDataStore.Content.UIListLayout.VerticalAlignment = Enum.VerticalAlignment.Top
	end
end

function App.tryListDataStores(self: App)
	local prefix = self.ui.styleStates.connect.prefix:getText(function(err)
		self.uiMessages:error(err)
	end)
	if prefix == "" then
		prefix = nil
	end

	self:listDataStores(prefix)
end

function App._trySwapEditKeyView(
	self: App,
	keyName: string,
	options: { version: string?, popCurrentCrumb: boolean? }
): (boolean, string?)
	if self._isGettingKey then
		return false, "Already getting another key."
	end

	self._isGettingKey = true

	self.ui.styleStates.breadcrumbs:setDisabled(true):update()

	options = options or {}

	local success: boolean, err: string?
	local forkedSession = self.session:fork()
	if options.version then
		success, err = forkedSession:tryLoadVersion(keyName, options.version)
	else
		success, err = forkedSession:tryLoadKey(keyName)
	end

	task.wait()

	self._isGettingKey = false
	self.ui.styleStates.breadcrumbs:setDisabled(false):update()

	if not success then
		return false, err
	end

	if self.editKeyView then
		self.editKeyView:destroy()
	end

	local editKeyView = EditKeyView.from({
		theme = Theme,
		uiMessages = self.uiMessages,
		frame = self.ui.gui.EditKey,
		session = forkedSession,
		transactor = self._keyTransactor,
		swapCallback = function(keyName, version)
			return self:_trySwapEditKeyView(keyName, {
				popCurrentCrumb = true,
				version = version,
			})
		end,
		isVersionLoaded = not not options.version,
	})

	editKeyView.deleted:Connect(function()
		self.ui.styleStates.breadcrumbs:popCrumb()
		self:_onKeyDeleted(keyName, self.session.connection)
	end)

	editKeyView.idLookedUp:Connect(function(id)
		self:_tryLookupId(id)
	end)

	self.editKeyView = editKeyView

	if options.popCurrentCrumb then
		self.ui.styleStates.breadcrumbs:popCrumb({ silently = true })
	end
	self.ui.styleStates.breadcrumbs:addCrumb(KEY_ICON, "key", keyName)

	return true
end

function App._onKeyDeleted(self: App, keyName: string, connection: Types.DataStoreConnection)
	local isSameConnection = Session.areConnectionsSame(self.session.connection, connection)
	if not Settings.get("listDeletedKeys") then
		if isSameConnection then
			self.ui.styleStates.browse.loadMore:tryRemove(keyName)
		end
	end

	local lastCrumb = self.ui.styleStates.breadcrumbs.crumbs[#self.ui.styleStates.breadcrumbs.crumbs]
	-- NOTE: This will not work if the user quickly switches to AllScopes, reconnects to the DataStore, then gets the key (since the name will be different because AllScopes required the scope)
	if lastCrumb.category == "key" and (lastCrumb.name == keyName) and isSameConnection then
		if self.editKeyView then
			self.editKeyView:destroy()
			self.editKeyView = nil
		end

		self.ui.styleStates.breadcrumbs:popCrumb()
		self.session:resetKey()
	end
end

function App.listKeys(self: App, prefix: string?)
	if self._isListingKey then
		return
	end

	self._isListingKey = true

	local loadingBar = LoadingBarStyleState.from(Theme, self.ui.gui.BrowseKeys.Prefix.LoadingBar)
	loadingBar.container.Visible = true
	task.spawn(loadingBar.animate, loadingBar)
	self.ui.styleStates.browse.prefix:setDisabled(true):update()
	self.ui.styleStates.browse.listButton:setDisabled(true):update()

	local success, err = self.session:tryCreateKeyPages(prefix)

	loadingBar.container.Visible = false
	loadingBar:destroy()

	self.ui.styleStates.browse.prefix:setDisabled(false):update()
	self.ui.styleStates.browse.listButton:setDisabled(false):update()

	self._isListingKey = false

	if not success then
		self.uiMessages:reportDataStoreError(err)
		return
	end

	self.ui.styleStates.browse.loadMore:clear()
	self.session.keyPages:syncWithLoadMoreListStyleState(self.ui.styleStates.browse.loadMore)

	local empty = self.session.keyPages:isEmpty()
	self.ui.gui.BrowseKeys.Keys.Table.Visible = not empty
	self.ui.gui.BrowseKeys.Keys.Empty.Visible = empty
	self.ui.gui.BrowseKeys.Keys.Instructions.Visible = false
end

function App.tryListKeys(self: App)
	local prefix = self.ui.styleStates.browse.prefix:getText(function(err: string)
		self.uiMessages:error(err)
	end)
	if prefix == "" then
		prefix = nil
	end

	self:listKeys(prefix)
end

function App._wrapOrderedDataStoreOperation(self: App, func: () -> ())
	if self.ui.orderedDataStoreView.locked then
		return
	end

	self.ui.orderedDataStoreView:setLocked(true)
	self.ui.styleStates.breadcrumbs:setDisabled(true):update()

	local endLoadingBar = LoadingBarStyleState.show(Theme, self.ui.orderedDataStoreView.frame.LoadingBar)

	-- Main
	func()
	--

	task.delay(0, function()
		self.ui.orderedDataStoreView:setLocked(false)
	end)
	self.ui.styleStates.breadcrumbs:setDisabled(false):update()

	endLoadingBar()
end

function App._tryListOrderedKeys(self: App)
	self:_wrapOrderedDataStoreOperation(function()
		local success, err = self.session:tryCreateOrderedKeyPages(
			self.ui.orderedDataStoreView.order,
			self.ui.orderedDataStoreView.minValue,
			self.ui.orderedDataStoreView.maxValue
		)

		if not success then
			self.uiMessages:reportDataStoreError(err)
			task.wait() -- Wait for tweens so they don't clash with each other when updating... TODO: make this not necessary
		else
			self.ui.orderedDataStoreView:setActiveKey(nil)
			self.ui.orderedDataStoreView.styleStates.loadMore:clear()
			self.session.keyPages:syncWithLoadMoreListStyleState(self.ui.orderedDataStoreView.styleStates.loadMore)

			self.ui.orderedDataStoreView:setKeysState(if self.session.keyPages:isEmpty() then "empty" else "notEmpty")
		end
	end)
end

function App._tryLookupId(self: App, id: number)
	local info = nil
	local card = self.ui:createUserCard()
	local success, err = pcall(function()
		info = UserService:GetUserInfosByUserIdsAsync({ id })
	end)

	if not success then
		card:abort()
		self.uiMessages:error(err)
	elseif info[1] then
		local thumbnailUrl = nil
		local success, err = pcall(function()
			thumbnailUrl =
				Players:GetUserThumbnailAsync(id, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
			local label = Instance.new("ImageLabel")
			label.Image = thumbnailUrl
			ContentProvider:PreloadAsync({ label })
		end)

		if not success then
			card:abort()
			self.uiMessages:error(err)
		else
			card:populate(thumbnailUrl, info[1])
		end
	else
		card:abort()
		self.uiMessages:error("User not found.")
	end
end

function App._updateAllScopes(self: App)
	if Settings.get("allScopes") then
		self.ui.gui.ConnectDataStore.Content.Form.DataStoreScope.TextBox.Text = ""
	end

	self.ui.gui.ConnectDataStore.Content.Form.DataStoreScope.Visible = (
		self.ui.styleStates.connect.orderedDataStoreCheckbox.value or (not Settings.get("allScopes"))
	) and (self.ui.styleStates.connect.tabs.selecting:lower() == "connect")
end

function App:toggleEnabled()
	self.widget.Enabled = not self.widget.enabled
	if self.widget.Enabled then
		self.ui:autoFocus()
	end
end

function App:getEnabled()
	return self.widget.Enabled
end

function App:destroy()
	for _, connection in self.connections do
		connection:Disconnect()
	end
	self._keyTransactor:destroy()
	self.ui:destroy()
end

export type App = typeof(App.new("DataDelve"))
return App
