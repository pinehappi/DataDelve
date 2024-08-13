--!strict

local DESCENDING_ICON = "rbxassetid://17650920474"
local ASCENDING_ICON = "rbxassetid://17650919434"

local rfmt = require(script.Parent.Parent.rfmt)

local StyleState = script.Parent.StyleState
local Assets = script.Parent.Assets

local Theme = require(script.Parent.Theme)
local UIMessages = require(script.Parent.UIMessages)
local Tooltip = require(script.Parent.Tooltip)
local StyleStateHelper = require(StyleState.StyleStateHelper)

local BackgroundStyleState = require(StyleState.BackgroundStyleState)
local ButtonStyleState = require(StyleState.ButtonStyleState)
local LabelStyleState = require(StyleState.LabelStyleState)
local LoadMoreListStyleState = require(StyleState.LoadMoreListStyleState)
local SeparatorStyleState = require(StyleState.SeparatorStyleState)

local DatePickerStyleState = require(StyleState.Input.DatePickerStyleState)

local ContextMenuStyleState = require(StyleState.Utility.ContextMenuStyleState)

local VersionsView = {}
VersionsView.__index = VersionsView

function VersionsView.from(theme: Theme.Theme, uiMessages: UIMessages.UIMessages, frame: typeof(Assets.Widget.Versions))
	local self = setmetatable({}, VersionsView)
	self.theme = theme
	self.uiMessages = uiMessages
	self.frame = frame
	self.connections = {}
	
	-- State

	self.currentVersion = nil :: string?
	self.locked = false

	self.order = Enum.SortDirection.Descending
	self.minDate = nil
	self.maxDate = nil
	
	-- Events
	
	self._versionLoaded = Instance.new("BindableEvent")
	self.versionLoaded = self._versionLoaded.Event
	
	self._versionDeleted = Instance.new("BindableEvent")
	self.versionDeleted = self._versionDeleted.Event
	
	self._reloaded = Instance.new("BindableEvent")
	self.reloaded = self._reloaded.Event
	
	-- Style states
	
	self.styleStates = {
		background = BackgroundStyleState.from(theme, frame, {
			style = "popup"
		}),
		title = LabelStyleState.from(theme, frame.Title),
		instructions = LabelStyleState.from(theme, frame.Instructions),
		close = ButtonStyleState.from(theme, frame["Escape Layout"].Close, {
			style = "dormant"
		}),
		
		order = ButtonStyleState.from(theme, frame.Actions.Order),
		list = ButtonStyleState.from(theme, frame.Actions.List, {
			style = "primary",
		}),
		minDate = DatePickerStyleState.from(theme, frame.Actions.MinDate),
		maxDate = DatePickerStyleState.from(theme, frame.Actions.MaxDate, {
			upToEndOfDay = true
		}),
		loadMore = LoadMoreListStyleState.from(theme, frame.List.Table, {
			createItemStyleState = function(loadMoreListStyleState, info: DataStoreObjectVersionInfo)
				local row = Assets.VersionRow:Clone()
				local styleState = ButtonStyleState.from(theme, row, {
					style = "transparent"
				})
				row.Created.Text = DateTime.fromUnixTimestampMillis(info.CreatedTime):FormatUniversalTime("ll LT", "en-us")
				row.Deleted.Text = if info.IsDeleted then "Yes" else "No"
				row.Version.Text = info.Version
				if info.Version == self.currentVersion then
					row.Version.FontFace = Font.new(row.Version.FontFace.Family, Enum.FontWeight.Bold, row.Version.FontFace.Style)
				end
				
				row.Name = info.Version
				row.Parent = loadMoreListStyleState.frame
				
				row.MouseButton2Click:Connect(function()
					if not row.Active then return end
					local gui = row:FindFirstAncestorWhichIsA("PluginGui")
					if gui then
						loadMoreListStyleState:setSelectingStyleState(styleState)
						local option = ContextMenuStyleState.prompt(theme, gui, gui:GetRelativeMousePosition(), {
							options = {
								{ icon=self.theme.icons.import, text="Load" },
								{ icon=self.theme.icons.delete, text="Delete" },
							}
						})
						loadMoreListStyleState:setSelectingStyleState(nil)
						
						if option == "Load" then
							self._versionLoaded:Fire(info.Version)
						elseif option == "Delete" then
							self._versionDeleted:Fire(info.Version)
						end
					end
				end)
				
				row.Activated:Connect(function()
					self._versionLoaded:Fire(info.Version)
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
		
		listLabels = LabelStyleState.fromDescendants(theme, frame.List),
		listSeparators = SeparatorStyleState.fromDescendants(theme, frame.List),
	}
	
	-- Event connections
	
	table.insert(self.connections, theme.colorsChanged:Connect(function()
		task.wait()
		StyleStateHelper.update(self.styleStates :: any)
	end))
	
	self.styleStates.order.button.Activated:Connect(function()
		if self.order == Enum.SortDirection.Ascending then
			self.order = Enum.SortDirection.Descending
			self.styleStates.order.button.ImageLabel.Image = DESCENDING_ICON
		else
			self.order = Enum.SortDirection.Ascending
			self.styleStates.order.button.ImageLabel.Image = ASCENDING_ICON
		end
		self._reloaded:Fire()
	end)
	self.styleStates.list.button.Activated:Connect(function()
		self._reloaded:Fire()
	end)
	
	self.styleStates.minDate.textBox.FocusLost:Connect(function(entered)
		local date = self.styleStates.minDate:getValue()
		self.minDate = date
		
		if entered then
			self._reloaded:Fire()
		end
	end)
	self.styleStates.maxDate.textBox.FocusLost:Connect(function(entered)
		local date = self.styleStates.maxDate:getValue()
		self.maxDate = date
		
		if entered then
			self._reloaded:Fire()
		end
	end)
	
	self.styleStates.minDate.errorChanged:Connect(function()
		self:_updateListButtonsLocked()
	end)
	self.styleStates.maxDate.errorChanged:Connect(function()
		self:_updateListButtonsLocked()
	end)
	
	-- Tooltips
	Tooltip.bindButtonGeneric(self.theme, self.styleStates.order.button, `Order\nToggle between newest-to-oldest or oldest-to-newest.`)
	Tooltip.bindButtonGeneric(self.theme, self.styleStates.list.button, `Lists versions. Equivalent to {rfmt.code("ListVersionsAsync")}.`)

	return self
end

function VersionsView:_updateListButtonsLocked()
	local locked = self.styleStates.minDate.error or self.styleStates.maxDate.error
	self.styleStates.order:setDisabled(self.locked or locked):update()
	self.styleStates.list:setDisabled(self.locked or locked):update()
end

function VersionsView:setCurrentVersion(currentVersion: string)
	self.currentVersion = currentVersion
end

function VersionsView:setLocked(locked: boolean)
	self.locked = locked

	self.styleStates.minDate:setDisabled(locked):update()
	self.styleStates.maxDate:setDisabled(locked):update()
	self:_updateListButtonsLocked()

	for _, styleState in self.styleStates.loadMore.itemStyleStates do
		styleState:setDisabled(styleState.SECRET_ACTUALLY_DISABLE or locked):update()
	end
end

function VersionsView:deleteVersion(version: string)
	for _, styleState in self.styleStates.loadMore.itemStyleStates do
		if styleState.button.Name == version then
			styleState.button.Deleted.Text = "Yes"
			styleState.SECRET_ACTUALLY_DISABLE = true
			styleState:setDisabled(true):update("instant")
		end
	end
end

function VersionsView:reset()
	self.styleStates.loadMore:clear()
	
	self.currentVersion = nil
	
	self.order = Enum.SortDirection.Descending
	self.styleStates.order.button.ImageLabel.Image = DESCENDING_ICON

	self.minDate = nil
	self.styleStates.minDate.textBox.Text = ""
	
	self.maxDate = nil
	self.styleStates.maxDate.textBox.Text = ""

	self.frame.List.Visible = false
end

function VersionsView:destroy()
	
end

return VersionsView