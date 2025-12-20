--!strict

-- I was going to use this more, but I forgot about it. Now it houses these two types.

type OldDataStoreConnectionBase = {
	name: string,
	scope: string?,
	isOrdered: boolean,
}
type OldAllScopesDataStoreConnection = OldDataStoreConnectionBase & {
	isOrdered: false,
	allScopes: true,
}
type OldNormalDataStoreConnection = OldDataStoreConnectionBase & {
	isOrdered: boolean,
	allScopes: false,
}
export type OldDataStoreConnection = OldAllScopesDataStoreConnection | OldNormalDataStoreConnection

export type NormalDataStoreConnection = {
	type: "normal",
	name: string,
	scope: string?,
}
export type OrderedDataStoreConnection = {
	type: "ordered",
	name: string,
	scope: string,
}
export type AllScopesDataStoreConnection = {
	type: "allScopes",
	name: string,
}
export type GlobalDataStoreConnection = {
	type: "global",
	-- this is just for the UI so we don't have to special-case this
	name: "global",
}
export type DataStoreConnection =
	NormalDataStoreConnection
	| OrderedDataStoreConnection
	| AllScopesDataStoreConnection
	| GlobalDataStoreConnection

export type DataStoreConnectionRecord = {
	connection: DataStoreConnection,
	lastAccess: typeof(DateTime.now().UnixTimestamp),
	-- newly added stuff
	pinned: boolean?,
}

return {}
