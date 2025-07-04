--!strict

local SelectionService = game:GetService("Selection")

local Theme = require(script.Parent.Parent.Theme)
local UIMessages = require(script.Parent.Parent.UIMessages)
local Session = require(script.Parent.Parent.Parent.Session)
local Transactor = require(script.Parent.Parent.Parent.Transactor)

local ExportImportHelper = require(script.Parent.Parent.Parent.ExportImportHelper)
local PopupHelper = require(script.Parent.Parent.PopupHelper)
local JSONHelper = require(script.Parent.Parent.Parent.JSONHelper)
local Validators = require(script.Parent.Parent.Parent.Validators)
local Tooltip = require(script.Parent.Parent.Tooltip)

local StyleState = script.Parent.Parent.StyleState
local Assets = script.Parent.Parent.Assets

local VersionsView = require(script.Parent.VersionsView)

local StyleStateWrapper = require(StyleState.StyleStateWrapper)
local StyleStateHelper = require(StyleState.StyleStateHelper)
local BackgroundStyleState = require(StyleState.BackgroundStyleState)
local ButtonStyleState = require(StyleState.ButtonStyleState)
local LabelStyleState = require(StyleState.LabelStyleState)

local CheckboxStyleState = require(StyleState.Input.CheckboxStyleState)
local ShortcutsTextBoxStyleState = require(StyleState.Input.ShortcutsTextBoxStyleState)

local ConfirmDialogStyleState = require(StyleState.Utility.ConfirmDialogStyleState)
local LoadingBarStyleState = require(StyleState.Utility.LoadingBarStyleState)
local ContextMenuStyleState = require(StyleState.Utility.ContextMenuStyleState)
local PopupFormStyleState = require(StyleState.Utility.PopupFormStyleState)

local Tree = require(script.Parent.Parent.Viewers.Tree)

local rfmt = require(script.Parent.Parent.Parent.rfmt)
local showShadowOnScroll = require(script.Parent.Parent.Utilities.showShadowOnScroll)

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

type Viewer = any
export type Transaction = () -> ()

-- Callback to swap this edit key view with one for newKey.
-- Returns `true` for success and `false` for fail with error message
export type SwapCallback = (
	newKey: string,
	version: string?,
	openWithVersionsView: "openVersionsView"?
) -> (boolean, string?)

export type EditKeyViewFromParams = {
	theme: Theme.Theme,
	uiMessages: UIMessages.UIMessages,
	frame: EditFrame,
	inputReceiver: Frame,
	session: Session.Session,
	transactor: Transactor.Transactor,
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

	_shouldDeleteBeDisabled: (EditKeyView) -> boolean,
	_updateDisabled: (EditKeyView) -> (),
	_updateUndoRedoButtons: (EditKeyView, speed: StyleStateHelper.TransitionSpeed) -> (),
	_setViewer: (EditKeyView, data: any, isDirty: boolean?) -> (),
	_tryOpenVersionsView: (EditKeyView) -> (),
	_updateVersionsViewMode: (EditKeyView) -> (),

	_createDataUsageCard: (EditKeyView, dataUsage: number, metadataUsage: number) -> (),
	_promptDuplicateMoveKey: (
		EditKeyView,
		position: Vector2,
		isAllScopes: boolean
	) -> { key: string, shouldDelete: boolean }?,
}

export type EditKeyViewFields = {
	_swapCallback: SwapCallback,

	deleted: RBXScriptSignal,
	_deleted: BindableEvent,

	idLookedUp: RBXScriptSignal,
	_idLookedUp: BindableEvent,

	_session: Session.Session,
	_transactor: Transactor.Transactor,

	_theme: Theme.Theme,
	_uiMessages: UIMessages.UIMessages,
	_styleStates: typeof(getStyleStates(({} :: any) :: Theme.Theme, {} :: EditFrame, false)),
	_tooltipDestructors: { Tooltip.TooltipDestructor },

	_frame: EditFrame,
	_inputReceiver: Frame,
	_widget: PluginGui,

	_connections: { RBXScriptConnection },

	_viewer: Viewer,
	_versionsView: VersionsView.VersionsView?,

	_dead: boolean,
}

