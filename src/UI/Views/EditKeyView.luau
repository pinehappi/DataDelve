--!strict

local Theme = require(script.Parent.Parent.Theme)
local UIMessages = require(script.Parent.Parent.UIMessages)
local Session = require(script.Parent.Parent.Parent.Session)
local Transactor = require(script.Parent.Parent.Parent.Transactor)
local Settings = require(script.Parent.Parent.Parent.Settings)

local ExportImportHelper = require(script.Parent.Parent.Parent.ExportImportHelper)
local PopupHelper = require(script.Parent.Parent.PopupHelper)
local JSONHelper = require(script.Parent.Parent.Parent.JSONHelper)
local Validators = require(script.Parent.Parent.Parent.Validators)
local Tooltip = require(script.Parent.Parent.Tooltip)
local ModalState = require(script.Parent.Parent.ModalState)

local StyleState = script.Parent.Parent.StyleState
local Assets = script.Parent.Parent.Assets

local VersionsView = require(script.Parent.VersionsView)
local SearchView = require(script.Parent.SearchView)

local StyleStateWrapper = require(StyleState.StyleStateWrapper)
local StyleStateHelper = require(StyleState.StyleStateHelper)
local BackgroundStyleState = require(StyleState.BackgroundStyleState)
local ButtonStyleState = require(StyleState.ButtonStyleState)
local LabelStyleState = require(StyleState.LabelStyleState)

local TextBoxStyleState = require(StyleState.Input.TextBoxStyleState)
local CheckboxStyleState = require(StyleState.Input.CheckboxStyleState)
local ShortcutsTextBoxStyleState = require(StyleState.Input.ShortcutsTextBoxStyleState)

local ConfirmDialogStyleState = require(StyleState.Utility.ConfirmDialogStyleState)
local LoadingBarStyleState = require(StyleState.Utility.LoadingBarStyleState)
local ContextMenuStyleState = require(StyleState.Utility.ContextMenuStyleState)
local PopupFormStyleState = require(StyleState.Utility.PopupFormStyleState)

local ViewerTypes = require(script.Parent.Parent.Viewers.Types)
local TreeViewer = require(script.Parent.Parent.Viewers.Tree)
local CodeViewer = require(script.Parent.Parent.Viewers.Code)

local rfmt = require(script.Parent.Parent.Parent.rfmt)

local SEARCH_KEYCODE = Enum.KeyCode.Slash
local CLOSE_SEARCH_KEYCODE = Enum.KeyCode.Escape
local VERSIONS_MODAL_ID = "versions"

--[==[ THINGS THAT HAVE TO COME FIRST SO THEY CAN BE USED LATER ]==]

export type EditFrame = typeof(Assets.Views.EditKey)

-- Only putting this up here so it can be used in typeof below
local function getStyleStates(theme: Theme.Theme, frame: EditFrame, shouldDeleteBeDisabled: boolean)
	return {
		delete = ButtonStyleState.from(theme, frame.Container.Delete, {
			style = "secondary",
			disabled = shouldDeleteBeDisabled,
		}),
		save = ButtonStyleState.from(theme, frame.Container.Save, {
			style = "primary",
		}),
		refresh = ButtonStyleState.from(theme, frame.Container.Refresh, {
			style = "secondary",
		}),
		more = ButtonStyleState.from(theme, frame.Container.More, {
			style = "transparent",
		}),

		versions = ButtonStyleState.from(theme, frame.Container.LeftTopbar.Versions, {
			style = "secondary",
		}),

		undo = ButtonStyleState.from(theme, frame.Container.LeftTopbar.Undo, {
			style = "dormant",
		}),
		redo = ButtonStyleState.from(theme, frame.Container.LeftTopbar.Redo, {
			style = "dormant",
		}),
	}
end

--[==[ CLASS TYPES ]==]

export type Transaction = () -> ()

-- Callback to swap this edit key view with one for newKey.
-- Returns `true` for success and `false` for fail with error message
export type SwapCallback = (newKey: string, version: string?, session: Session.Session?) -> (boolean, string?)

export type EditKeyViewFromParams = {
	theme: Theme.Theme,
	uiMessages: UIMessages.UIMessages,
	frame: EditFrame,
	inputReceiver: Frame,
	session: Session.Session,
	transactor: Transactor.Transactor,
	versionsView: VersionsView.VersionsView,
	swapCallback: SwapCallback,
	isVersionLoaded: boolean,

	-- when versions view is open in drawer mode (on the side), we want to preserve it between version loads
	-- so you can quickly swap between them. This option will be set to true when you switched to a new view
	-- using the verisons drawer
	openWithVersionsView: boolean?,
}

