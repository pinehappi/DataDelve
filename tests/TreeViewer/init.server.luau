-- Tests for tree viewer

local FUZZ_TESTS = 25

local Theme = require(script.Parent.Parent.UI.Theme)
local Tree = require(script.Parent.Parent.UI.Viewers.Tree)

local fuzzUserIds = require(script.fuzzUserIds)
local fuzzJSON = require(script.fuzzJSON)

type SearchForQuery = { key: string | number, value: any?, isContainer: boolean? }
type Operation = {
	type: "delete",
	searchFor: SearchForQuery,
	onlyChildren: boolean?,
} | {
	type: "insertInto",
	searchFor: SearchForQuery,
	key: string?,
	value: any,
	isArray: boolean?,
} | {
	type: "insertAfter",
	searchFor: SearchForQuery,
	key: string?,
	value: any,
	isArray: boolean?,
} | {
	type: "move",
	move: SearchForQuery,
	before: SearchForQuery,
} | {
	type: "moveEnd",
	move: SearchForQuery,
} | {
	type: "edit",
	searchFor: SearchForQuery,
	value: any,
	isArray: boolean?,
}

local fakeKeyInfo = {
	CreatedTime = 0,
	UpdatedTime = 0,
	UserIds = {},
	Version = "",
	Metadata = nil,
}

local testTree1 = {
	hello = 5,
	taxi = 3,
	nested = {
		hello = "y aw3faw3 faw3f aw3 aw3 aw3 faw3 fw3 faw3 aw3 wa3 aw3 aw3f es",
		aeoae = "wasafw 3faw3 awf aw3 aw3 aw3 aw aw aw3 aw3 aw3 aw3 aw3 aw3 aw wa3 aw3 wa3 aw3tt 3asup",
		moreNEsted = {
			3,
			4,
			5,
			6,
			6,
			"slayy",
			{
				"wafawefawf awfawefawefawfeawefawfwaef awef awef aewf awef awefssup",
				43,
				{ "Uusfa wefawf waefewa fawfa weafwaef awef awef awfe aw3f awe waaw efus", 45, true, false },
			},
		},
	},
	car = 34,
	tree = "wassa w3f aw3f aw3f aw3 aw3 aw3f aw wa3 aw3 aw wa3 aw3 aw3a w3fup",
	city = false,
	abc = true,
}

local testTree2 = {
	hello = 5,
	taxi = 3,
	nested = {
		hello = "y aw3faw3 faw3f aw3 aw3 aw3 faw3 fw3 faw3 aw3 wa3 aw3 aw3f es",
		aeoae = "wasafw 3faw3 awf aw3 aw3 aw3 aw aw aw3 aw3 aw3 aw3 aw3 aw3 aw wa3 aw3 wa3 aw3tt 3asup",
		moreNEsted = {
			hello = 5,
			taxi = 3,
			nested = {
				hello = "y aw3faw3 faw3f aw3 aw3 aw3 faw3 fw3 faw3 aw3 wa3 aw3 aw3f es",
				aeoae = "wasafw 3faw3 awf aw3 aw3 aw3 aw aw aw3 aw3 aw3 aw3 aw3 aw3 aw wa3 aw3 wa3 aw3tt 3asup",
				moreNEsted = {
					3,
					4,
					5,
					6,
					6,
					"slayy",
					{
						"wafawefawf awfawefawefawfeawefawfwaef awef awef aewf awef awefssup",
						43,
						{ "Uusfa wefawf waefewa fawfa weafwaef awef awef awfe aw3f awe waaw efus", 45, true, false },
					},
					{
						hello = 5,
						taxi = 3,
						nested = {
							hello = "y aw3faw3 faw3f aw3 aw3 aw3 faw3 fw3 faw3 aw3 wa3 aw3 aw3f es",
							aeoae = "wasafw 3faw3 awf aw3 aw3 aw3 aw aw aw3 aw3 aw3 aw3 aw3 aw3 aw wa3 aw3 wa3 aw3tt 3asup",
							moreNEsted = {
								3,
								4,
								5,
								6,
								6,
								"slayy",
								{
									"wafawefawf awfawefawefawfeawefawfwaef awef awef aewf awef awefssup",
									43,
									{
										"Uusfa wefawf waefewa fawfa weafwaef awef awef awfe aw3f awe waaw efus",
										45,
										true,
										false,
									},
								},
							},
						},
						car = 34,
						tree = "wassa w3f aw3f aw3f aw3 aw3 aw3f aw wa3 aw3 aw wa3 aw3 aw3a w3fup",
						city = false,
						abc = true,
					},
				},
			},
			car = 34,
			tree = "wassa w3f aw3f aw3f aw3 aw3 aw3f aw wa3 aw3 aw wa3 aw3 aw3a w3fup",
			city = false,
			abc = true,
		},
	},
	car = 34,
	tree = "wassa w3f aw3f aw3f aw3 aw3 aw3f aw wa3 aw3 aw wa3 aw3 aw3a w3fup",
	city = false,
	abc = true,
}

local testTree3 = {
	1,
	2,
	3,
	nil,
	4,
	5,
	nil,
	nil,
	nil,
	nil,
	nil,
	6,
}

local testTree4 = {
	{ 1, 2, 3 },
	{ 4, 5, 6 },
	{ 7, 8, 9 },
	{ 10, 11, 12 },
}

local testTree5 = { 1 / 0 }

local testTree6 = {
	nested = {
		hello = "y aw3faw3 faw3f aw3 aw3 aw3 faw3 fw3 faw3 aw3 wa3 aw3 aw3f es",
		aeoae = "wasafw 3faw3 awf aw3 aw3 aw3 aw aw aw3 aw3 aw3 aw3 aw3 aw3 aw wa3 aw3 wa3 aw3tt 3asup",
		moreNEsted = {
			3,
			4,
			5,
			"slayy",
			{
				"wafawefawf awfawefawefawfeawefawfwaef awef awef aewf awef awefssup",
				43,
				{ "Uusfa wefawf waefewa fawfa weafwaef awef awef awfe aw3f awe waaw efus", 45, true, false },
			},
			6,
			6,
		},
	},
}

-- Utilities

local function buffersEqual(b1: buffer, b2: buffer)
	return buffer.tostring(b1) == buffer.tostring(b2)
