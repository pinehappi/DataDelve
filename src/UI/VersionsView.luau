--!strict

local DESCENDING_ICON = "rbxassetid://17650920474"
local ASCENDING_ICON = "rbxassetid://17650919434"

local rfmt = require(script.Parent.Parent.rfmt)

local StyleState = script.Parent.StyleState
local Assets = script.Parent.Assets

local Session = require(script.Parent.Parent.Session)
local Transactor = require(script.Parent.Parent.Transactor)

local Theme = require(script.Parent.Theme)
local UIMessages = require(script.Parent.UIMessages)
local Tooltip = require(script.Parent.Tooltip)
local PopupHelper = require(script.Parent.PopupHelper)
local StyleStateHelper = require(StyleState.StyleStateHelper)

local BackgroundStyleState = require(StyleState.BackgroundStyleState)
local ButtonStyleState = require(StyleState.ButtonStyleState)
local LabelStyleState = require(StyleState.LabelStyleState)
local LoadMoreListStyleState = require(StyleState.LoadMoreListStyleState)
local SeparatorStyleState = require(StyleState.SeparatorStyleState)

local DatePickerStyleState = require(StyleState.Input.DatePickerStyleState)

local ContextMenuStyleState = require(StyleState.Utility.ContextMenuStyleState)
local ConfirmDialogStyleState = require(StyleState.Utility.ConfirmDialogStyleState)
local LoadingBarStyleState = require(StyleState.Utility.LoadingBarStyleState)

local createTabSwitchGroup = require(script.Parent.Utilities.createTabSwitchGroup)

local VersionsView = {}
VersionsView.__index = VersionsView

-- Returns true with a callback if the version load should be continued with
-- or false if user cancelled.
export type LoadVersionCallback = (version: string) -> (boolean, (() -> (boolean, string?))?)

export type VersionsViewFromParams = {
	theme: Theme.Theme,
	uiMessages: UIMessages.UIMessages,
	widget: PluginGui,
	frame: typeof(Assets.Views.VersionsPopup),
	session: Session.Session,
	loadVersion: LoadVersionCallback,
}

