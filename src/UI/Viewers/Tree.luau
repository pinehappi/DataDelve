-- Handles displaying data in a tree.

-- Overview of how this works:
--  1. Flatten out the JSON into two flat arrays (see #_initializeBranchesFromData)
--       Given index n, _flatBranch[n] has the key, value, and metadata about the nth branch in the tree and _flatDepths[n] has
--       the depth of that branch.
--  2. Render based on what branches should be visible.
--       Methods to look out for in this step are _redrawBranches, _updateBranchFrame, and _initializeBranchFrame
--  There are also many special cases for the Key Info of a DataStore key included in the code.

-- Other random notes:

-- Right now insertions, deletions, and toggling visiblity are O(n)
-- This could be improved by not flattening the base tree since it doesn't really help with anything since the main iteration hotpath is in
-- _redrawBranches which iterates over visibleIndexes which can be constructed from the tree as needed instead of flattening the tree in the beginning
-- so there shouldn't be a major performance gain from using an array over a tree (probably)

-- NOTE: right now `Display as Time` for objects is disabled because it requires the children to update the parent when they change
-- NOTE: right now hierarchy bars are disabled because they're ugly

local Settings = require(script.Parent.Parent.Parent.Settings)

local JSONHelper = require(script.Parent.Parent.Parent.JSONHelper)
local Validators = require(script.Parent.Parent.Parent.Validators)
local StyleState = script.Parent.Parent.StyleState
local PopupHelper = require(script.Parent.Parent.PopupHelper)
local HexEditorWidget = require(script.Parent.Parent.Widgets.HexEditorWidget)
local Assets = script.Parent.Parent.Assets

local StyleStateWrapper = require(StyleState.StyleStateWrapper)
local BackgroundStyleState = require(StyleState.BackgroundStyleState)
local LabelStyleState = require(StyleState.LabelStyleState)
local ButtonStyleState = require(StyleState.ButtonStyleState)

local ContextMenuStyleState = require(StyleState.Utility.ContextMenuStyleState)
local ConfirmDialogStyleState = require(StyleState.Utility.ConfirmDialogStyleState)
local TextBoxStyleState = require(StyleState.Input.TextBoxStyleState)
local JsonTextBoxStyleState = require(StyleState.Input.JsonTextBoxStyleState)
local SelectStyleState = require(StyleState.Input.SelectStyleState)
local SwitchStyleState = require(StyleState.Input.SwitchStyleState)

local TimestampHelper = require(script.Parent.Parent.Utilities.TimestampHelper)
local promptKeyValueForm = require(script.Parent.Parent.Utilities.promptKeyValueForm)
local getHighlightColors = require(script.Parent.Parent.Utilities.getHighlightColors)
local lockObjectWithoutResize = require(script.Parent.Parent.Utilities.lockObjectWithoutResize)
local checkTrulyVisible = require(script.Parent.Parent.Utilities.checkTrulyVisible)

local SIZE_PER_BRANCH = script.Branch.AbsoluteSize.Y
local DRAG_AND_DROP_REGION_SIZE = 10

local FRAME_POOL_SIZE_LIMIT = 256
local UNDO_LIMIT = 64

-- For inconsolata
local CHAR_WIDTH = 7.2
local DEFAULT_FONT = Font.new(script.Branch.Key.FontFace.Family)
local ITALIC_FONT = Font.new(script.Branch.Key.FontFace.Family, Enum.FontWeight.Regular, Enum.FontStyle.Italic)
local ITALIC_BOLD_FONT = Font.new(script.Branch.Key.FontFace.Family, Enum.FontWeight.Bold, Enum.FontStyle.Italic)

type HotkeyAction = | "DELETE" | "OPEN" | "CLOSE" | "NEXT" | "PREVIOUS" | "RENAME"
local HOTKEYS: { [Enum.KeyCode]: HotkeyAction } = table.freeze({
	[Enum.KeyCode.Delete] = "DELETE",
	[Enum.KeyCode.Backspace] = "DELETE",
	[Enum.KeyCode.Right] = "OPEN",
	[Enum.KeyCode.L] = "OPEN",
	[Enum.KeyCode.Left] = "CLOSE",
	[Enum.KeyCode.H] = "CLOSE",
	[Enum.KeyCode.Down] = "NEXT",
	[Enum.KeyCode.J] = "NEXT",
	[Enum.KeyCode.Up] = "PREVIOUS",
	[Enum.KeyCode.K] = "PREVIOUS",
	[Enum.KeyCode.F2] = "RENAME",
	[Enum.KeyCode.Return] = "RENAME",
	[Enum.KeyCode.Insert] = "INSERT",
})

local Tree = {}
Tree.__index = Tree

local FLAGS = {
	"ISROOT", -- for the root of the data
	"ISKEYROOT", -- for the root of key info
	"ISUSERID", -- if it is a user id
	"ISUSERIDS", -- if iti s the array that contains user ids
	"ISMETADATA", -- if its the metadata dictionary
	"LOCKKEY", -- if key cannot be edited
	"LOCKVALUE", -- if value cannot be edited
	"ISTIME", -- if it should display as time (can either be timestamp or universal time table)
}

export type KeyInfo = {
	CreatedTime: number,
	UpdatedTime: number,
	Version: string,
	UserIds: { number },
	Metadata: any,
}

export type TreeOptions = {
	data: JSONHelper.JSONValue,
	keyInfo: KeyInfo?,
	dirty: boolean?, -- If it's dirty by default

	readOnly: boolean,
	allOpen: boolean?, -- If all the branches start out open

	isTesting: boolean?,

	inputReceiver: Frame | UserInputService | nil,
}

function Tree.new(
	theme,
	uiMessages,
	frame: ScrollingFrame & { UIListLayout: UIListLayout, UIPadding: UIPadding },
	options: TreeOptions
)
	local self = setmetatable({
		theme = theme,
		uiMessages = uiMessages,
		frame = frame,
		gui = frame:FindFirstAncestorWhichIsA("PluginGui"),

		disabled = false,
		readOnly = options.readOnly,

		_colors = getHighlightColors(theme),

		_inModal = false,
		_hoveringBranchIndex = nil,
		_selectingBranchIndex = nil,
		_selectingBranchVisibleIndex = nil,
		_selectingBranchOffset = 0, -- How much the frame grew
		_selectingIsDragging = false,

		_flatDepths = {},
		_flatBranches = {}, -- tuple { KEY, VALUE, IS_OPENED }
		_userIdsIndex = nil, -- Index of UserIds array

		_visibleIndexes = {}, -- Array of all visible indexes
		_frames = {}, -- All current visible frames (their called frames because they used to be frames, but their buttons now)
		_framePool = {}, -- Pool of unused frames. Helps a little bit with performance (but that was only with one test, may not always be the case)
		_frameConnections = {},

		_maxKeyWidth = math.max(101, frame.AbsoluteSize.X * 0.5),

		-- Overflow predictively based on scroll speed to render branches that will appear
		_overflowOffset = 0,
		_overflowDirection = false, -- False is up (negative), true is down (positive)

		-- Bars to help see hierarchy.
		_hierarchyBarFolder = Instance.new("Folder", frame),
		_hierarchyBars = {},

		_undoStack = {},
		_undoStackPosition = 0,

		_isTesting = options.isTesting,
	}, Tree)

	--
	self._dirtyChanged = Instance.new("BindableEvent")
	self.dirtyChanged = self._dirtyChanged.Event
	self.isDirty = options.dirty or false
	self._initialDirty = options.dirty or false

	self._historyChanged = Instance.new("BindableEvent")
	self.historyChanged = self._historyChanged.Event

	self._idLookedUp = Instance.new("BindableEvent")
	self.idLookedUp = self._idLookedUp.Event

	self._selectionChanged = Instance.new("BindableEvent")
	self.selectionChanged = self._selectionChanged.Event

	self.frame.CanvasPosition = Vector2.new(0, 0)
	self.frame.BackgroundColor3 = self._colors.background
	self.frame.ScrollBarImageColor3 = self._colors.scrollbar

	local rootIndex = self:_initializeBranchesFromData(options.data, options.keyInfo or {
		CreatedTime = nil,
		UpdatedTime = nil,
		Version = nil,
		UserIds = {},
		Metadata = nil,
	}, options.allOpen)
	self:_updateBranchVisible(1)
	self:_updateBranchVisible(rootIndex)
	self:_redrawBranches()

	local lastCanvasPosition = self.frame.CanvasPosition.Y
	local lastAbsoluteSizeUpdate = 0
	self._connections = {
		self.frame:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
			local delta = self.frame.CanvasPosition.Y - lastCanvasPosition
			if math.abs(delta) < 300 then -- Overflow orks better when scrolling with wheel (smoother), rather than jumping around wiht scroll bar
				if delta > 0 then
					self._overflowOffset = math.abs(delta)
					self._overflowDirection = true
				else
					self._overflowOffset = math.abs(delta)
					self._overflowDirection = false
				end
			else
				self._overflowOffset = 0
			end
			lastCanvasPosition = self.frame.CanvasPosition.Y

			self:_redrawBranches()
		end),
		self.frame:GetPropertyChangedSignal("AbsoluteWindowSize"):Connect(function()
			self:_redrawBranches()

			lastAbsoluteSizeUpdate = os.clock()

			task.delay(0.5, function()
				if os.clock() - lastAbsoluteSizeUpdate >= 0.495 then
					lastAbsoluteSizeUpdate = os.clock()
					-- TODO: should not do this if the tree is not visible

					self._maxKeyWidth = math.max(101, frame.AbsoluteSize.X * 0.5)
					for i, frame in self._frames do
						self:_updateBranchFrameSize(frame, self._flatBranches[i])
					end
				end
			end)
		end),

		self.frame.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseMovement then
				self:_setHovering(nil)
			end
		end),

		theme.colorsChanged:Connect(function()
			self:_updateColors()
		end),

		Settings.changed:Connect(function(settingName)
			if settingName == "highlightColors" or settingName == "useAlternatingKeyColors" then
				self:_updateColors()
			end
		end),
	}

	if options.inputReceiver then
		table.insert(
			self._connections,
			options.inputReceiver.InputBegan:Connect(function(input: InputObject, gpe: boolean?)
				if gpe then
					return
				end
				if not checkTrulyVisible(self.frame) then
					return
				end

				local action: HotkeyAction? = HOTKEYS[input.KeyCode]
				if action == "DELETE" then
					self:tryDeleteSelected()
				elseif action == "OPEN" then
					self:tryOpenSelected()
				elseif action == "CLOSE" then
					self:tryCloseSelected()
				elseif action == "NEXT" then
					self:trySelectNext()
				elseif action == "PREVIOUS" then
					self:trySelectPrevious()
				elseif action == "RENAME" then
					self:tryEditKeySelected()
				elseif action == "INSERT" then
					self:tryInsertSelected()
				end
			end)
		)
	end

	return self
end

local ARRAY_SENTINEL = newproxy()
local OBJECT_SENTINEL = newproxy()
local DECREMENT_DEPTH_SENTINEL = newproxy()