end

local function tablesEqual(a, b): boolean
	for i, v in a do
		if typeof(v) == "table" then
			if (not b[i]) or (not tablesEqual(v, b[i])) then
				print("NOT EQUAL AT (A1)", "B:", b[i], "A:", v, "KEY:", i)
				return false
			end
		elseif typeof(v) == "buffer" then
			return buffersEqual(v, b[i])
		elseif v ~= b[i] then
			print("NOT EQUAL AT (A2)", "B:", b[i], "A:", v, "KEY:", i)
			return false
		end
	end
	for i, v in b do
		if typeof(v) == "table" then
			if (not a[i]) or (not tablesEqual(v, a[i])) then
				print("NOT EQUAL AT (B1)", "A:", a[i], "B:", v, "KEY:", i)
				return false
			end
		elseif typeof(v) == "buffer" then
			return buffersEqual(v, a[i])
		elseif v ~= a[i] then
			print("NOT EQUAL AT (B2)", "A:", a[i], "B:", v, "KEY:", i)
			return false
		end
	end
	return true
end

local function equals(a, b): boolean
	if typeof(a) ~= typeof(b) then
		return false
	elseif typeof(a) == "table" then
		return tablesEqual(a, b)
	elseif typeof(a) == "buffer" then
		return buffersEqual(a, b)
	else
		return a == b
	end
end

local function searchFor(tree, query: SearchForQuery)
	local atData = false
	for i, branch in tree._flatBranches do
		if not atData then
			atData = branch.ISROOT
			if not atData then
				continue
			end
		end
		if
			branch[1] == query.key
			and (query.value == nil or branch[2] == query.value)
			and (if query.isContainer then typeof(branch[2]) == "userdata" else true)
		then
			return i
		end
	end
end

local function runOperation(tree, operation: Operation)
	if operation.type == "delete" then
		tree:_deleteBranch({
			index = searchFor(tree, operation.searchFor),
			onlyChildren = operation.onlyChildren,
			pushAction = not operation.onlyChildren,
		})
	elseif operation.type == "insertAfter" then
		local index = searchFor(tree, operation.searchFor)
		tree:_digExpand(index)
		tree:_tryInsertAfter({
			index = index,
			key = operation.key,
			value = { value = operation.value, isArray = operation.isArray },
			pushAction = true,
		})
	elseif operation.type == "insertInto" then
		local index = searchFor(tree, operation.searchFor)
		tree:_digExpand(index)
		tree:_tryInsertInto({
			index = index,
			key = operation.key,
			value = { value = operation.value, isArray = operation.isArray },
			pushAction = true,
		})
	elseif operation.type == "move" then
		local moveIndex = searchFor(tree, operation.move)
		local beforeIndex = searchFor(tree, operation.before)
		tree:_digExpand(moveIndex)
		tree:_moveArrayElement({
			branchIndex = moveIndex,
			branchVisibleIndex = table.find(tree._visibleIndexes, moveIndex),
			moveBeforeIndex = beforeIndex,
			moveBeforeVisibleIndex = table.find(tree._visibleIndexes, beforeIndex),
			pushAction = true,
		})
	elseif operation.type == "moveEnd" then
		local moveIndex = searchFor(tree, operation.move)
		tree:_digExpand(moveIndex)
		tree:_moveArrayElementToEnd({
			branchIndex = moveIndex,
			branchVisibleIndex = table.find(tree._visibleIndexes, moveIndex),
			pushAction = true,
		})
	elseif operation.type == "edit" then
		local index = searchFor(tree, operation.searchFor)
		tree:_digExpand(index)
		tree:_editValue({
			index = index,
			value = { value = operation.value, isArray = operation.isArray },
			pushAction = true,
		})
	end
end

local function testOutput(name: string, data, expected, operations: { Operation })
	local function aux(showKeyInfo, searchTerm)
		local name = `{name} showKeyInfo:{showKeyInfo} searchTerm:{searchTerm}`
		local viewer
		local passed = false
		local success = xpcall(function()
			local fake = script.Parent.Parent.UI.Assets.Views.EditKey.Container.Content:Clone()
			local keyInfo = table.clone(fakeKeyInfo)
			keyInfo.UserIds = fuzzUserIds()
			if typeof(data) == "table" then
				keyInfo.Metadata = data
			else
				keyInfo.Metadata = { data }
			end

			viewer = Tree.new(Theme.global, {}, fake, {
				rootName = "test",
				data = data,
				keyInfo = keyInfo,
				isTesting = true,
				showKeyInfo = showKeyInfo,
			})

			if searchTerm then
				viewer:setSearch(searchTerm)
			end

			for _, operation in operations do
				if typeof(operation) ~= "table" then
					continue
				end

				runOperation(viewer, operation)
			end

			local value = viewer:getValue().value
			local userIds, metadata = viewer:getKeyInfo()
			if not equals(expected, value) then
				warn(`{name} failed`)
				warn("got:", value)
				warn("expected:", expected)
				return
			end

			if showKeyInfo then
				if not tablesEqual(userIds, keyInfo.UserIds) then
					warn(`userIds {name} failed`)
					warn("got:", userIds)
					warn("expected:", expected)
					return
				end
				if not tablesEqual(metadata, keyInfo.Metadata) then
					warn(`metadata {name} failed`)
					warn("got:", metadata)
					warn("expected:", expected)
					return
				end
			else
				if not tablesEqual(userIds, {}) then
					warn(`userIds {name} failed`)
					warn("got:", userIds)
					warn("expected to be empty")
				end
				if not tablesEqual(metadata, {}) then
					warn(`metadata {name} failed`)
					warn("got:", metadata)
					warn("expected to be empty")
				end
			end

			passed = true
		end, function(err)
			warn(`{name} errored. Show Key Info: {showKeyInfo}`, err, debug.traceback(nil, 2))
		end)

		if not success then
			warn("value:", data)
			warn("dump:", viewer:_dump())
		elseif passed and #operations == 1 and not operations.skipUndoRedo then
			viewer:undo()
			local undoed = viewer:getValue().value
			if not equals(undoed, data) then
				warn({ `{name} Undo failed` })
				warn("value:", undoed)
				warn("expected:", data)
				return
			end

			viewer:redo()
			local redoed = viewer:getValue().value
			if not equals(redoed, expected) then
				warn({ `{name} Redo failed` })
				warn("value:", redoed)
				warn("expected:", redoed)
				return
			end
		end
	end

	aux(true, nil)
	aux(false, nil)

	aux(true, "test")
	aux(false, "test")

	aux(true, "..................")
	aux(false, "..................")