function VersionsView.from(params: VersionsViewFromParams)
	local self = setmetatable({}, VersionsView)
	self.theme = params.theme
	self.uiMessages = params.uiMessages
	self.frame = params.frame
	self.widget = params.widget
	self.connections = {}

	-- State

	self._session = params.session
	self._loadVersionCallback = params.loadVersion
	self._transactor = Transactor.new()

	self.order = Enum.SortDirection.Descending
	self.minDate = nil
	self.maxDate = nil

	-- UI

	self.modal = PopupHelper.modal(self.frame, self.widget, {
		scrimTransparency = 0.5,
	})

	self.styleStates = {
		background = BackgroundStyleState.from(self.theme, self.frame, {
			style = "popup",
		}),
		title = LabelStyleState.from(self.theme, self.frame.Title),
		instructions = LabelStyleState.from(self.theme, self.frame.Instructions),
		close = ButtonStyleState.from(self.theme, self.frame["Escape Layout"].Close, {
			style = "dormant",
		}),

		order = ButtonStyleState.from(self.theme, self.frame.Actions.Order),
		list = ButtonStyleState.from(self.theme, self.frame.Actions.List, {
			style = "primary",
		}),
		minDate = DatePickerStyleState.from(self.theme, self.frame.Actions.MinDate),
		maxDate = DatePickerStyleState.from(self.theme, self.frame.Actions.MaxDate, {
			upToEndOfDay = true,
		}),
		loadMore = LoadMoreListStyleState.from(self.theme, self.frame.List.Table, {
			createItemStyleState = function(loadMoreListStyleState, info: DataStoreObjectVersionInfo)
				local row = Assets.VersionRow:Clone()
				local styleState = ButtonStyleState.from(self.theme, row, {
					style = "transparent",
				})
				row.Created.Text = DateTime.fromUnixTimestampMillis(info.CreatedTime)
					:FormatUniversalTime("ll LT", "en-us")
				row.Deleted.Text = if info.IsDeleted then "Yes" else "No"
				row.Version.Text = info.Version
				if info.Version == self._session.currentVersion then
					row.Version.FontFace =
						Font.new(row.Version.FontFace.Family, Enum.FontWeight.Bold, row.Version.FontFace.Style)
				end

				row.Name = info.Version
				row.Parent = loadMoreListStyleState.frame

				row.MouseButton2Click:Connect(function()
					if not row.Active then
						return
					end

					local resetSelecting = loadMoreListStyleState:setSelectingStyleState(styleState)
					local option =
						ContextMenuStyleState.prompt(self.theme, self.widget, self.widget:GetRelativeMousePosition(), {
							options = {
								{ icon = self.theme.icons.import, text = "Load" },
								{ icon = self.theme.icons.delete, text = "Delete" },
							},
						})
					resetSelecting()

					if option == "Load" then
						self:_loadVersion(info.Version)
					elseif option == "Delete" then
						self:_deleteVersion(info.Version)
					end
				end)

				row.Activated:Connect(function()
					self:_loadVersion(info.Version)
				end)

				styleState:setDisabled(info.IsDeleted):update("instant")
				if info.IsDeleted then
					-- Inject this secretly into the styleState so when locked state is change
					-- it knows to make sure to disable this
					styleState.SECRET_ACTUALLY_DISABLE = true
				end
				return styleState
			end,
		}),

		listLabels = LabelStyleState.fromDescendants(self.theme, self.frame.List),
		listSeparators = SeparatorStyleState.fromDescendants(self.theme, self.frame.List),
	}

	-- Extra setup

	createTabSwitchGroup({
		self.styleStates.minDate.textBox,
		self.styleStates.maxDate.textBox,
	})

	-- Event connections

	table.insert(
		self.connections,
		self.theme.colorsChanged:Connect(function()
			task.wait()
			StyleStateHelper.update(self.styleStates :: any)
		end)
	)

	table.insert(
		self.connections,
		self.styleStates.order.button.Activated:Connect(function()
			if self.order == Enum.SortDirection.Ascending then
				self.order = Enum.SortDirection.Descending
				self.styleStates.order.button.ImageLabel.Image = DESCENDING_ICON
			else
				self.order = Enum.SortDirection.Ascending
				self.styleStates.order.button.ImageLabel.Image = ASCENDING_ICON
			end
			self:_reload()
		end)
	)
	table.insert(
		self.connections,
		self.styleStates.list.button.Activated:Connect(function()
			self:_reload()
		end)
	)

	table.insert(
		self.connections,
		self.styleStates.minDate.textBox.FocusLost:Connect(function(entered, input)
			if input == nil then
				return
			end

			local date = self.styleStates.minDate:getValue()
			self.minDate = date

			if entered then
				self:_reload()
			end
		end)
	)

	table.insert(
		self.connections,
		self.styleStates.maxDate.textBox.FocusLost:Connect(function(entered, input)
			if input == nil then
				return
			end

			local date = self.styleStates.maxDate:getValue()
			self.maxDate = date

			if entered then
				self:_reload()
			end
		end)
	)

	table.insert(
		self.connections,
		self.styleStates.loadMore.buttonStyleState.button.Activated:Connect(function()
			if self._session.versionPages then
				if not self._session.versionPages.isFinished then
					self:_runOperation(function()
						local _, err = self._session.versionPages:increment()
						if err then
							self.uiMessages:reportDataStoreError(err)
						end
					end)
				end
			end
		end)
	)

	table.insert(
		self.connections,
		self.styleStates.minDate.errorChanged:Connect(function()
			self:_updateListButtonsLocked()
		end)
	)
	table.insert(
		self.connections,
		self.styleStates.maxDate.errorChanged:Connect(function()
			self:_updateListButtonsLocked()
		end)
	)

	table.insert(
		self.connections,
		self.styleStates.close.button.Activated:Connect(function()
			if self._transactor.locked then
				return
			end
			self:destroy(true)
		end)
	)

	table.insert(
		self.connections,
		self.modal.cancelled:Connect(function()
			if self._transactor.locked then
				return
			end
			self:destroy(true)
		end)
	)

	table.insert(
		self.connections,
		self._transactor.lockedChanged:Connect(function(locked)
			self.styleStates.minDate:setDisabled(locked):update()
			self.styleStates.maxDate:setDisabled(locked):update()
			self:_updateListButtonsLocked()

			for _, styleState in self.styleStates.loadMore.itemStyleStates do
				styleState:setDisabled(styleState.SECRET_ACTUALLY_DISABLE or locked):update()
			end
		end)
	)

	-- Tooltips
	self._tooltipDestructors = {
		Tooltip.bindButtonGeneric(
			self.theme,
			self.styleStates.order.button,
			`Order\nToggle between newest-to-oldest or oldest-to-newest.`
		),
		Tooltip.bindButtonGeneric(
			self.theme,
			self.styleStates.list.button,
			`Lists versions. Equivalent to {rfmt.code("ListVersionsAsync")}.`
		),
	}

	task.spawn(function()
		self:_reload()
	end)

	return self
