local UIMessages = require(script.Parent.Parent.UIMessages)
local Theme = require(script.Parent.Parent.Theme)

export type BufferViewerFromOptions = {
	uiMessages: UIMessages.UIMessages,
	theme: Theme.Theme,
	inputReceiver: GuiObject,
	widget: PluginGui,
}

export type BufferViewer = {
	capabilities: Capabilities,
	from: (buf: buffer, container: Frame, options: BufferViewerFromOptions) -> BufferViewer,
	setValue: (BufferViewer, buf: buffer) -> (),
	getValue: (BufferViewer) -> buffer,
	destroy: (BufferViewer) -> (),

	undo: (UndoRedoCapability) -> (),
	redo: (UndoRedoCapability) -> (),
	canUndo: (UndoRedoCapability) -> boolean,
	canRedo: (UndoRedoCapability) -> boolean,
	historyChanged: RBXScriptSignal,
}

return {}