end

-- Tests

testOutput("Test Preserves 1", testTree1, testTree1, {})
testOutput("Test Preserves 2", testTree2, testTree2, {})
testOutput("Test Preserves 3", testTree3, testTree3, {})
testOutput("Test Preserves 4", testTree4, testTree4, {})
testOutput("Test Preserves 5", testTree5, testTree5, {})
testOutput("Test Preserves 5", testTree6, testTree6, {})

local randomNumber = math.random()
testOutput("Test Preserves String", "test", "test", {})
testOutput("Test Preserves Empty", {}, {}, {})
testOutput("Test Preserves Number", randomNumber, randomNumber, {})
testOutput("Test Preserves Bool", false, false, {})
testOutput("Test Preserves Nil", nil, nil, {})
testOutput("Test Preserves Number", 1e+123, 1e+123, {})
testOutput("Test Preserves Buffer", buffer.fromstring("hello\0 world"), buffer.fromstring("hello\0 world"), {})

for i = 1, FUZZ_TESTS do
	local json = fuzzJSON()
	testOutput(`Test Fuzz Preserves {i}`, json, json, {})
end

local fuzz = math.random()

testOutput("Test Insert After 1", testTree1, {
	hello = 5,
	taxi = 3,
	nested = {
		hello = "y aw3faw3 faw3f aw3 aw3 aw3 faw3 fw3 faw3 aw3 wa3 aw3 aw3f es",
		aeoae = "wasafw 3faw3 awf aw3 aw3 aw3 aw aw aw3 aw3 aw3 aw3 aw3 aw3 aw wa3 aw3 wa3 aw3tt 3asup",
		moreNEsted = {
			3,
			4,
			5,
			6,
			6,
			"slayy",
			{
				"wafawefawf awfawefawefawfeawefawfwaef awef awef aewf awef awefssup",
				43,
				{ "Uusfa wefawf waefewa fawfa weafwaef awef awef awfe aw3f awe waaw efus", 45, true, false },
			},
		},
		testplzwork = fuzz, -- SHOULD INSERT HERE
	},
	car = 34,
	tree = "wassa w3f aw3f aw3f aw3 aw3 aw3f aw wa3 aw3 aw wa3 aw3 aw3a w3fup",
	city = false,
	abc = true,
}, {
	{
		type = "insertAfter",
		searchFor = { key = "moreNEsted" },
		key = "testplzwork",
		value = fuzz,
	},
})

testOutput("Test Insert After 2", testTree1, {
	hello = 5,
	taxi = 3,
	nested = {
		hello = "y aw3faw3 faw3f aw3 aw3 aw3 faw3 fw3 faw3 aw3 wa3 aw3 aw3f es",
		aeoae = "wasafw 3faw3 awf aw3 aw3 aw3 aw aw aw3 aw3 aw3 aw3 aw3 aw3 aw wa3 aw3 wa3 aw3tt 3asup",
		moreNEsted = {
			3,
			4,
			5,
			6,
			6,
			"slayy",
			{
				"wafawefawf awfawefawefawfeawefawfwaef awef awef aewf awef awefssup",
				43,
				{ "Uusfa wefawf waefewa fawfa weafwaef awef awef awfe aw3f awe waaw efus", 45, true, false },
			},
		},
	},
	car = 34,
	tree = "wassa w3f aw3f aw3f aw3 aw3 aw3f aw wa3 aw3 aw wa3 aw3 aw3a w3fup",
	city = false,
	abc = true,
	testplzwork = fuzz, -- SHOULD INSERT HERE
}, {
	{
		type = "insertAfter",
		searchFor = { key = "abc" },
		key = "testplzwork",
		value = fuzz,
	},
})

testOutput("Test Insert After 3", {
	a = 1,
	b = {
		a1 = 2,
		b2 = 3,
		c3 = 4,
	},
}, {
	a = 1,
	b = {
		a1 = 2,
		b2 = 3,
		c3 = 4,
	},
	test = "worked",
}, {
	{
		type = "insertAfter",
		searchFor = { key = "b" },
		key = "test",
		value = "worked",
	},
})

testOutput("Test Insert After 3", {
	1,
	{
		2,
		3,
		4,
	},
}, {
	1,
	{
		2,
		3,
		4,
	},
	10, -- <-- INSERT HERE
}, {
	{
		type = "insertAfter",
		searchFor = { key = 2, isContainer = true },
		key = "Ykoaeksf",
		value = 10,
	},
})

testOutput("Test Insert After 4", {
	1,
	{
		2,
		3,
		4,
		{ { { { {} } } } },
	},
	6,
	7,
	8,
	9,
	10,
}, {
	1,
	{
		2,
		3,
		4,
		{ { { { {} } } } },
	},
	999, -- <-- INSERT HERE
	6,
	7,
	8,
	9,
	10,
}, {
	{
		type = "insertAfter",
		searchFor = { key = 2, isContainer = true },
		key = "Ykoaeksf",
		value = 999,
	},
})

testOutput("Test Insert After 5 (At End)", {
	1,
	{
		2,
		3,
		4,
		{ { { { {} } } } },
	},
	6,
	7,
	8,
	9,
	10,
}, {
	1,
	{
		2,
		3,
		4,
		{ { { { {} } } } },
	},
	6,
	7,
	8,
	9,
	10,
	999, -- <-- INSERT HERE
}, {
	{
		type = "insertAfter",
		searchFor = { key = 7 },
		key = "yayasdfokaksdf",
		value = 999,
	},
})

testOutput("Test Insert Multiple After", {
	1,
	{
		2,
		3,
		4,
		{ { { { {} } } } },
	},
	6,
	7,
	8,
	9,
	10,
}, {
	1,
	{
		2,
		3,
		4,
		{ { { { {} } } } },
	},
	6,
	7,
	8,
	9,
	10,
	testTree4, -- <-- INSERT HERE
}, {
	{
		type = "insertAfter",
		searchFor = { key = 7 },
		key = "yayasdfokaksdf",
		value = testTree4,
	},
})