export type EditKeyViewImplementation = {
	__index: EditKeyViewImplementation,

	from: (EditKeyViewFromParams) -> EditKeyView,

	destroy: (EditKeyView, completely: boolean?) -> (),

	update: (EditKeyView, StyleStateHelper.TransitionSpeed) -> (),

	_initializeInteraction: (EditKeyView) -> (),
	_runOperation: (EditKeyView, Transactor.Transaction) -> (),

	_isDirty: (EditKeyView) -> (),
	_updateSaveDisabled: (EditKeyView, speed: StyleStateHelper.TransitionSpeed) -> (),
	_shouldPromptConfirmation: (EditKeyView) -> boolean,

	_shouldDeleteBeDisabled: (EditKeyView) -> boolean,
	_updateDisabled: (EditKeyView) -> (),
	_updateUndoRedoButtons: (EditKeyView, speed: StyleStateHelper.TransitionSpeed) -> (),
	_switchViewerMode: (EditKeyView, mode: ViewerTypes.ViewerMode) -> (),
	_setViewer: (EditKeyView, data: any, userIds: { number }?, metadata: unknown?, isDirty: boolean?) -> (),
	_tryOpenVersionsView: (EditKeyView) -> (),
	handleLoadVersion: (EditKeyView, version: string) -> (boolean, nil | () -> (boolean, string?)),
	_updateVersionsViewMode: (EditKeyView) -> (),
	_getKeyInfo: (EditKeyView) -> ({ number }?, unknown?),

	_createDataUsageCard: (EditKeyView, dataUsage: number, metadataUsage: number) -> (),
	_promptDuplicateMoveKey: (
		EditKeyView,
		position: Vector2,
		isAllScopes: boolean
	) -> { key: string, shouldDelete: boolean }?,
	_promptSwitchingError: (EditKeyView, message: string) -> boolean,

	_canSearch: (EditKeyView) -> boolean,
	_startSearch: (EditKeyView) -> (),
	_endSearch: (EditKeyView) -> (),
}

export type EditKeyViewFields = {
	_swapCallback: SwapCallback,

	deleted: RBXScriptSignal,
	_deleted: BindableEvent,

	idLookedUp: RBXScriptSignal,
	_idLookedUp: BindableEvent,

	session: Session.Session,
	_transactor: Transactor.Transactor,

	_theme: Theme.Theme,
	_uiMessages: UIMessages.UIMessages,
	_styleStates: typeof(getStyleStates(({} :: any) :: Theme.Theme, {} :: EditFrame, false)),
	_tooltipDestructors: { Tooltip.TooltipDestructor },
	_modalState: ModalState.ModalState,

	_frame: EditFrame,
	_inputReceiver: Frame,
	_widget: PluginGui,

	_connections: { RBXScriptConnection },

	_viewerMode: ViewerTypes.ViewerMode,
	_viewer: ViewerTypes.Viewer,

	_isVersionLoaded: boolean,
	versionsView: VersionsView.VersionsView,
	_searchView: SearchView.SearchView?,
	_searchResultsConnection: RBXScriptConnection?,

	_cachedData: unknown?,
	_cachedMetadata: unknown?,
	_cachedUserIds: { number }?,

	_dead: boolean,
}

export type EditKeyView = typeof(setmetatable({} :: EditKeyViewFields, {} :: EditKeyViewImplementation))

--[==[ IMPLEMENTATION ]==]

local EditKeyView: EditKeyViewImplementation = {} :: EditKeyViewImplementation
EditKeyView.__index = EditKeyView

function EditKeyView.from(params)
	local self = setmetatable({}, EditKeyView)
	self._dead = false
	self._isVersionLoaded = params.isVersionLoaded
	self.versionsView = params.versionsView

	-- Events

	self._deleted = Instance.new("BindableEvent")
	self.deleted = self._deleted.Event :: RBXScriptSignal

	self._idLookedUp = Instance.new("BindableEvent")
	self.idLookedUp = self._idLookedUp.Event :: RBXScriptSignal

	-- State

	self.session = params.session
	self._swapCallback = params.swapCallback
	self._transactor = params.transactor

	self._viewerMode = Settings.data.viewerMode :: any
	self._viewer = nil :: any

	self._cachedData = self.session.currentValue
	self._cachedMetadata = self.session.currentKeyInfo and self.session.currentKeyInfo:GetMetadata()
	self._cachedUserIds = self.session.currentKeyInfo and self.session.currentKeyInfo:GetUserIds()

	-- UI

	self._theme = params.theme
	self._uiMessages = params.uiMessages
	self._frame = params.frame
	self._inputReceiver = params.inputReceiver
	self._styleStates = getStyleStates(params.theme, params.frame, (self :: any):_shouldDeleteBeDisabled())
	self._modalState = ModalState.new()
	self._widget = params.frame:FindFirstAncestorWhichIsA("PluginGui")

	self._connections = {}
	self._tooltipDestructors = {
		Tooltip.bindButtonGeneric(
			self._theme,
			self._frame.Container.LeftTopbar.Versions,
			`Equivalent to {rfmt.code("ListVersionsAsync")}.`
		),
		Tooltip.bindButtonGeneric(
			self._theme,
			self._frame.Container.Save,
			`Save\nEquivalent to {rfmt.code("UpdateAsync")}.`
		),
		Tooltip.bindButtonGeneric(
			self._theme,
			self._frame.Container.Refresh,
			`Refresh\nEquivalent to {rfmt.code("GetAsync")}.`
		),
		Tooltip.bindButtonGeneric(
			self._theme,
			self._frame.Container.Delete,
			`Delete\nEquivalent to {rfmt.code("RemoveAsync")}.`
		),
	}

	self:_initializeInteraction()

	table.insert(
		self._connections,
		self._theme.colorsChanged:Connect(function()
			task.wait()

			self:update("slow")
		end)
	)

	table.insert(
		self._connections,
		self._transactor.lockedChanged:Connect(function()
			self:_updateDisabled()
		end)
	)

	table.insert(
		self._connections,
		self._frame:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			self:_updateVersionsViewMode()
		end)
	)

	table.insert(
		self._connections,
		self.versionsView.closed:Connect(function()
			self:_updateVersionsViewMode()
		end)
	)

	table.insert(
		self._connections,
		self._inputReceiver.InputBegan:Connect(function(input)
			if self._modalState.isInside then
				return
			end

			if input.KeyCode == SEARCH_KEYCODE then
				if self._viewer:getSearchCapability() then
					local searchView = (self :: any)._searchView :: SearchView.SearchView?
					if searchView then
						local connection: RBXScriptConnection
						connection = input:GetPropertyChangedSignal("UserInputState"):Connect(function()
							if input.UserInputState ~= Enum.UserInputState.Change then
								connection:Disconnect()
								if (self :: any)._searchView == searchView then
									-- wait a bit so the `/` doesn't get typed
									task.delay(0.05, function()
										searchView:captureFocus()
									end)
								end
							end
						end)
					else
						self:_startSearch()
					end
				end
			elseif input.KeyCode == CLOSE_SEARCH_KEYCODE then
				-- escape doesn't seem to fire an event, so this doesn't work at the moment
				self:_endSearch()
			end
		end)
	)

	local userIds, metadata = self:_getKeyInfo()
	self:_setViewer(self.session.currentValue, userIds, metadata)

	-- fix ui update race condition
	task.delay(0, function()
		task.wait()
		self:_updateDisabled()
	end)

	if params.openWithVersionsView then
		self:_tryOpenVersionsView()
	end
	self:_updateVersionsViewMode()

	return self