end

function VersionsView:_loadVersion(version: string)
	local shouldContinue, continueCallback = self._loadVersionCallback(version)
	if shouldContinue and continueCallback then
		local success = self:_runOperation(function()
			local success, err = continueCallback()
			if not success then
				self.uiMessages:reportDataStoreError(err)
			else
				self.uiMessages:success(`Loaded version {version}.`)
			end
		end)

		if success then
			self:destroy(true)
		end
	end
end

function VersionsView:_deleteVersion(version: string)
	if self._transactor.locked then
		return
	end

	local popupPosition = self.widget:GetRelativeMousePosition()
	if
		not ConfirmDialogStyleState.confirm(self.theme, self.widget, popupPosition, {
			title = "Delete version?",
			message = "This is PERMANENT. You cannot undo this.",
		})
	then
		return
	end

	if self._transactor.locked then
		return
	end

	if
		not ConfirmDialogStyleState.confirm(self.theme, self.widget, popupPosition, {
			title = "Are you sure?",
			message = 'Deleting this version is <font color="#ff0000"><b>PERMANENT</b></font>. You cannot undo this!',
		})
	then
		return
	end

	self:_runOperation(function()
		local success, err = self._session:tryDeleteCurrentKeyVersion(version)
		if not success then
			self.uiMessages:reportDataStoreError(err)
		else
			self:_deleteVersionRow(version)
		end
	end)
end

function VersionsView:_reload()
	self.styleStates.loadMore:clear()
	self.styleStates.loadMore:setLoadMoreVisible(false)

	self:_runOperation(function()
		local success, err = self._session:tryCreateVersionPages(self.order, self.minDate, self.maxDate)

		if not success then
			self.uiMessages:reportDataStoreError(err)
		else
			self.frame.List.Visible = true

			self.frame.List.Table.Visible = not self._session.versionPages:isEmpty()
			self.frame.List.Empty.Visible = self._session.versionPages:isEmpty()

			self._session.versionPages:syncWithLoadMoreListStyleState(self.styleStates.loadMore)
		end
	end)
end

function VersionsView:_runOperation(transaction: Transactor.Transaction): boolean
	if self._transactor.locked then
		return false
	end

	local endLoadingBar = LoadingBarStyleState.show(self.theme, self.frame["Escape Layout"].LoadingBar)
	local success = self._transactor:transact(transaction)
	endLoadingBar()
	return success
end

function VersionsView:_updateListButtonsLocked()
	local locked = self.styleStates.minDate.error or self.styleStates.maxDate.error
	self.styleStates.order:setDisabled(self._transactor.locked or locked):update()
	self.styleStates.list:setDisabled(self._transactor.locked or locked):update()
end

function VersionsView:_deleteVersionRow(version: string)
	for _, styleState in self.styleStates.loadMore.itemStyleStates do
		if styleState.button.Name == version then
			styleState.button.Deleted.Text = "Yes"
			styleState.SECRET_ACTUALLY_DISABLE = true
			styleState:setDisabled(true):update("instant")
		end
	end
end

function VersionsView:destroy(completely: boolean)
	local self = self :: any
	StyleStateHelper.destroy(self.styleStates)

	for _, destructor in self._tooltipDestructors do
		destructor()
	end

	for _, connection in self.connections do
		connection:Disconnect()
	end

	self._transactor:destroy()
	self.modal:destroy()

	if completely then
		self.frame:Destroy()
	end

	table.clear(self)
end

return VersionsView