testOutput("Test Insert Mutliple After 2", {
	a = 1,
	b = {
		a1 = 2,
		b2 = 3,
		c3 = 4,
	},
	c = 10,
}, {
	a = 1,
	b = {
		a1 = 2,
		b2 = 3,
		c3 = 4,
		test = testTree2, -- <-- INSERT HERE
	},
	c = 10,
}, {
	{
		type = "insertAfter",
		searchFor = { key = "c3" },
		key = "test",
		value = testTree2,
	},
})

testOutput("Test Insert Multiple After 3 (Empty)", { {} }, { {}, testTree2 }, {
	{
		type = "insertAfter",
		searchFor = { key = 1 },
		key = "testplzwork",
		value = testTree2,
	},
})

testOutput("Test Insert Multiple After 4 (Sandwich)", { {}, {} }, { {}, testTree2, {} }, {
	{
		type = "insertAfter",
		searchFor = { key = 1 },
		key = "testplzwork",
		value = testTree2,
	},
})

testOutput("Test Insert Multiple After 5 (Sandwich Keys)", { a = {}, c = {} }, { a = {}, b = testTree1, c = {} }, {
	{
		type = "insertAfter",
		searchFor = { key = "a" },
		key = "b",
		value = testTree1,
	},
})

testOutput("Test Insert Mutliple After 6 (Big Test)", {
	hello = 5,
	taxi = 3,
	nested = {
		hello = "y aw3faw3 faw3f aw3 aw3 aw3 faw3 fw3 faw3 aw3 wa3 aw3 aw3f es",
		aeoae = "wasafw 3faw3 awf aw3 aw3 aw3 aw aw aw3 aw3 aw3 aw3 aw3 aw3 aw wa3 aw3 wa3 aw3tt 3asup",
		moreNEsted = {
			hello = 5,
			taxi = 3,
			nested = {
				hello = "y aw3faw3 faw3f aw3 aw3 aw3 faw3 fw3 faw3 aw3 wa3 aw3 aw3f es",
				aeoae = "wasafw 3faw3 awf aw3 aw3 aw3 aw aw aw3 aw3 aw3 aw3 aw3 aw3 aw wa3 aw3 wa3 aw3tt 3asup",
				moreNEsted = {
					3,
					4,
					5,
					6,
					6,
					"slayy",
					{
						"wafawefawf awfawefawefawfeawefawfwaef awef awef aewf awef awefssup",
						43,
						{ "Uusfa wefawf waefewa fawfa weafwaef awef awef awfe aw3f awe waaw efus", 45, true, false },
					},
					{
						hello = 5,
						taxi = 3,
						nested = {
							hello = "y aw3faw3 faw3f aw3 aw3 aw3 faw3 fw3 faw3 aw3 wa3 aw3 aw3f es",
							aeoae = "wasafw 3faw3 awf aw3 aw3 aw3 aw aw aw3 aw3 aw3 aw3 aw3 aw3 aw wa3 aw3 wa3 aw3tt 3asup",
							moreNEsted = {
								3,
								4,
								5,
								6,
								6,
								"slayy",
								{
									"wafawefawf awfawefawefawfeawefawfwaef awef awef aewf awef awefssup",
									43,
									{
										"Uusfa wefawf waefewa fawfa weafwaef awef awef awfe aw3f awe waaw efus",
										45,
										true,
										false,
									},
								},
							},
						},
						car = 34,
						tree = "wassa w3f aw3f aw3f aw3 aw3 aw3f aw wa3 aw3 aw wa3 aw3 aw3a w3fup",
						city = false,
						abc = true,
					},
				},
			},
			APPLE = 34,
			tree = "wassa w3f aw3f aw3f aw3 aw3 aw3f aw wa3 aw3 aw wa3 aw3 aw3a w3fup",
			city = false,
			abc = true,
		},
	},
	car = 34,
	tree = "wassa w3f aw3f aw3f aw3 aw3 aw3f aw wa3 aw3 aw wa3 aw3 aw3a w3fup",
	city = false,
	abc = true,
}, {
	hello = 5,
	taxi = 3,
	nested = {
		hello = "y aw3faw3 faw3f aw3 aw3 aw3 faw3 fw3 faw3 aw3 wa3 aw3 aw3f es",
		aeoae = "wasafw 3faw3 awf aw3 aw3 aw3 aw aw aw3 aw3 aw3 aw3 aw3 aw3 aw wa3 aw3 wa3 aw3tt 3asup",
		moreNEsted = {
			hello = 5,
			taxi = 3,
			nested = {
				hello = "y aw3faw3 faw3f aw3 aw3 aw3 faw3 fw3 faw3 aw3 wa3 aw3 aw3f es",
				aeoae = "wasafw 3faw3 awf aw3 aw3 aw3 aw aw aw3 aw3 aw3 aw3 aw3 aw3 aw wa3 aw3 wa3 aw3tt 3asup",
				moreNEsted = {
					3,
					4,
					5,
					6,
					6,
					"slayy",
					{
						"wafawefawf awfawefawefawfeawefawfwaef awef awef aewf awef awefssup",
						43,
						{ "Uusfa wefawf waefewa fawfa weafwaef awef awef awfe aw3f awe waaw efus", 45, true, false },
					},
					{
						hello = 5,
						taxi = 3,
						nested = {
							hello = "y aw3faw3 faw3f aw3 aw3 aw3 faw3 fw3 faw3 aw3 wa3 aw3 aw3f es",
							aeoae = "wasafw 3faw3 awf aw3 aw3 aw3 aw aw aw3 aw3 aw3 aw3 aw3 aw3 aw wa3 aw3 wa3 aw3tt 3asup",
							moreNEsted = {
								3,
								4,
								5,
								6,
								6,
								"slayy",
								{
									"wafawefawf awfawefawefawfeawefawfwaef awef awef aewf awef awefssup",
									43,
									{
										"Uusfa wefawf waefewa fawfa weafwaef awef awef awfe aw3f awe waaw efus",
										45,
										true,
										false,
									},
								},
							},
						},
						car = 34,
						tree = "wassa w3f aw3f aw3f aw3 aw3 aw3f aw wa3 aw3 aw wa3 aw3 aw3a w3fup",
						city = false,
						abc = true,
					},
				},
			},
			APPLE = 34,
			PEAR = testTree2,
			TOMATO = testTree4,
			ONION = testTree3,
			tree = "wassa w3f aw3f aw3f aw3 aw3 aw3f aw wa3 aw3 aw wa3 aw3 aw3a w3fup",
			city = false,
			abc = true,
		},
	},
	car = 34,
	tree = "wassa w3f aw3f aw3f aw3 aw3 aw3f aw wa3 aw3 aw wa3 aw3 aw3a w3fup",
	city = false,
	abc = true,
}, {
	{
		type = "insertAfter",
		searchFor = { key = "APPLE" },
		key = "PEAR",
		value = testTree2,
	},
	{
		type = "insertAfter",
		searchFor = { key = "PEAR" },
		key = "TOMATO",
		value = testTree4,
	},
	{
		type = "insertAfter",
		searchFor = { key = "TOMATO" },
		key = "ONION",
		value = testTree3,
	},
})

