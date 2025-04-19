--!strict

local Theme = require(script.Parent.Parent.Theme)
local History = require(script.Parent.Parent.Parent.History)
local Types = require(script.Parent.Parent.Parent.Types)

local Assets = script.Parent.Parent.Assets

local StyleState = script.Parent.Parent.StyleState
local StyleStateHelper = require(StyleState.StyleStateHelper)
local ButtonStyleState = require(StyleState.ButtonStyleState)
local LabelStyleState = require(StyleState.LabelStyleState)

local ContextMenuStyleState = require(StyleState.Utility.ContextMenuStyleState)

export type HistoryFrame = typeof(Assets.Widgets.MainApp.ConnectDataStore.Content.History)
type ConnectionRow = typeof(Assets.ConnectionRow)

local function getStyleStates(theme: Theme.Theme, frame: HistoryFrame)
	return {
		labels = LabelStyleState.fromDescendants(theme, frame),
	}
end

type HistoryFieldImplementation = {
	__index: HistoryFieldImplementation,

	from: (HistoryFrame) -> HistoryView,

	update: (HistoryView, StyleStateHelper.TransitionSpeed) -> (),
	destroy: (HistoryView, completely: boolean) -> (),

	_updateConnectionsHistory: (HistoryView) -> (),
}

type HistoryViewFields = {
	frame: HistoryFrame,
	_widget: PluginGui,
	_history: History.History,
	_theme: Theme.Theme,
	_styleStates: typeof(getStyleStates({} :: any, {} :: any)),
	_connections: { RBXScriptConnection },

	_connectionRecordStyleStates: { StyleStateHelper.StyleState },

	_connectionRecordSelected: BindableEvent,
	_connectionRecordDeleted: BindableEvent,
	_connectionRecordPinChanged: BindableEvent,
	_connectionRecordLoaded: BindableEvent,

	connectionRecordSelected: RBXScriptSignal,
	connectionRecordDeleted: RBXScriptSignal,
	connectionRecordPinChanged: RBXScriptSignal,
	connectionRecordLoaded: RBXScriptSignal,
}

export type HistoryView = typeof(setmetatable({} :: HistoryViewFields, {} :: HistoryFieldImplementation))

local HistoryView = {} :: HistoryFieldImplementation
HistoryView.__index = HistoryView

function HistoryView.from(theme: Theme.Theme, history: History.History, frame: HistoryFrame)
	local self = setmetatable({}, HistoryView)
	self.frame = frame
	self._history = history
	self._widget = frame:FindFirstAncestorWhichIsA("PluginGui")

	self._connectionRecordSelected = Instance.new("BindableEvent")
	self._connectionRecordDeleted = Instance.new("BindableEvent")
	self._connectionRecordPinChanged = Instance.new("BindableEvent")
	self._connectionRecordLoaded = Instance.new("BindableEvent")

	self.connectionRecordSelected = self._connectionRecordSelected.Event :: RBXScriptSignal
	self.connectionRecordDeleted = self._connectionRecordDeleted.Event :: RBXScriptSignal
	self.connectionRecordPinChanged = self._connectionRecordPinChanged.Event :: RBXScriptSignal
	self.connectionRecordLoaded = self._connectionRecordLoaded.Event :: RBXScriptSignal

	self._theme = theme
	self._styleStates = getStyleStates(theme, frame)

	self._connectionRecordStyleStates = {}
	self._connections = {
		theme.colorsChanged:Connect(function()
			task.wait()
			self:update("slow")
		end),
		history.connectionsChanged:Connect(function()
			self:_updateConnectionsHistory()
		end),
	}

	self:_updateConnectionsHistory()
	return self
end

local function updateConnectionRowPinVisual(row: ConnectionRow, theme: Theme.Theme, pinned: boolean?)
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

function HistoryView:_updateConnectionsHistory()
	local records = self._history.connectionRecords
	local isVisible = (#records > 0)

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
		row.ConnectionType.Text = if record.connection.allScopes
			then "AllScopes"
			elseif record.connection.isOrdered then "Ordered"
			else "Normal"
		row.LastAccess.Text = DateTime.fromUnixTimestamp(record.lastAccess):FormatUniversalTime("ll LT", "en-us")
		row.LayoutOrder = if record.pinned then 0 else 1
		updateConnectionRowPinVisual(row, self._theme, record.pinned)
		row.Parent = self.frame.Table

		local styleState = ButtonStyleState.from(self._theme, row, {
			style = "transparent",
		})

		table.insert(self._connectionRecordStyleStates, styleState)

		row.Activated:Connect(function()
			self._connectionRecordSelected:Fire(record)
		end)
		row.MouseButton2Click:Connect(function()
			styleState:setSelecting(true):update()
			local option =
				ContextMenuStyleState.prompt(self._theme, self._widget, self._widget:GetRelativeMousePosition(), {
					options = {
						if record.pinned
							then { icon = self._theme.icons.unpin, text = "Unpin" }
							else { icon = self._theme.icons.pin, text = "Pin" },
						{ icon = self._theme.icons.import, text = "Load" },
						{ icon = self._theme.icons.delete, text = "Delete" },
					},
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

function HistoryView:update(speed: StyleStateHelper.TransitionSpeed)
	StyleStateHelper.update(self._styleStates, speed)
end

function HistoryView:destroy(completely)
	for _, connection in self._connections do
		connection:Disconnect()
	end

	for _, styleState in self._connectionRecordStyleStates do
		styleState:destroy(true)
	end

	for _, v in self :: any do
		if v:IsA("BindableEvent") then
			v:Destroy()
		end
	end

	table.clear(self :: any)
end

return HistoryView
