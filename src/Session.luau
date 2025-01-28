-- Main interface with datastores

local Types = require(script.Parent.Types)
local Pages = require(script.Parent.Pages)

local DataStoreService = game:GetService("DataStoreService")

local Settings = require(script.Parent.Settings)

type Session = any

local Session = {}
Session.__index = Session

-- Static

function Session.new()
	local self = setmetatable({
		datastore = nil,
		connection = nil :: Types.DataStoreConnection?,

		dataStorePages = nil,

		keyPages = nil,

		currentKey = nil,
		currentValue = nil,
		currentKeyInfo = nil,
		currentVersion = nil,
		versionPages = nil,
	}, Session)

	return self
end

-- Methods

local actionRequestBudgets = {
	list = { [Enum.DataStoreRequestType.ListAsync] = 1 },
	listOrdered = { [Enum.DataStoreRequestType.GetSortedAsync] = 1 },
	["duplicate"] = { [Enum.DataStoreRequestType.SetIncrementAsync] = 1, [Enum.DataStoreRequestType.GetAsync] = 1 },
	["move"] = { [Enum.DataStoreRequestType.SetIncrementAsync] = 2, [Enum.DataStoreRequestType.GetAsync] = 1 },
}
function Session:hasBudgetFor(action: "list" | "listOrdered" | "duplicate" | "move"): boolean
	for requestType, amount in actionRequestBudgets[action] do
		if DataStoreService:GetRequestBudgetForRequestType(requestType) < amount then
			return false
		end
	end
	return true
end

function Session:tryConnect(connection: Types.DataStoreConnection): (boolean, string?)
	local datastore = nil
	if connection.isOrdered then
		local success, err = pcall(function()
			datastore = DataStoreService:GetOrderedDataStore(connection.name, connection.scope)
		end)

		if not success then
			return false, err
		end

		self:resetKey()
		self.datastore = datastore
	else
		local params = Instance.new("DataStoreOptions")
		params.AllScopes = not not connection.allScopes
		if connection.allScopes then
			connection.scope = "" -- Has to be to work
		end

		local success, err = pcall(function()
			datastore = DataStoreService:GetDataStore(connection.name, connection.scope, params)
		end)

		if not success then
			return false, err
		end

		self:resetKey()
		self.datastore = datastore
	end

	self.keyPages = nil
	self.connection = connection

	return true
end

function Session:tryLoadKey(key: string): (boolean, string?)
	local params = Instance.new("DataStoreGetOptions")
	params.UseCache = false

	local value, keyInfo = nil
	local success, err = pcall(function()
		value, keyInfo = self.datastore:GetAsync(key, params)
	end)

	if not success then
		return false, err
	end

	self:resetKey()

	self.currentKey = key
	self.currentValue = value
	self.currentKeyInfo = keyInfo

	return true
end

function Session:tryLoadVersion(key: string, version: string): (boolean, string?)
	assert(not self.connection.isOrdered)

	local value, keyInfo = nil
	local success, err = pcall(function()
		value, keyInfo = self.datastore:GetVersionAsync(key, version)
	end)

	if not success then
		return false, err
	end

	self.currentKey = key
	self.currentValue = value
	self.currentKeyInfo = keyInfo
	self.currentVersion = version

	return true
end

function Session:resetKey()
	self.currentKey = nil
	self.currentValue = nil
	self.currentKeyInfo = nil
	self.currentVersion = nil
	self.versionPages = nil
end

function Session:trySeeKeyChanged(): "changed" | "failed" | "unchanged"
	assert(not self.connection.isOrdered)

	if self.currentVersion then
		-- Loading a version will always have the UpdatedTime before the latest UpdatedTime,
		-- so just ignore this check
		return "failed"
	end

	local params = Instance.new("DataStoreGetOptions")
	params.UseCache = false

	local gotValue, gotKeyInfo = nil, nil
	local success, err = pcall(function()
		gotValue, gotKeyInfo = self.datastore:GetAsync(self.currentKey, params)
	end)

	if success then
		if self.currentKeyInfo then
			if self.currentKeyInfo.UpdatedTime + 1 < gotKeyInfo.UpdatedTime then
				return "changed"
			else
				return "unchanged"
			end
		elseif gotKeyInfo then
			return "changed"
		end
	else
		return "failed"
	end
end