testOutput("Test Insert Into 1", testTree1, {
	hello = 5,
	taxi = 3,
	nested = {
		hello = "y aw3faw3 faw3f aw3 aw3 aw3 faw3 fw3 faw3 aw3 wa3 aw3 aw3f es",
		aeoae = "wasafw 3faw3 awf aw3 aw3 aw3 aw aw aw3 aw3 aw3 aw3 aw3 aw3 aw wa3 aw3 wa3 aw3tt 3asup",
		moreNEsted = {
			3,
			4,
			5,
			6,
			6,
			"slayy",
			{
				"wafawefawf awfawefawefawfeawefawfwaef awef awef aewf awef awefssup",
				43,
				{ "Uusfa wefawf waefewa fawfa weafwaef awef awef awfe aw3f awe waaw efus", 45, true, false },
			},
		},
		testplzwork = fuzz, -- SHOULD INSERT HERE
	},
	car = 34,
	tree = "wassa w3f aw3f aw3f aw3 aw3 aw3f aw wa3 aw3 aw wa3 aw3 aw3a w3fup",
	city = false,
	abc = true,
}, {
	{
		type = "insertInto",
		searchFor = { key = "nested" },
		key = "testplzwork",
		value = fuzz,
	},
})

testOutput("Test Insert Into 2", testTree1, {
	hello = 5,
	taxi = 3,
	nested = {
		hello = "y aw3faw3 faw3f aw3 aw3 aw3 faw3 fw3 faw3 aw3 wa3 aw3 aw3f es",
		aeoae = "wasafw 3faw3 awf aw3 aw3 aw3 aw aw aw3 aw3 aw3 aw3 aw3 aw3 aw wa3 aw3 wa3 aw3tt 3asup",
		moreNEsted = {
			3,
			4,
			5,
			6,
			6,
			"slayy",
			{
				"wafawefawf awfawefawefawfeawefawfwaef awef awef aewf awef awefssup",
				43,
				{ "Uusfa wefawf waefewa fawfa weafwaef awef awef awfe aw3f awe waaw efus", 45, true, false },
			},
		},
	},
	testplzwork = fuzz, -- SHOULD INSERT HERE
	car = 34,
	tree = "wassa w3f aw3f aw3f aw3 aw3 aw3f aw wa3 aw3 aw wa3 aw3 aw3a w3fup",
	city = false,
	abc = true,
}, {
	{
		type = "insertInto",
		searchFor = { key = "Data" },
		key = "testplzwork",
		value = fuzz,
	},
})

testOutput("Test Insert Into 3", {
	1,
	2,
	3,
}, {
	0, -- <-- INSERT HERE
	1,
	2,
	3,
}, {
	{
		type = "insertInto",
		searchFor = { key = "Data" },
		key = "!@$!$!",
		value = 0,
	},
})

testOutput("Test Insert Into 4", {
	1,
	2,
	3,
	{ 4 },
}, {
	1,
	2,
	3,
	{ 0, 4 }, -- <-- INSERT HERE
}, {
	{
		type = "insertInto",
		searchFor = { key = 4, isContainer = true },
		key = "!@$!$!",
		value = 0,
	},
})

testOutput("Test Insert Into 5", {
	1,
	2,
	{
		hey = "stop",
		eating = {
			"my",
			"food",
		},
	},
	3,
}, {
	1,
	2,
	{
		["!@$!$!"] = 0, -- <-- INSERT HERE
		hey = "stop",
		eating = {
			"my",
			"food",
		},
	},
	3,
}, {
	{
		type = "insertInto",
		searchFor = { key = 3, isContainer = true },
		key = "!@$!$!",
		value = 0,
	},
})

testOutput("Test Insert Into 6 (Empty)", {}, { dog = 1 }, {
	{
		type = "insertInto",
		searchFor = { key = "Data" },
		key = "dog",
		value = 1,
	},
})

testOutput("Test Insert Multiple Into 1", {
	1,
	2,
	{
		hey = "stop",
		eating = {
			"my",
			"food",
		},
	},
	3,
}, {
	1,
	2,
	{
		["!@$!$!"] = { "this", "is", "an", "array" }, -- <-- INSERT HERE
		hey = "stop",
		eating = {
			"my",
			"food",
		},
	},
	3,
}, {
	{
		type = "insertInto",
		searchFor = { key = 3, isContainer = true },
		key = "!@$!$!",
		value = { "this", "is", "an", "array" },
		isArray = true,
	},
})

testOutput("Test Insert Multiple Into 2", {
	nested = {
		{ 1, 2, 3 },
		{ test = {} },
		{ 1, 2, 3 },
		{ 1, 2, 3 },
		{ 1, 2, 3 },
	},
}, {
	nested = {
		{ 1, 2, 3 },
		{ test = { hey = testTree2 } },
		{ 1, 2, 3 },
		{ 1, 2, 3 },
		{ 1, 2, 3 },
	},
}, {
	{
		type = "insertInto",
		searchFor = { key = "test" },
		key = "hey",
		value = testTree2,
	},
})

