local plugin = script:FindFirstAncestorWhichIsA("Plugin")

local Players = game:GetService("Players")
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
History:load(plugin)

local Tree = require(script.Parent.UI.Viewers.Tree)

local Validators = require(script.Parent.Validators)
local PopupHelper = require(script.Parent.UI.PopupHelper)
local LoadingBarStyleState = require(script.Parent.UI.StyleState.Utility.LoadingBarStyleState)
local ConfirmDialogStyleState = require(script.Parent.UI.StyleState.Utility.ConfirmDialogStyleState)
local ContextMenuStyleState = require(script.Parent.UI.StyleState.Utility.ContextMenuStyleState)

local Theme = require(script.Parent.UI.Theme).global
local BUI = require(script.Parent.UI)
local BUIMessages = require(script.Parent.UI.UIMessages)
local ExportImportHelper = require(script.Parent.ExportImportHelper)

local promptKeyValueForm = require(script.Parent.UI.Utilities.promptKeyValueForm)
local constraintTextBoxStyleState = require(script.Parent.UI.Utilities.constrainTextBoxStyleState)

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
	local uiMessages = BUIMessages.new(Theme)
	local self = setmetatable({
		id = id,
		session = Session.new(),
		ui = BUI.new(Theme, uiMessages),
		uiMessages = uiMessages,

		viewer = nil,

		connections = {},

		_isUpdatingKey = false,
		_isGettingKey = false,
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
				else Validators.dataStoreKey()
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

		local success, err = self:tryGetKey(keyName)

		loadingBar.container.Visible = false
		loadingBar:destroy()
		self.ui.styleStates.browse.key:setDisabled(false):update()

		if err then
			self.uiMessages:reportDataStoreError(err)
			return
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

	self.ui.keySelected:Connect(function(key: DataStoreKey)
		local success, err = self:tryGetKey(key.KeyName)
		if not success then
			self.uiMessages:reportDataStoreError(err)
			return
		end
	end)

	self.ui.idLookedUp:Connect(function(key: number)
		local id = tonumber(key:match("%d+"))
		if not id then
			self.uiMessages:error("Invalid Id.")
			return
		end

		self:_tryLookupId(id)
	end)

	-- Saving

	self.ui.styleStates.edit.save.button.Activated:Connect(function()
		if not self:_canEditCurrentKey() then
			return
		end

		local value, hasNil = self.viewer:getValue()
		if hasNil then
			if
				not ConfirmDialogStyleState.confirm(Theme, self.widget, self.widget:GetRelativeMousePosition(), {
					title = "Contains nil value",
					message = "Nil values will not be saved because of how Lua tables are. Nil gaps within arrays may delete any values after the gap.",
					yesText = "Ok",
					noText = "Cancel",
				})
			then
				return
			end
		end

		local userIds, metadata = self.viewer:getKeyInfo()

		self:_wrapEditKeyOperation(function()
			local success, err = self.session:trySaveCurrentKey(value, userIds, metadata)
			if not success then
				self.uiMessages:reportDataStoreError(err)
			else
				self.viewer:undirty()
				self.uiMessages:success("Save successful!")
			end
		end)
	end)

	self.ui.styleStates.edit.refresh.button.Activated:Connect(function()
		if not self:_canEditCurrentKey() then
			return
		end

		if self.viewer.isDirty then
			local confirmed =
				ConfirmDialogStyleState.confirm(Theme, self.widget, self.widget:GetRelativeMousePosition(), {
					title = "Refresh key?",
					message = if self.session.currentVersion
						then "This will delete any changes made. It will also reset to the latest version"
						else "This will delete any changes made.",
				})

			if not confirmed then
				return
			end
		end

		self:_wrapEditKeyOperation(function()
			local success, err = self:tryGetKey(self.session.currentKey, { popCurrentCrumb = true })
			if not success then
				self.uiMessages:reportDataStoreError(err)
			else
				self.uiMessages:success("Refreshed key.")
			end
		end)
	end)

	-- TODO: deleting does not remove the key if it is in the ListKeysAsync list which may be unexpected
	self.ui.styleStates.edit.delete.button.Activated:Connect(function()
		if not self:_canEditCurrentKey() then
			return
		end

		local confirmed = ConfirmDialogStyleState.confirm(Theme, self.widget, self.widget:GetRelativeMousePosition(), {
			title = "Delete key?",
			message = "Are you sure you want to do this?",
		})

		if confirmed then
			if not self:_canEditCurrentKey() then
				return
			end

			local confirmedAgain =
				ConfirmDialogStyleState.confirm(Theme, self.widget, self.widget:GetRelativeMousePosition(), {
					title = "Confirm again",
					message = `You are going to delete the key <b>{self.session.currentKey}</b>.`,
				})

			if confirmedAgain then
				if not self:_canEditCurrentKey() then
					return
				end

				self:_wrapEditKeyOperation(function()
					local success, err = self.session:tryDeleteCurrentKey()

					if success then
						self.session:resetKey()
						self.ui.styleStates.breadcrumbs:popCrumb()
					else
						self.uiMessages:reportDataStoreError(err)
					end
				end)
			end
		end
	end)

	self.ui.styleStates.edit.more.button.Activated:Connect(function()
		if not self:_canEditCurrentKey() then
			return
		end

		-- Prompt
		local position = self.ui.styleStates.edit.more.button.AbsolutePosition
			+ self.ui.styleStates.edit.more.button.AbsoluteSize
			+ Vector2.new(0, 6)

		local contextMenuStyleState, contextMenuModal = ContextMenuStyleState.createMenu(Theme, self.widget, position, {
			options = {
				{ icon = Theme.icons.export, text = "Export to JSON" },
				{ icon = Theme.icons.import, text = "Import from JSON" },
				ContextMenuStyleState.SEPARATOR,
				{ icon = Theme.icons.rename, text = "Transfer/Rename Key" },
				{ icon = Theme.icons.storage, text = "View Data Usage" },
			},
		})

		contextMenuStyleState.frame.Position = UDim2.fromOffset(position.X, position.Y)
		contextMenuStyleState.frame.AnchorPoint = Vector2.new(1, 0)

		self.ui.styleStates.edit.more:setSelecting(true):update()
		local result = contextMenuStyleState.selected:Wait()

		contextMenuModal:destroy()
		contextMenuStyleState:destroy(true)

		-- Respond
		if self:_canEditCurrentKey() then
			if result == "Export to JSON" then
				local confirmDialogStyleState, confirmDialogModal =
					ConfirmDialogStyleState.createDialog(Theme, self.widget, position, {
						title = "Usage notice",
						message = `The file will be saved with the file extension {rfmt.code(".lua")}. You must change it to {rfmt.code(
							".json"
						)} after exporting it. This is a limitation of Roblox. Script injection permissions are also required to create a script for export.`,
						yesText = "Understood",
						noText = "Cancel",
					})

				local confirmed = confirmDialogStyleState.interacted:Wait()
				confirmDialogModal:destroy()
				confirmDialogStyleState:destroy(true)

				if confirmed then
					local value = self.viewer:getValue()
					local name = if self.session.connection.scope
						then `{self.session.connection.scope}_{self.session.connection.name}_{self.session.currentKey}`
						else `{self.session.connection.name}_{self.session.currentKey}`
					local exported, err = ExportImportHelper.export(name, value)

					if exported then
						uiMessages:success("Exported to JSON.")
					else
						uiMessages:error(err or "Export cancelled.")
					end
				end
			elseif result == "Import from JSON" then
				local passed = true
				if self.viewer.isDirty then
					local confirmed = ConfirmDialogStyleState.confirm(Theme, self.widget, position, {
						title = "Import from JSON?",
						message = "This will override any changes made.",
					})

					if not confirmed then
						passed = false
					end
				end

				if passed then
					local success, result = ExportImportHelper.import()
					if not success then
						if result then
							uiMessages:error(result)
						else
							uiMessages:error("Import failed.")
						end
					else
						self:_wrapEditKeyOperation(function()
							self:_setViewer(result, true)
							task.wait(0) -- prevent race conditions with tweens for buttons
						end)
					end
				end
			elseif result == "Transfer/Rename Key" then
				if
					ConfirmDialogStyleState.confirm(Theme, self.widget, position, {
						title = "Usage Notice",
						message = `This will first call {rfmt.code("SetAsync")} to transfer the contents of this key to another. `
							.. `You may then delete the current key to effectively rename it. Note that version history is not transferred.`,
						yesText = "Understood",
						noText = "Cancel",
					})
				then
					local confirmDialogFrame = ConfirmDialogStyleState.template:Clone()

					confirmDialogFrame.Position = UDim2.fromOffset(position.X, position.Y)

					local confirmDialogStyleState = ConfirmDialogStyleState.from(Theme, confirmDialogFrame, {
						title = "Do you want to delete this key?",
						message = `The key is <b>{self.session.currentKey}</b>.`,
						yesText = "Yes",
						noText = "No",
					})
					local modal = PopupHelper.modal(confirmDialogFrame, self.widget, {
						zIndex = 20,
					})

					PopupHelper.clamp(confirmDialogFrame, self.widget)

					local cancelled = false
					modal.cancelled:Connect(function()
						confirmDialogStyleState:interact(false)
						cancelled = true
					end)

					local shouldDelete = confirmDialogStyleState.interacted:Wait()

					modal:destroy()
					confirmDialogStyleState:destroy(true)

					if not cancelled then
						if self.session:hasBudgetFor(if shouldDelete then "rename" else "transfer") then
							local result = promptKeyValueForm(Theme, self.widget, {
								position = position,
								anchorPoint = Vector2.new(1, 0),
								title = if shouldDelete then "Rename to" else "Transfer to",

								includeKey = true,
								includeValue = false,

								yesText = if shouldDelete then "Rename" else "Transfer",

								constraint = if self.session.connection.allScopes then "renameAllScopes" else "rename",
							})

							if result then
								local data = self.viewer:getValue()
								if data == nil then
									self.uiMessages:error("Cannot transfer empty key.")
								else
									local userIds, metadata = self.viewer:getKeyInfo()

									self:_wrapEditKeyOperation(function()
										local success, err = self.session:tryTransferCurrentKey({
											data = data,
											metadata = metadata,
											userIds = userIds,

											newKey = result.key,
											deleteKey = shouldDelete,
										})

										if success then
											local success, err = self:tryGetKey(result.key, { popCurrentCrumb = true })

											if not success then
												self.uiMessages:reportDataStoreError(err)
											else
												self.uiMessages:success(
													if shouldDelete
														then `Renamed key to <b>{result.key}</b>.`
														else `Transferred key to <b>{result.key}</b>.`
												)
											end
										else
											self.uiMessages:reportDataStoreError(err)
										end
									end)
								end
							end
						else
							self.uiMessages:warn(
								"You are unable to transfer/rename the key at this moment because the requests will be throttled. "
									.. "Wait and make fewer requests so that there can be budget for this."
							)
						end
					end
				end
			elseif result == "View Data Usage" then
				local keyUsage: number
				local metadataUsage: number
				self:_wrapEditKeyOperation(function()
					keyUsage = #(HttpService:JSONEncode(self.viewer:getValue()))
					local _, metadata = self.viewer:getKeyInfo()
					metadataUsage = #(HttpService:JSONEncode(metadata))
				end)

				self.ui:createDataUsageCard(keyUsage, metadataUsage)
			end
		end

		self.ui.styleStates.edit.more:setSelecting(false):update()
	end)

	-- Versions

	local versionSuccessfullyLoaded = Instance.new("BindableEvent")
	self.ui.styleStates.edit.versions.button.Activated:Connect(function()
		self.ui.versionsView:reset()

		if self.session.currentKeyInfo then
			self.ui.versionsView:setCurrentVersion(self.session.currentKeyInfo.Version)
		end

		local modal = PopupHelper.modal(self.ui.versionsView.frame, self.widget, {
			scrimTransparency = 0.5,
		})
		self.ui.versionsView.frame.Visible = true

		local loadedConnection: RBXScriptSignal
		local closeConnection: RBXScriptSignalXscr
		local function cleanup()
			if self.ui.versionsView.locked then
				return
			end
			loadedConnection:Disconnect()
			closeConnection:Disconnect()

			modal:destroy()
			self.ui.versionsView.frame.Visible = false
		end

		modal.cancelled:Connect(cleanup)
		loadedConnection = versionSuccessfullyLoaded.Event:Connect(cleanup)
		closeConnection = self.ui.versionsView.styleStates.close.button.Activated:Connect(cleanup)

		-- try load

		self:_tryListVersions()
	end)

	self.ui.versionsView.reloaded:Connect(function()
		if not self.ui.versionsView.styleStates.list.button.Active then
			return
		end
		self:_tryListVersions()
	end)

	-- Same code as refresh, but pass version as param
	self.ui.versionsView.versionLoaded:Connect(function(version: string)
		if not self:_canEditCurrentKey() then
			return
		end

		if self.viewer.isDirty then
			local confirmed =
				ConfirmDialogStyleState.confirm(Theme, self.widget, self.widget:GetRelativeMousePosition(), {
					title = "Load version?",
					message = "This will delete any changes made.",
				})

			if not confirmed then
				return
			end
		end

		self:_wrapVersionsOperation(function()
			local success, err = self:tryGetKey(self.session.currentKey, { version = version, popCurrentCrumb = true })
			if not success then
				self.uiMessages:reportDataStoreError(err)
			else
				self.uiMessages:success(`Loaded version {version}.`)

				self.ui.versionsView:setLocked(false) -- So that the cleanup function goes through
				versionSuccessfullyLoaded:Fire()
			end
		end)
	end)

	self.ui.versionsView.versionDeleted:Connect(function(version: string)
		if
			not ConfirmDialogStyleState.confirm(Theme, self.widget, self.widget:GetRelativeMousePosition(), {
				title = "Delete version?",
				message = "This is PERMANENT. You cannot undo this.",
			})
		then
			return
		end

		if
			not ConfirmDialogStyleState.confirm(Theme, self.widget, self.widget:GetRelativeMousePosition(), {
				title = "Are you sure?",
				message = 'Deleting this version is <font color="#ff0000"><b>PERMANENT</b></font>. You cannot undo this!',
			})
		then
			return
		end

		self:_wrapVersionsOperation(function()
			local success, err = self.session:tryDeleteCurrentKeyVersion(version)
			if not success then
				self.uiMessages:reportDataStoreError(err)
			else
				self.ui.versionsView:deleteVersion(version)
			end
		end)
	end)

	self.ui.versionsView.styleStates.loadMore.buttonStyleState.button.Activated:Connect(function()
		if self.session.versionPages then
			if not self.session.versionPages.isFinished then
				self:_wrapVersionsOperation(function()
					local _, err = self.session.versionPages:increment()
					if err then
						self.uiMessages:reportDataStoreError(err)
					end
				end)
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
				task.wait() -- Wait for tweens so they don't clash with each other when updating... TODO: make this not necessary
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
				task.wait() -- Wait for tweens so they don't clash with each other when updating... TODO: make this not necessary
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
			self.ui:updateBreadcrumbsVisibility()
			self.ui:setActiveView(self.ui.styleStates.breadcrumbs:getCurrentCrumb().category)
		else
			self.ui.styleStates.settingsButton:setSelecting(true):update()
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

	-- Enabled
	self._enabledChanged = Instance.new("BindableEvent")
	self.enabledChanged = self._enabledChanged.Event
	self.widget:GetPropertyChangedSignal("Enabled"):Connect(function()
		self._enabledChanged:Fire(self.widget.Enabled)
	end)

	-- Init
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
	if Settings.get("allScopes") and not connection.isOrdered then
		connection.allScopes = true
		connection.scope = "" -- Has to be to work
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

function App._setViewer(self: App, data: any, dirty: boolean)
	if self.viewer then
		self.viewer:destroy()
	end
	self.viewer = Tree.new(Theme, self.uiMessages, self.ui.gui.EditKey.Content.ScrollingFrame, {
		data = data,
		keyInfo = self.session.currentKeyInfo and {
			CreatedTime = self.session.currentKeyInfo.CreatedTime,
			UpdatedTime = self.session.currentKeyInfo.UpdatedTime,
			Version = self.session.currentKeyInfo.Version,
			UserIds = self.session.currentKeyInfo:GetUserIds(),
			Metadata = self.session.currentKeyInfo:GetMetadata(),
		},

		dirty = dirty,
		readOnly = false,
	})

	self.ui.styleStates.edit.save:setDisabled((not self.viewer.isDirty) or self._isUpdatingKey):update("instant")

	self.viewer.dirtyChanged:Connect(function(dirty)
		self.ui.styleStates.edit.save:setDisabled(self._isUpdatingKey or not dirty):update()
	end)

	self.viewer.idLookedUp:Connect(function(key)
		self:_tryLookupId(key)
	end)
end

function App.tryGetKey(
	self: App,
	keyName: string,
	options: { version: string, popCurrentCrumb: boolean }
): (boolean, string?)
	if self._isGettingKey then
		return false, "Already getting another key."
	end

	self._isGettingKey = true
	self.ui.styleStates.breadcrumbs:setDisabled(true):update()

	options = options or {}

	local success: boolean, err: string?
	if options.version then
		success, err = self.session:tryLoadVersion(keyName, options.version)
	else
		success, err = self.session:tryLoadKey(keyName)
	end

	task.wait()

	self._isGettingKey = false
	self.ui.styleStates.breadcrumbs:setDisabled(false):update()

	if not success then
		return false, err
	end

	self:_setViewer(self.session.currentValue, not not options.version) -- Version always dirty so it can override

	if options.popCurrentCrumb then
		self.ui.styleStates.breadcrumbs:popCrumb({ silently = true })
	end
	self.ui.styleStates.breadcrumbs:addCrumb(KEY_ICON, "key", keyName)

	self:_setEditActionsDisabled(false)

	return true
end

function App.listKeys(self: App, prefix: string?)
	-- TODO: user may be able to switch to a different datastore which will mess things up

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

function App._canEditCurrentKey(self: App): boolean
	if not self.viewer then
		self.uiMessages:error("No viewer.")
		return false
	end
	if not self.session.datastore then
		self.uiMessages:error("No DataStore.")
		return false
	end
	if not self.session.currentKey then
		self.uiMessages:error("No key.")
		return false
	end
	if self._isUpdatingKey then
		self.uiMessages:error("Key currently updating.")
		return false
	end
	return true
end

function App._setUpdatingKey(self: App, locked: boolean)
	if locked then
		self._isUpdatingKey = true
		self.viewer:setDisabled(true)
		self.ui.styleStates.breadcrumbs:setDisabled(true):update()
		self:_setEditActionsDisabled(true)
	else
		self._isUpdatingKey = false
		self.viewer:setDisabled(false)
		self.ui.styleStates.breadcrumbs:setDisabled(false):update()
		self:_setEditActionsDisabled(false)
	end
end

function App._wrapEditKeyOperation(self: App, func: () -> ())
	self:_setUpdatingKey(true)

	local endLoadingBar = LoadingBarStyleState.show(Theme, self.ui.gui.EditKey.LoadingBar)

	-- Main
	func()
	--

	endLoadingBar()
	task.delay(
		0,
		function() -- Delay in-case the function fails immediately, does not cause race condition for style states
			self:_setUpdatingKey(false)
		end
	)
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

function App._tryListOrderedKeys(self: ReplicatedStorage)
	self:_wrapOrderedDataStoreOperation(function()
		local success, err = self.session:tryCreateOrderedKeyPages(
			self.ui.orderedDataStoreView.order,
			self.ui.orderedDataStoreView.minValue,
			self.ui.orderedDataStoreView.maxValue
		)

		if not success then
			self.uiMessages:reportDataStoreError(err)
			task.wait() -- Wait for tweens so they don't clash with each other when updating... TODO: max this not necessary
		else
			self.ui.orderedDataStoreView:setActiveKey(nil)
			self.ui.orderedDataStoreView.styleStates.loadMore:clear()
			self.session.keyPages:syncWithLoadMoreListStyleState(self.ui.orderedDataStoreView.styleStates.loadMore)

			self.ui.orderedDataStoreView:setKeysState(if self.session.keyPages:isEmpty() then "empty" else "notEmpty")
		end
	end)
end

function App._setEditActionsDisabled(self: App, disabled: boolean)
	if disabled then
		self.ui.styleStates.edit.save:setDisabled(true):update()
		self.ui.styleStates.edit.refresh:setDisabled(true):update()
		self.ui.styleStates.edit.delete:setDisabled(true):update()
		self.ui.styleStates.edit.more:setDisabled(true):update()
	else
		self.ui.styleStates.edit.save:setDisabled(if self.viewer then not self.viewer.isDirty else false):update()
		self.ui.styleStates.edit.refresh:setDisabled(false):update()
		self.ui.styleStates.edit.delete:setDisabled(not self.session.currentKeyInfo):update()
		self.ui.styleStates.edit.more:setDisabled(false):update()
	end
end

function App._wrapVersionsOperation(self: App, func: () -> ())
	if self.ui.versionsView.locked then
		return
	end

	self.ui.versionsView:setLocked(true)
	self:_setUpdatingKey(true)

	local loadingBar = LoadingBarStyleState.from(Theme, self.ui.versionsView.frame["Escape Layout"].LoadingBar)
	loadingBar.container.Visible = true
	task.spawn(loadingBar.animate, loadingBar)

	-- Main
	func()
	--

	task.delay(0, function()
		self.ui.versionsView:setLocked(false)
		self:_setUpdatingKey(false)
	end)

	loadingBar.container.Visible = false
	loadingBar:destroy()
end

function App._tryListVersions(self: App)
	self.ui.versionsView.styleStates.loadMore:clear()
	self.ui.versionsView.styleStates.loadMore:setLoadMoreVisible(false)

	self:_wrapVersionsOperation(function()
		local success, err = self.session:tryCreateVersionPages(
			self.ui.versionsView.order,
			self.ui.versionsView.minDate,
			self.ui.versionsView.maxDate
		)

		if not success then
			self.uiMessages:reportDataStoreError(err)
		else
			self.ui.versionsView.frame.List.Visible = true

			self.ui.versionsView.frame.List.Table.Visible = not self.session.versionPages:isEmpty()
			self.ui.versionsView.frame.List.Empty.Visible = self.session.versionPages:isEmpty()

			self.session.versionPages:syncWithLoadMoreListStyleState(self.ui.versionsView.styleStates.loadMore)
		end
	end)
end

function App._tryLookupId(self: App, id: number)
	local info = nil
	-- TODO: do something while yielding
	local success, err = pcall(function()
		info = UserService:GetUserInfosByUserIdsAsync({ id })
	end)

	if not success then
		self.uiMessages:error(err)
	elseif info[1] then
		local card = self.ui:createUserCard()

		local thumbnailUrl = nil
		local success, err = pcall(function()
			thumbnailUrl =
				Players:GetUserThumbnailAsync(id, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
		end)

		if not success then
			card:abort()
			self.uiMessages:error(err)
		else
			card:populate(thumbnailUrl, info[1])
		end
	else
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
end

export type App = typeof(App.new("DataDelve"))
return App