function Tree:_initializeBranchesFromData(data: JSONHelper.JSONValue, keyInfo: KeyInfo, allOpen: boolean?)
	local dataDepths, dataBranches = self:_flatten({
		key = "Data",
		value = data,
		initialDepth = 0,
		expectLarge = true,
		allOpen = allOpen,
	})
	dataBranches[1].ISROOT = true
	dataBranches[1].LOCKKEY = true

	local metadataDepths, metadataBranches = self:_flatten({
		key = "Metadata",
		value = keyInfo.Metadata,
		initialDepth = 1,
		expectLarge = true,
	})
	metadataBranches[1].LOCKKEY = true
	metadataBranches[1].LOCKVALUE = true
	metadataBranches[1].ISMETADATA = true
	metadataBranches[1][3] = true -- Auto-open

	local keyInfoDepths = table.create(5 + #keyInfo.UserIds)
	local keyInfoBranches = table.create(5 + #keyInfo.UserIds)
	table.insert(
		keyInfoBranches,
		{ "Key Info", OBJECT_SENTINEL, false, LOCKKEY = true, LOCKVALUE = true, ISKEYROOT = true }
	)
	table.insert(keyInfoDepths, 0)
	table.insert(keyInfoBranches, {
		"CreatedTime",
		keyInfo.CreatedTime,
		LOCKKEY = true,
		LOCKVALUE = true,
		ISTIME = true,
	})
	table.insert(keyInfoDepths, 1)
	table.insert(keyInfoBranches, {
		"UpdatedTime",
		keyInfo.UpdatedTime,
		LOCKKEY = true,
		LOCKVALUE = true,
		ISTIME = true,
	})
	table.insert(keyInfoDepths, 1)
	table.insert(keyInfoBranches, { "Version", keyInfo.Version, LOCKKEY = true, LOCKVALUE = true })
	table.insert(keyInfoDepths, 1)
	table.insert(
		keyInfoBranches,
		{ "UserIds", ARRAY_SENTINEL, true, LOCKKEY = true, LOCKVALUE = true, ISUSERIDS = true }
	)
	table.insert(keyInfoDepths, 1)
	self._userIdsIndex = #keyInfoDepths
	for i, id in keyInfo.UserIds do
		table.insert(keyInfoBranches, { i, id, ISUSERID = true })
		table.insert(keyInfoDepths, 2)
	end

	-- Combine it all together
	local totalCapacity = #keyInfoDepths + #metadataDepths + #dataDepths
	local depths = table.create(totalCapacity)
	local branches = table.create(totalCapacity)

	table.move(keyInfoDepths, 1, #keyInfoDepths, 1, depths)
	table.move(keyInfoBranches, 1, #keyInfoBranches, 1, branches)

	table.move(metadataDepths, 1, #metadataDepths, #depths + 1, depths)
	table.move(metadataBranches, 1, #metadataBranches, #branches + 1, branches)

	local rootIndex = #branches + 1
	table.move(dataDepths, 1, #dataDepths, #depths + 1, depths)
	table.move(dataBranches, 1, #dataBranches, #branches + 1, branches)

	-- Final touches
	self._visibleIndexes = { 1, rootIndex }

	self._flatDepths = depths
	self._flatBranches = branches

	return rootIndex
end

type FlattenOptions = {
	key: string,
	value: JSONHelper.JSONValue,
	initialDepth: number,
	expectLarge: boolean,
	allOpen: boolean?,
}
-- Flattens out table for fast iterating
function Tree:_flatten(options: FlattenOptions)
	local initialCapacity = if options.expectLarge then 256 else 4
	local depths = table.create(initialCapacity)
	local branches = table.create(initialCapacity)

	-- Stack is array of {KEY, VALUE}
	local stack = { { options.key, options.value } }
	local depth = options.initialDepth
	local allOpen = options.allOpen
	while #stack > 0 do
		local t = table.remove(stack)
		if t == DECREMENT_DEPTH_SENTINEL then
			depth -= 1
			continue
		end

		if typeof(t[2]) == "table" then
			if #t[2] > 0 then -- It's an array
				table.insert(depths, depth)
				table.insert(branches, { t[1], ARRAY_SENTINEL, allOpen or t[3] or depth < 1 })

				depth += 1
				table.insert(stack, DECREMENT_DEPTH_SENTINEL)

				-- Go backwards so array values are inserted in order
				-- Use maxn because there may be nil values in between
				for i = table.maxn(t[2]), 1, -1 do
					table.insert(stack, { i, t[2][i] })
				end
			else
				table.insert(depths, depth)
				table.insert(branches, { t[1], OBJECT_SENTINEL, allOpen or t[3] or depth < 1 })

				depth += 1
				table.insert(stack, DECREMENT_DEPTH_SENTINEL)

				-- Collect the keys so we can sort them
				local keys = table.create(8)
				local object = t[2]
				for k, _ in object do
					table.insert(keys, k)
				end

				table.sort(keys)

				-- Now when we add them to the stack, they are in ASCII order
				for i = #keys, 1, -1 do
					local key = keys[i]
					table.insert(stack, { key, object[key] })
				end
			end
		else
			-- Show it as a timestamp if it looks like one.
			if typeof(t[1]) == "string" and typeof(t[2]) == "number" then
				if TimestampHelper.guessTimestampType(t[2], "conservative") then
					local loweredKey = t[1]:lower()
					if
						loweredKey:match("time")
						or loweredKey:match("last")
						or loweredKey:match("current")
						or loweredKey:match("previous")
						or loweredKey:match("start")
						or loweredKey:match("update")
						or loweredKey:match("create")
						or loweredKey:match("stamp")
					then
						t.ISTIME = true
					end
				end
			end

			table.insert(depths, depth)
			table.insert(branches, t)
		end
	end

	return depths, branches
end

-- For debugging
function Tree:_dump(): string
	local builder = {}
	for i = 1, #self._flatBranches do
		local value = self._flatBranches[i][2]
		if value == ARRAY_SENTINEL then
			value = "[]"
		elseif value == OBJECT_SENTINEL then
			value = "{}"
		end
		table.insert(builder, `[{i}] {self._flatDepths[i]}: {self._flatBranches[i][1]} = {value}`)
	end
	return table.concat(builder, "\n")
end

-- Utilities for analyzing branches

function Tree:_getRootIndex(): number
	local didKeyInfo = false
	for i, depth in self._flatDepths do
		if depth == 0 then
			if didKeyInfo then
				return i
			else
				didKeyInfo = true
			end
		end
	end
end

-- Gets the index of the parent of the branch at the given index, or nil if it does not exist for whatever reason
function Tree:_getParentIndex(index: number): number?
	local depth = self._flatDepths[index]
	for i = index, 1, -1 do
		if self._flatDepths[i] == depth - 1 then
			return i
		end
	end
end

function Tree:_doesBranchHaveChildren(index: number)
	return self._flatDepths[index + 1] == self._flatDepths[index] + 1
end

-- Returns if any siblings branches have the same key name
function Tree:_doesSiblingOrSelfHaveKey(index: number, key: string): boolean
	if self._flatBranches[index][1] == key then
		return true
	end

	local selfDepth = self._flatDepths[index]
	-- Do siblings before
	-- Stop at 2 because 1 is always ROOT
	for i = index - 1, 2, -1 do
		local depth = self._flatDepths[i]
		if depth < selfDepth then
			break
		elseif depth == selfDepth then
			if self._flatBranches[i][1] == key then
				return true
			end
		end
	end
	-- Do siblings after
	for i = index + 1, #self._flatDepths do
		local depth = self._flatDepths[i]
		if depth < selfDepth then
			break
		elseif depth == selfDepth then
			if self._flatBranches[i][1] == key then
				return true
			end
		end
	end
	return false
end

function Tree:_doesChildHaveKey(index: number, key: string): boolean
	local branch = self._flatBranches[index]
	assert(branch[2] == ARRAY_SENTINEL or branch[2] == OBJECT_SENTINEL)
	local childDepth = self._flatDepths[index + 1]
	if childDepth then
		if childDepth == self._flatDepths[index] + 1 then
			return self:_doesSiblingOrSelfHaveKey(index + 1, key)
		end
	end

	return false
end

local validUniversalTimeRanges = {
	Year = { 1400, 9999 },
	Month = { 1, 12 },
	Day = { 1, 31 },
	Hour = { 0, 23 },
	Minute = { 0, 59 },
	Second = { 0, 60 },
	Millisecond = { 0, 999 },
}
local reverseTimeOrder = { "Millisecond", "Second", "Minute", "Hour", "Day", "Month", "Year" }
-- NOTE: note used at the moment
function Tree:_getUniversalTimeTable(index: number)
	local branch = self._flatBranches[index]
	assert(branch[2] == OBJECT_SENTINEL)
	local childDepth = self._flatDepths[index] + 1

	local universalTimeTable = {}

	for i = 1, 7 do
		local child = self._flatBranches[index + i]
		if child and self._flatDepths[index + i] == childDepth then
			local range = validUniversalTimeRanges[child[1]]
			if range and (typeof(child[2]) == "number") and (range[1] <= child[2]) and (child[2] <= range[2]) then
				universalTimeTable[child[1]] = child[2]
			else
				return nil
			end
		else
			break
		end
	end

	local hadLastOne = false
	for _, t in reverseTimeOrder do
		if (not universalTimeTable[t]) and hadLastOne then
			-- There's a hole!
			return nil
		end
		hadLastOne = universalTimeTable[t]
	end

	return universalTimeTable
end

function Tree:_getAmountOfUserIds(): number
	local index = self._userIdsIndex + 1
	while true do
		local depth = self._flatDepths[index]
		if depth ~= 2 then
			break
		else
			index += 1
		end
	end
	return (index - self._userIdsIndex) - 1
end

-- Utilities for manipulating branches

function Tree:_bumpVisibleIndexesAfter(index: number, bumpAmount: number, precomputedVisibleIndex: number?)
	local visibleIndex = precomputedVisibleIndex or table.find(self._visibleIndexes, index)
	if visibleIndex then
		for i = visibleIndex + 1, #self._visibleIndexes do
			self._visibleIndexes[i] += bumpAmount
		end
	end

	if self._selectingBranchVisibleIndex and visibleIndex and self._selectingBranchVisibleIndex > visibleIndex then
		self._selectingBranchVisibleIndex += bumpAmount
	end
end

function Tree:_bumpVisibleIndexesIncluding(index: number, bumpAmount: number, precomputedVisibleIndex: number?)
	local visibleIndex = precomputedVisibleIndex or table.find(self._visibleIndexes, index)
	if visibleIndex then
		for i = visibleIndex, #self._visibleIndexes do
			self._visibleIndexes[i] += bumpAmount
		end
	end

	if self._selectingBranchVisibleIndex and self._selectingBranchVisibleIndex >= visibleIndex then
		self._selectingBranchVisibleIndex += bumpAmount
	end
end

-- This bumps the indexes of an array
function Tree:_bumpSiblingIndexesIncluding(index: number, bumpAmount: number)
	assert(typeof(self._flatBranches[index][1]) == "number")

	local depth = self._flatDepths[index]
	for i = index, #self._flatDepths do
		local d = self._flatDepths[i]
		if d == depth then
			self._flatBranches[i][1] += bumpAmount
		elseif d < depth then
			break
		end
	end
end

-- Returns how many siblings are after the branch at this index
function Tree:_getSiblingsAfter(index: number)
	local depth = self._flatDepths[index]
	local count = 0
	for i = index, #self._flatDepths do
		local scannedDepth = self._flatDepths[i]
		if scannedDepth == depth then
			count += 1
		elseif scannedDepth < depth then
			break
		end
	end
	return count
end

-- TODO: do this in-place?
-- Splices out part of an array from startIndex to endIndex? inclusively
local function spliceOut(array: { unknown }, startIndex: number, endIndex: number?)
	if endIndex then
		local new = table.create((startIndex - 1) + (#array - endIndex))
		table.move(array, 1, startIndex - 1, 1, new)
		table.move(array, endIndex + 1, #array, startIndex, new)
		return new
	else
		local new = table.create(startIndex - 1)
		table.move(array, 1, startIndex - 1, 1, new)
		return new
	end
end

local function spliceIn(destination: { unknown }, destinationIndex: number, array: { unknown })
	table.move(destination, destinationIndex, #destination, destinationIndex + #array)
	table.move(array, 1, #array, destinationIndex, destination)
end

-- Like splice in, but replaces the value it splices in at
local function spliceReplace(destination: { unknown }, destinationIndex: number, array: { unknown })
	table.move(destination, destinationIndex + 1, #destination, destinationIndex + #array)
	table.move(array, 1, #array, destinationIndex, destination)
end

--[[ ACTIONS ]]
type ActionValue = {
	value: JSONHelper.JSONValue,
	isArray: boolean,
}

type InsertAction = {
	kind: "insert",
	index: number,
	key: string | number,
	value: ActionValue,
	depth: number,
}
type DeleteAction = {
	kind: "delete",
	index: number,
	key: string | number,
	value: ActionValue,
	depth: number,
}
type EditKeyAction = {
	kind: "editKey",
	index: number,
	from: string,
	to: string,
}
type EditValueAction = {
	kind: "editValue",
	index: number,
	from: ActionValue,
	to: ActionValue,
}
type EditBothAction = {
	kind: "editBoth",
	index: number,

	fromKey: string,
	toKey: string,
	fromValue: ActionValue,
	toValue: ActionValue,
}
type MoveAction = {
	kind: "move",
	startIndex: number,
	branchSize: number, -- The reason this is stored is so that it does not have to be recalculated for undo/redo
	endIndex: index,
}
type Action = InsertAction | DeleteAction | EditKeyAction | EditValueAction | MoveAction

function Tree:_pushAction(action: Action)
	for i = self._undoStackPosition + 1, #self._undoStack do
		table.remove(self._undoStack)
	end

	if #self._undoStack + 1 > UNDO_LIMIT then
		table.remove(self._undoStack, 1)
	end

	table.insert(self._undoStack, action)
	self._undoStackPosition = #self._undoStack

	self._historyChanged:Fire()
end

function Tree:_informBug(options: { message: string, dumpExtra: any })
	local betterMessage = `{options.message}. Please report this bug.`
	self.uiMessages:error(betterMessage)
	warn(`{options.message}\nextra:{JSONHelper.encode(options.dumpExtra)}\ndump:{self:_dump()}`)
end

type InsertResult = | { kind: "error", message: string } | { kind: "success", branch: any, index: number }

-- This assumes that the index to insert into is visible!
-- Returns the branch if it was successful and the index of it
-- Make sure to redrawBranches after
function Tree:_tryInsertInto(options: {
	index: number,
	key: string | number,
	value: ActionValue,
	pushAction: boolean?,
}): InsertResult
	local index = options.index
	local key = options.key
	local value = options.value
	local pushAction = options.pushAction

	self:_makeDirty()

	local branch = self._flatBranches[index]
	local depth = self._flatDepths[index]
	assert(branch[2] == ARRAY_SENTINEL or branch[2] == OBJECT_SENTINEL)

	if self:_doesChildHaveKey(index, key) then
		return {
			kind = "error",
			message = `Already contains key: {key}.`,
		}
	end

	local insertAt = index + 1

	-- Special-case for array make sure key is a number
	if branch[2] == ARRAY_SENTINEL then
		key = 1

		-- Don't bump if it's empty
		local firstChildDepth = self._flatDepths[index + 1]
		if firstChildDepth and firstChildDepth == depth + 1 then
			self:_bumpSiblingIndexesIncluding(insertAt, 1)
		end
	end

	local insertingDepths, insertingBranches = self:_flatten({
		key = key,
		value = value.value,
		initialDepth = depth + 1,
		expectLarge = false,
		allOpen = true,
	})
	local totalInserted = #insertingDepths

	if value.isArray then
		insertingBranches[1][2] = ARRAY_SENTINEL
	end

	spliceIn(self._flatDepths, insertAt, insertingDepths)
	spliceIn(self._flatBranches, insertAt, insertingBranches)

	-- Parent branch was open
	if branch[3] then
		local visibleIndex = table.find(self._visibleIndexes, index)
		if visibleIndex then
			local insertingVisibleIndexes = table.create(totalInserted)
			for i = 1, totalInserted do
				table.insert(insertingVisibleIndexes, insertAt + i - 1)
			end

			self:_bumpVisibleIndexesAfter(index, totalInserted, visibleIndex)
			spliceIn(self._visibleIndexes, visibleIndex + 1, insertingVisibleIndexes)
		end
	else
		branch[3] = true
		self:_bumpVisibleIndexesAfter(index, totalInserted)
		self:_updateBranchVisible(index)
	end

	self:_clearFrames()
	self:_updateCanvasSize()

	if pushAction then
		self:_pushAction({
			kind = "insert",
			index = insertAt,
			key = key,
			depth = depth + 1,
			value = value,
		} :: InsertAction)
	end

	return {
		kind = "success",
		branch = insertingBranches[1],
		index = insertAt,
	}
end

-- This assumes that the index to insert after is visible!
-- Returns the branch if successful and the index of it.
-- Make sure to redrawBranches after
function Tree:_tryInsertAfter(options: {
	index: number,
	key: string,
	value: ActionValue,
	pushAction: boolean,
}): (any, any)
	local index = options.index
	local key = options.key
	local value = options.value
	local pushAction = options.pushAction

	self:_makeDirty()

	local depth = self._flatDepths[index]
	local len = #self._flatDepths
	assert(depth >= 1, "Cannot insert after root node.")

	if self:_doesSiblingOrSelfHaveKey(index, key) then
		return {
			kind = "error",
			message = `Sibling already has key: {key}.`,
		}
	end

	local insertAt = index
	repeat
		insertAt += 1
	until insertAt > len or self._flatDepths[insertAt] <= depth

	-- Special case for array
	if typeof(self._flatBranches[index][1]) == "number" then
		local next = self._flatDepths[insertAt]
		-- Otherwise it's at the end
		if next and next == depth then
			key = self._flatBranches[insertAt][1]
			self:_bumpSiblingIndexesIncluding(insertAt, 1)
		else
			key = self._flatBranches[index][1] + 1
		end
	end

	local insertingDepths, insertingBranches = self:_flatten({
		key = key,
		value = value.value,
		initialDepth = depth,
		expectLarge = false,
		allOpen = true,
	})
	local totalInserted = #insertingDepths

	if value.isArray then
		insertingBranches[1][2] = ARRAY_SENTINEL
	end

	-- Visible indexes updating

	local insertingVisibleIndexes = table.create(totalInserted)
	for i = 1, totalInserted do
		table.insert(insertingVisibleIndexes, insertAt + i - 1)
	end

	local insertingAtVisibleIndex = table.find(self._visibleIndexes, insertAt)
	if insertingAtVisibleIndex then
		self:_bumpVisibleIndexesIncluding(insertAt, totalInserted, insertingAtVisibleIndex)
		spliceIn(self._visibleIndexes, insertingAtVisibleIndex, insertingVisibleIndexes)
	elseif insertAt > len then
		spliceIn(self._visibleIndexes, #self._visibleIndexes + 1, insertingVisibleIndexes)
	else
		self:_informBug({
			message = "`tryInsertAfter` failed because visible index not found",
			dumpExtra = { options },
		})
	end

	-- This has to be done after updating the visible indexes because it will mess it up
	spliceIn(self._flatDepths, insertAt, insertingDepths)
	spliceIn(self._flatBranches, insertAt, insertingBranches)

	self:_clearFrames()
	self:_updateCanvasSize()

	if pushAction then
		self:_pushAction({
			kind = "insert",
			index = insertAt,
			key = key,
			depth = depth,
			value = value,
		} :: InsertAction)
	end

	return {
		kind = "success",
		branch = insertingBranches[1],
		index = insertAt,
	}
end

-- ASSUMES the branch is visible
function Tree:_deleteBranch(options: { index: number, onlyChildren: boolean?, pushAction: boolean })
	local index = options.index
	self:_makeDirty()

	local branch = self._flatBranches[index]

	local deleteSelf = not options.onlyChildren

	local pushAction = (options.pushAction == true)
	local deleting = nil
	local deletingIndex = nil
	local deletingDepth = nil
	local deletingKey = nil

	if pushAction then
		assert(deleteSelf, "cannot push delete action where only children are deleted")
		deleting = self:_unflatten(index).value
		deletingIndex = index
		deletingKey = branch[1]
		deletingDepth = self._flatDepths[index]
	end

	if deleteSelf then
		-- Special-case for array elements, have to do it before anything to preserve the indexes
		if typeof(branch[1]) == "number" then
			self:_bumpSiblingIndexesIncluding(index, -1)
		end
	end

	local originalIndex = index

	if branch[2] == ARRAY_SENTINEL or branch[2] == OBJECT_SENTINEL then
		local startDepth = self._flatDepths[index]
		local len = #self._flatDepths
		local hasChildren = self._flatDepths[index + 1] == startDepth + 1

		-- Delete all children
		if hasChildren then
			index += 1

			local startVisibleIndex = table.find(self._visibleIndexes, index)
			local endVisibleIndex = nil
			local endIndex = nil
			for i = index, len do
				local depth = self._flatDepths[i]
				if depth <= startDepth then
					endVisibleIndex = table.find(self._visibleIndexes, i)
					if endVisibleIndex then
						endVisibleIndex -= 1
					end
					endIndex = i - 1
					break
				end
			end

			endVisibleIndex = endVisibleIndex or #self._visibleIndexes
			endIndex = endIndex or len

			-- + 1 because splice is inclusive
			local spliceSize = endIndex - index + 1

			if endIndex then
				self:_bumpVisibleIndexesAfter(endIndex, -spliceSize, endVisibleIndex)
				if
					self._selectingBranchIndex
					and (index <= self._selectingBranchIndex and self._selectingBranchIndex <= endIndex)
				then
					self._selectingBranchIndex = nil
					self._selectingBranchVisibleIndex = nil
					self._selectingBranchOffset = 0
				end
			elseif self._selectingBranchIndex and (self._selectingBranchIndex >= index) then
				self._selectingBranchIndex = nil
				self._selectingBranchVisibleIndex = nil
				self._selectingBranchOffset = 0
				self._selectingIsDragging = false
			end

			if startVisibleIndex and endVisibleIndex then
				self._visibleIndexes = spliceOut(self._visibleIndexes, startVisibleIndex, endVisibleIndex)
			end

			self._flatDepths = spliceOut(self._flatDepths, index, endIndex)
			self._flatBranches = spliceOut(self._flatBranches, index, endIndex)
		end
	end

	if deleteSelf then
		table.remove(self._flatDepths, originalIndex)
		table.remove(self._flatBranches, originalIndex)

		local visibleIndex = table.find(self._visibleIndexes, originalIndex)
		self:_bumpVisibleIndexesAfter(originalIndex, -1, visibleIndex)
		table.remove(self._visibleIndexes, visibleIndex)

		if originalIndex == self._selectingBranchIndex then
			self._selectingBranchIndex = nil
			self._selectingBranchVisibleIndex = nil
			self._selectingBranchOffset = 0
			self._selectingIsDragging = false
		end
	end

	if options.pushAction then
		self:_pushAction({
			kind = "delete",
			index = deletingIndex,
			key = deletingKey,
			depth = deletingDepth,
			value = deleting,
		} :: DeleteAction)
	end

	self:_clearFrames()
	self:_updateCanvasSize()
end

-- Index is the index in _flatBranches
function Tree:_moveArrayElement(options: {
	branchIndex: number,
	branchVisibleIndex: number,
	moveBeforeIndex: number,
	moveBeforeVisibleIndex: number,
	pushAction: boolean,
})
	local branchIndex = options.branchIndex
	local branchVisibleIndex = options.branchVisibleIndex
	local moveBeforeIndex = options.moveBeforeIndex
	local moveBeforeVisibleIndex = options.moveBeforeVisibleIndex

	local branch = self._flatBranches[branchIndex]
	local depth = self._flatDepths[branchIndex]

	assert(typeof(branch[1]) == "number")

	-- Don't move if it's the same spot
	if moveBeforeIndex == branchIndex then
		return
	end

	local newArrayIndex = -1
	if moveBeforeIndex > branchIndex then
		for i = moveBeforeIndex - 1, branchIndex + 1, -1 do
			local scannedDepth = self._flatDepths[i]
			if scannedDepth == depth then
				newArrayIndex = self._flatBranches[i][1] + 1
				break
			end
		end
	elseif moveBeforeIndex < branchIndex then
		newArrayIndex = self._flatBranches[moveBeforeIndex][1]
	end

	if (newArrayIndex < 0) or (newArrayIndex == branchIndex) then
		return
	end

	-- Find the bounds of the branch
	local branchStartIndex = branchIndex
	local branchEndIndex = nil
	for i = branchIndex + 1, #self._flatBranches do
		local scannedDepth = self._flatDepths[i]
		if scannedDepth <= depth then
			branchEndIndex = i - 1
			break
		end
	end
	if not branchEndIndex then
		branchEndIndex = #self._flatBranches
	end

	local branchStartVisibleIndex = branchVisibleIndex
	local branchEndVisibleIndex: number
	if branchStartIndex == branchEndIndex then
		branchEndVisibleIndex = branchVisibleIndex
	else
		local i = branchVisibleIndex + 1
		while true do
			local index = self._visibleIndexes[i]
			if index then
				if index > branchEndIndex then
					break
				end
			else
				break
			end

			i += 1
		end
		branchEndVisibleIndex = i - 1
	end

	-- Move things around
	local branchSize = branchEndIndex - branchStartIndex
	local branchVisibleSize = branchEndVisibleIndex - branchStartVisibleIndex

	local flatBranchesLen = #self._flatBranches
	local newFlatBranches = table.create(flatBranchesLen)
	local newFlatDepths = table.create(flatBranchesLen)
	local newVisibleIndexes = table.create(#self._visibleIndexes)

	if moveBeforeIndex < branchIndex then
		table.move(self._flatBranches, 1, moveBeforeIndex - 1, 1, newFlatBranches)
		table.move(self._flatDepths, 1, moveBeforeIndex - 1, 1, newFlatDepths)

		table.move(self._flatBranches, branchStartIndex, branchEndIndex, moveBeforeIndex, newFlatBranches)
		table.move(self._flatDepths, branchStartIndex, branchEndIndex, moveBeforeIndex, newFlatDepths)

		table.move(
			self._flatBranches,
			moveBeforeIndex,
			branchStartIndex - 1,
			moveBeforeIndex + branchSize + 1,
			newFlatBranches
		)
		table.move(
			self._flatDepths,
			moveBeforeIndex,
			branchStartIndex - 1,
			moveBeforeIndex + branchSize + 1,
			newFlatDepths
		)

		table.move(self._flatBranches, branchEndIndex + 1, flatBranchesLen, branchEndIndex + 1, newFlatBranches)
		table.move(self._flatDepths, branchEndIndex + 1, flatBranchesLen, branchEndIndex + 1, newFlatDepths)

		-- Update visible indexes
		table.move(self._visibleIndexes, 1, moveBeforeVisibleIndex - 1, 1, newVisibleIndexes)
		local inbetweenRegionSize = branchStartIndex - moveBeforeIndex
		for i = 0, branchVisibleSize do
			newVisibleIndexes[moveBeforeVisibleIndex + i] = self._visibleIndexes[branchStartVisibleIndex + i]
				- inbetweenRegionSize
		end
		for i = 0, branchStartVisibleIndex - moveBeforeVisibleIndex - 1 do
			newVisibleIndexes[moveBeforeVisibleIndex + branchVisibleSize + 1 + i] = self._visibleIndexes[moveBeforeVisibleIndex + i]
				+ branchSize
				+ 1
		end
		table.move(
			self._visibleIndexes,
			branchEndVisibleIndex + 1,
			#self._visibleIndexes,
			branchEndVisibleIndex + 1,
			newVisibleIndexes
		)
	elseif moveBeforeIndex > branchIndex then
		table.move(self._flatBranches, 1, branchStartIndex - 1, 1, newFlatBranches)
		table.move(self._flatDepths, 1, branchStartIndex - 1, 1, newFlatDepths)

		table.move(self._flatBranches, branchEndIndex + 1, moveBeforeIndex - 1, branchStartIndex, newFlatBranches)
		table.move(self._flatDepths, branchEndIndex + 1, moveBeforeIndex - 1, branchStartIndex, newFlatDepths)

		local inbetweenRegionSize = (moveBeforeIndex - 1) - branchEndIndex
		table.move(
			self._flatBranches,
			branchStartIndex,
			branchEndIndex,
			branchStartIndex + inbetweenRegionSize,
			newFlatBranches
		)
		table.move(
			self._flatDepths,
			branchStartIndex,
			branchEndIndex,
			branchStartIndex + inbetweenRegionSize,
			newFlatDepths
		)

		table.move(self._flatBranches, moveBeforeIndex, flatBranchesLen, moveBeforeIndex, newFlatBranches)
		table.move(self._flatDepths, moveBeforeIndex, flatBranchesLen, moveBeforeIndex, newFlatDepths)

		-- Update visible indexes
		table.move(self._visibleIndexes, 1, branchStartVisibleIndex - 1, 1, newVisibleIndexes)
		local inbetweenRegionVisibleSize = (moveBeforeVisibleIndex - 1) - branchEndVisibleIndex
		for i = 0, inbetweenRegionVisibleSize do
			newVisibleIndexes[branchStartVisibleIndex + i] = self._visibleIndexes[branchEndVisibleIndex + i + 1]
				- branchSize
				- 1
		end
		for i = 0, branchVisibleSize do
			newVisibleIndexes[branchStartVisibleIndex + inbetweenRegionVisibleSize + 1 + i] = self._visibleIndexes[branchStartVisibleIndex + i]
				+ inbetweenRegionSize
				+ 1
		end
		table.move(
			self._visibleIndexes,
			moveBeforeVisibleIndex,
			#self._visibleIndexes,
			moveBeforeVisibleIndex,
			newVisibleIndexes
		)
	end

	self._flatBranches = newFlatBranches
	self._flatDepths = newFlatDepths
	self._visibleIndexes = newVisibleIndexes

	-- Recount the indexes
	branch[1] = newArrayIndex
	if moveBeforeIndex < branchIndex then
		local i = moveBeforeIndex + branchSize + 1
		local count = 1
		while true do
			local scannedDepth = self._flatDepths[i]
			if not scannedDepth then
				break
			end

			if scannedDepth == depth then
				local scannedBranch = self._flatBranches[i]
				scannedBranch[1] = newArrayIndex + count
				count += 1
			elseif scannedDepth < depth then
				break
			end

			i += 1
		end
	else
		local i = moveBeforeIndex - branchSize - 1
		local count = 1
		while true do
			local scannedDepth = self._flatDepths[i]
			if not scannedDepth then
				break
			end

			if scannedDepth == depth then
				local scannedBranch = self._flatBranches[i]
				scannedBranch[1] = newArrayIndex - count
				count += 1
			elseif scannedDepth < depth then
				break
			end

			i -= 1
		end
	end

	local rootBranchIndex = if moveBeforeIndex < branchIndex then moveBeforeIndex else moveBeforeIndex - branchSize - 1

	if options.pushAction then
		self:_pushAction({
			kind = "move",
			startIndex = branchIndex,
			branchSize = branchSize + 1,
			endIndex = rootBranchIndex,
		} :: MoveAction)
	end

	self:_clearFrames()
	self:_redrawBranches()

	if self._selectingBranchIndex == branchIndex then
		self:_selectBranch(rootBranchIndex)
	end

	self:_makeDirty()
end

-- Special case when dragging and dropping to the end of the tree
-- ASSUMES that the end is a valid dropping point
-- ASSUMES that the entire tree is open so you can see the end
function Tree:_moveArrayElementToEnd(options: { branchIndex: number, branchVisibleIndex: number, pushAction: boolean })
	local branchIndex = options.branchIndex
	local branchVisibleIndex = options.branchVisibleIndex

	assert(typeof(self._flatBranches[branchIndex][1]) == "number")

	local moveToIndex = #self._flatBranches
	local branchStartIndex = branchIndex
	local branchStartVisibleIndex = branchVisibleIndex
	local branchEndIndex = nil

	-- Scan bounds of branch
	local branch = self._flatBranches[branchIndex]
	local depth = self._flatDepths[branchIndex]
	for i = branchIndex + 1, #self._flatBranches do
		if self._flatDepths[i] <= depth then
			branchEndIndex = i - 1
			break
		end
	end
	if not branchEndIndex then
		branchEndIndex = #self._flatBranches
	end

	-- Scan for visible bounds of branch
	local branchStartVisibleIndex = branchVisibleIndex
	local branchEndVisibleIndex: number
	if branchStartIndex == branchEndIndex then
		branchEndVisibleIndex = branchVisibleIndex
	else
		local i = branchVisibleIndex + 1
		while true do
			local index = self._visibleIndexes[i]
			if index then
				if index > branchEndIndex then
					break
				end
			else
				break
			end

			i += 1
		end
		branchEndVisibleIndex = i - 1
	end

	-- Bump visible indexes down to fill the hole left after moving
	local branchSize = branchEndIndex - branchStartIndex + 1
	local branchVisibleSize = branchEndVisibleIndex - branchStartVisibleIndex + 1
	self:_bumpSiblingIndexesIncluding(branchIndex, -1)
	branch[1] += self:_getSiblingsAfter(branchIndex)

	-- Move everything
	local branchTemp = table.create(branchSize)
	local depthTemp = table.create(branchSize)
	local visibleTemp = table.create(branchVisibleSize)
	-- First move branch into temp tables
	table.move(self._flatBranches, branchStartIndex, branchEndIndex, 1, branchTemp)
	table.move(self._flatDepths, branchStartIndex, branchEndIndex, 1, depthTemp)
	table.move(self._visibleIndexes, branchStartVisibleIndex, branchEndVisibleIndex, 1, visibleTemp)
	-- Then bump everything down to fill the hole
	local remaining = #self._flatBranches - branchEndIndex
	table.move(self._flatBranches, branchEndIndex + 1, #self._flatBranches, branchStartIndex, self._flatBranches)
	table.move(self._flatDepths, branchEndIndex + 1, #self._flatDepths, branchStartIndex, self._flatDepths)
	local visibleRemaining = #self._visibleIndexes - branchEndVisibleIndex
	for i = 0, (#self._visibleIndexes - branchEndVisibleIndex - 1) do
		self._visibleIndexes[branchStartVisibleIndex + i] = self._visibleIndexes[branchEndVisibleIndex + 1 + i]
			- branchSize
	end
	-- Then move back the branch to the end
	table.move(branchTemp, 1, branchSize, branchStartIndex + remaining, self._flatBranches)
	table.move(depthTemp, 1, branchSize, branchStartIndex + remaining, self._flatDepths)
	for i = 0, branchVisibleSize - 1 do
		self._visibleIndexes[branchStartVisibleIndex + visibleRemaining + i] = visibleTemp[1 + i] + remaining
	end

	local rootBranchIndex = #self._flatBranches - (branchSize - 1)
	if options.pushAction then
		self:_pushAction({
			kind = "move",
			startIndex = branchIndex,
			branchSize = branchSize,
			endIndex = rootBranchIndex,
		} :: MoveAction)
	end

	self:_clearFrames()
	self:_redrawBranches()

	if self._selectingBranchIndex == branchIndex then
		self:_selectBranch(rootBranchIndex)
	end

	self:_makeDirty()
end

type EditResult = | { kind: "error", message: string } | { kind: "success" }

-- Returns if the value was edited
function Tree:_editValue(options: {
	index: number,
	value: ActionValue,
	pushAction: boolean,
}): EditResult
	local index = options.index
	local value = options.value
	local branch = self._flatBranches[index]

	if branch.ISUSERID and (not Validators.userId(value.value)) then
		return {
			kind = "error",
			message = "UserId must be a positive integer.",
		}
	end

	local editing = nil
	if options.pushAction then
		editing = self:_unflatten(index).value
	end

	local deletedChildren = false
	if branch[2] == ARRAY_SENTINEL or branch[2] == OBJECT_SENTINEL then
		if self:_doesBranchHaveChildren(index) then
			self:_deleteBranch({ index = index, onlyChildren = true })
			deletedChildren = true
		end
	end

	-- Default path
	self:_makeDirty()

	local insertingDepths, insertingBranches = self:_flatten({
		key = branch[1],
		value = value.value,
		initialDepth = self._flatDepths[index],
		expectLarge = false,
		allOpen = true,
	})

	local totalInserting = #insertingBranches

	if value.isArray then
		insertingBranches[1][2] = ARRAY_SENTINEL
	end

	if totalInserting > 1 then
		for _, flag in FLAGS do
			if branch[flag] then
				insertingBranches[1][flag] = branch[flag]
			end
		end

		local visibleIndex = table.find(self._visibleIndexes, index)
		if visibleIndex then
			local insertingVisibleIndexes = table.create(totalInserting)
			for i = 1, totalInserting do
				table.insert(insertingVisibleIndexes, index + i - 1)
			end
			self:_bumpVisibleIndexesAfter(index, totalInserting - 1, visibleIndex)
			spliceReplace(self._visibleIndexes, visibleIndex, insertingVisibleIndexes)
		end

		spliceReplace(self._flatDepths, index, insertingDepths)
		spliceReplace(self._flatBranches, index, insertingBranches)

		self:_clearFrames()
		self:_updateCanvasSize()
		self:_redrawBranches()
	else
		branch[2] = insertingBranches[1][2]

		if deletedChildren then
			self:_updateCanvasSize()
			self:_redrawBranches()
		else
			local frame = self._frames[index]
			if frame then
				self:_updateBranchFrame(self._frames[index], branch, index)
			end
		end
	end

	if options.pushAction then
		self:_pushAction({
			kind = "editValue",
			index = index,
			from = editing,
			to = value,
		} :: EditValueAction)
	end

	return {
		kind = "success",
	}
end

-- Returns true if was edited
function Tree:_editKey(options: {
	index: number,
	key: string,
	pushAction: boolean,
	skipSiblingCheck: boolean?,
}): EditResult
	local index = options.index
	local key = options.key

	if (not options.skipSiblingCheck) and self:_doesSiblingOrSelfHaveKey(index, key) then
		return {
			kind = "error",
			message = `Duplicate key: {key}.`,
		}
	end

	local frame = self._frames[index]
	local branch = self._flatBranches[index]
	local originalKey = branch[1]
	self:_makeDirty()
	branch[1] = key
	self:_updateBranchFrame(frame, branch, index)

	if options.pushAction then
		self:_pushAction({
			kind = "editKey",
			index = index,
			from = originalKey,
			to = key,
		} :: EditKeyAction)
	end

	return {
		kind = "success",
	}
end

function Tree:_processResult(result: EditResult | InsertResult): boolean
	if result.kind == "success" then
		return true
	else
		self.uiMessages:error(result.message)
		return false
	end
end

function Tree:_insertForUndoRedo(
	options: { index: number, depth: number, key: string | number, value: ActionValue }
): InsertResult
	local insertAt = options.index
	local insertAtDepth = nil
	repeat
		insertAt = insertAt - 1
		insertAtDepth = self._flatDepths[insertAt]
	until insertAtDepth == options.depth or insertAtDepth == options.depth - 1 or insertAt <= 0

	if insertAt <= 0 then
		self:_informBug({
			message = "Couldn't find spot to insert for undo/redo.",
			dumpExtra = options,
		})
		return
	end

	local result: InsertResult
	local key = if typeof(options.key) == "number" then nil else options.key
	if insertAtDepth == options.depth then
		self:_digExpand(insertAt)
		result = self:_tryInsertAfter({
			index = insertAt,
			key = key,
			value = options.value,
		})
	elseif insertAtDepth == options.depth - 1 then
		self:_digExpand(insertAt)
		result = self:_tryInsertInto({
			index = insertAt,
			key = key,
			value = options.value,
		})
	else
		self:_informBug({
			message = `Unable to insert for undo/redo.`,
			dumpExtra = options,
		})
		return nil
	end

	if result.kind == "error" then
		self:_informBug({
			message = `Failed to insert for undo/redo. {result.message}.`,
			dumpExtra = options,
		})
	else
		local parentIndex = self:_getParentIndex(options.index)
		if parentIndex and self._userIdsIndex == parentIndex then
			result.branch.ISUSERID = true
		end

		self:_selectBranch(result.index, true)

		self:_redrawBranches()
	end

	return result
end

function Tree:_deleteBranchForUndoRedo(index: number)
	local parentIndex = self:_getParentIndex(index)
	self:_digExpand(index)
	self:_deleteBranch({ index = index })

	if parentIndex then
		self:_selectBranch(parentIndex, true)
	end

	self:_redrawBranches()
end

function Tree:_moveArrayElementForUndoRedo(fromIndex: number, toIndex: number)
	local branchIndex = fromIndex
	local branchVisibleIndex = table.find(self._visibleIndexes, branchIndex)
	if branchVisibleIndex then
		if toIndex > #self._flatBranches then
			self:_moveArrayElementToEnd({
				branchIndex = branchIndex,
				branchVisibleIndex = branchVisibleIndex,
			})
		else
			local moveBeforeIndex = toIndex
			local moveBeforeVisibleIndex = table.find(self._visibleIndexes, moveBeforeIndex)
			if moveBeforeVisibleIndex then
				self:_moveArrayElement({
					branchIndex = branchIndex,
					branchVisibleIndex = branchVisibleIndex,
					moveBeforeIndex = moveBeforeIndex,
					moveBeforeVisibleIndex = moveBeforeVisibleIndex,
				})
			end
		end
	end
end

function Tree:_scrollTo(visibleIndex: number)
	local scrollTo = SIZE_PER_BRANCH * (visibleIndex - 1)
	if self._selectingBranchVisibleIndex and self._selectingBranchVisibleIndex > visibleIndex then
		scrollTo += self._selectingBranchOffset
	end
	if self.frame.CanvasPosition.Y + self.frame.AbsoluteSize.Y < scrollTo + SIZE_PER_BRANCH then
		self.frame.CanvasPosition = Vector2.new(0, scrollTo + SIZE_PER_BRANCH - self.frame.AbsoluteSize.Y)
	elseif self.frame.CanvasPosition.Y > scrollTo then
		self.frame.CanvasPosition = Vector2.new(0, scrollTo)
	end
end

function Tree:_focusBranch(index: number)
	self:_digExpand(index)

	if self._isTesting then
		return
	end

	self:_selectBranch(index, true)

	local visibleIndex = table.find(self._visibleIndexes, index)
	if visibleIndex then
		self:_scrollTo(visibleIndex)
	end
end

-- Make sure you can actually undo before calling this with `:canUndo()`
function Tree:_undo()
	local action = self._undoStack[self._undoStackPosition] :: Action
	self._undoStackPosition -= 1

	if action.kind == "insert" then
		self:_deleteBranchForUndoRedo(action.index)
	elseif action.kind == "delete" then
		self:_insertForUndoRedo({
			index = action.index,
			key = action.key,
			value = action.value,
			depth = action.depth,
		})
	elseif action.kind == "editKey" then
		self:_focusBranch(action.index)
		self:_editKey({
			index = action.index,
			key = action.from,
		})
	elseif action.kind == "editValue" then
		self:_focusBranch(action.index)
		self:_editValue({
			index = action.index,
			value = action.from,
		})
	elseif action.kind == "editBoth" then
		self:_focusBranch(action.index)
		self:_editKey({
			index = action.index,
			key = action.fromKey,
		})
		self:_editValue({
			index = action.index,
			value = action.fromValue,
		})
	elseif action.kind == "move" then
		self:_moveArrayElementForUndoRedo(
			action.endIndex,
			if action.endIndex < action.startIndex then action.startIndex + action.branchSize else action.startIndex
		)
	end

	self._historyChanged:Fire()
end

-- Make sure you can actually redo before calling this with `:canRedo()`
function Tree:_redo()
	self._undoStackPosition += 1
	local action = self._undoStack[self._undoStackPosition] :: Action

	if action.kind == "insert" then
		self:_insertForUndoRedo({
			index = action.index,
			key = action.key,
			value = action.value,
			depth = action.depth,
		})
	elseif action.kind == "delete" then
		self:_deleteBranchForUndoRedo(action.index)
	elseif action.kind == "editKey" then
		self:_focusBranch(action.index)
		self:_editKey({
			index = action.index,
			key = action.to,
		})
	elseif action.kind == "editValue" then
		self:_focusBranch(action.index)
		self:_editValue({
			index = action.index,
			value = action.to,
		})
	elseif action.kind == "editBoth" then
		self:_focusBranch(action.index)
		self:_editKey({
			index = action.index,
			key = action.toKey,
		})
		self:_editValue({
			index = action.index,
			value = action.toValue,
		})
	elseif action.kind == "move" then
		self:_moveArrayElementForUndoRedo(
			action.startIndex,
			if action.endIndex > action.startIndex then action.endIndex + action.branchSize else action.endIndex
		)
	end

	self._historyChanged:Fire()
end

function Tree:_expandAll(index: number)
	local selfDepth = self._flatDepths[index]
	self._flatBranches[index][3] = true
	self._frames[index].Arrow.Image = self.theme.icons.downArrow
	for i = index + 1, #self._flatDepths do
		local depth = self._flatDepths[i]
		if depth <= selfDepth then
			break
		else
			local branch = self._flatBranches[i]
			if branch[3] ~= nil then
				branch[3] = true
				local frame = self._frames[i]
				if frame then
					frame.Arrow.Image = self.theme.icons.downArrow
				end
			end
		end
	end

	self:_updateBranchVisible(index)
	self:_redrawBranches()
end

function Tree:_collapseAll(index: number)
	local selfDepth = self._flatDepths[index]
	self._flatBranches[index][3] = false
	self._frames[index].Arrow.Image = self.theme.icons.rightArrow
	for i = index + 1, #self._flatDepths do
		local depth = self._flatDepths[i]
		if depth <= selfDepth then
			break
		else
			local branch = self._flatBranches[i]
			if branch[3] ~= nil then
				branch[3] = false
				local frame = self._frames[i]
				if frame then
					frame.Arrow.Image = self.theme.icons.rightArrow
				end
			end
		end
	end

	self:_updateBranchVisible(index)
	self:_redrawBranches()
	self:_clearNonVisibleBranches()
end

-- Expands the tree so that the branch at the given index is visible
-- DOES NOT _redrawBranches! You must do that after. The reason is that this is used for undo which sequences multiple operations so it
-- would be wasteful to _redrawBranches multiple times.
function Tree:_digExpand(index: number)
	local currentDepth = self._flatDepths[index]
	for i = index, 1, -1 do
		local depth = self._flatDepths[i]
		if depth < currentDepth then
			local branch = self._flatBranches[i]
			if branch[3] ~= nil then
				branch[3] = true
				local frame = self._frames[i]
				if frame then
					frame.Arrow.Image = self.theme.icons.downArrow
				end
			end
		end

		if depth == 0 then
			self:_updateBranchVisible(i)
			break
		end
	end
end

function Tree:_toggleOpen(index: number)
	-- DONT REMEMBER WHAT THIS CHECK WAS FOR, KEEPING IT BECAUSE IT DOESN'T SEEM LIKE IT WOULD BREAK ANYTHING
	if self._selectingIsDragging then
		return
	end

	local branch = self._flatBranches[index]
	local frame = self._frames[index]

	branch[3] = not branch[3]
	self:_updateBranchVisible(index)
	self:_redrawBranches()

	if not branch[3] then
		frame.Arrow.Image = self.theme.icons.rightArrow
		self:_clearNonVisibleBranches()
	else
		frame.Arrow.Image = self.theme.icons.downArrow
	end
end

function Tree:_updateCanvasSize()
	self.frame.CanvasSize =
		UDim2.fromOffset(0, SIZE_PER_BRANCH * #self._visibleIndexes + (self._selectingBranchOffset or 0))
end

-- NOTE: Ignores utf-8, but should still work OK (rather be bigger than necessary than smaller than necessary)
function Tree:_updateBranchFrameSize(frame, branch)
	local keyLen = #frame.Key.Text
	local keyWidth =
		math.clamp(CHAR_WIDTH * keyLen + 20, if typeof(branch[1]) == "number" then 25 else 100, self._maxKeyWidth)
	frame.Key.Size = UDim2.fromOffset(keyWidth, 18)
	frame.Value.Position = UDim2.fromOffset(25 + keyWidth, 0)
	frame.Value.Size = UDim2.new(1, -(25 + keyWidth), 0, 18)
end

-- Updates styling
function Tree:_updateBranchFrame(frame, branch, index)
	local colors = if index == self._selectingBranchIndex then self._colors.selectText else self._colors

	if self.disabled then
		-- Reason using this is because Roblox default theme has green comments which
		-- don't look disabled, so opt for the built-in theme one.
		local realDisabledColor = self.theme.colors.disabledText
		frame.Key.TextColor3 = realDisabledColor
		frame.Value.TextColor3 = realDisabledColor
		return
	end

	self:_updateBranchFrameBackgroundColor(index, frame)

	local keyColor = nil
	if Settings.get("useAlternatingKeyColors") then
		local depth = (self._flatDepths[index] - 1) % 3 + 1
		if depth == 1 then
			keyColor = "key"
		else
			keyColor = "key" .. depth
		end
	end

	if branch.ISROOT or branch.ISKEYROOT then
		frame.Key.Text = branch[1]
		frame.Key.FontFace = ITALIC_BOLD_FONT
		frame.Key.TextColor3 = colors.root
	elseif typeof(branch[1]) == "number" then
		frame.Key.Text = `{branch[1]})`
		frame.Key.FontFace = DEFAULT_FONT
		frame.Key.TextColor3 = if keyColor then colors[keyColor] else colors.index
	else
		frame.Key.Text = branch[1]
		frame.Key.FontFace = DEFAULT_FONT
		frame.Key.TextColor3 = if keyColor then colors[keyColor] else colors.key
	end

	local value = branch[2]

	local font = DEFAULT_FONT
	local arrowVisible = false
	local processed = false

	if branch.ISTIME then
		if typeof(value) == "number" then
			local success, time = pcall(function()
				return TimestampHelper.bestGuessIntoDateTime(value):FormatUniversalTime("ll LTS", "en-us")
			end)
			if success then
				frame.Value.Text = time
				frame.Value.TextColor3 = colors.number
				processed = true
			end
		elseif value == OBJECT_SENTINEL then
			local universalTimeTable = self:_getUniversalTimeTable(index)
			if universalTimeTable then
				local success, time = pcall(function()
					return DateTime.fromUniversalTime(
						universalTimeTable.Year,
						universalTimeTable.Month,
						universalTimeTable.Day,
						universalTimeTable.Hour,
						universalTimeTable.Minute,
						universalTimeTable.Second,
						universalTimeTable.Millisecond
					):FormatUniversalTime("ll LTS", "en-us")
				end)
				if success then
					frame.Value.Text = time
					frame.Value.TextColor3 = colors.number
					processed = true
				end
			end
		end
	end

	if not processed then
		if typeof(value) == "number" then
			frame.Value.Text = tostring(value)
			frame.Value.TextColor3 = colors.number
		elseif typeof(value) == "string" then
			frame.Value.Text = JSONHelper.escapeString(value)
			frame.Value.TextColor3 = colors.string
		elseif value == OBJECT_SENTINEL then
			frame.Value.TextColor3 = colors.object
			if self:_doesBranchHaveChildren(index) then
				frame.Value.Text = "{object}"
				arrowVisible = true
			else
				frame.Value.Text = "{empty object}"
				arrowVisible = false
			end
		elseif value == ARRAY_SENTINEL then
			frame.Value.TextColor3 = colors.array
			if self:_doesBranchHaveChildren(index) then
				frame.Value.Text = "[array]"
				arrowVisible = true
			else
				frame.Value.Text = "[empty array]"
				arrowVisible = false
			end
		elseif typeof(value) == "boolean" then
			frame.Value.Text = tostring(value)
			frame.Value.TextColor3 = colors.boolean
		elseif typeof(value) == "buffer" then
			frame.Value.Text = `<buffer {buffer.len(value)}>`
			frame.Value.TextColor3 = colors.buffer
		elseif typeof(value) == "nil" then
			frame.Value.Text = "null"
			frame.Value.TextColor3 = colors.null
			font = ITALIC_FONT
		end
	end

	frame.Arrow.Visible = arrowVisible
	if arrowVisible then
		frame.Arrow.ImageColor3 = colors.plain
	end

	if frame.Value.FontFace ~= font then
		frame.Value.FontFace = font
	end

	if branch.ISKEYROOT then
		frame.Value.Text = "" -- Still want it to be visible so you can double click and open it up
	end

	if branch.LOCKKEY and not branch.ISROOT then
		frame.Key.TextColor3 = colors.disabled
	end
	if branch.LOCKVALUE then
		frame.Value.TextColor3 = colors.disabled
	end

	self:_updateBranchFrameSize(frame, branch)
end

type ExtraSecretTypes = "UserId" | "empty array" | "empty object"
type PrecisionMenuOptions = {
	position: Vector2,
	captureValueTextBox: boolean?,

	title: string,
	yesText: string,
	noText: string,

	showKey: boolean,
	lockKey: boolean,
	key: string | number,
	value: JSONHelper.JSONValue,
	type: JSONHelper.JSONType | ExtraSecretTypes,

	showUnexpand: boolean,
	keyValidator: Validators.Validator,
	onSubmit: (promptKeyValueForm.FormResult?) -> boolean, -- If boolean false, cancel the submit
	onUnexpand: (promptKeyValueForm.FormResult) -> boolean, -- If boolean false, cancel the unexpand
}

-- You must manually setInModal when using this.
-- captureValueTextBox parameter is to tell it to CaptureFocus on the value instead of the key
function Tree:_promptPrecisionMenu(options: PrecisionMenuOptions): promptKeyValueForm.FormResult?
	local lockKey = options.lockKey or (typeof(options.key) == "number")
	local lockType = (options.type == "UserId")
	if lockKey then
		options.captureValueTextBox = true
	end

	local defaultType = options.type
	-- When switching between types, consult this to see what the default value should be
	local defaultValues = {
		[defaultType] = options.value,
	}

	local position = options.position or self.gui:GetRelativeMousePosition()
	local editFrame = Assets.EditKey:Clone()
	editFrame.Position = UDim2.fromOffset(position.X, position.Y)
	local modal = PopupHelper.modal(editFrame, self.gui)

	local wrapper = StyleStateWrapper.new(self.theme, {
		background = BackgroundStyleState.from(self.theme, editFrame, {
			style = "popup",
		}),
		titleLabel = LabelStyleState.from(self.theme, editFrame.Title),
		keyLabel = LabelStyleState.from(self.theme, editFrame.Form.Key.Title),
		typeLabel = LabelStyleState.from(self.theme, editFrame.Form.Type.Title),
		valueLabel = LabelStyleState.from(self.theme, editFrame.Form.Value.Title),

		typeSelect = SelectStyleState.from(self.theme, editFrame.Form.Type.Select, {
			default = defaultType,
			options = {
				"string",
				"number",
				"boolean",
				"empty object",
				"empty array",
				"buffer",
				"null",
			},
		}),
		keyTextBox = TextBoxStyleState.from(self.theme, editFrame.Form.Key.TextBox),

		confirm = ButtonStyleState.from(self.theme, editFrame.Form.Buttons.Confirm, { style = "primary" }),
		cancel = ButtonStyleState.from(self.theme, editFrame.Form.Buttons.Cancel, { style = "secondary" }),

		unexpand = ButtonStyleState.from(self.theme, editFrame["Escape Layout"].Expand, { style = "dormant" }),
	})

	wrapper.styleStates.titleLabel.label.Text = options.title
	wrapper.styleStates.confirm.button.TextLabel.Text = options.yesText
	wrapper.styleStates.cancel.button.TextLabel.Text = options.noText

	editFrame.Form.Key.Visible = options.showKey
	if options.showUnexpand then
		wrapper.styleStates.unexpand.button.Visible = true
		lockObjectWithoutResize(
			wrapper.styleStates.unexpand.button,
			editFrame,
			Vector2.new(1, 0),
			UDim2.fromOffset(-3, 0)
		)
	end

	local doneEvent = Instance.new("BindableEvent")

	local function updateConfirmButtonDisabled()
		if wrapper.styleStates.keyTextBox.error then
			wrapper.styleStates.confirm:setDisabled(true):update()
		elseif wrapper.styleStates.value and wrapper.styleStates.value.error then
			wrapper.styleStates.confirm:setDisabled(true):update()
		else
			wrapper.styleStates.confirm:setDisabled(false):update()
		end
	end

	wrapper.styleStates.keyTextBox.textBox:GetPropertyChangedSignal("Text"):Connect(function()
		local valid, err = options.keyValidator(wrapper.styleStates.keyTextBox.textBox.Text)
		if valid then
			wrapper.styleStates.keyTextBox:setError(nil):update("veryFast")
		else
			wrapper.styleStates.keyTextBox:setError(err):update("veryFast")
		end
	end)

	wrapper.styleStates.keyTextBox.errorChanged:Connect(updateConfirmButtonDisabled)

	local submit: () -> () -- pre-declare
	-- This variable is used when the user first switches to a type and the plugin has to find out the best default value (based on the last value).
	-- For the object, array, and null when converting to string, calling tostring on them will not yield a useful value, so just default to "" in that case
	local lastValue = if defaultType:find("object")
			or defaultType:find("array")
			or defaultType == "null"
		then ""
		else defaultValues[defaultType]

	local function updateValueInput()
		if wrapper.styleStates.value then
			wrapper.styleStates.value:destroy(true)
			wrapper.styleStates.value = nil
			updateConfirmButtonDisabled()
		end

		local valueType = wrapper.styleStates.typeSelect.selection

		if valueType == "string" then
			defaultValues["string"] = defaultValues["string"]
				or (if typeof(lastValue) == "buffer" then buffer.tostring(lastValue) else tostring(lastValue))
				or ""

			local textArea = script.EditMenuInputTemplates.TextArea:Clone()
			wrapper.styleStates.value = TextBoxStyleState.from(self.theme, textArea)
			textArea.Parent = editFrame.Form.Value

			textArea:GetPropertyChangedSignal("Text"):Connect(function()
				lastValue = textArea.Text
				defaultValues["string"] = lastValue
			end)

			textArea.Text = defaultValues["string"]
			editFrame.Form.Value.Visible = true
		elseif valueType == "number" or valueType == "UserId" then
			defaultValues[valueType] = defaultValues[valueType] or tonumber(lastValue) or 0

			local textBox = script.EditMenuInputTemplates.TextBox:Clone()
			local styleState = TextBoxStyleState.from(self.theme, textBox)
			wrapper.styleStates.value = styleState
			textBox.Parent = editFrame.Form.Value

			styleState.errorChanged:Connect(updateConfirmButtonDisabled)

			textBox:GetPropertyChangedSignal("Text"):Connect(function()
				-- NOTE: When SignalBehavior is Deferred, when right clicking out of the modal in the edit menu this will cause an error
				--	     because the textBox's Text will change to " " (idk why). In Immediate mode this will not error because the TextBox is
				--       not destroyed yet.
				if not textBox.Parent then
					return
				end

				local number = tonumber(textBox.Text)
				if not number then
					styleState:setError("Invalid number."):update("veryFast")
				else
					if valueType == "UserId" then
						local valid, err = Validators.userId(number)
						if not valid then
							styleState:setError(err):update("veryFast")
							return
						end
					end

					styleState:setError(nil):update("veryFast")
					lastValue = number
					defaultValues[valueType] = lastValue
				end
			end)

			textBox.FocusLost:Connect(function(entered)
				if entered then
					submit()
				end
			end)

			textBox.Text = defaultValues[valueType]
			editFrame.Form.Value.Visible = true
		elseif valueType == "boolean" then
			defaultValues["boolean"] = defaultValues["boolean"]
				or (lastValue == "true" or lastValue == "t" or lastValue == "#t")

			local switch = script.EditMenuInputTemplates.Switch:Clone()
			local styleState = SwitchStyleState.from(self.theme, switch, {
				default = defaultValues["boolean"],
			})
			wrapper.styleStates.value = styleState
			switch.Parent = editFrame.Form.Value
			styleState.toggled:Connect(function()
				lastValue = styleState.value
				defaultValues["boolean"] = lastValue
			end)

			editFrame.Form.Value.Visible = true
		elseif valueType == "buffer" then
			defaultValues["buffer"] = defaultValues["buffer"] or buffer.create(0)

			local link = script.EditMenuInputTemplates.HexEditorLink:Clone()
			local styleState = ButtonStyleState.from(self.theme, link, {
				style = "secondary",
			})
			wrapper.styleStates.value = styleState
			link.Parent = editFrame.Form.Value

			link.Activated:Connect(function()
				local hexEditorWidget =
					HexEditorWidget.new("DATADELVE HEX EDITOR WIDGET", self.theme, defaultValues["buffer"])

				-- Make a dummy object to get a modal up
				local dummyObject = Instance.new("Frame")
				dummyObject.BackgroundTransparency = 1
				dummyObject.Size = UDim2.fromOffset(0, 0)

				local modal = PopupHelper.modal(dummyObject, self.gui, {
					zIndex = PopupHelper.DEFAULT_MODAL_ZINDEX + 5,
				})

				-- Set up result connections
				local resultInstructionEvent = Instance.new("BindableEvent")

				modal.cancelled:Connect(function()
					resultInstructionEvent:Fire(nil)
				end)

				hexEditorWidget.interacted:Connect(function(submit)
					if submit then
						resultInstructionEvent:Fire("submit")
					else
						resultInstructionEvent:Fire(nil)
					end
				end)

				task.wait(0.5) -- A little debounce in case the user clicks again because they don't see the widget
				local shouldSubmit: boolean
				if not hexEditorWidget.dead then
					shouldSubmit = resultInstructionEvent.Event:Wait()
				else
					shouldSubmit = false
				end

				-- Wait for result instruction then act on it
				if shouldSubmit then
					local got, size = hexEditorWidget.editor:getRawBuffer()
					local copy = buffer.create(size)
					buffer.copy(copy, 0, got, 0, size)
					lastValue = copy
					defaultValues["buffer"] = lastValue
				end

				modal:destroy(true)
				hexEditorWidget:destroy()
			end)

			editFrame.Form.Value.Visible = true
		else
			if valueType == "empty array" or valueType == "empty object" then
				defaultValues[valueType] = {}
			end
			editFrame.Form.Value.Visible = false
		end

		PopupHelper.clamp(editFrame, self.gui)
	end

	local function cleanup()
		modal:destroy()
		editFrame:Destroy()
		wrapper:destroy()

		doneEvent:Fire()
	end

	-- Events
	local result: promptKeyValueForm.FormResult? = nil

	function submit()
		if wrapper.styleStates.confirm.disabled then
			return
		end

		result = {
			key = wrapper.styleStates.keyTextBox.textBox.Text,
			value = defaultValues[wrapper.styleStates.typeSelect.selection],
			type = wrapper.styleStates.typeSelect.selection,
		}

		if options.onSubmit(result) then
			cleanup()
		end
	end

	modal.cancelled:Connect(cleanup)
	wrapper.styleStates.confirm.button.Activated:Connect(submit)
	wrapper.styleStates.cancel.button.Activated:Connect(cleanup)
	wrapper.styleStates.keyTextBox.textBox.FocusLost:Connect(function(entered)
		if entered then
			submit()
		end
	end)

	wrapper.styleStates.unexpand.button.Activated:Connect(function()
		result = {
			key = wrapper.styleStates.keyTextBox.textBox.Text,
			value = defaultValues[wrapper.styleStates.typeSelect.selection],
			type = wrapper.styleStates.typeSelect.selection,
		}

		assert(result)

		if options.onUnexpand(result) then
			cleanup()
		end
	end)

	wrapper.styleStates.typeSelect.changed:Connect(updateValueInput)

	-- Intialize
	if lockKey then
		wrapper.styleStates.keyTextBox:setDisabled(true):update("instant")
	end
	if lockType then
		wrapper.styleStates.typeSelect.buttonStyleState:setDisabled(true):update("instant")
	end
	updateValueInput()
	wrapper.styleStates.keyTextBox.textBox.Text = options.key
	if options.captureValueTextBox then
		if wrapper.styleStates.value and wrapper.styleStates.value.textBox then
			wrapper.styleStates.value.textBox:CaptureFocus()
		end
	else
		wrapper.styleStates.keyTextBox.textBox:CaptureFocus()
	end

	doneEvent.Event:Wait()

	return result
end

function Tree:_promptEditMenu(index: number, options: { captureValueTextBox: boolean?, position: Vector2 })
	self:_setInModal(true)

	local branch = self._flatBranches[index]
	local lockKey = (typeof(branch[1]) == "number") or branch.LOCKKEY
	local type = if branch.ISUSERID
		then "UserId"
		elseif branch[2] == ARRAY_SENTINEL then "array"
		elseif branch[2] == OBJECT_SENTINEL then "object"
		else type(branch[2])
	if type == "nil" then
		type = "null"
	elseif type == "array" or type == "object" then
		if not self:_doesBranchHaveChildren(index) then
			type = "empty " .. type
		end
	end

	local start = {
		key = branch[1],
		value = branch[2],
		type = type,
	}

	self:_promptPrecisionMenu({
		position = options.position,
		captureValueTextBox = options.captureValueTextBox,

		title = "Edit",
		yesText = "Confirm",
		noText = "Cancel",

		showKey = true,
		lockKey = lockKey,
		key = start.key,
		value = start.value,
		type = start.type,

		keyValidator = function(text)
			local invalid = (text ~= start.key) and self:_doesSiblingOrSelfHaveKey(index, text)
			if invalid then
				return false, "Sibling already has this key."
			else
				return true, nil
			end
		end,
		onSubmit = function(result)
			if result then
				local newKey = result.key
				if lockKey then
					-- When it's an array, the number will be converted to a string which we don't want to happen. lockKey is always on for array elements.
					newKey = start.key
				end

				if result.type == start.type and result.value == start.value then
					-- No change to value

					if start.key == newKey then
						-- Don't do anything becaues no change
						return true
					elseif
						self:_processResult(
							self:_editKey({ index = index, key = newKey, skipSiblingCheck = true, pushAction = true })
						)
					then
						return true
					else
						return false
					end
				end

				local newValue = result.value
				local newValueIsArray = (result.type == "array") or (result.type == "empty array")
				if result.type == "empty array" then
					newValue = {}
				elseif result.type == "empty object" then
					newValue = {}
				elseif result.type == "null" then
					newValue = nil
				end

				if
					self:_processResult(self:_editValue({
						index = index,
						value = { value = newValue, isArray = newValueIsArray },
						pushAction = true,
					}))
				then
					if
						(newKey ~= start.key)
						and self:_processResult(self:_editKey({
							index = index,
							key = newKey,
							pushAction = true,
							skipSiblingCheck = true,
						}))
					then
						if
							self._undoStack[#self._undoStack - 1].kind == "editValue"
							and self._undoStack[#self._undoStack].kind == "editKey"
						then
							-- NOTE: if you're last action is an "edit both" the undo stack limit will be one less
							local editKey = table.remove(self._undoStack)
							local editValue = table.remove(self._undoStack)
							self._undoStackPosition -= 2
							self:_pushAction({
								kind = "editBoth",
								index = index,
								fromKey = editKey.from,
								toKey = editKey.to,
								fromValue = editValue.from,
								toValue = editValue.to,
							} :: EditBothAction)
						end
					end
					return true
				else
					return false
				end
			end
		end,
	})

	self:_setInModal(false)
end

function Tree:_promptInsertForm(options: {
	title: string,
	keyValidator: Validators.Validator,
	isArray: boolean,
	useUserIdConstraint: boolean,
	position: Vector2,
})
	local formResult = promptKeyValueForm(self.theme, self.gui, {
		position = options.position,
		title = options.title,

		includeKey = not options.isArray,
		includeValue = true,

		constraint = if options.useUserIdConstraint then "userId" else nil,
		extraKeyValidator = options.keyValidator,
		onExpand = function(current)
			if options.useUserIdConstraint then
				current.type = "UserId"
			end

			local result: promptKeyValueForm.OnExpandResult? = nil
			self:_promptPrecisionMenu({
				position = options.position,

				title = options.title,
				yesText = "Insert",
				noText = "Cancel",

				showKey = not options.isArray,
				lockKey = options.isArray,
				key = current.key,
				value = current.value,
				type = current.type,

				showUnexpand = true,
				keyValidator = options.keyValidator,
				onSubmit = function(res)
					if res then
						-- strip secret types
						if res.type == "UserId" then
							res.type = "number"
						elseif res.type == "empty object" then
							res.type = "object"
						elseif res.type == "empty array" then
							res.type = "array"
						end

						result = {
							operation = "submit",
							result = res,
						}
					end

					return true
				end,
				onUnexpand = function(res)
					-- strip secret types
					if res.type == "UserId" then
						res.type = "number"
					elseif res.type == "empty object" then
						res.type = "object"
					elseif res.type == "empty array" then
						res.type = "array"
					end

					result = {
						operation = "unexpand",
						current = res,
					}

					return true
				end,
			})

			if not result then
				return {
					operation = "cancel",
				}
			else
				return result
			end
		end,
	})

	return formResult
end

-- Creates a modal text box then returns what the user put into it.
-- First return: User response
-- Second return: The inputted value. If `side` was "value", the JSON that was parsed.
-- Third return: If `side` was "value", whether or not it was an array that was parsed.
function Tree:_promptModalTextBox(
	branchFrame,
	side: "key" | "value",
	options: {
		defaultText: string,
		locked: boolean?,
	}
): ("submit" | "empty" | "cancel", any, boolean)
	local isKey = (side == "key")
	local gui = self.frame:FindFirstAncestorWhichIsA("LayerCollector")
	local target = if isKey then branchFrame.Key else branchFrame.Value
	local textBox = Assets.ModalTextBox:Clone()

	local width = target.AbsoluteSize.X
	local offset = 0
	-- If it is the key, ignore the indent
	if isKey then
		width += branchFrame.UIPadding.PaddingLeft.Offset
		offset = branchFrame.UIPadding.PaddingLeft.Offset
	end

	local modal = PopupHelper.modal(textBox, gui, {
		includeDropShadow = false,
	})
	local attachment = PopupHelper.attach(textBox, target, {
		anchor = Vector2.new(0, 0),
		offset = Vector2.new(offset, 0),
	})
	local styleState = if isKey
		then TextBoxStyleState.from(self.theme, textBox)
		else JsonTextBoxStyleState.from(self.theme, textBox)

	if isKey then
		styleState
			:overrideBackgroundColor(self._colors.background)
			:overrideTextColor(self._colors.plain)
			:update("instant")
	end

	textBox.Text = options.defaultText
	textBox.PlaceholderText = side:sub(1, 1):upper() .. side:sub(2)
	textBox.Parent = gui
	textBox.Size = UDim2.fromOffset(width, 0)

	local params = Instance.new("GetTextBoundsParams")
	params.RichText = false
	params.Font = textBox.FontFace
	params.Size = textBox.TextSize
	params.Width = width

	textBox:CaptureFocus()
	if options.locked then
		textBox.TextEditable = false
		textBox.SelectionStart = 1
		textBox.CursorPosition = #textBox.Text + 1
	end

	local stop = false
	local entered = false

	modal.cancelled:Once(function()
		stop = true
	end)
	textBox.FocusLost:Connect(function(e)
		entered = e
		stop = true
	end)

	repeat
		task.wait()
	until stop

	modal:destroy()
	attachment:destroy()
	styleState:destroy()
	textBox:Destroy()

	if entered and not options.locked then
		if textBox.Text == "" then
			return "empty", textBox.Text, false
		end

		if isKey then
			return "submit", textBox.Text, false
		else
			return "submit", styleState:getJson()
		end
	end

	return "cancel", nil, false
end

function Tree:_promptEditKey(index: number)
	if self.readOnly then
		return
	end

	local branch = self._flatBranches[index]
	local frame = self._frames[index]
	local locked = false

	if branch.ISROOT or branch.LOCKKEY then
		if branch[2] == ARRAY_SENTINEL or branch[2] == OBJECT_SENTINEL then
			self:_toggleOpen(index)
			return
		else
			locked = true
		end

		self.uiMessages:warn("Cannot edit this key.")
	end
	if typeof(branch[1]) == "number" then
		self.uiMessages:warn("Drag and drop to change the order of elements in an array.")
		return
	end

	self:_setInModal(true)

	local userResponse, newKey = self:_promptModalTextBox(frame, "key", {
		defaultText = frame.Key.Text,
		locked = locked,
	})

	self:_setInModal(false)

	if userResponse == "empty" then
		self.uiMessages:error("Key was empty.")
	elseif userResponse == "submit" then
		-- It did not change
		if newKey == branch[1] then
			return
		end

		self:_processResult(self:_editKey({
			index = index,
			key = newKey,
			pushAction = true,
		}))
	end
end

function Tree:_promptEditValue(index: number)
	if self.readOnly then
		return
	end

	local branch = self._flatBranches[index]
	local frame = self._frames[index]
	local locked = false

	if branch.LOCKVALUE then
		if branch[2] == ARRAY_SENTINEL or branch[2] == OBJECT_SENTINEL then
			self:_toggleOpen(index)
			return
		else
			locked = true
		end

		self.uiMessages:warn("Cannot edit this value.")
	end

	self:_setInModal(true)

	if (typeof(branch[2]) == "string" and branch[2]:find("\n")) or (typeof(branch[2]) == "buffer") then
		-- Read-only edit menu not supported so abort.
		if locked then
			return
		end

		self:_promptEditMenu(index, {
			captureValueTextBox = true,
			position = Vector2.new(frame.Value.AbsolutePosition.X, frame.Value.AbsolutePosition.Y),
		})
		return
	end

	local userResponse, newValue, newValueIsArray = self:_promptModalTextBox(frame, "value", {
		defaultText = JSONHelper.toInputString(
			branch[2],
			if branch[2] == ARRAY_SENTINEL
				then "array"
				elseif branch[2] == OBJECT_SENTINEL then "object"
				elseif typeof(branch[2]) == "nil" then "null"
				else typeof(branch[2])
		),
		locked = locked,
	})

	self:_setInModal(false)

	if userResponse == "empty" then
		self.uiMessages:error("Value was empty.")
	elseif userResponse == "submit" then
		self:_processResult(self:_editValue({
			index = index,
			value = { value = newValue, isArray = newValueIsArray },
			pushAction = true,
		}))
	end
end

function Tree:_promptInsertInto(index: number, position: Vector2)
	local branch = self._flatBranches[index]

	local isArray = (branch[2] == ARRAY_SENTINEL)
	if isArray and branch.ISUSERIDS then
		local amount = self:_getAmountOfUserIds()
		if amount >= 4 then
			self.uiMessages:error("Max number of UserIds is 4.")
			self:_setInModal(false)
			return
		end
	end

	self:_setInModal(true)

	local result = self:_promptInsertForm({
		title = "Insert Into",
		keyValidator = function(key)
			if self:_doesChildHaveKey(index, key) then
				return false, "Already contains key."
			else
				return true, nil
			end
		end,
		isArray = (branch[2] == ARRAY_SENTINEL),
		useUserIdConstraint = branch.ISUSERIDS,
		position = position,
	})

	self:_setInModal(false)
	if result then
		local valueIsArray = (result.type == "array")

		if isArray then
			result.key = nil
		end

		local insertResult = self:_tryInsertInto({
			index = index,
			key = result.key,
			value = { value = result.value, isArray = valueIsArray },
			pushAction = true,
		})
		if insertResult.kind == "error" then
			self.uiMessages:error(insertResult.message)
		else
			if branch.ISUSERIDS then
				insertResult.branch.ISUSERID = true
			end

			self:_redrawBranches()

			-- When it is successful, the err is actually the index of the branch inserted
			self:_selectBranch(insertResult.index)
		end
	end
end

function Tree:_promptInsertAfter(index: number, position: Vector2)
	local branch = self._flatBranches[index]
	local isArray = (typeof(branch[1]) == "number")

	if isArray and branch.ISUSERID then
		local amount = self:_getAmountOfUserIds()
		if amount >= 4 then
			self.uiMessages:error("Max number of UserIds is 4.")
			self:_setInModal(false)
			return
		end
	end

	self:_setInModal(true)

	local result = self:_promptInsertForm({
		title = "Insert After",
		keyValidator = function(key)
			if self:_doesSiblingOrSelfHaveKey(index, key) then
				return false, "Sibling already has key"
			else
				return true, nil
			end
		end,
		isArray = (typeof(branch[1]) == "number"),
		useUserIdConstraint = branch.ISUSERID,
		position = position,
	})

	self:_setInModal(false)

	if result then
		if result then
			local valueIsArray = (result.type == "array")

			if isArray then
				result.key = nil
			end

			local insertResult = self:_tryInsertAfter({
				index = index,
				key = result.key,
				value = { value = result.value, isArray = valueIsArray },
				pushAction = true,
			})
			if insertResult.kind == "error" then
				self.uiMessages:error(insertResult.message)
			else
				if branch.ISUSERID then
					insertResult.branch.ISUSERID = true
				end

				self:_redrawBranches()

				-- When it is successful, the err is actually the index of the branch inserted
				self:_selectBranch(insertResult.index)
			end
		end
	end
end

local function setBranchWraps(frame, wraps: boolean)
	if wraps then
		frame.Key.AutomaticSize = Enum.AutomaticSize.Y
		frame.Value.AutomaticSize = Enum.AutomaticSize.Y
		frame.Key.RichText = true
		frame.Value.RichText = true
		frame.Key.TextTruncate = Enum.TextTruncate.None
		frame.Value.TextTruncate = Enum.TextTruncate.None
		frame.Key.TextWrapped = true
		frame.Value.TextWrapped = true
	else
		frame.Key.AutomaticSize = Enum.AutomaticSize.None
		frame.Value.AutomaticSize = Enum.AutomaticSize.None
		frame.Key.RichText = false
		frame.Value.RichText = false
		frame.Key.TextTruncate = Enum.TextTruncate.AtEnd
		frame.Value.TextTruncate = Enum.TextTruncate.AtEnd
		frame.Key.TextWrapped = false
		frame.Value.TextWrapped = false
	end
end

-- Sets up all the events for a branch frame
function Tree:_initializeBranchFrame(frame, index: number)
	local depth = self._flatDepths[index]
	local branch = self._flatBranches[index]
	self:_updateBranchFrame(frame, branch, index)

	frame.Arrow.Image = if branch[3] then self.theme.icons.downArrow else self.theme.icons.rightArrow

	local function tryStartDrag(input: InputObject)
		if self.disabled then
			return
		end
		if self.readOnly then
			return
		end

		if typeof(branch[1]) ~= "number" then
			-- Right now you can only drag and drop array elements
			return
		end

		local cleanup: () -> ()
		local ended = false
		local copyFrame: typeof(script.DraggingBranch)
		local dropAtFrame: typeof(script.DropAtFrame)
		local stateChangedConnection = input.Changed:Connect(function()
			if
				input.UserInputState == Enum.UserInputState.End
				or input.UserInputState == Enum.UserInputState.Cancel
			then
				cleanup()
			end
		end)

		function cleanup()
			self._selectingIsDragging = false

			ended = true
			stateChangedConnection:Disconnect()

			if copyFrame then
				copyFrame:Destroy()
			end
			if dropAtFrame then
				dropAtFrame:Destroy()
			end
		end

		local startPosition = self.gui:GetRelativeMousePosition()
		local offset = frame.AbsolutePosition - startPosition

		local lowerLimitVisibleIndex = nil
		local upperLimitVisibleIndex = nil
		local dropBeforeIndex = -1

		local dt = 0
		while not ended do
			local mousePosition = self.gui:GetRelativeMousePosition()
			local offsetPosition = mousePosition + offset

			if not self._selectingIsDragging then
				if (mousePosition - startPosition).Magnitude > 5 then
					self:_setHovering(nil)
					self:_selectBranch(index, true)
					self._selectingIsDragging = true

					copyFrame = script.DraggingBranch:Clone()
					dropAtFrame = script.DropAtFrame:Clone()

					copyFrame.BackgroundColor3 = self._colors.background
					copyFrame.Key.Text = frame.Key.Text
					copyFrame.Key.TextColor3 = frame.Key.TextColor3
					copyFrame.Value.Text = frame.Value.Text
					copyFrame.Value.TextColor3 = frame.Value.TextColor3

					dropAtFrame.BackgroundColor3 = self._colors.mainAccent
					dropAtFrame.Start.BackgroundColor3 = self._colors.mainAccent
					dropAtFrame.End.BackgroundColor3 = self._colors.mainAccent

					copyFrame.Parent = self.gui
					copyFrame.Position = UDim2.fromOffset(offsetPosition.X, offsetPosition.Y)
				end
			else
				-- Try scrolling if near top/bottom
				local distanceFromTop = self.frame.AbsolutePosition.Y - mousePosition.Y
				if -4 < distanceFromTop and distanceFromTop < 14 then
					self.frame.CanvasPosition = Vector2.new(0, self.frame.CanvasPosition.Y - 100 * dt)
				end

				local distanceFromBottom = self.frame.AbsolutePosition.Y + self.frame.AbsoluteSize.Y - mousePosition.Y
				if -14 < distanceFromBottom and distanceFromBottom < 4 then
					self.frame.CanvasPosition = Vector2.new(0, self.frame.CanvasPosition.Y + 100 * dt)
				end

				-- Main behavior

				local relativePosition = mousePosition
					- self.frame.AbsolutePosition
					+ Vector2.new(0, self.frame.CanvasPosition.Y)
				copyFrame.Position = UDim2.fromOffset(offsetPosition.X, offsetPosition.Y)

				local selectingStart = SIZE_PER_BRANCH * (self._selectingBranchVisibleIndex - 1)
				local selectingEnd = SIZE_PER_BRANCH * self._selectingBranchVisibleIndex + self._selectingBranchOffset
				if selectingStart < relativePosition.Y and relativePosition.Y < selectingEnd then
					-- Hover target is self
					dropAtFrame.Parent = nil
				else
					dropBeforeIndex = -1
					-- TODO: dropBeforeIndex should consider the 3px space in the selecting branch
					if relativePosition.Y < selectingStart then
						local index = math.floor(relativePosition.Y / SIZE_PER_BRANCH)
						local positionRelativeToIndex = relativePosition.Y - (SIZE_PER_BRANCH * index)
						if positionRelativeToIndex <= DRAG_AND_DROP_REGION_SIZE / 2 then
							dropBeforeIndex = index + 1
						elseif positionRelativeToIndex >= SIZE_PER_BRANCH - DRAG_AND_DROP_REGION_SIZE / 2 then
							dropBeforeIndex = index + 2
						end
					elseif relativePosition.Y > selectingEnd then
						local index = math.floor((relativePosition.Y - selectingEnd) / SIZE_PER_BRANCH)
							+ self._selectingBranchVisibleIndex
						local positionRelativeToIndex = relativePosition.Y
							- (SIZE_PER_BRANCH * index)
							- self._selectingBranchOffset
						if positionRelativeToIndex <= DRAG_AND_DROP_REGION_SIZE / 2 then
							dropBeforeIndex = index + 1
						elseif positionRelativeToIndex >= SIZE_PER_BRANCH - DRAG_AND_DROP_REGION_SIZE / 2 then
							dropBeforeIndex = index + 2
						end
					end

					local scanBeforeIndex = dropBeforeIndex
					if dropBeforeIndex < 0 then
						dropBeforeIndex = -1
					elseif dropBeforeIndex > #self._visibleIndexes then
						scanBeforeIndex = #self._visibleIndexes + 1
						dropBeforeIndex = #self._visibleIndexes + 1
					end

					-- Calculate limits if possible
					if
						not lowerLimitVisibleIndex
						and scanBeforeIndex > 0
						and scanBeforeIndex < self._selectingBranchVisibleIndex
					then
						for i = self._selectingBranchVisibleIndex, scanBeforeIndex, -1 do
							local scannedDepth = self._flatDepths[self._visibleIndexes[i]]
							if scannedDepth < depth then
								lowerLimitVisibleIndex = i + 1
								break
							end
						end
					end
					if
						not upperLimitVisibleIndex
						and scanBeforeIndex > 0
						and scanBeforeIndex > self._selectingBranchVisibleIndex
					then
						for i = self._selectingBranchVisibleIndex, scanBeforeIndex do
							-- scannedDepth might be nil if scanning up to the end
							local scannedDepth = self._flatDepths[self._visibleIndexes[i]]
							if scannedDepth and (scannedDepth < depth) then
								upperLimitVisibleIndex = i
								break
							end
						end
					end

					-- Limit it
					if lowerLimitVisibleIndex and scanBeforeIndex < lowerLimitVisibleIndex then
						dropBeforeIndex = -1
					elseif upperLimitVisibleIndex and scanBeforeIndex > upperLimitVisibleIndex then
						dropBeforeIndex = -1
					end

					-- Make sure it's dropping into the array
					if scanBeforeIndex > 0 then
						local scanBeforeDepth = self._flatDepths[self._visibleIndexes[scanBeforeIndex]]
						if scanBeforeIndex > self._selectingBranchVisibleIndex then
							if
								(
									scanBeforeDepth == nil --[[ This means its at the end of the tree ]]
								) or (scanBeforeDepth < depth)
							then
								for i = scanBeforeIndex - 1, self._selectingBranchVisibleIndex, -1 do
									local scannedDepth = self._flatDepths[self._visibleIndexes[i]]
									if scannedDepth == depth then
										break
									elseif scannedDepth < depth then
										dropBeforeIndex = -1
										break
									end
								end
							elseif scanBeforeDepth ~= depth then
								dropBeforeIndex = -1
							end
						else
							if scanBeforeDepth ~= depth then
								dropBeforeIndex = -1
							end
						end
					end

					if dropBeforeIndex < 0 then
						dropAtFrame.Parent = nil
					else
						dropAtFrame.Parent = self.gui
						dropAtFrame.Position = UDim2.fromOffset(
							self.frame.AbsolutePosition.X,
							self.frame.AbsolutePosition.Y
								+ SIZE_PER_BRANCH * (dropBeforeIndex - 1)
								- self.frame.CanvasPosition.Y
								+ (
									if dropBeforeIndex > self._selectingBranchVisibleIndex
										then self._selectingBranchOffset
										else 0
								)
						)
						dropAtFrame.Size = UDim2.fromOffset(self.frame.AbsoluteCanvasSize.X, 2)
					end
				end
			end

			dt = task.wait()
		end

		if dropBeforeIndex > 0 then
			if dropBeforeIndex == #self._visibleIndexes + 1 then
				self:_moveArrayElementToEnd({
					branchIndex = index,
					branchVisibleIndex = self._selectingBranchVisibleIndex,
					pushAction = true,
				})
			else
				self:_moveArrayElement({
					branchIndex = index,
					branchVisibleIndex = self._selectingBranchVisibleIndex,
					moveBeforeIndex = self._visibleIndexes[dropBeforeIndex],
					moveBeforeVisibleIndex = dropBeforeIndex,
					pushAction = true,
				})
			end
		end
	end

	local function onSingleClick()
		self:_selectBranch(index)
		if Settings.get("clickToOpen") then
			self:_toggleOpen(index)
		end
	end

	local function onRightClick()
		if self.disabled then
			return
		end
		if self.readOnly then
			return
		end
		if self._selectingIsDragging then
			return
		end

		self:_selectBranch(index, true)

		local options: { [number]: any } = {}

		if not branch.LOCKVALUE then
			table.insert(options, { icon = self.theme.icons.edit, text = "Edit" })
		end

		if not (branch.LOCKVALUE or branch.LOCKKEY or branch.ISROOT) then
			table.insert(options, { icon = self.theme.icons.delete, text = "Delete" })
		end

		if depth >= 1 and not branch.LOCKVALUE then
			table.insert(options, { icon = self.theme.icons.insert, text = "Insert After" })
		end

		-- Special case for user ids, should be able to insert ids
		if
			((branch[2] == ARRAY_SENTINEL or branch[2] == OBJECT_SENTINEL) and not branch.LOCKVALUE)
			or branch.ISUSERIDS
			or branch.ISMETADATA
		then
			table.insert(options, { icon = self.theme.icons.insert, text = "Insert Into" })
		end

		if branch.ISUSERID then
			table.insert(options, ContextMenuStyleState.SEPARATOR)
			table.insert(options, { icon = self.theme.icons.lookup, text = "Lookup Id" })
		end

		-- Expand/collapse options
		if branch[2] == ARRAY_SENTINEL or branch[2] == OBJECT_SENTINEL then
			if self:_doesBranchHaveChildren(index) then
				table.insert(options, ContextMenuStyleState.SEPARATOR)
				--[[if (not branch.ISTIME) and self:_getUniversalTimeTable(index) then
					table.insert(options, "Display as Time")
				elseif branch.ISTIME then
					table.insert(options, "Display as Object")
				end]]
				table.insert(options, "Expand All")
				table.insert(options, "Collapse All")
			end
		else
			if branch.ISTIME then
				if typeof(branch[2]) == "number" then
					table.insert(options, ContextMenuStyleState.SEPARATOR)
					table.insert(options, "Display as Number")
				end
			elseif typeof(branch[2]) == "number" then
				-- It may be a timestamp!
				if Validators.integer(branch[2]) and (branch[2] > 0) and not branch.ISUSERID then
					table.insert(options, ContextMenuStyleState.SEPARATOR)
					table.insert(options, "Display as Time")
				end
			end
		end

		if #options == 0 then
			return
		end

		local position = self.gui:GetRelativeMousePosition()
		local option = ContextMenuStyleState.prompt(self.theme, self.gui, position, {
			options = options,
			passThroughInput = true,
		})

		if option == "Edit" then
			self:_promptEditMenu(index, { position = position })
		elseif option == "Delete" then
			self:_deleteBranch({ index = index, pushAction = true })
			self:_redrawBranches()
		elseif option == "Insert Into" then
			self:_promptInsertInto(index, position)
		elseif option == "Insert After" then
			self:_promptInsertAfter(index, position)
		elseif option == "Lookup Id" then
			self._idLookedUp:Fire(branch[2])
		elseif option == "Expand All" then
			self:_expandAll(index)
		elseif option == "Collapse All" then
			self:_collapseAll(index)
		elseif option == "Display as Time" then
			branch.ISTIME = true
			self:_updateBranchFrame(frame, branch, index)
		elseif option == "Display as Number" or option == "Display as Object" then
			branch.ISTIME = false
			self:_updateBranchFrame(frame, branch, index)
		end

		self:_setInModal(false)
	end

	self._frameConnections[index] = {
		frame.Arrow.Activated:Connect(function()
			self:_toggleOpen(index)
		end),

		frame.Key.MouseButton2Click:Connect(onRightClick),
		frame.Value.MouseButton2Click:Connect(onRightClick),
		frame.MouseButton2Click:Connect(onRightClick),

		frame.Key.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				tryStartDrag(input)
			end
		end),
		frame.Value.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				tryStartDrag(input)
			end
		end),

		frame.Activated:Connect(function(_, count)
			count = count % 2
			if count == 0 then
				onSingleClick()
			end
		end),
		frame.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				tryStartDrag(input)
			elseif input.UserInputType == Enum.UserInputType.MouseMovement then
				self:_setHovering(index)
			end
		end),
		frame.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseMovement then
				if self._hoveringBranchIndex == index then
					self:_setHovering(nil)
				end
			end
		end),

		-- Updating values
		frame.Key.Activated:Connect(function(_, count)
			if self.disabled then
				return
			end

			count = count % 2

			if count == 0 then
				onSingleClick()
			elseif count == 1 then
				self:_promptEditKey(index)
			end
		end),
		frame.Value.Activated:Connect(function(_, count)
			if self.disabled then
				return
			end

			count = count % 2

			if count == 0 then
				onSingleClick()
			elseif count == 1 then
				self:_promptEditValue(index)
			end
		end),

		-- Selection stuff
		frame:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			if self._selectingBranchIndex == index then
				self._selectingBranchOffset = frame.AbsoluteSize.Y - SIZE_PER_BRANCH
				self:_updateCanvasSize()
				self:_redrawBranches()
			end
		end),
	}

	self:_updateBranchFrameBackgroundColor(index)
	if self._selectingBranchIndex == index then
		setBranchWraps(frame, true)
	else
		setBranchWraps(frame, false)
	end
end

function Tree:_removeFrame(index: number, frame)
	frame = frame or self._frames[index]
	if #self._framePool > FRAME_POOL_SIZE_LIMIT then
		frame:Destroy()
		self._frames[index] = nil
		self._frameConnections[index] = nil
		return
	end
	local frame = self._frames[index]
	--frame.Visible = false
	frame.Parent = nil
	self._frames[index] = nil

	local connections = self._frameConnections[index]
	for _, c in connections do
		c:Disconnect()
	end
	self._frameConnections[index] = nil

	table.insert(self._framePool, frame)
end

function Tree:_clearFrames()
	for _, frame in self._frames do
		--frame.Visible = false
		frame.Parent = nil
	end
	for _, connections in self._frameConnections do
		for _, c in connections do
			c:Disconnect()
		end
	end
	self._frames = {}
	self._frameConnections = {}
end

-- This actually updates if it is open, not if it is visible...
-- TODO: change the name of this function
function Tree:_updateBranchVisible(index)
	local startVisibleIndex = table.find(self._visibleIndexes, index)
	if not startVisibleIndex then
		warn("Branch opened that is not visible. How!?")
		return
	end

	local startDepth = self._flatDepths[index]
	local i = index + 1

	-- Close
	if not self._flatBranches[index][3] then
		local endVisibleIndex = nil
		local len = #self._flatDepths
		while i <= len do
			local depth = self._flatDepths[i]
			if depth <= startDepth then
				endVisibleIndex = table.find(self._visibleIndexes, i)
				if endVisibleIndex then
					endVisibleIndex -= 1
				end
				break
			end
			i += 1
		end

		if self._selectingBranchVisibleIndex then
			if
				startVisibleIndex + 1 < self._selectingBranchVisibleIndex
				and self._selectingBranchVisibleIndex < (endVisibleIndex or #self._visibleIndexes)
			then
				self._selectingBranchVisibleIndex = nil
			end
		end
		-- Splicing the closed region out
		-- Add 1 so it doesn't include the parent branch
		self._visibleIndexes = spliceOut(self._visibleIndexes, startVisibleIndex + 1, endVisibleIndex)
		-- Open
	else
		local addedVisibleIndexes = table.create(32)
		local openedStack = table.create(8)
		table.insert(openedStack, self._flatBranches[index][3])

		local endVisibleIndex = nil
		local lastDepth = self._flatDepths[index]
		local len = #self._flatDepths
		while i <= len do
			local depth = self._flatDepths[i]
			if depth <= startDepth then
				endVisibleIndex = table.find(self._visibleIndexes, i)
				break
			end

			if depth > lastDepth then
				if openedStack[#openedStack] then
					table.insert(openedStack, self._flatBranches[i - 1][3])
				else
					table.insert(openedStack, false)
				end
			elseif depth < lastDepth then
				for i = 1, lastDepth - depth do
					table.remove(openedStack)
				end
			end
			if openedStack[#openedStack] then
				table.insert(addedVisibleIndexes, i)
			end

			lastDepth = depth
			i += 1
		end

		-- Splicing the opened region in
		local newVisibleIndexes = table.create(#self._visibleIndexes + #addedVisibleIndexes)
		table.move(self._visibleIndexes, 1, startVisibleIndex, 1, newVisibleIndexes)
		table.move(addedVisibleIndexes, 1, #addedVisibleIndexes, #newVisibleIndexes + 1, newVisibleIndexes)
		if endVisibleIndex then
			table.move(
				self._visibleIndexes,
				endVisibleIndex,
				#self._visibleIndexes,
				#newVisibleIndexes + 1,
				newVisibleIndexes
			)
		end
		self._visibleIndexes = newVisibleIndexes

		if self._selectingBranchIndex and not self._selectingBranchVisibleIndex then
			self._selectingBranchVisibleIndex = table.find(self._visibleIndexes, self._selectingBranchIndex)
		end
	end

	self:_updateCanvasSize()
end

function Tree:_clearNonVisibleBranches()
	for index, frame in self._frames do
		if not table.find(self._visibleIndexes, index) then
			self:_removeFrame(index, frame)
		end
	end
end

-- Redraws branches to only render which ones the user can see.
function Tree:_redrawBranches()
	local startOffset = SIZE_PER_BRANCH * math.floor(self.frame.CanvasPosition.Y / SIZE_PER_BRANCH)
	local branchesToRender = math.ceil(self.frame.AbsoluteWindowSize.Y / SIZE_PER_BRANCH) + 1

	if not self._overflowDirection then
		startOffset = math.max(0, startOffset - (SIZE_PER_BRANCH * math.floor(self._overflowOffset / SIZE_PER_BRANCH)))
	end
	-- Always increase branchesToRender because for upwards overflow, it will need to render more to fill the frame
	branchesToRender += math.floor(self._overflowOffset / SIZE_PER_BRANCH)

	-- Stuff to adjust for selecting branch being bigger
	if self._selectingBranchVisibleIndex then
		-- Keep the selecting frame visible when its going to go out of frame
		local selectingBranchTop = SIZE_PER_BRANCH * self._selectingBranchVisibleIndex + self._selectingBranchOffset
		if
			self.frame.CanvasPosition.Y >= SIZE_PER_BRANCH * self._selectingBranchVisibleIndex
			and self.frame.CanvasPosition.Y <= selectingBranchTop
		then
			local distanceFromSelectingBranch = (
				startOffset - SIZE_PER_BRANCH * (self._selectingBranchVisibleIndex - 1)
			)
			startOffset -= distanceFromSelectingBranch
			self.frame.UIPadding.PaddingTop = UDim.new(0, startOffset)
			-- Simulate the offset as if the selecting branch were rendered when it goes out of frame
		elseif self.frame.CanvasPosition.Y > selectingBranchTop then
			startOffset = SIZE_PER_BRANCH
				* (
					math.floor((self.frame.CanvasPosition.Y - selectingBranchTop) / SIZE_PER_BRANCH)
					+ self._selectingBranchVisibleIndex
				)
			self.frame.UIPadding.PaddingTop = UDim.new(0, startOffset + self._selectingBranchOffset)
		else
			self.frame.UIPadding.PaddingTop = UDim.new(0, startOffset)
		end
	else
		self.frame.UIPadding.PaddingTop = UDim.new(0, startOffset)
	end

	local startVisibleIndex = math.floor(startOffset / SIZE_PER_BRANCH) + 1
	local endVisibleIndex = startVisibleIndex + branchesToRender
	local startIndex = self._visibleIndexes[startVisibleIndex]
	local endIndex = self._visibleIndexes[endVisibleIndex]

	local tempPool = table.create(8)
	if startIndex then
		for i, frame in self._frames do
			if i < startIndex then
				table.insert(tempPool, { i, frame })
			elseif endIndex and (i > endIndex) then
				table.insert(tempPool, { i, frame })
			end
		end
	end

	local maxDepth = 0
	for visibleI = startVisibleIndex, endVisibleIndex do
		local i = self._visibleIndexes[visibleI]
		if not i then
			endIndex = self._visibleIndexes[visibleI - 1]

			if endIndex then -- May not exist if startVisibleIndex does not exist
				for i, frame in self._frames do
					if i > endIndex then
						table.insert(tempPool, { i, frame })
					end
				end
			end
			break
		end

		local frame = self._frames[i]
		if not frame then
			if #tempPool > 0 then
				local v = table.remove(tempPool)
				frame = v[2]

				for _, c in self._frameConnections[v[1]] do
					c:Disconnect()
				end
				self._frames[v[1]] = nil
				self._frameConnections[v[1]] = nil
			elseif #self._framePool > 0 then
				frame = table.remove(self._framePool)
				--frame.Visible = true
				frame.Parent = self.frame
			else
				frame = script.Branch:Clone()
				frame.Parent = self.frame
			end
			self._frames[i] = frame

			local depth = self._flatDepths[i]

			frame.LayoutOrder = visibleI
			frame.UIPadding.PaddingLeft = UDim.new(0, 22 * depth)
			self:_initializeBranchFrame(frame, i)

			maxDepth = math.max(maxDepth, depth)
		else
			frame.LayoutOrder = visibleI
		end
	end
	--self:_tryAddHierarchyBarsUpTo(maxDepth) TODO: re-add this later

	for _, v in tempPool do
		self:_removeFrame(v[1], v[2])
	end
end

function Tree:_tryAddHierarchyBarsUpTo(amount: number)
	if amount > #self._hierarchyBars then
		for i = #self._hierarchyBars + 1, amount do
			local bar = script.HierarchyBar:Clone()
			bar.Size = UDim2.fromOffset(1, self.frame.AbsoluteWindowSize.Y + SIZE_PER_BRANCH)
			bar.Position = UDim2.fromOffset(20 + 22 * (i - 1), 0)

			table.insert(self._hierarchyBars, bar)
			bar.Parent = self._hierarchyBarFolder
		end
	end
end

function Tree:_setInModal(inModal: boolean)
	self._inModal = inModal
	self.frame.ScrollingEnabled = not inModal

	if self._hoveringBranchIndex then
		local hoveringIndex = self._hoveringBranchIndex
		self._hoveringBranchIndex = nil
		self:_updateBranchFrameBackgroundColor(hoveringIndex)
	end
end

function Tree:_updateBranchFrameBackgroundColor(index: boolean, frame: Frame?)
	frame = frame or self._frames[index]
	if frame then
		if self._selectingBranchIndex == index then
			frame.BackgroundColor3 = self._colors.selectBackground
		elseif self._hoveringBranchIndex == index then
			frame.BackgroundColor3 = self._colors.hoverBackground
		else
			frame.BackgroundColor3 = self._colors.background
		end
	end
end

function Tree:_setHovering(index: number?)
	if self._inModal then
		return
	end
	if self._selectingIsDragging then
		return
	end

	local lastIndex = self._hoveringBranchIndex

	if index ~= lastIndex then
		self._hoveringBranchIndex = index
		if lastIndex then
			self:_updateBranchFrameBackgroundColor(lastIndex)
		end
		if index then
			self:_updateBranchFrameBackgroundColor(index)
		end
	end
end

function Tree:_selectBranch(index: number, dontDeselect: boolean)
	if self._selectingIsDragging then
		return
	end
	if self._isTesting then
		return
	end

	local lastIndex = self._selectingBranchIndex

	local mousePosition = self.gui:GetRelativeMousePosition()

	if index ~= lastIndex then
		self._selectingBranchIndex = index
		self._selectingBranchVisibleIndex = table.find(self._visibleIndexes, index)
		self._selectingBranchOffset = 0

		if lastIndex then
			self:_updateBranchFrameBackgroundColor(lastIndex)

			local frame = self._frames[lastIndex]
			if frame then
				self:_updateBranchFrame(frame, self._flatBranches[lastIndex], lastIndex)
				setBranchWraps(frame, false)
			end
		end
		self:_updateBranchFrameBackgroundColor(index)

		local frame = self._frames[index]
		if frame then
			self:_updateBranchFrame(frame, self._flatBranches[index], index)
			setBranchWraps(frame, true)
		end

		self:_updateCanvasSize()
		self._selectionChanged:Fire()
	elseif (not dontDeselect) and lastIndex then
		self._selectingBranchIndex = nil
		self._selectingBranchVisualIndex = nil
		self._selectingBranchOffset = 0
		self:_updateBranchFrameBackgroundColor(lastIndex)

		local frame = self._frames[index]
		if frame then
			self:_updateBranchFrame(frame, self._flatBranches[index], index)
			setBranchWraps(frame, false)
			self:_redrawBranches()
		end

		self:_updateCanvasSize()
		self._selectionChanged:Fire()
	end
end

function Tree:_updateAllBranchFrames()
	for index, frame in self._frames do
		self:_updateBranchFrame(frame, self._flatBranches[index], index)
	end
end

function Tree:_updateColors()
	self._colors = getHighlightColors(self.theme)
	self.frame.BackgroundColor3 = self._colors.background
	self.frame.ScrollBarImageColor3 = self._colors.scrollbar
	self:_updateAllBranchFrames()
end

function Tree:_makeDirty()
	self.isDirty = true
	self._dirtyChanged:Fire(true)
end

function Tree:setDisabled(disabled: boolean)
	self.disabled = disabled
	self:_updateAllBranchFrames()
end

function Tree:undirty()
	self.isDirty = false
	self._dirtyChanged:Fire(false)
end

function Tree:canUndo()
	return (#self._undoStack > 0) and (self._undoStackPosition > 0)
end

function Tree:canRedo()
	return (#self._undoStack > 0) and (self._undoStackPosition < #self._undoStack)
end

function Tree:undo()
	if self:canUndo() then
		self:_undo()
	end
end

function Tree:redo()
	if self:canRedo() then
		self:_redo()
	end
end

type UnflattenResult = {
	value: ActionValue,
	hasNil: boolean,
}

function Tree:_unflatten(index: number): UnflattenResult
	local firstBranch = self._flatBranches[index]
	if not (firstBranch[2] == ARRAY_SENTINEL or firstBranch[2] == OBJECT_SENTINEL) then
		return {
			value = { value = firstBranch[2], isArray = firstBranch[2] == ARRAY_SENTINEL },
			hasNil = false,
		}
	end

	local result = {}
	local branchStack = table.create(8)
	table.insert(branchStack, result)

	local initialDepth = self._flatDepths[index]
	local lastDepth = initialDepth + 1
	local hasNil = false

	for i = index + 1, #self._flatBranches do
		local branch = self._flatBranches[i]
		local depth = self._flatDepths[i]

		if depth < lastDepth then
			for i = lastDepth - 1, depth, -1 do
				table.remove(branchStack)
			end
		end

		if depth <= initialDepth then
			break
		end

		local key = branch[1]
		local value = branch[2]
		local currentBranch = branchStack[#branchStack]

		if value == ARRAY_SENTINEL or value == OBJECT_SENTINEL then
			value = {}
			currentBranch[key] = value
			table.insert(branchStack, value)
			depth += 1
		else
			if value == nil then
				hasNil = true
			end
			currentBranch[key] = value
		end

		lastDepth = depth
	end

	return {
		value = { value = result, isArray = firstBranch[2] == ARRAY_SENTINEL },
		hasNil = hasNil,
	}
end

-- Recreates the tree from the flat internal representation
-- The second return value is if there were any nil values
function Tree:getValue(): (any, boolean)
	local result = self:_unflatten(self:_getRootIndex())
	return result.value.value, result.hasNil
end

-- Returns UserId and Metadata
function Tree:getKeyInfo(): ({ number }, { [string]: any })
	local metadata = {}
	local userIds = {}

	local branchStack = table.create(4)
	table.insert(branchStack, metadata)

	local startUserIds = false
	local startMetadata = false

	local lastDepth = nil
	for i, branch in self._flatBranches do
		if not startUserIds then
			if branch.ISUSERIDS then
				startUserIds = true
				continue
			else
				continue
			end
		end

		if not startMetadata then
			if branch.ISMETADATA then
				startMetadata = true
				lastDepth = self._flatDepths[i]
				continue
			else
				-- Add user ids
				table.insert(userIds, branch[2])
				continue
			end
		end

		if branch.ISROOT then
			break
		end

		local depth = self._flatDepths[i]

		-- First branch
		if depth < lastDepth then
			for i = lastDepth - 1, depth, -1 do
				table.remove(branchStack)
			end
		end

		local key = branch[1]
		local value = branch[2]
		local currentBranch = branchStack[#branchStack]

		if value == ARRAY_SENTINEL or value == OBJECT_SENTINEL then
			value = {}
			currentBranch[key] = value
			table.insert(branchStack, value)
			depth += 1
		else
			if typeof(key) == "number" then
				table.insert(currentBranch, value)
			else
				currentBranch[key] = value
			end
		end

		lastDepth = depth
	end

	return userIds, metadata
end

--[[ HOTKEY OPERATIONS ]]

function Tree:tryDeleteSelected(): boolean
	if not self._selectingBranchIndex then
		return false
	end

	self:_deleteBranch({ index = self._selectingBranchIndex, pushAction = true })
	self:_redrawBranches()

	return true
end

function Tree:tryOpenSelected(): boolean
	if not self._selectingBranchIndex then
		return false
	end

	local branch = self._flatBranches[self._selectingBranchIndex]
	if branch[2] ~= ARRAY_SENTINEL and branch[2] ~= OBJECT_SENTINEL then
		-- Doing delay (task.defer did not work) because if this was triggered by a hotkey, the pressed key will be inserted into the textbox
		task.delay(0, function()
			self:_promptEditValue(self._selectingBranchIndex)
		end)
		return true
	end

	if branch[3] then
		return
	end

	self:_toggleOpen(self._selectingBranchIndex)
	return true
end

function Tree:tryCloseSelected(): boolean
	if not self._selectingBranchIndex then
		return false
	end

	local branch = self._flatBranches[self._selectingBranchIndex]
	if branch[2] ~= ARRAY_SENTINEL and branch[2] ~= OBJECT_SENTINEL then
		return
	end

	if not branch[3] then
		return
	end

	self:_toggleOpen(self._selectingBranchIndex)
	return true
end

function Tree:trySelectNext(): boolean
	if not self._selectingBranchIndex then
		return false
	end

	local nextVisibleIndex = self._selectingBranchVisibleIndex + 1
	local nextIndex = self._visibleIndexes[nextVisibleIndex]
	if nextIndex then
		self:_selectBranch(nextIndex)
		self:_scrollTo(nextVisibleIndex)
		return true
	end

	return false
end

function Tree:trySelectPrevious(): boolean
	if not self._selectingBranchIndex then
		return false
	end

	local previousVisibleIndex = self._selectingBranchVisibleIndex - 1
	local previousIndex = self._visibleIndexes[previousVisibleIndex]
	if previousIndex then
		self:_selectBranch(previousIndex)
		self:_scrollTo(previousVisibleIndex)
		return true
	end

	return false
end

function Tree:tryEditKeySelected(): boolean
	if not self._selectingBranchIndex then
		return false
	end

	self:_promptEditKey(self._selectingBranchIndex)
	return true
end

function Tree:tryInsertSelected(): boolean
	if not self._selectingBranchIndex then
		return false
	end

	local frame = self._frames[self._selectingBranchIndex]
	local branch = self._flatBranches[self._selectingBranchIndex]
	if branch and frame then
		if branch[2] == OBJECT_SENTINEL or branch[2] == ARRAY_SENTINEL then
			self:_promptInsertInto(self._selectingBranchIndex, frame.Value.AbsolutePosition)
		else
			self:_promptInsertAfter(self._selectingBranchIndex, frame.Value.AbsolutePosition)
		end
	end

	return false
end

--[[ HOTKEY OPERATIONS END ]]

function Tree:destroy(completely: boolean)
	assert(not completely, "Tree should not own the scrolling frame that contains it.")
	self._dirtyChanged:Destroy()

	self:_clearFrames()
	for _, connection in self._connections do
		connection:Disconnect()
	end
	for _, frame in self._framePool do
		frame:Destroy()
	end
	for _, bar in self._hierarchyBars do
		bar:Destroy()
	end
	self._hierarchyBarFolder:Destroy()

	for _, event in self do
		if typeof(event) == "Instance" and event:IsA("BindableEvent") then
			event:Destroy()
		end
	end
end

return Tree
