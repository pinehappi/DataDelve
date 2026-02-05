--!strict

local UIMessages = require(script.Parent.Parent.UIMessages)
local Theme = require(script.Parent.Parent.Theme)

export type BufferViewerMode = "Hex" | "Deserializer"

export type BufferViewerFromOptions = {
	uiMessages: UIMessages.UIMessages,
	theme: Theme.Theme,
	inputReceiver: GuiObject,
	widget: PluginGui,
}

export type BufferViewer = {
	from: (buf: buffer, container: Frame, options: BufferViewerFromOptions) -> BufferViewer,
	setValue: (BufferViewer, buf: buffer) -> (),
	getValue: (BufferViewer) -> buffer,
	destroy: (BufferViewer) -> (),
	
	undo: (BufferViewer) -> (),
	redo: (BufferViewer) -> (),
	canUndo: (BufferViewer) -> boolean,
	canRedo: (BufferViewer) -> boolean,
	historyChanged: RBXScriptSignal,
}

return {}