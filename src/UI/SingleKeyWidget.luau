--!strict
-- This is a widget for a single key, used for "Open in New Widget"

local plugin = script:FindFirstAncestorOfClass("Plugin")

local HttpService = game:GetService("HttpService")

local Theme = require(script.Parent.Theme)
local Session = require(script.Parent.Parent.Session)
local Transactor = require(script.Parent.Parent.Transactor)
local UIMessages = require(script.Parent.UIMessages)

local Assets = script.Parent.Assets
local StyleState = script.Parent.StyleState

local EditKeyView = require(script.Parent.EditKeyView)

local StyleStateHelper = require(StyleState.StyleStateHelper)
local BackgroundStyleState = require(StyleState.BackgroundStyleState)

local WIDGET_INFO = DockWidgetPluginGuiInfo.new(
	Enum.InitialDockState.Float, -- Widget will be initialized in floating panel
	false,
	false,
	400,
	250,
	350,
	230
)

export type SingleKeyParamNewParams = {
	keyName: string,
	theme: Theme.Theme,
	session: Session.Session,
}

export type SingleKeyWidgetImplementation = {
	__index: SingleKeyWidgetImplementation,

	new: (SingleKeyParamNewParams) -> (SingleKeyWidget?, string?),
	destroy: (SingleKeyWidget) -> (),

	_trySwapEditKeyView: (SingleKeyWidget, keyName: string, version: string?) -> (boolean, string?),
}

export type SingleKeyWidgetFields = {
	deleted: RBXScriptSignal,
	_deleted: BindableEvent,

	_theme: Theme.Theme,
	_session: Session.Session,
	_transactor: Transactor.Transactor,
	_uiMessages: UIMessages.UIMessages,

	_id: string,
	_widget: DockWidgetPluginGui,
	_frame: typeof(Assets.SingleKeyWidget),
	_styleStates: { StyleStateHelper.StyleState },
	_editKeyView: EditKeyView.EditKeyView,
	_editKeyFrame: EditKeyView.EditFrame,

	_connections: { RBXScriptConnection },
}

export type SingleKeyWidget = typeof(setmetatable({} :: SingleKeyWidgetFields, {} :: SingleKeyWidgetImplementation))

local SingleKeyWidget = {} :: SingleKeyWidgetImplementation
SingleKeyWidget.__index = SingleKeyWidget

function SingleKeyWidget.new(params)
	local self = setmetatable({}, SingleKeyWidget)
	self._session = params.session
	self._transactor = Transactor.new()

	self._theme = params.theme
	self._id = HttpService:GenerateGUID()
	self._widget = plugin:CreateDockWidgetPluginGui(self._id, WIDGET_INFO)
	self._widget.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	self._widget.Title = if self._session.connection.scope and (self._session.connection.scope ~= "")
		then `{self._session.connection.name}/{self._session.connection.scope}/{params.keyName}`
		else `{self._session.connection.name}/{params.keyName}`
	self._widget.Name = "DataDelve HexEditor"
	self._widget.Enabled = false

	self._frame = Assets.SingleKeyWidget:Clone()
	self._frame.Parent = self._widget

	self._uiMessages = UIMessages.new(self._theme)
	self._uiMessages:setParent(self._widget)

	self._styleStates = {
		BackgroundStyleState.from(self._theme, self._frame.Background),
	}

	self._editKeyFrame = Assets.Views.EditKey:Clone()
	self._editKeyFrame.Position = UDim2.fromOffset(0, 0)
	self._editKeyFrame.Size = UDim2.fromScale(1, 1)
	self._editKeyFrame.Parent = self._widget
	self._editKeyView = nil :: any

	self._deleted = Instance.new("BindableEvent")
	self.deleted = self._deleted.Event :: RBXScriptSignal

	local success, err = (self :: any):_trySwapEditKeyView(params.keyName)
	if not success then
		return nil, err
	end
	self._widget.Enabled = true

	self._connections = {
		self._widget.Destroying:Connect(function()
			self:destroy()
		end),

		self._widget:GetPropertyChangedSignal("Enabled"):Connect(function()
			if not self._widget.Enabled then
				self:destroy()
			end
		end),

		self._theme.colorsChanged:Connect(function()
			StyleStateHelper.update(self._styleStates :: any)
		end),
	}

	return self
end

function SingleKeyWidget:_trySwapEditKeyView(keyName: string, version: string?)
	local success: boolean, err: string?
	local forkedSession = self._session:fork()
	if version then
		success, err = forkedSession:tryLoadVersion(keyName, version)
	else
		success, err = forkedSession:tryLoadKey(keyName)
	end

	task.wait()

	if not success then
		return false, err
	end

	if self._editKeyView then
		self._editKeyView:destroy()
	end

	local editKeyView = EditKeyView.from({
		theme = self._theme,
		uiMessages = self._uiMessages,
		frame = self._editKeyFrame,
		session = forkedSession,
		transactor = self._transactor,
		swapCallback = function(keyName, version)
			return self:_trySwapEditKeyView(keyName, version)
		end,
		isVersionLoaded = not not version,
	})

	editKeyView.deleted:Connect(function()
		self._deleted:Fire()
		self:destroy()
	end)

	editKeyView.idLookedUp:Connect(function(id)
		-- TODO: add this feature
		self._uiMessages:warn("This feature is not yet implemented for single key widgets.")
		--self:_tryLookupId(id)
	end)

	self._editKeyView = editKeyView

	return true, nil
end

function SingleKeyWidget:destroy()
	StyleStateHelper.destroy(self._styleStates :: any)

	self._uiMessages:destroy()
	self._editKeyView:destroy(true)

	if self._widget.Parent then
		self._widget:Destroy()
	end

	for _, connection in self._connections do
		connection:Disconnect()
	end

	table.clear(self :: any)
end

return SingleKeyWidget