end

function EditKeyView:update(speed: StyleStateHelper.TransitionSpeed)
	StyleStateHelper.update(self._styleStates, speed)
	if self._searchView then
		self._searchView:update(speed)
	end
end

function EditKeyView:destroy(completely)
	local self = self :: any
	self._dead = true
	self.swapCallback = nil

	if self._viewer then
		self._viewer:destroy()
	end

	if self._searchView then
		self._searchView:destroy()
	end

	if self._searchResultsConnection then
		self._searchResultsConnection:Disconnect()
	end

	StyleStateHelper.destroy(self._styleStates)

	for _, destructor in self._tooltipDestructors do
		destructor()
	end

	for _, connection in self._connections do
		connection:Disconnect()
	end
	self._connections = nil

	if completely then
		self._widget:Destroy()
	end

	-- TODO: find more robust way to do this
	-- Keep this around for a bit because when the deleted method is called, this view is destroyed, but we still need to keep some stuff for a
	-- a bit.
	task.delay(30, function()
		self._idLookedUp:Destroy()
		self._deleted:Destroy()
		table.clear(self)
	end)
end

function EditKeyView:_initializeInteraction()
	local moreMenuActive = false

	self._connections = {
		self._styleStates.save.button.Activated:Connect(function()
			if self._transactor.locked then
				return
			end

			local valueResult = self._viewer:getValue()
			if valueResult.kind == "failure" then
				self._uiMessages:error(valueResult.message)
				return
			elseif valueResult.hasNil then
				if
					not ConfirmDialogStyleState.confirm(
						self._theme,
						self._widget,
						self._widget:GetRelativeMousePosition(),
						{
							title = "Contains nil value",
							message = "Nil values will not be saved because of how Lua tables are. Nil gaps within arrays may delete any values after the gap.",
							yesText = "Ok",
							noText = "Cancel",
						}
					)
				then
					return
				end
			end

			if self.session:trySeeKeyChanged() == "changed" then
				if
					not ConfirmDialogStyleState.confirm(
						self._theme,
						self._widget,
						self._widget:GetRelativeMousePosition(),
						{
							title = "Key written to while editing",
							message = "This key was written to somewhere else while you were editing it. You may be overwritting this new data.",
							yesText = "Continue",
							noText = "Abort",
						}
					)
				then
					return
				end
			end

			local userIds, metadata = self:_getKeyInfo()

			self:_runOperation(function()
				local success, err = self.session:trySaveCurrentKey(valueResult.value, userIds, metadata)
				if not success then
					self._uiMessages:reportDataStoreError(err)
				else
					local dirtyCapability = self._viewer:getDirtyCapability()
					if dirtyCapability then
						dirtyCapability:undirty()
					end

					self._uiMessages:success("Save successful!")
				end
			end)
		end),

		self._styleStates.refresh.button.Activated:Connect(function()
			if self._transactor.locked then
				return
			end

			if self:_shouldPromptConfirmation() then
				local confirmed = ConfirmDialogStyleState.confirm(
					self._theme,
					self._widget,
					self._widget:GetRelativeMousePosition(),
					{
						title = "Refresh key?",
						message = if self.session.currentVersion
							then "This will delete any changes made. It will also reset to the latest version"
							else "This will delete any changes made.",
					}
				)

				if not confirmed then
					return
				end
			end

			self:_runOperation(function()
				--local success, err = self:tryGetKey(self.session.currentKey, { popCurrentCrumb = true })
				local success, err = self._swapCallback(self.session.currentKey)
				if not success then
					self._uiMessages:reportDataStoreError(err)
				else
					self._uiMessages:success("Refreshed key.")
				end
			end)
		end),

		self._styleStates.delete.button.Activated:Connect(function()
			if self._transactor.locked then
				return
			end

			local popupPosition = self._widget:GetRelativeMousePosition()
			local confirmed = ConfirmDialogStyleState.confirm(self._theme, self._widget, popupPosition, {
				title = "Delete key?",
				message = "Are you sure you want to do this?",
			})

			if confirmed then
				if self._transactor.locked then
					return
				end

				local confirmedAgain = ConfirmDialogStyleState.confirm(self._theme, self._widget, popupPosition, {
					title = "Confirm again",
					message = `You are going to delete the key <b>{self.session.currentKey}</b>.`,
				})

				if confirmedAgain then
					if self._transactor.locked then
						return
					end

					self:_runOperation(function()
						local keyName = self.session.currentKey
						local success, err = self.session:tryDeleteCurrentKey()

						if success then
							self._uiMessages:success(`Deleted <b>{keyName}</b>.`)
							self._deleted:Fire()
						else
							self._uiMessages:reportDataStoreError(err)
						end
					end)
				end
			end
		end),

		self._styleStates.undo.button.Activated:Connect(function()
			if self._transactor.locked then
				return
			end

			local historyCapability = self._viewer:getHistoryCapability()
			if historyCapability then
				historyCapability:undo()
			end
		end),

		self._styleStates.redo.button.Activated:Connect(function()
			if self._transactor.locked then
				return
			end

			local historyCapability = self._viewer:getHistoryCapability()
			if historyCapability then
				historyCapability:redo()
			end
		end),

		self._styleStates.more.button.Activated:Connect(function()
			if self._transactor.locked then
				return
			end
			if moreMenuActive then
				return
			end

			moreMenuActive = true

			-- Prompt
			local position = self._styleStates.more.button.AbsolutePosition
				+ self._styleStates.more.button.AbsoluteSize
				+ Vector2.new(0, 6)

			local viewModeOptions = {
				{ icon = if self._viewerMode == "Tree" then self._theme.icons.check else "", text = "Tree" },
				{ icon = if self._viewerMode == "Code" then self._theme.icons.check else "", text = "Code" },
				--[[ContextMenuStyleState.SEPARATOR,
				{ icon = self._theme.icons.hex, text = "Hex" },
				{ icon = self._theme.icons.script, text = "Deserializer" },]]
			}

			local options: { ContextMenuStyleState.Option } = {
				{ icon = self._theme.icons.export, text = "Export to File" },
				{ icon = self._theme.icons.import, text = "Import from File" },
				ContextMenuStyleState.SEPARATOR,
				{ icon = self._theme.icons.copy, text = "Duplicate/Move Key" },
				{ icon = self._theme.icons.storage, text = "View Data Usage" },
				ContextMenuStyleState.SEPARATOR,
				{ text = "View Mode", options = viewModeOptions },
			}

			if self:_canSearch() then
				table.insert(options, 1, { icon = self._theme.icons.lookup, text = "Search", hotkey = "/" })
			end

			local result: string
			local attachment: any
			local contextMenuStyleState, contextMenuModal =
				ContextMenuStyleState.createMenu(self._theme, self._widget, {
					submenuDirection = "left",
					options = options,
				})

			contextMenuStyleState.frame.Name = "More Menu"
			contextMenuStyleState.frame.Position = UDim2.fromOffset(position.X, position.Y)
			contextMenuStyleState.frame.AnchorPoint = Vector2.new(1, 0)
			task.spawn(function()
				contextMenuStyleState:animate()
				if not result then
					attachment = PopupHelper.attach(contextMenuStyleState.frame, self._styleStates.more.button, {
						anchor = Vector2.new(1, 1),
						offset = Vector2.new(0, 6),
					})
				end
			end)

			self._styleStates.more:setSelecting(true):update()

			result = self._modalState:wrap(function()
				return contextMenuStyleState.selected:Wait()
			end)

			if attachment then
				attachment:destroy()
			end

			contextMenuModal:destroy()
			contextMenuStyleState:destroy(true)

			-- Respond
			if not self._transactor.locked then
				if result == "Search" then
					if self:_canSearch() then
						if self._searchView then
							self._searchView:captureFocus()
						else
							self:_startSearch()
						end
					end
				elseif result == "Export to File" then
					local valueResult = self._viewer:getValue()
					if valueResult.kind == "failure" then
						self._uiMessages:error(valueResult.message)
					else
						local name = if self.session.connection.scope
							then `{self.session.connection.scope}_{self.session.connection.name}_{self.session.currentKey}`
							else `{self.session.connection.name}_{self.session.currentKey}`
						local exported, err = ExportImportHelper.export(name, valueResult.value)

						if exported then
							self._uiMessages:success("Exported to file.")
						else
							self._uiMessages:error(err or "Export cancelled.")
						end
					end
				elseif result == "Import from File" then
					local passed = true
					if self:_shouldPromptConfirmation() then
						local confirmed = self._modalState:wrap(function()
							return ConfirmDialogStyleState.confirm(self._theme, self._widget, position, {
								title = "Import from file?",
								message = "This will override any changes made.",
							})
						end)

						if not confirmed then
							passed = false
						end
					end

					if passed then
						local success, result = ExportImportHelper.import()
						if not success then
							if result then
								self._uiMessages:error(result)
							else
								self._uiMessages:error("Import failed.")
							end
						else
							self:_runOperation(function()
								local userIds, metadata = self:_getKeyInfo()
								self:_setViewer(result, userIds, metadata, true)
								task.wait(0) -- prevent race conditions with tweens for buttons
							end)
						end
					end
				elseif result == "Duplicate/Move Key" then
					if not self.session:hasBudgetFor("move") then
						self._uiMessages:warn(
							"You are unable to duplicate/move the key at this moment because the requests will be throttled. "
								.. "Wait and make fewer requests so that there can be budget for this."
						)
					else
						local duplicateAction = self._modalState:wrap(function()
							return self:_promptDuplicateMoveKey(position, self.session.connection.type == "allScopes")
						end)
						if duplicateAction then
							if duplicateAction.key == self.session.currentKey then
								self._uiMessages:error(`The key is already named <b>{self.session.currentKey}</b>`)
							else
								local valueResult = self._viewer:getValue()
								if valueResult.kind == "failure" then
									self._uiMessages:error(valueResult.message)
								elseif valueResult.value == nil then
									self._uiMessages:error("Cannot duplicate empty key.")
								else
									local userIds, metadata = self:_getKeyInfo()

									self:_runOperation(function()
										local success, err = self.session:tryDuplicateKey({
											data = valueResult.value,
											metadata = metadata,
											userIds = userIds,

											newKey = duplicateAction.key,
											deleteKey = duplicateAction.shouldDelete,
										})

										if success then
											local success, err = self._swapCallback(duplicateAction.key)
											--self:tryGetKey(duplicateAction.key, { popCurrentCrumb = true })

											if not success then
												self._uiMessages:reportDataStoreError(err)
											else
												self._uiMessages:success(
													if duplicateAction.shouldDelete
														then `Moved key to <b>{duplicateAction.key}</b>.`
														else `Duplicated key to <b>{duplicateAction.key}</b>.`
												)
											end
										else
											self._uiMessages:reportDataStoreError(err)
										end
									end)
								end
							end
						end
					end
				elseif result == "View Data Usage" then
					local keyUsage: number
					local metadataUsage: number
					local valueResult = self._viewer:getValue()
					if valueResult.kind == "failure" then
						self._uiMessages:error(valueResult.message)
					else
						self:_runOperation(function()
							keyUsage = #(JSONHelper.encode(valueResult.value))
							local _, metadata = self:_getKeyInfo()
							metadataUsage = #(JSONHelper.encode(metadata))
						end)

						self:_createDataUsageCard(keyUsage, metadataUsage)
					end
				elseif typeof(result) == "table" and result[1] == "View Mode" then
					if result[2] == "Tree" then
						self:_switchViewerMode("Tree")
					elseif result[2] == "Code" then
						self:_switchViewerMode("Code")
					end
				end
			end

			self._styleStates.more:setSelecting(false):update()
			moreMenuActive = false
		end),

		self._styleStates.versions.button.Activated:Connect(function()
			self:_tryOpenVersionsView()
		end),
	}