testOutput("Test Insert Multiple Into 3", {
	nested = {
		{ 1, 2, 3 },
		{ test = {} },
		{ 1, 2, 3 },
		{ 1, 2, 3 },
		{ 1, 2, 3 },
	},
}, {
	nested = {
		{ 1, 2, 3 },
		{ test = {} },
		{ 1, 2, 3 },
		{ testTree4, 1, 2, 3 },
		{ 1, 2, 3 },
	},
}, {
	{
		type = "insertInto",
		searchFor = { key = 4 },
		key = "hey",
		value = testTree4,
	},
})

testOutput("Test Insert Multiple Into 4", {
	hello = 5,
	taxi = 3,
	nested = {
		hello = "y aw3faw3 faw3f aw3 aw3 aw3 faw3 fw3 faw3 aw3 wa3 aw3 aw3f es",
		aeoae = "wasafw 3faw3 awf aw3 aw3 aw3 aw aw aw3 aw3 aw3 aw3 aw3 aw3 aw wa3 aw3 wa3 aw3tt 3asup",
		moreNEsted = {
			hello = 5,
			taxi = 3,
			nested = {
				hello = "y aw3faw3 faw3f aw3 aw3 aw3 faw3 fw3 faw3 aw3 wa3 aw3 aw3f es",
				aeoae = "wasafw 3faw3 awf aw3 aw3 aw3 aw aw aw3 aw3 aw3 aw3 aw3 aw3 aw wa3 aw3 wa3 aw3tt 3asup",
				moreNEsted = {
					3,
					4,
					5,
					6,
					6,
					"slayy",
					{
						"wafawefawf awfawefawefawfeawefawfwaef awef awef aewf awef awefssup",
						43,
						{ "Uusfa wefawf waefewa fawfa weafwaef awef awef awfe aw3f awe waaw efus", 45, true, false },
					},
					{
						hello = 5,
						taxi = 3,
						nested = {
							hello = "y aw3faw3 faw3f aw3 aw3 aw3 faw3 fw3 faw3 aw3 wa3 aw3 aw3f es",
							aeoae = "wasafw 3faw3 awf aw3 aw3 aw3 aw aw aw3 aw3 aw3 aw3 aw3 aw3 aw wa3 aw3 wa3 aw3tt 3asup",
							moreNEsted = {
								3,
								4,
								5,
								6,
								6,
								"slayy",
								{
									"wafawefawf awfawefawefawfeawefawfwaef awef awef aewf awef awefssup",
									43,
									{
										"Uusfa wefawf waefewa fawfa weafwaef awef awef awfe aw3f awe waaw efus",
										45,
										true,
										false,
									},
								},
							},
						},
						car = 34,
						tree = "wassa w3f aw3f aw3f aw3 aw3 aw3f aw wa3 aw3 aw wa3 aw3 aw3a w3fup",
						city = false,
						abc = true,
						yay = {},
					},
				},
			},
			car = 34,
			tree = "wassa w3f aw3f aw3f aw3 aw3 aw3f aw wa3 aw3 aw wa3 aw3 aw3a w3fup",
			city = false,
			abc = true,
		},
	},
	car = 34,
	tree = "wassa w3f aw3f aw3f aw3 aw3 aw3f aw wa3 aw3 aw wa3 aw3 aw3a w3fup",
	city = false,
	abc = true,
}, {
	hello = 5,
	taxi = 3,
	nested = {
		hello = "y aw3faw3 faw3f aw3 aw3 aw3 faw3 fw3 faw3 aw3 wa3 aw3 aw3f es",
		aeoae = "wasafw 3faw3 awf aw3 aw3 aw3 aw aw aw3 aw3 aw3 aw3 aw3 aw3 aw wa3 aw3 wa3 aw3tt 3asup",
		moreNEsted = {
			hello = 5,
			taxi = 3,
			nested = {
				hello = "y aw3faw3 faw3f aw3 aw3 aw3 faw3 fw3 faw3 aw3 wa3 aw3 aw3f es",
				aeoae = "wasafw 3faw3 awf aw3 aw3 aw3 aw aw aw3 aw3 aw3 aw3 aw3 aw3 aw wa3 aw3 wa3 aw3tt 3asup",
				moreNEsted = {
					3,
					4,
					5,
					6,
					6,
					"slayy",
					{
						"wafawefawf awfawefawefawfeawefawfwaef awef awef aewf awef awefssup",
						43,
						{ "Uusfa wefawf waefewa fawfa weafwaef awef awef awfe aw3f awe waaw efus", 45, true, false },
					},
					{
						hello = 5,
						taxi = 3,
						nested = {
							hello = "y aw3faw3 faw3f aw3 aw3 aw3 faw3 fw3 faw3 aw3 wa3 aw3 aw3f es",
							aeoae = "wasafw 3faw3 awf aw3 aw3 aw3 aw aw aw3 aw3 aw3 aw3 aw3 aw3 aw wa3 aw3 wa3 aw3tt 3asup",
							moreNEsted = {
								3,
								4,
								5,
								6,
								6,
								"slayy",
								{
									"wafawefawf awfawefawefawfeawefawfwaef awef awef aewf awef awefssup",
									43,
									{
										"Uusfa wefawf waefewa fawfa weafwaef awef awef awfe aw3f awe waaw efus",
										45,
										true,
										false,
									},
								},
							},
						},
						car = 34,
						tree = "wassa w3f aw3f aw3f aw3 aw3 aw3f aw wa3 aw3 aw wa3 aw3 aw3a w3fup",
						city = false,
						abc = true,
						yay = { rah = testTree2 },
					},
				},
			},
			car = 34,
			tree = "wassa w3f aw3f aw3f aw3 aw3 aw3f aw wa3 aw3 aw wa3 aw3 aw3a w3fup",
			city = false,
			abc = true,
		},
	},
	car = 34,
	tree = "wassa w3f aw3f aw3f aw3 aw3 aw3f aw wa3 aw3 aw wa3 aw3 aw3a w3fup",
	city = false,
	abc = true,
}, {
	{
		type = "insertInto",
		searchFor = { key = "yay" },
		key = "rah",
		value = testTree2,
	},
})

testOutput("Test Insert Multiple Into 5 (Empty)", {}, {
	yes = testTree5,
}, {
	{
		type = "insertInto",
		searchFor = { key = "Data" },
		key = "yes",
		value = testTree5,
	},
})

