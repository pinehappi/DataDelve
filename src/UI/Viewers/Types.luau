--!strict

local JSONHelper = require(script.Parent.Parent.Parent.JSONHelper)
local Theme = require(script.Parent.Parent.Theme)
local UIMessages = require(script.Parent.Parent.UIMessages)

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

export type BaseViewer = {
	dirtyChanged: RBXScriptSignal,
	isDirty: boolean,
	idLookedUp: RBXScriptSignal,

	setDisabled: (BaseViewer, disabled: boolean) -> (),
	undirty: (BaseViewer) -> (),

	getValue: (BaseViewer) -> GetValueResult,

	destroy: (BaseViewer) -> (),
}

export type HistoryCapableViewer = BaseViewer & {
	historyChanged: RBXScriptSignal,

	canUndo: (Viewer) -> (),
	undo: (Viewer) -> (),

	canRedo: (Viewer) -> (),
	redo: (Viewer) -> (),

	isHistoryCapable: true,
	isKeyInfoCapable: false, -- this is not actually true, it is just for the type narrowing
}

export type KeyInfoCapableViewer = BaseViewer & {
	getKeyInfo: (Viewer) -> (--[[userIds:]]
		{ number }, --[[metadata]]
		{ [string]: any }
	),

	isHistoryCapable: false, -- this is not actually true, it is just for the type narrowing
	isKeyInfoCapable: true,
}

export type Viewer = KeyInfoCapableViewer | HistoryCapableViewer

return {}