export type EditKeyView = typeof(setmetatable({} :: EditKeyViewFields, {} :: EditKeyViewImplementation))

--[==[ IMPLEMENTATION ]==]

local EditKeyView: EditKeyViewImplementation = {} :: EditKeyViewImplementation
EditKeyView.__index = EditKeyView

function EditKeyView.from(params)
	local self = setmetatable({}, EditKeyView)
	self._dead = false

	-- Events

	self._deleted = Instance.new("BindableEvent")
	self.deleted = self._deleted.Event :: RBXScriptSignal

	self._idLookedUp = Instance.new("BindableEvent")
	self.idLookedUp = self._idLookedUp.Event :: RBXScriptSignal

	-- State

	self._swapCallback = params.swapCallback
	self._session = params.session
	self._transactor = params.transactor

	self._viewer = nil :: any
	self._versionsView = nil

	-- UI

	self._theme = params.theme
	self._uiMessages = params.uiMessages
	self._frame = params.frame
	self._inputReceiver = params.inputReceiver
	self._styleStates = getStyleStates(params.theme, params.frame, (self :: any):_shouldDeleteBeDisabled())
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
		showShadowOnScroll(self._frame.Container.Content.ScrollingFrame, self._frame.Container.Content.Shadow)
	)
	table.insert(
		self._connections,
		self._theme.colorsChanged:Connect(function()
			task.wait()

			StyleStateHelper.update(self._styleStates, "slow")
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
			if self._versionsView then
				self:_updateVersionsViewMode()
			end
		end)
	)

	self:_setViewer(self._session.currentValue, params.isVersionLoaded)
	self:_updateDisabled()

	if params.openWithVersionsView then
		self:_tryOpenVersionsView()
	end
	self:_updateVersionsViewMode()

	return self
end

function EditKeyView:update(speed: StyleStateHelper.TransitionSpeed)
	StyleStateHelper.update(self._styleStates, speed)
end