--[[testOutput("Test Delete 1", testTree1, nil, {
	{
		type = "delete",
		searchFor = { key = "Data" },
	},
})]]

testOutput("Test Delete 2", testTree3, {}, {
	skipUndoRedo = true,
	{
		type = "delete",
		searchFor = { key = "Data" },
		onlyChildren = true,
	},
})

testOutput("Test Delete 3", testTree1, {
	hello = 5,
	taxi = 3,
	-- DELETED HERE
	car = 34,
	tree = "wassa w3f aw3f aw3f aw3 aw3 aw3f aw wa3 aw3 aw wa3 aw3 aw3a w3fup",
	city = false,
	abc = true,
}, {
	{
		type = "delete",
		searchFor = { key = "nested" },
		onlyChildren = false,
	},
})

testOutput("Test Delete 4", testTree1, {
	hello = 5,
	taxi = 3,
	nested = {},
	car = 34,
	tree = "wassa w3f aw3f aw3f aw3 aw3 aw3f aw wa3 aw3 aw wa3 aw3 aw3a w3fup",
	city = false,
	abc = true,
}, {
	skipUndoRedo = true,
	{
		type = "delete",
		searchFor = { key = "nested" },
		onlyChildren = true,
	},
})

testOutput("Test Delete 5", testTree1, {
	hello = 5,
	taxi = 3,
	nested = {
		hello = "y aw3faw3 faw3f aw3 aw3 aw3 faw3 fw3 faw3 aw3 wa3 aw3 aw3f es",
		aeoae = "wasafw 3faw3 awf aw3 aw3 aw3 aw aw aw3 aw3 aw3 aw3 aw3 aw3 aw wa3 aw3 wa3 aw3tt 3asup",
		moreNEsted = {
			3,
			4,
			5,
			6,
			"slayy",
			{
				"wafawefawf awfawefawefawfeawefawfwaef awef awef aewf awef awefssup",
				43,
				{ "Uusfa wefawf waefewa fawfa weafwaef awef awef awfe aw3f awe waaw efus", 45, true, false },
			},
		},
	},
	car = 34,
	tree = "wassa w3f aw3f aw3f aw3 aw3 aw3f aw wa3 aw3 aw wa3 aw3 aw3a w3fup",
	city = false,
	abc = true,
}, {
	{
		type = "delete",
		searchFor = { key = 4 },
		onlyChildren = false,
	},
})

testOutput("Test Delete 6", testTree1, {
	hello = 5,
	taxi = 3,
	nested = {
		hello = "y aw3faw3 faw3f aw3 aw3 aw3 faw3 fw3 faw3 aw3 wa3 aw3 aw3f es",
		aeoae = "wasafw 3faw3 awf aw3 aw3 aw3 aw aw aw3 aw3 aw3 aw3 aw3 aw3 aw wa3 aw3 wa3 aw3tt 3asup",
		moreNEsted = {
			3,
			4,
			5,
			6,
			6,
			"slayy",
			{},
		},
	},
	car = 34,
	tree = "wassa w3f aw3f aw3f aw3 aw3 aw3f aw wa3 aw3 aw wa3 aw3 aw3a w3fup",
	city = false,
	abc = true,
}, {
	skipUndoRedo = true,
	{
		type = "delete",
		searchFor = { key = 7 },
		onlyChildren = true,
	},
})

testOutput("Test Delete 7", testTree1, {
	hello = 5,
	taxi = 3,
	nested = {
		hello = "y aw3faw3 faw3f aw3 aw3 aw3 faw3 fw3 faw3 aw3 wa3 aw3 aw3f es",
		aeoae = "wasafw 3faw3 awf aw3 aw3 aw3 aw aw aw3 aw3 aw3 aw3 aw3 aw3 aw wa3 aw3 wa3 aw3tt 3asup",
		moreNEsted = {
			3,
			4,
			5,
			6,
			6,
			"slayy",
		},
	},
	car = 34,
	tree = "wassa w3f aw3f aw3f aw3 aw3 aw3f aw wa3 aw3 aw wa3 aw3 aw3a w3fup",
	city = false,
	abc = true,
}, {
	{
		type = "delete",
		searchFor = { key = 7 },
		onlyChildren = false,
	},
})

testOutput("Test Move 1", testTree1, {
	hello = 5,
	taxi = 3,
	nested = {
		hello = "y aw3faw3 faw3f aw3 aw3 aw3 faw3 fw3 faw3 aw3 wa3 aw3 aw3f es",
		aeoae = "wasafw 3faw3 awf aw3 aw3 aw3 aw aw aw3 aw3 aw3 aw3 aw3 aw3 aw wa3 aw3 wa3 aw3tt 3asup",
		moreNEsted = {
			{
				"wafawefawf awfawefawefawfeawefawfwaef awef awef aewf awef awefssup",
				43,
				{ "Uusfa wefawf waefewa fawfa weafwaef awef awef awfe aw3f awe waaw efus", 45, true, false },
			},
			3,
			4,
			5,
			6,
			6,
			"slayy",
		},
	},
	car = 34,
	tree = "wassa w3f aw3f aw3f aw3 aw3 aw3f aw wa3 aw3 aw wa3 aw3 aw3a w3fup",
	city = false,
	abc = true,
}, {
	{
		type = "move",
		move = { key = 7 },
		before = { key = 1 },
	},
})

testOutput("Test Move 2", testTree4, {
	{ 7, 8, 9 },
	{ 1, 2, 3 },
	{ 4, 5, 6 },
	{ 10, 11, 12 },
}, {
	{
		type = "move",
		move = { key = 3, isContainer = true },
		before = { key = 1, isContainer = true },
	},
})

testOutput("Test Move 3", testTree4, {
	{ 1, 2, 3 },
	{ 4, 5, 6 },
	{ 7, 8, 9 },
	{ 10, 12, 11 },
}, {
	{
		type = "move",
		move = { key = 3, value = 12 },
		before = { key = 2, value = 11 },
	},
})

testOutput("Test Move 4", testTree4, {
	{ 4, 5, 6 },
	{ 7, 8, 9 },
	{ 1, 2, 3 },
	{ 10, 11, 12 },
}, {
	{
		type = "move",
		move = { key = 1, isContainer = true },
		before = { key = 4, isContainer = true },
	},
})

