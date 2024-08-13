--!strict

-- I was going to use this more, but I forgot about it. Now it houses these two types.

type DataStoreConnectionBase = {
	name: string,
	scope: string?,
	isOrdered: boolean,
}
type AllScopesDataStoreConnection = DataStoreConnectionBase & {
	isOrdered: false,
	allScopes: true,
}
type NormalDataStoreConnection = DataStoreConnectionBase & {
	isOrdered: boolean,
	allScopes: false,
}
export type DataStoreConnection = AllScopesDataStoreConnection | NormalDataStoreConnection

export type DataStoreConnectionRecord = {
	connection: DataStoreConnection,
	lastAccess: typeof(DateTime.now().UnixTimestamp),
	-- newly added stuff
	pinned: boolean?,
}

return {}