end

function EditKeyView:_shouldDeleteBeDisabled()
	return not self.session.currentKeyInfo
end

function EditKeyView:_updateDisabled()
	local locked = self._transactor.locked
	if locked then
		self._viewer:setDisabled(true)
		self._styleStates.save:setDisabled(true):update()
		self._styleStates.refresh:setDisabled(true):update()
		self._styleStates.delete:setDisabled(true):update()
		self._styleStates.more:setDisabled(true):update()
		self._styleStates.versions:setDisabled(true):update()
	else
		self._viewer:setDisabled(false)
		self:_updateSaveDisabled()
		self._styleStates.refresh:setDisabled(false):update()
		self._styleStates.delete:setDisabled(self:_shouldDeleteBeDisabled()):update()
		self._styleStates.more:setDisabled(false):update()
		self._styleStates.versions:setDisabled(false):update()
	end
end

function EditKeyView:_runOperation(transaction)
	local endLoadingBar = LoadingBarStyleState.show(self._theme, self._frame.Container.LoadingBar)
	self._transactor:transact(transaction)
	endLoadingBar()
end

local KEY_MAX_SIZE = 4_194_304
local METADATA_MAX_SIZE = 299
function EditKeyView:_createDataUsageCard(keyUsage, metadataUsage)
	local card = Assets.Cards.DataUsageCard:Clone()

	local function updateBarColor(speed: StyleStateHelper.TransitionSpeed)
		StyleStateHelper.tween(card.KeyBar, StyleStateHelper.getTweenInfoForSpeed(speed), {
			BackgroundColor3 = self._theme.colors.button.secondary.body.default,
		})
		StyleStateHelper.tween(card.KeyBar.UIStroke, StyleStateHelper.getTweenInfoForSpeed(speed), {
			Color = self._theme.colors.button.secondary.outline.default,
		})
		StyleStateHelper.tween(card.KeyBar.Clipper.Fill, StyleStateHelper.getTweenInfoForSpeed(speed), {
			BackgroundColor3 = self._theme.colors.mainAccent,
		})

		StyleStateHelper.tween(card.MetadataBar, StyleStateHelper.getTweenInfoForSpeed(speed), {
			BackgroundColor3 = self._theme.colors.button.secondary.body.default,
		})
		StyleStateHelper.tween(card.MetadataBar.UIStroke, StyleStateHelper.getTweenInfoForSpeed(speed), {
			Color = self._theme.colors.button.secondary.outline.default,
		})
		StyleStateHelper.tween(card.MetadataBar.Clipper.Fill, StyleStateHelper.getTweenInfoForSpeed(speed), {
			BackgroundColor3 = self._theme.colors.mainAccent,
		})
	end

	updateBarColor("instant")

	local wrapper = StyleStateWrapper.new(self._theme, {
		background = BackgroundStyleState.from(self._theme, card, { style = "popup" }),
		mainTitle = LabelStyleState.from(self._theme, card.MainTitle),
		dataLabel = LabelStyleState.from(
			self._theme,
			card.KeyLabel,
			{ style = if keyUsage > KEY_MAX_SIZE then "error" else "text" }
		),
		metadataTitle = LabelStyleState.from(self._theme, card.MetadataTitle),
		metadataLabel = LabelStyleState.from(
			self._theme,
			card.MetadataLabel,
			{ style = if metadataUsage > METADATA_MAX_SIZE then "error" else "text" }
		),
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
			StyleStateHelper.tween(bar.Clipper :: any, tweenInfo, {
				Size = UDim2.fromScale(percentage, 1),
			})
			StyleStateHelper.tween(bar.Clipper.Fill :: any, tweenInfo, {
				Size = UDim2.fromScale(1 / percentage, 1),
			})
		end

		label.Text = `{tostring(usage):reverse():gsub("(%d%d%d)", "%1,"):gsub(",$", ""):reverse()}/{tostring(max)
			:reverse()
			:gsub("(%d%d%d)", "%1,")
			:gsub(",$", "")
			:reverse()} bytes`
	end

	updateBar(keyUsage, KEY_MAX_SIZE, wrapper.styleStates.dataLabel.label, card.KeyBar)
	updateBar(metadataUsage, METADATA_MAX_SIZE, wrapper.styleStates.metadataLabel.label, card.MetadataBar)

	local modal = PopupHelper.modal(card, self._widget)
	self._modalState:push()

	local function cleanup()
		self._modalState:pop()

		modal:destroy()
		wrapper:destroy()
		card:Destroy()
	end

	modal.cancelled:Once(cleanup)

	return card
end

function EditKeyView:_promptDuplicateMoveKey(position, isAllScopes)
	local popup, modal = PopupFormStyleState.createPopup(self._theme, self._widget, Vector2.zero, {
		title = "Duplicate/Move Key",
		buttons = { { text = "Duplicate", options = { style = "primary" } }, { text = "Cancel" } },
		addContents = function(parent)
			local message = Assets.Forms.Message:Clone()
			message.Text = `This will call {rfmt.code("SetAsync")} on the new key with the contents of this key.`
			message.Parent = parent

			local textRow = Assets.Forms.TextRow:Clone()
			textRow.Title.Text = "Key"
			textRow.Parent = parent

			local confirm = Assets.Forms.ConfirmActionCheckboxRow:Clone()
			confirm.Message.Text = "Delete this key after (will effectively move the key)"
			confirm.Parent = parent

			return {
				message = LabelStyleState.from(self._theme, message),

				keyLabel = LabelStyleState.from(self._theme, textRow.Title),
				keyTextBox = ShortcutsTextBoxStyleState.from(self._theme, textRow.TextBox),

				confirmLabel = LabelStyleState.from(self._theme, confirm.Message),
				confirmCheckbox = CheckboxStyleState.from(self._theme, confirm.Check, {
					inputPair = confirm,
				}),
			}
		end,
	})

	popup.frame.AutomaticSize = Enum.AutomaticSize.Y

	local styleStates = popup.wrapper.styleStates

	local validator = if isAllScopes then Validators.allScopesKey else Validators.dataStoreKey

	popup.frame.Position = UDim2.fromOffset(position.X, position.Y)
	popup.frame.AnchorPoint = Vector2.new(1, 0)

	PopupHelper.clamp(popup.frame, self._widget, {
		boundaryDistance = 5,
	})

	local resultEvent = Instance.new("BindableEvent")

	local function updateDisabled(instant: boolean)
		if styleStates.contents.keyTextBox.textBox.Text == "" then
			styleStates.contents.keyTextBox:setError(nil):update("vertFast")
			styleStates.buttons.Duplicate:setDisabled(true):update(if instant then "instant" else nil)
		else
			local valid, err = validator(styleStates.contents.keyTextBox.textBox.Text)
			if valid then
				styleStates.contents.keyTextBox:setError(nil):update("vertFast")
				styleStates.buttons.Duplicate:setDisabled(false):update(if instant then "instant" else nil)
			else
				styleStates.contents.keyTextBox:setError(err):update("vertFast")
				styleStates.buttons.Duplicate:setDisabled(true):update(if instant then "instant" else nil)
			end
		end
	end

	styleStates.contents.keyTextBox.textBox.FocusLost:Connect(function(entered, input)
		if input and entered and not styleStates.buttons.Duplicate.disabled then
			popup:interact("Duplicate")
		end
	end)
	styleStates.contents.keyTextBox.textBox:GetPropertyChangedSignal("Text"):Connect(updateDisabled)
	updateDisabled(true)
	styleStates.contents.confirmCheckbox.toggled:Connect(function(value)
		if value then
			styleStates.buttons.Duplicate.button.TextLabel.Text = "Move"
		else
			styleStates.buttons.Duplicate.button.TextLabel.Text = "Duplicate"
		end
	end)

	popup.interacted:Connect(function(action)
		if action == "Duplicate" then
			resultEvent:Fire(true)
		else
			resultEvent:Fire(false)
		end
	end)

	styleStates.contents.keyTextBox.textBox:CaptureFocus()

	local shouldSubmit = resultEvent.Event:Wait()

	do -- Wrap in do because of ambiguity with the cast
		(popup :: any):destroy(true)
		modal:destroy()
	end

	if shouldSubmit then
		return {
			key = styleStates.contents.keyTextBox:getText(function(err: string)
				self._uiMessages:error(err)
			end),
			shouldDelete = styleStates.contents.confirmCheckbox.value,
		}
	else
		return nil
	end
end

-- returns if they should go through with the switch or not
function EditKeyView:_promptSwitchingError(errMessage)
	local popup, modal = PopupFormStyleState.createPopup(self._theme, self._widget, Vector2.zero, {
		title = "Error With Data",
		buttons = {
			{ text = "Discard and Continue" },
			{ text = "Cancel" },
		},
		addContents = function(parent)
			local message = Assets.Forms.Message:Clone()
			message.Text = "Do you want to continue switching and discard your changes?"
			message.Parent = parent

			local textArea = Assets.Forms.TextArea:Clone()
			textArea.TextEditable = false
			textArea.Text = errMessage
			textArea.Size = UDim2.new(1, 0, 0, 100)
			textArea.Parent = parent

			return {
				message = LabelStyleState.from(self._theme, message),
				textArea = TextBoxStyleState.from(self._theme, textArea),
			}
		end,
	})

	popup.frame.Position = UDim2.fromScale(0.5, 0.5)
	popup.frame.AnchorPoint = Vector2.new(0.5, 0.5)
	popup.frame.Size = UDim2.fromOffset(320, 0)
	popup.frame.AutomaticSize = Enum.AutomaticSize.Y

	PopupHelper.clamp(popup.frame, self._widget, {
		boundaryDistance = 5,
	})

	local shouldContinue: boolean? = nil

	popup.interacted:Connect(function(action)
		if action == "Discard and Continue" then
			shouldContinue = true
		else
			shouldContinue = false
		end
	end)

	repeat
		task.wait()
	until shouldContinue ~= nil
;
	(popup :: any):destroy(true)
	modal:destroy()

	return shouldContinue :: boolean
end

function EditKeyView:_updateUndoRedoButtons(speed: StyleStateHelper.TransitionSpeed)
	local historyCapability = self._viewer:getHistoryCapability()

	self._styleStates.undo.button.Visible = not not historyCapability
	self._styleStates.redo.button.Visible = not not historyCapability

	if historyCapability then
		self._styleStates.undo:setDisabled(not historyCapability:canUndo()):update(speed)
		self._styleStates.redo:setDisabled(not historyCapability:canRedo()):update(speed)
	end
end

function EditKeyView:_shouldPromptConfirmation()
	local dirtyCapability = self._viewer:getDirtyCapability()
	if dirtyCapability then
		return dirtyCapability.isDirty
	else
		return false
	end
end

function EditKeyView:_isDirty()
	local dirtyCapability = self._viewer and self._viewer:getDirtyCapability()
	-- if no dirtyCapability, just count as dirty always
	return (not dirtyCapability) or dirtyCapability.isDirty
end

function EditKeyView:_updateSaveDisabled(speed)
	self._styleStates.save
		:setDisabled(self._transactor.locked or ((not self._isVersionLoaded) and (not self:_isDirty())))
		:update(speed)
end

function EditKeyView:_switchViewerMode(mode: ViewerTypes.ViewerMode)
	if self._viewerMode == mode then
		return
	end

	-- TODO: retain key info changes
	local valueResult = self._viewer:getValue()
	local data: unknown
	if valueResult.kind == "failure" then
		local shouldContinue = self:_promptSwitchingError(valueResult.message)
		if not shouldContinue then
			return
		else
			data = self._cachedData
		end
	else
		data = valueResult.value
	end

	self._viewerMode = mode
	Settings.data.viewerMode = mode -- Synchronize. Saving might behave funky with multiple views open.

	local userIds, metadata = self:_getKeyInfo()
	self:_setViewer(data, userIds, metadata, self:_isDirty())
end

function EditKeyView:_setViewer(data: any, userIds: { number }?, metadata: unknown?, isStartDirty: boolean?)
	if self._viewer then
		self._viewer:destroy()
	end

	self._cachedData = data
	self._cachedUserIds = userIds
	self._cachedMetadata = metadata

	local options = {
		data = data,
		keyInfo = self.session.currentKeyInfo and {
			CreatedTime = self.session.currentKeyInfo.CreatedTime,
			UpdatedTime = self.session.currentKeyInfo.UpdatedTime,
			Version = self.session.currentKeyInfo.Version,
			UserIds = userIds,
			Metadata = metadata,
		},

		dirty = isStartDirty,
		readOnly = false,

		inputReceiver = self._inputReceiver,
		modalState = self._modalState,
	}

	if self._viewerMode == "Tree" then
		self._viewer = TreeViewer.new(self._theme, self._uiMessages, self._frame.Container.Content, options)
	else
		self._viewer = CodeViewer.new(self._theme, self._uiMessages, self._frame.Container.Content, options) :: any
	end

	self:_updateUndoRedoButtons("instant")

	local historyCapabiity = self._viewer:getHistoryCapability()
	if historyCapabiity then
		historyCapabiity.historyChanged:Connect(function()
			self:_updateUndoRedoButtons()
		end)
	end

	local dirtyCapability = self._viewer:getDirtyCapability()
	if dirtyCapability then
		dirtyCapability.dirtyChanged:Connect(function(dirty)
			self:_updateSaveDisabled()
		end)
	end

	self:_updateSaveDisabled("instant")

	self._viewer.idLookedUp:Connect(function(key)
		self._idLookedUp:Fire(key)
	end)
end

function EditKeyView:handleLoadVersion(version: string)
	if self._viewer then
		local continueCallback = function()
			if self._transactor.locked or not self._viewer then
				return false
			end

			local swapResult: boolean
			self._transactor:transact(function()
				swapResult = self._swapCallback(
					self.session.currentKey,
					version,
					if self.versionsView.visible and self.versionsView.mode == "drawer" then self.session else nil
				)
			end)
			return swapResult
		end

		if not self:_shouldPromptConfirmation() then
			return true, continueCallback
		else
			local confirmed =
				ConfirmDialogStyleState.confirm(self._theme, self._widget, self._widget:GetRelativeMousePosition(), {
					title = "Load version?",
					message = "This will delete any changes made.",
				})

			if confirmed then
				return true, continueCallback
			end
		end
	end

	return false, nil
end

function EditKeyView:_tryOpenVersionsView()
	(self.versionsView :: any):show()
	self:_updateVersionsViewMode()
end

function EditKeyView:_updateVersionsViewMode()
	if not self.versionsView.visible then
		self._frame.Container.Position = UDim2.fromOffset(0, 0)
		self._frame.Container.Size = UDim2.fromScale(1, 1)
		self._frame.Container.LeftTopbar.Versions.Visible = true
		self._modalState:popId(VERSIONS_MODAL_ID)
	elseif self._frame.AbsoluteSize.X > 700 then
		self.versionsView:setViewMode("drawer")
		self._frame.Container.Position = UDim2.fromOffset(self.versionsView.frame.AbsoluteSize.X, 0)
		self._frame.Container.Size = UDim2.new(1, -self.versionsView.frame.AbsoluteSize.X, 1, 0)
		self._frame.Container.LeftTopbar.Versions.Visible = false
		self._modalState:popId(VERSIONS_MODAL_ID)
	else
		self.versionsView:setViewMode("popup")
		self._frame.Container.Position = UDim2.fromOffset(0, 0)
		self._frame.Container.Size = UDim2.fromScale(1, 1)
		self._frame.Container.LeftTopbar.Versions.Visible = true
		self._modalState:pushId(VERSIONS_MODAL_ID)
	end
end

function EditKeyView:_canSearch()
	return not not self._viewer:getSearchCapability()
end

function EditKeyView:_startSearch()
	if self._searchView then
		return
	end

	local searchCapability = self._viewer:getSearchCapability()
	assert(searchCapability, "no search available")

	local searchView: SearchView.SearchView = SearchView.new({
		theme = self._theme,
		parent = self._frame.Container.SearchContainer,
		position = UDim2.new(0, 8, 1, -8),
		anchorPoint = Vector2.new(0, 1),

		nextClicked = function()
			searchCapability:jumpNextMatch()
		end,
		prevClicked = function()
			searchCapability:jumpPrevMatch()
		end,
		closeClicked = function()
			self:_endSearch()
		end,
		searchChanged = function(searchTerm)
			searchCapability:setSearch(searchTerm)
		end,
	})

	self._searchView = searchView
	self._searchResultsConnection = searchCapability.searchResultsChanged:Connect(
		function(result: ViewerTypes.SearchResult)
			searchView:setResult(result)
		end
	)

	task.spawn(function()
		searchView:animateIn()
		searchView:captureFocus()
	end)
end

function EditKeyView:_endSearch()
	local searchView = self._searchView
	if searchView then
		self._searchView = nil
		task.spawn(function()
			searchView:animateOut()
			searchView:destroy()
		end)
	end

	local searchCapability = self._viewer:getSearchCapability()
	if searchCapability then
		searchCapability:endSearch()
	end

	local connection = self._searchResultsConnection
	if connection then
		connection:Disconnect()
		self._searchResultsConnection = nil
	end
end

function EditKeyView:_getKeyInfo()
	local keyInfoCapability = self._viewer and self._viewer:getKeyInfoCapability()
	if keyInfoCapability then
		return keyInfoCapability:getKeyInfo()
	elseif self._cachedUserIds and self._cachedMetadata then
		return self._cachedUserIds, self._cachedMetadata
	else
		return nil, nil
	end
end

return EditKeyView
