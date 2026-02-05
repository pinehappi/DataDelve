-- History for datastore connections and keys

local MAIN_HISTORY_KEY = "DataDelveHistory alpha 1"

local Types = require(script.Parent.Types)

local History = {}
History.__index = History

function History.new(gameId: number)
	local self = setmetatable({
		gameId = tostring(gameId),
	}, History)

	-- Sorted by most recent
	self.connectionRecords = {}

	self._connectionsChanged = Instance.new("BindableEvent")
	self.connectionsChanged = self._connectionsChanged.Event

	return self
end

local function shallowEquals(a, b): boolean
	for i, v in a do
		if b[i] ~= v then
			return false
		end
	end
	for i, v in b do
		if a[i] ~= v then
			return false
		end
	end
	return true
end

function History:addConnection(connection: Types.DataStoreConnection)
	for i, v in self.connectionRecords do
		if shallowEquals(v.connection, connection) then
			v.lastAccess = DateTime.now().UnixTimestamp
			table.remove(self.connectionRecords, i)
			table.insert(self.connectionRecords, 1, v)

			if #self.connectionRecords > 32 then
				table.remove(self.connectionRecords)
			end

			self._connectionsChanged:Fire()
			return
		end
	end

	-- If it did not find a match
	table.insert(self.connectionRecords, 1, {
		connection = table.freeze(connection),
		lastAccess = DateTime.now().UnixTimestamp,
	})

	if #self.connectionRecords > 32 then
		table.remove(self.connectionRecords)
	end

	self._connectionsChanged:Fire()
end

function History:pinConnectionRecord(connection: Types.DataStoreConnection)
	for _, v in self.connectionRecords do
		if shallowEquals(v.connection, connection) then
			v.pinned = true
			self._connectionsChanged:Fire()
			break
		end
	end
end

function History:unpinConnectionRecord(connection: Types.DataStoreConnection)
	for _, v in self.connectionRecords do
		if shallowEquals(v.connection, connection) then
			v.pinned = false
			self._connectionsChanged:Fire()
			break
		end
	end
end

function History:removeConnectionRecord(connection: Types.DataStoreConnection)
	for i, v in self.connectionRecords do
		if shallowEquals(v.connection, connection) then
			table.remove(self.connectionRecords, i)
			self._connectionsChanged:Fire()
			return
		end
	end
end

local function convertOldConnectionToNew(connection: Types.OldDataStoreConnection): Types.DataStoreConnection
	if connection.allScopes then
		return {
			type = "allScopes",
			name = connection.name
		}
	elseif connection.isOrdered then
		return {
			type = "ordered",
			name = connection.name,
			scope = connection.scope,
		}
	else
		return {
			type = "normal",
			name = connection.name,
			scope = connection.scope,
		}
	end
end

local function convertRecordsToNew(records)
	local newRecords = {}
	
	for _, v in records do
		table.insert(newRecords, {
			connection = convertOldConnectionToNew(v.connection),
			lastAccess = v.lastAccess,
			pinned = v.pinned,
		})
	end
	
	return newRecords
end

function History:load(plugin: Plugin)
	local loadedData = plugin:GetSetting(MAIN_HISTORY_KEY) or {
		games = {},
	}

	local gameLoadedData = loadedData.games[self.gameId]
	if not gameLoadedData then
		gameLoadedData = {
			isNew = true,
			connectionRecords = {},
		}
		loadedData.games[self.gameId] = gameLoadedData
	end

	self.connectionRecords =
		if gameLoadedData.isNew then gameLoadedData.connectionRecords
		else convertRecordsToNew(gameLoadedData.connectionRecords)
end

function History:save(plugin: Plugin)
	local loadedData = plugin:GetSetting(MAIN_HISTORY_KEY) or {
		games = {},
	}

	loadedData.games[self.gameId] = {
		isNew = true,
		connectionRecords = self.connectionRecords,
	}

	-- TODO: undo this!!
	plugin:SetSetting(MAIN_HISTORY_KEY, loadedData)
end

History.global = History.new(game.GameId)
export type History = typeof(History.new(1))
return History
