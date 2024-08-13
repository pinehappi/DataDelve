-- Tests for tree viewer

local Theme = require(script.Parent.Parent.UI.Theme)
local Tree = require(script.Parent.Parent.UI.Viewers.Tree)

local fuzzUserIds = require(script.fuzzUserIds)

type Operation =
	{
		type: "delete",
		index: number,
		onlyChildren: boolean,
	}
	| {
		type: "insertInto",
		index: number,
		key: string?,
		value: number,
	}
	| {
		type: "insertAfter",
		index: number,
		key: string?,
		value: number
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
			3,4,5,6,6,"slayy",{"wafawefawf awfawefawefawfeawefawfwaef awef awef aewf awef awefssup", 43, {"Uusfa wefawf waefewa fawfa weafwaef awef awef awfe aw3f awe waaw efus", 45, true, false}}
		}
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
					3,4,5,6,6,"slayy",{"wafawefawf awfawefawefawfeawefawfwaef awef awef aewf awef awefssup", 43, {"Uusfa wefawf waefewa fawfa weafwaef awef awef awfe aw3f awe waaw efus", 45, true, false}},
					{
						hello = 5,
						taxi = 3,
						nested = {
							hello = "y aw3faw3 faw3f aw3 aw3 aw3 faw3 fw3 faw3 aw3 wa3 aw3 aw3f es",
							aeoae = "wasafw 3faw3 awf aw3 aw3 aw3 aw aw aw3 aw3 aw3 aw3 aw3 aw3 aw wa3 aw3 wa3 aw3tt 3asup",
							moreNEsted = {
								3,4,5,6,6,"slayy",{"wafawefawf awfawefawefawfeawefawfwaef awef awef aewf awef awefssup", 43, {"Uusfa wefawf waefewa fawfa weafwaef awef awef awfe aw3f awe waaw efus", 45, true, false}}
							},
						},
						car = 34,
						tree = "wassa w3f aw3f aw3f aw3 aw3 aw3f aw wa3 aw3 aw wa3 aw3 aw3a w3fup",
						city = false,
						abc = true,
					}
				}
			},
			car = 34,
			tree = "wassa w3f aw3f aw3f aw3 aw3 aw3f aw wa3 aw3 aw wa3 aw3 aw3a w3fup",
			city = false,
			abc = true,
		}
	},
	car = 34,
	tree = "wassa w3f aw3f aw3f aw3 aw3 aw3f aw wa3 aw3 aw wa3 aw3 aw3a w3fup",
	city = false,
	abc = true,
}

local testTree3 = {
	1,2,3,nil,4,5, nil, nil, nil, nil, nil, 6
}

local testTree4 = {
	{1,2, 3},
	{4,5,6},
	{7,8,9},
	{10,11,12}
}

local testTree5 = {1/0}

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

local function runOperation(tree, operation: Operation)
	if operation.type == "delete" then
		tree:_deleteBranch(operation.index, { onlyChildren=operation.onlyChildren })
	elseif operation.type == "insertAfter" then
		tree:_tryInsertAfter(operation.index, operation.key, operation.value)
	elseif operation.type == "insertInto" then
		tree:_tryInsertInto(operation.index, operation.key, operation.value)
	end
end

local function testOutput(name: string, data, expected, operations: {Operation})
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
			keyInfo = keyInfo
		})
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


-- These tests will not work because key order is not preserved

--[[
local fuzz = math.random()

assert(testOutput(
	testTree1,
	{
		hello = 5,
		taxi = 3,
		nested = {
			hello = "y aw3faw3 faw3f aw3 aw3 aw3 faw3 fw3 faw3 aw3 wa3 aw3 aw3f es",
			aeoae = "wasafw 3faw3 awf aw3 aw3 aw3 aw aw aw3 aw3 aw3 aw3 aw3 aw3 aw wa3 aw3 wa3 aw3tt 3asup",
			moreNEsted = {
				3,4,5,6,6,"slayy",{"wafawefawf awfawefawefawfeawefawfwaef awef awef aewf awef awefssup", 43, {"Uusfa wefawf waefewa fawfa weafwaef awef awef awfe aw3f awe waaw efus", 45, true, false}}
			},
			test = fuzz, -- SHOULD INSERT HERE
		},
		car = 34,
		tree = "wassa w3f aw3f aw3f aw3 aw3 aw3f aw wa3 aw3 aw wa3 aw3 aw3a w3fup",
		city = false,
		abc = true,
	},
	{
		type = "insertAfter",
		index = 4,
		key = "test",
		value = fuzz
	}
	), "Test Insert After At End 1")
assert(testOutput(
	testTree1,
	{
		hello = 5,
		taxi = 3,
		nested = {
			hello = "y aw3faw3 faw3f aw3 aw3 aw3 faw3 fw3 faw3 aw3 wa3 aw3 aw3f es",
			aeoae = "wasafw 3faw3 awf aw3 aw3 aw3 aw aw aw3 aw3 aw3 aw3 aw3 aw3 aw wa3 aw3 wa3 aw3tt 3asup",
			moreNEsted = {
				3,4,5,6,6,"slayy",{"wafawefawf awfawefawefawfeawefawfwaef awef awef aewf awef awefssup", 43, {"Uusfa wefawf waefewa fawfa weafwaef awef awef awfe aw3f awe waaw efus", 45, true, false}}
			},
		},
		car = 34,
		tree = "wassa w3f aw3f aw3f aw3 aw3 aw3f aw wa3 aw3 aw wa3 aw3 aw3a w3fup",
		city = false,
		abc = true,
	},
	{
		type = "insertAfter",
		index = 7,
		key = "test",
		value = fuzz
	}
	), "Test Insert After At End 1")

fuzz = math.random()

]]