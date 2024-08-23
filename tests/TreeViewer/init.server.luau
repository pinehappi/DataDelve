-- Tests for tree viewer

local Theme = require(script.Parent.Parent.UI.Theme)
local Tree = require(script.Parent.Parent.UI.Viewers.Tree)

local fuzzUserIds = require(script.fuzzUserIds)

type SearchForQuery = { key: string | number, value: any?, isContainer: boolean }
type Operation = {
	type: "delete",
	searchFor: SearchForQuery,
	onlyChildren: boolean,
} | {
	type: "insertInto",
	searchFor: SearchForQuery,
	key: string?,
	value: number,
} | {
	type: "insertAfter",
	searchFor: SearchForQuery,
	key: string?,
	value: number,
} | {
	type: "move",
	move: SearchForQuery,
	before: SearchForQuery,
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

local function tablesEqual(a, b): boolean
	for i, v in a do
		if typeof(v) == "table" then
			if (not b[i]) or (not tablesEqual(v, b[i])) then
				return false
			end
		elseif v ~= b[i] then
			return false
		end
	end
	for i, v in b do
		if typeof(v) == "table" then
			if (not a[i]) or (not tablesEqual(v, a[i])) then
				return false
			end
		elseif v ~= a[i] then
			return false
		end
	end
	return true
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
		tree:_deleteBranch(searchFor(tree, operation.searchFor), { onlyChildren = operation.onlyChildren })
	elseif operation.type == "insertAfter" then
		tree:_tryInsertAfter(searchFor(tree, operation.searchFor), operation.key, operation.value)
	elseif operation.type == "insertInto" then
		tree:_tryInsertInto(searchFor(tree, operation.searchFor), operation.key, operation.value)
	elseif operation.type == "move" then
		local moveIndex = searchFor(tree, operation.move)
		local beforeIndex = searchFor(tree, operation.before)
		tree:_moveArrayElement(
			moveIndex,
			table.find(tree._visibleIndexes, moveIndex),
			beforeIndex,
			table.find(tree._visibleIndexes, beforeIndex)
		)
	end
end

local function testOutput(name: string, data, expected, operations: { Operation })
	local success, err = pcall(function()
		local fake = script.Parent.Parent.UI.Assets.Widget.EditKey.Content.ScrollingFrame:Clone()
		local keyInfo = table.clone(fakeKeyInfo)
		keyInfo.UserIds = fuzzUserIds()
		if typeof(data) == "table" then
			keyInfo.Metadata = data
		end

		local viewer = Tree.new(Theme.global, {}, fake, {
			rootName = "test",
			data = data,
			keyInfo = keyInfo,
		})
		for _, operation in operations do
			if operation.type == "move" then
				viewer:_expandAll(viewer._rootIndex) -- "move" doesn't work if the branch you moved is not visible
				break
			end
		end
		for _, operation in operations do
			runOperation(viewer, operation)
		end

		local value = viewer:getValue()
		local userIds, metadata = viewer:getKeyInfo()
		if typeof(expected) == "table" then
			if not tablesEqual(value, expected) then
				warn(`data {name} failed`)
				warn("got:", value)
				warn("expected:", expected)
				return
			end
		elseif value ~= expected then
			warn(`{name} failed`)
			warn("got:", value)
			warn("expected:", expected)
			return
		end

		if not tablesEqual(userIds, keyInfo.UserIds) then
			warn(`userIds {name} failed`)
			warn("got:", userIds)
			warn("expected:", expected)
			return
		end
		if not tablesEqual(userIds, keyInfo.UserIds) then
			warn(`metadata {name} failed`)
			warn("got:", userIds)
			warn("expected:", expected)
		end
	end)
	if not success then
		warn(`{name} errored`)
		warn("value:", data)
		warn("err:", err)
	end
end

testOutput("Test Preserves 1", testTree1, testTree1, {})
testOutput("Test Preserves 2", testTree2, testTree2, {})
testOutput("Test Preserves 3", testTree3, testTree3, {})
testOutput("Test Preserves 4", testTree4, testTree4, {})
testOutput("Test Preserves 5", testTree5, testTree5, {})

local randomNumber = math.random()
testOutput("Test Preserves String", "test", "test", {})
testOutput("Test Preserves Empty", {}, {}, {})
testOutput("Test Preserves Number", randomNumber, randomNumber, {})
testOutput("Test Preserves Bool", false, false, {})
testOutput("Test Preserves Nil", nil, nil, {})
testOutput("Test Preserves Number", 1e+123, 1e+123, {})

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

testOutput("Test Delete 1", testTree1, nil, {
	{
		type = "delete",
		searchFor = { key = "Data" },
	},
})

testOutput("Test Delete 2", testTree3, {}, {
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
		onlyChildren = false,
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
		onlyChildren = false,
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
		onlyChildren = false,
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
		onlyChildren = false,
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
		onlyChildren = false,
	},
})

fuzz = math.random()
