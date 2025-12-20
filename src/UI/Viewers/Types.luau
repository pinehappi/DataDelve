--!strict

local JSONHelper = require(script.Parent.Parent.Parent.JSONHelper)
local Theme = require(script.Parent.Parent.Theme)
local UIMessages = require(script.Parent.Parent.UIMessages)
local ModalState = require(script.Parent.Parent.ModalState)

export type ViewerMode = "Tree" | "Code"

export type KeyInfo = {
	CreatedTime: number,
	UpdatedTime: number,
	Version: string,
	UserIds: { number },
	Metadata: any,
}

export type NewOptions = {
	data: JSONHelper.JSONValue,
	keyInfo: KeyInfo?,
	dirty: boolean?, -- If it's dirty by default

	modalState: ModalState.ModalState,

	readOnly: boolean, -- default: false

	-- default: false
	-- If all the branches start out open
	allOpen: boolean?,

	-- default: true. Difference between this and `keyInfo = nil` is that `keyInfo = nil` will still
	-- show the the Key Info area, but disabling this will completely disable the Key Info area.
	showKeyInfo: boolean?,

	isTesting: boolean?, -- default: false

	inputReceiver: Frame | UserInputService | nil,
}

export type ViewerClass = {
	from: (Theme.Theme, UIMessages.UIMessages, GuiObject, NewOptions) -> Viewer,
}

export type GetValueResult = | { kind: "success", value: unknown, hasNil: boolean } | { kind: "failure", message: string }

export type Viewer = {
	dirtyChanged: RBXScriptSignal,
	isDirty: boolean,
	idLookedUp: RBXScriptSignal,

	setDisabled: (Viewer, disabled: boolean) -> (),
	undirty: (Viewer) -> (),

	getValue: (Viewer) -> GetValueResult,

	getHistoryCapability: (Viewer) -> HistoryCapability?,
	getKeyInfoCapability: (Viewer) -> KeyInfoCapability?,
	getSearchCapability: (Viewer) -> SearchCapability?,

	destroy: (Viewer) -> (),
}

export type HistoryCapability = {
	historyChanged: RBXScriptSignal,

	canUndo: (HistoryCapability) -> (),
	undo: (HistoryCapability) -> (),

	canRedo: (HistoryCapability) -> (),
	redo: (HistoryCapability) -> (),
}

export type KeyInfoCapability = {
	getKeyInfo: (KeyInfoCapability) -> (--[[userIds:]]
		{ number }, --[[metadata]]
		{ [string]: any }
	),
}

export type SearchResult = {
	kind: "success",
	matches: number,
} | {
	kind: "none",
}

export type SearchCapability = {
	setSearch: (SearchCapability, term: string) -> (),
	endSearch: (SearchCapability) -> (),
	jumpNextMatch: (SearchCapability) -> (),
	jumpPrevMatch: (SearchCapability) -> (),
	searchResultsChanged: RBXScriptSignal,
}

return {}