function EditKeyView:destroy(completely)
	local self = self :: any
	self._dead = true
	self.swapCallback = nil

	if self._viewer then
		self._viewer:destroy()
	end

	if self._versionsView then
		self._versionsView:destroy(true)
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

			local value, hasNil = self._viewer:getValue()
			if hasNil then
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

			if self._session:trySeeKeyChanged() == "changed" then
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

			local userIds, metadata = self._viewer:getKeyInfo()

			self:_runOperation(function()
				local success, err = self._session:trySaveCurrentKey(value, userIds, metadata)
				if not success then
					self._uiMessages:reportDataStoreError(err)
				else
					self._viewer:undirty()
					self._uiMessages:success("Save successful!")
				end
			end)
		end),

		self._styleStates.refresh.button.Activated:Connect(function()
			if self._transactor.locked then
				return
			end

			if self._viewer.isDirty then
				local confirmed = ConfirmDialogStyleState.confirm(
					self._theme,
					self._widget,
					self._widget:GetRelativeMousePosition(),
					{
						title = "Refresh key?",
						message = if self._session.currentVersion
							then "This will delete any changes made. It will also reset to the latest version"
							else "This will delete any changes made.",
					}
				)

				if not confirmed then
					return
				end
			end

			self:_runOperation(function()
				--local success, err = self:tryGetKey(self._session.currentKey, { popCurrentCrumb = true })
				local success, err = self._swapCallback(self._session.currentKey)
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
					message = `You are going to delete the key <b>{self._session.currentKey}</b>.`,
				})

				if confirmedAgain then
					if self._transactor.locked then
						return
					end

					self:_runOperation(function()
						local keyName = self._session.currentKey
						local success, err = self._session:tryDeleteCurrentKey()

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

			self._viewer:undo()
		end),

		self._styleStates.redo.button.Activated:Connect(function()
			if self._transactor.locked then
				return
			end

			self._viewer:redo()
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

			local contextMenuStyleState, contextMenuModal =
				ContextMenuStyleState.createMenu(self._theme, self._widget, {
					options = {
						{ icon = self._theme.icons.export, text = "Export to File" },
						{ icon = self._theme.icons.import, text = "Import from File" },
						ContextMenuStyleState.SEPARATOR,
						{ icon = self._theme.icons.rename, text = "Duplicate/Move Key" },
						{ icon = self._theme.icons.storage, text = "View Data Usage" },
					},
				})

			contextMenuStyleState.frame.Name = "More Menu"
			contextMenuStyleState.frame.Position = UDim2.fromOffset(position.X, position.Y)
			contextMenuStyleState.frame.AnchorPoint = Vector2.new(1, 0)
			task.spawn(contextMenuStyleState.animate, contextMenuStyleState)

			self._styleStates.more:setSelecting(true):update()
			local result = contextMenuStyleState.selected:Wait()

			contextMenuModal:destroy()
			contextMenuStyleState:destroy(true)

			-- Respond
			if not self._transactor.locked then
				if result == "Export to File" then
					local value = self._viewer:getValue()
					local name = if self._session.connection.scope
						then `{self._session.connection.scope}_{self._session.connection.name}_{self._session.currentKey}`
						else `{self._session.connection.name}_{self._session.currentKey}`
					local exported, err = ExportImportHelper.export(name, value)

					if exported then
						self._uiMessages:success("Exported to file.")
					else
						self._uiMessages:error(err or "Export cancelled.")
					end
				elseif result == "Import from File" then
					local passed = true
					if self._viewer.isDirty then
						local confirmed = ConfirmDialogStyleState.confirm(self._theme, self._widget, position, {
							title = "Import from file?",
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
								self._uiMessages:error(result)
							else
								self._uiMessages:error("Import failed.")
							end
						else
							self:_runOperation(function()
								self:_setViewer(result, true)
								task.wait(0) -- prevent race conditions with tweens for buttons
							end)
						end
					end
				elseif result == "Duplicate/Move Key" then
					if not self._session:hasBudgetFor("move") then
						self._uiMessages:warn(
							"You are unable to duplicate/move the key at this moment because the requests will be throttled. "
								.. "Wait and make fewer requests so that there can be budget for this."
						)
					else
						local duplicateAction =
							self:_promptDuplicateMoveKey(position, self._session.connection.allScopes)
						if duplicateAction then
							if duplicateAction.key == self._session.currentKey then
								self._uiMessages:error(`The key is already named <b>{self._session.currentKey}</b>`)
							else
								local data = self._viewer:getValue()
								if data == nil then
									self._uiMessages:error("Cannot duplicate empty key.")
								else
									local userIds, metadata = self._viewer:getKeyInfo()

									self:_runOperation(function()
										local success, err = self._session:tryDuplicateKey({
											data = data,
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
					self:_runOperation(function()
						keyUsage = #(JSONHelper.encode(self._viewer:getValue()))
						local _, metadata = self._viewer:getKeyInfo()
						metadataUsage = #(JSONHelper.encode(metadata))
					end)

					self:_createDataUsageCard(keyUsage, metadataUsage)
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
	return not self._session.currentKeyInfo
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
		self._styleStates.save:setDisabled(if self._viewer then not self._viewer.isDirty else false):update()
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

	local function cleanup()
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

	local shouldSubmit = resultEvent.Event:Wait()

	do -- Wrap indo because of ambiguity with the cast
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

function EditKeyView:_updateUndoRedoButtons(speed: StyleStateHelper.TransitionSpeed)
	self._styleStates.undo:setDisabled(not self._viewer:canUndo()):update(speed)
	self._styleStates.redo:setDisabled(not self._viewer:canRedo()):update(speed)
end

function EditKeyView:_setViewer(data: any, isDirty: boolean?)
	if self._viewer then
		self._viewer:destroy()
	end

	self._viewer = Tree.new(self._theme, self._uiMessages, self._frame.Container.Content.ScrollingFrame, {
		data = data,
		keyInfo = self._session.currentKeyInfo and {
			CreatedTime = self._session.currentKeyInfo.CreatedTime,
			UpdatedTime = self._session.currentKeyInfo.UpdatedTime,
			Version = self._session.currentKeyInfo.Version,
			UserIds = self._session.currentKeyInfo:GetUserIds(),
			Metadata = self._session.currentKeyInfo:GetMetadata(),
		},

		dirty = isDirty,
		readOnly = false,
		inputReceiver = self._inputReceiver,
	})

	self._viewer.selectionChanged:Connect(function()
		SelectionService:Set({})
	end)

	self:_updateUndoRedoButtons("instant")
	self._viewer.historyChanged:Connect(function()
		self:_updateUndoRedoButtons()
	end)

	self._styleStates.save:setDisabled((not self._viewer.isDirty) or self._transactor.locked):update("instant")

	self._viewer.dirtyChanged:Connect(function(dirty)
		self._styleStates.save:setDisabled(self._transactor.locked or not dirty):update()
	end)

	self._viewer.idLookedUp:Connect(function(key)
		self._idLookedUp:Fire(key)
	end)
end

function EditKeyView:_tryOpenVersionsView()
	if self._versionsView then
		return
	end

	local versionsFrame = Assets.Views.VersionsPopup:Clone()
	local versionsView = VersionsView.from({
		theme = self._theme,
		uiMessages = self._uiMessages,
		widget = self._widget,
		container = self._frame,
		frame = versionsFrame,
		session = self._session,
		loadVersion = function(version: string)
			if self._viewer then
				local continueCallback = function()
					if self._transactor.locked or not self._viewer then
						return false
					end

					local swapResult: boolean
					self._transactor:transact(function()
						swapResult = self._swapCallback(
							self._session.currentKey,
							version,
							if self._versionsView and self._versionsView.mode == "drawer"
								then "openVersionsView"
								else nil
						)
					end)
					return swapResult
				end

				if not self._viewer.isDirty then
					return true, continueCallback
				else
					local confirmed = ConfirmDialogStyleState.confirm(
						self._theme,
						self._widget,
						self._widget:GetRelativeMousePosition(),
						{
							title = "Load version?",
							message = "This will delete any changes made.",
						}
					)

					if confirmed then
						return true, continueCallback
					end
				end
			end

			return false, nil
		end,
	})

	versionsView.closed:Connect(function()
		if (self._versionsView == versionsView) and not self._dead then
			self._versionsView = nil
			self:_updateVersionsViewMode()
		end
	end)

	self._versionsView = versionsView
	self:_updateVersionsViewMode()
end

function EditKeyView:_updateVersionsViewMode()
	if not self._versionsView then
		self._frame.Container.Position = UDim2.fromOffset(0, 0)
		self._frame.Container.Size = UDim2.fromScale(1, 1)
		self._frame.Container.LeftTopbar.Versions.Visible = true
	elseif self._frame.AbsoluteSize.X > 700 then
		self._versionsView:setViewMode("drawer")
		self._frame.Container.Position = UDim2.fromOffset(self._versionsView.frame.AbsoluteSize.X, 0)
		self._frame.Container.Size = UDim2.new(1, -self._versionsView.frame.AbsoluteSize.X, 1, 0)
		self._frame.Container.LeftTopbar.Versions.Visible = false
	else
		self._versionsView:setViewMode("popup")
		self._frame.Container.Position = UDim2.fromOffset(0, 0)
		self._frame.Container.Size = UDim2.fromScale(1, 1)
		self._frame.Container.LeftTopbar.Versions.Visible = true
	end
end

return EditKeyView