testOutput("Test Move 5", testTree4, {
	{ 1, 2, 3 },
	{ 4, 5, 6 },
	{ 7, 8, 9 },
	{ 11, 10, 12 },
}, {
	{
		type = "move",
		move = { key = 1, value = 10 },
		before = { key = 3, value = 12 },
	},
})

testOutput("Test Move End", testTree4, {
	{ 4, 5, 6 },
	{ 7, 8, 9 },
	{ 10, 11, 12 },
	{ 1, 2, 3 },
}, {
	{
		type = "moveEnd",
		move = { key = 1, isContainer = true },
	},
})

testOutput("Test Move End 2", testTree4, {
	{ 1, 2, 3 },
	{ 4, 5, 6 },
	{ 7, 8, 9 },
	{ 11, 12, 10 },
}, {
	{
		type = "moveEnd",
		move = { key = 1, value = 10 },
	},
})

testOutput("Test Move End 3", testTree3, {
	1,
	2,
	3,
	nil,
	5,
	nil,
	nil,
	nil,
	nil,
	nil,
	6,
	4,
}, {
	{
		type = "moveEnd",
		move = { key = 5, value = 4 },
	},
})

testOutput("Test Move End 4", testTree6, {
	nested = {
		hello = "y aw3faw3 faw3f aw3 aw3 aw3 faw3 fw3 faw3 aw3 wa3 aw3 aw3f es",
		aeoae = "wasafw 3faw3 awf aw3 aw3 aw3 aw aw aw3 aw3 aw3 aw3 aw3 aw3 aw wa3 aw3 wa3 aw3tt 3asup",
		moreNEsted = {
			3,
			4,
			5,
			"slayy",
			6,
			6,
			{
				"wafawefawf awfawefawefawfeawefawfwaef awef awef aewf awef awefssup",
				43,
				{ "Uusfa wefawf waefewa fawfa weafwaef awef awef awfe aw3f awe waaw efus", 45, true, false },
			},
		},
	},
}, {
	{
		type = "moveEnd",
		move = { key = 5, isContainer = true },
	},
})

testOutput("Test Move End 5", testTree6, {
	nested = {
		hello = "y aw3faw3 faw3f aw3 aw3 aw3 faw3 fw3 faw3 aw3 wa3 aw3 aw3f es",
		aeoae = "wasafw 3faw3 awf aw3 aw3 aw3 aw aw aw3 aw3 aw3 aw3 aw3 aw3 aw wa3 aw3 wa3 aw3tt 3asup",
		moreNEsted = {
			4,
			5,
			"slayy",
			{
				"wafawefawf awfawefawefawfeawefawfwaef awef awef aewf awef awefssup",
				43,
				{ "Uusfa wefawf waefewa fawfa weafwaef awef awef awfe aw3f awe waaw efus", 45, true, false },
			},
			6,
			6,
			3,
		},
	},
}, {
	{
		type = "moveEnd",
		move = { key = 1, value = 3 },
	},
})

for i = 1, 3 do
	local fuzz1 = fuzzJSON(0)
	testOutput("Test Edit 1 Fuzz " .. i, testTree6, {
		nested = {
			hello = "y aw3faw3 faw3f aw3 aw3 aw3 faw3 fw3 faw3 aw3 wa3 aw3 aw3f es",
			aeoae = "wasafw 3faw3 awf aw3 aw3 aw3 aw aw aw3 aw3 aw3 aw3 aw3 aw3 aw wa3 aw3 wa3 aw3tt 3asup",
			moreNEsted = {
				fuzz1,
				4,
				5,
				"slayy",
				{
					"wafawefawf awfawefawefawfeawefawfwaef awef awef aewf awef awefssup",
					43,
					{ "Uusfa wefawf waefewa fawfa weafwaef awef awef awfe aw3f awe waaw efus", 45, true, false },
				},
				6,
				6,
			},
		},
	}, {
		{
			type = "edit",
			searchFor = { key = 1, value = 3 },
			value = fuzz1,
		},
	})
end
for i = 1, 3 do
	local fuzz1 = fuzzJSON()
	testOutput("Test Edit 2 Fuzz " .. i, testTree6, {
		nested = {
			hello = "y aw3faw3 faw3f aw3 aw3 aw3 faw3 fw3 faw3 aw3 wa3 aw3 aw3f es",
			aeoae = "wasafw 3faw3 awf aw3 aw3 aw3 aw aw aw3 aw3 aw3 aw3 aw3 aw3 aw wa3 aw3 wa3 aw3tt 3asup",
			moreNEsted = {
				fuzz1,
				4,
				5,
				"slayy",
				{
					"wafawefawf awfawefawefawfeawefawfwaef awef awef aewf awef awefssup",
					43,
					{ "Uusfa wefawf waefewa fawfa weafwaef awef awef awfe aw3f awe waaw efus", 45, true, false },
				},
				6,
				6,
			},
		},
	}, {
		{
			type = "edit",
			searchFor = { key = 1, value = 3 },
			value = fuzz1,
		},
	})
end

testOutput("Test Edit 3 Has Children", {
	thisTable = {
		hasChildren = 1,
		its = true,
		its2 = false,
	},
}, {
	thisTable = 3,
}, {
	{
		type = "edit",
		searchFor = { key = "thisTable" },
		value = 3,
	},
})

testOutput("Test Edit 4 Has Children Replace Many", {
	thisTable = {
		hasChildren = 1,
		its = true,
		its2 = false,
	},
}, {
	thisTable = testTree2,
}, {
	{
		type = "edit",
		searchFor = { key = "thisTable" },
		value = testTree2,
	},
})

testOutput("Test Edit 5 Empty", {
	{},
}, {
	5,
}, {
	{
		type = "edit",
		searchFor = { key = 1 },
		value = 5,
	},
})

testOutput("Test Edit 6 Empty Replace Many", {
	{},
}, {
	testTree2,
}, {
	{
		type = "edit",
		searchFor = { key = 1 },
		value = testTree2,
	},
})

testOutput("Test Edit 7 Root", 1234, {
	a = 1,
	b = 2,
}, {
	{
		type = "edit",
		searchFor = { key = "Data" },
		value = {
			a = 1,
			b = 2,
		},
	},
})