function Session:trySaveCurrentKey(value: any, userIds: { number }, metadata: { [string]: any })
	assert(not self.connection.isOrdered)

	local newValue, newKeyInfo = nil, nil
	local success, err = pcall(function()
		-- NOTE: error in the callback will not propagate to the pcall so
		newValue, newKeyInfo = self.datastore:UpdateAsync(self.currentKey, function()
			if self.currentKeyInfo then
				return value, userIds or self.currentKeyInfo:GetUserIds(), metadata or self.currentKeyInfo:GetMetadata()
			else
				return value
			end
		end)
	end)

	if success then
		self.currentValue = newValue
		self.currentKeyInfo = newKeyInfo
		self.currentVersion = nil
	end

	return success, err
end

function Session:tryDeleteCurrentKey()
	local success, err = pcall(function()
		self.datastore:RemoveAsync(self.currentKey)
	end)

	if success then
		self:resetKey()
	end

	return success, err
end

function Session:tryDeleteKey(keyName: string)
	if keyName == self.currentKey then
		return self:tryDeleteCurrentKey()
	else
		local success, err = pcall(function()
			self.datastore:RemoveAsync(keyName)
		end)

		return success, err
	end
end

export type DuplicateKeyOptions = {
	data: any,
	metadata: any,
	userIds: number,

	newKey: string,
	deleteKey: boolean,
}

-- Must call tryLoadKey after to load the transferred key.
function Session:tryDuplicateKey(options: DuplicateKeyOptions): (boolean, string?)
	assert(not self.connection.isOrdered)
	assert(self.datastore)

	local success, err = pcall(function()
		local setOptions = Instance.new("DataStoreSetOptions")
		setOptions:SetMetadata(options.metadata)

		self.datastore:SetAsync(options.newKey, options.data, options.userIds, setOptions)
	end)

	if not success then
		return false, err
	end

	if options.deleteKey then
		local success, err = pcall(function()
			self.datastore:RemoveAsync(self.currentKey)
		end)

		if not success then
			return false, err
		end
	end

	return true
end

function Session:tryDeleteCurrentKeyVersion(version: string)
	assert(not self.connection.isOrdered)

	local success, err = pcall(function()
		self.datastore:RemoveVersionAsync(self.currentKey, version)
	end)

	return success, err
end

function Session:tryCreateVersionPages(
	order: Enum.SortDirection,
	minDate: number?,
	maxDate: number?
): (boolean, string?)
	assert(not self.connection.isOrdered)

	local pages, err = Pages.wrapListing(function()
		return self.datastore:ListVersionsAsync(self.currentKey, order, minDate, maxDate, 16)
	end)

	if err then
		return false, err
	else
		self.versionPages = pages
		return true
	end
end

-- DataStore listing
function Session:tryCreateDataStorePages(prefix: string?): (boolean, string?)
	local pages, err = Pages.wrapListing(function()
		return DataStoreService:ListDataStoresAsync(prefix)
	end)

	if err then
		return false, err
	else
		self.dataStorePages = pages
		return true
	end
end

function Session:tryCreateKeyPages(prefix: string?): (boolean, string?)
	assert(not self.connection.isOrdered)
	-- TODO: if all keys are deleted in the page, nothing will happen
	--       user should be informed that all the keys were deleted
	local pages, err = Pages.wrapListing(function()
		return self.datastore:ListKeysAsync(prefix, nil, nil, not Settings.get("listDeletedKeys"))
	end)

	if err then
		return false, err
	else
		self.keyPages = pages
		return true
	end
end

-- Ordered data store
function Session:tryCreateOrderedKeyPages(
	order: "ascending" | "descending",
	min: number?,
	max: number?
): (boolean, string?)
	assert(self.connection.isOrdered)

	local pages, err = Pages.wrapListing(function()
		return self.datastore:GetSortedAsync(order == "ascending", 50, min, max)
	end)

	if err then
		return false, err
	else
		self.keyPages = pages
		return true
	end
end

function Session:trySetOrderedKey(key: string, value: number): (boolean, string?)
	assert(self.connection.isOrdered)

	local success, err = pcall(function()
		self.datastore:SetAsync(key, value)
	end)

	if success then
		return true
	else
		return success, err
	end
end

function Session:tryRemoveOrderedKey(key: string): (boolean, string?)
	assert(self.connection.isOrdered)

	local success, err = pcall(function()
		self.datastore:RemoveAsync(key)
	end)

	if success then
		return true
	else
		return success, err
	end
end

function Session:tryGetOrderedKey(key: string): (number?, string?)
	assert(self.connection.isOrdered)

	local value = nil
	local success, err = pcall(function()
		value = self.datastore:GetAsync(key)
	end)

	if success then
		return value
	else
		return nil, err
	end
end

function Session:destroy() end

return Session
