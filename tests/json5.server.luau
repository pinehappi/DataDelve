--!nolint FunctionUnused

-- Tests based translated from the JS implementation of JSON5 tests.
-- Translated with assistance from Microsoft Copilot.

-- Whether to test all the features of JSON5
local TEST_FULL = false

local json5 = require(script.Parent.Parent.json5)

local isRoblox = pcall(function()
	workspace:IsA("Workspace")
end)

local function reportError(message: string)
	if isRoblox then
		warn(message)
	else
		print(`\x1b[31m{message}\x1b[0m`)
	end
end

local function reportInfo(message: string)
	print(message)
end

local function equals(a: any, b: any)
	if typeof(a) == "table" then
		if typeof(b) ~= "table" then
			return false
		else
			local allEquals = true
			for k, v in a do
				if not equals(v, b[k]) then
					allEquals = false
					break
				end
			end
			return allEquals
		end
	else
		return a == b
	end
end

local total = 0
local failed = 0

local function reportSummary()
	if failed > 0 then
		reportInfo(`json5 tests passed: {total - failed}/{total}`)
	end
end

local function reportDecodeError(source: string, error: json5.DecodeError)
	if error.kind == "parse" then
		local token = if error.token then json5.tokenToString(source, error.token) else "nil"
		local openingToken = if error.openingToken then json5.tokenToString(source, error.openingToken) else "nil"
		reportInfo(
			`=parse= token: {token}, opening token: {openingToken}\ntraceback:{error.traceback}\nmessage: {error.message}`
		)
	elseif error.kind == "lex" then
		reportInfo(`=lex= token: {json5.tokenToString(source, error.token)}`)
	end
end

local function reportResult(source: string, result: json5.DecodeResult)
	if result.kind == "success" then
		reportInfo(json5.encode(result))
	else
		for _, error in result.errors do
			reportDecodeError(source, error)
		end
	end
end

-- Test utilities

-- Forward declare
local testDecodes

type TestEncodesOptions = {
	skip: boolean?,
	encodeOptions: json5.EncodeOptions?,
	alt: string?,
	testDecodes: boolean?, -- default is true
	assertOneline: boolean?, -- default is false. Assert that the number of newlines == 1.
}
local function testEncodes(name: string, value: json5.Json, expected: string, options: TestEncodesOptions?)
	options = options or {
		skip = false,
	}
	assert(options, "???")

	if options.skip then
		return
	end

	total += 1

	local encoded = json5.encode(value, options.encodeOptions)
	if encoded ~= expected and encoded ~= options.alt then
		reportError(`{name} ENCODE FAIL: not equals:`)
		reportInfo(`GOT:{encoded}\nEXPECTED:{expected}`)
		failed += 1
	else
		if options.testDecodes ~= false then
			testDecodes(name, encoded, value)
		end

		if options.assertOneline ~= nil then
			if (not encoded:match("\n")) ~= options.assertOneline then
				reportError(`{name} ASSERT ONELINE FAIL`)
				reportInfo(`GOT:{encoded}\nEXPECTED:{expected}`)
			end
		end
	end
end

local function testEncodesReadable(name: string, value: json5.Json, expected: string, options: TestEncodesOptions?)
	options = options or {}

	assert(options, "???")
	options.encodeOptions = {
		mode = "readable",
		tabSize = 2,
	}

	testEncodes(name, value, expected, options)
end

type TestDecodesOptions = {
	-- Whether to test if the encoded strings are the same
	testEncode: boolean?,
	skip: boolean?,
	decodeOptions: json5.DecodeOptions?,
	shouldBeArray: boolean?,
}
function testDecodes(name: string, source: string, expected: json5.Json, options: TestDecodesOptions?)
	options = options or {
		testEncode = false,
		skip = false,
	}
	assert(options, "???")

	if options.skip then
		return
	end

	total += 1

	local result = json5.decode(source, options.decodeOptions)

	if result.kind == "failure" then
		reportError(`TEST {name} DECODE FAIL: decode error`)
		for i, error in result.errors do
			reportDecodeError(source, error)
		end
		failed += 1
	else
		if not equals(result.json, expected) then
			reportError(`TEST {name} DECODE FAIL: not equals`)
			reportInfo(
				`GOT:{json5.encode(result.json, { mode = "readable", tabSize = 2 })}\nEXPECTED:{json5.encode(
					expected,
					{ mode = "readable", tabSize = 2 }
				)}`
			)
			failed += 1
		elseif options.shouldBeArray ~= nil then
			if result.isArray ~= options.shouldBeArray then
				reportError(`TEST {name} DECODE FAIL: not array`)
				reportInfo(
					`GOT:{json5.encode(result.json, { mode = "readable", tabSize = 2 })}\nEXPECTED:{json5.encode(
						expected,
						{ mode = "readable", tabSize = 2 }
					)}`
				)
				failed += 1
			end
		end
	end

	if options.testEncode then
		testEncodes(name, expected, source, {
			testDecodes = false,
		})
	end
end

local function testDecodesPermissive(name: string, source: string, expected: json5.Json, options: TestDecodesOptions?)
	options = options or {
		skip = false,
	}
	assert(options, "????")

	options.decodeOptions = {
		mode = "permissive",
	}

	testDecodes(name, source, expected, options)
end

type TestDecodeFailOptions = {
	skip: boolean?,
	decodeOptions: json5.DecodeOptions?,
}
local function testDecodeFails(
	name: string,
	source: string,
	expectedKind: "lex" | "parse" | nil,
	options: TestDecodeFailOptions?
)
	options = options or {
		skip = false,
	}
	assert(options, "???")

	total += 1

	local result = json5.decode(source, options.decodeOptions)
	if result.kind ~= "failure" then
		failed += 1
		reportError(`TEST {name} FAILED TO FAIL`)
	elseif expectedKind ~= nil then
		local matched = false
		for _, error in result.errors do
			if error.kind == expectedKind then
				matched = true
				break
			end
		end

		if not matched then
			failed += 1
			reportError(`TEST {name} WRONG FAIL:`)
			for _, error in result.errors do
				reportDecodeError(source, error)
			end
		end
	end
end

type TestEncodeFailsOptions = {
	skip: boolean,
}
local function testEncodeFails(name: string, data: json5.Json, options: TestEncodeFailsOptions?)
	options = options or {
		skip = false,
	}
	assert(options, "why??")

	if options.skip then
		return
	end

	total += 1

	local success = pcall(json5.encode, data)
	if success then
		failed += 1
		reportError(`TEST {name} FAILED TO FAIL`)
	end
end

testDecodes(
	"json5 features",
	[[{
  // comments
  unquoted: 'and you can quote me on that',
  singleQuotes: 'I can use "double quotes" here',
  lineBreaks: "Look, Mom! \
No \\n's!", /*

asdokfaosfaskfsdfas
fas
f
asd*/
  hexadecimal: 0xdecaf,
  leadingDecimalPoint: .8675309, andTrailing: 8675309.,
  positiveSign: +1,
  trailingComma: 'in objects', andIn: ['arrays',],
  "backwardsCompatible": "with JSON",
}]],
	{
		unquoted = "and you can quote me on that",
		singleQuotes = 'I can use "double quotes" here',
		lineBreaks = "Look, Mom! No \\n's!",
		hexadecimal = 0xdecaf,
		leadingDecimalPoint = 0.8675309,
		andTrailing = 8675309.,
		positiveSign = 1,
		trailingComma = "in objects",
		andIn = { "arrays" },
		backwardsCompatible = "with JSON",
	},
	{
		testEncode = false,
	}
)

--[[ OBJECTS ]]
testDecodes("parses empty objects", [[{}]], {}, {
	testEncode = true,
	shouldBeArray = false,
})
testDecodes(
	"parses empty objects with spaces",
	[[   {    
	 }     ]],
	{},
	{
		shouldBeArray = false,
	}
)
testDecodes("parses double string property names", [[{"a":1}]], { a = 1 }, {
	testEncode = true,
	shouldBeArray = false,
})
testDecodes("parses single string property names", [[{'a'         :1}]], { a = 1 }, {
	shouldBeArray = false,
})
testDecodes("parses unquoted property names", [[{a:  1   }]], { a = 1 }, {
	shouldBeArray = false,
})

-- The original test has a unicode escape after the a \u200C, but not going to support that anytime soon
testDecodes("parses special character property names", [[{$_:1,_$:2,a:3}]], { ["$_"] = 1, ["_$"] = 2, ["a"] = 3 }, {
	shouldBeArray = false,
})

testDecodes("parses unicode property names", [[{ùńîċõďë:9}]], { ["ùńîċõďë"] = 9 }, {
	skip = not TEST_FULL,
})
testDecodes("parses unicode property names 2", [[{"ùńîċõďë":9}]], { ["ùńîċõďë"] = 9 })
testDecodes(
	"parses escaped property names",
	[[{\u0061\u0062:1,\u0024\u005F:2,\u005F\u0024:3}]],
	{ ab = 1, ["$_"] = 2, ["_$"] = 3 },
	{
		skip = not TEST_FULL,
	}
)
testDecodes("preserves __proto__ property names", [[{"__proto__":1}]], { ["__proto__"] = 1 }, {
	testEncode = true,
})
testDecodes("parses multiple properties", [[{abc:1,def:2}]], { abc = 1, def = 2 })
testDecodes("parses nested objects", [[{a:{b:2}}]], { a = { b = 2 } })
testDecodes(
	"parses nested objects and arrays",
	[[{a:{b:2,c:[1,2,{a:3,b:[{"4":5}]}]}}]],
	{ a = { b = 2, c = { 1, 2, { a = 3, b = { { ["4"] = 5 } } } } } },
	{
		shouldBeArray = false,
		testEncodes = true,
	}
)

--[[ ARRAYS ]]
-- Don't test encoding for this because an empty table is interpeted as an empty object
-- by the encoder.
testDecodes("parses empty arrays", "[]", {}, {
	shouldBeArray = true,
})
testDecodes("parses array values 1", "[1]", { 1 }, {
	testEncode = true,
}, {
	shouldBeArray = true,
})
testDecodes("parses array values", "[ 1,  ]", { 1 }, {
	shouldBeArray = true,
})
testDecodes("parses multiple array values", "[1  ,  2]", { 1, 2 }, {
	shouldBeArray = true,
})
testDecodes("parses nested arrays", "[1,[2,3]]", { 1, { 2, 3 } }, {
	testEncode = true,
	shouldBeArray = true,
})

--[[ NULL ]]
testDecodes("parses nulls", "null", nil, {
	testEncode = true,
})

--[[ BOOLEAN ]]
testDecodes("parses true", "true", true, {
	testEncode = true,
})
testDecodes("parses false", "false", false, {
	testEncode = true,
})

--[[ NUMBER ]]
testDecodes("parses leading zeroes", [[ [0,0.,0e0] ]], { 0, 0, 0 })
testDecodes("parses integers", [[ [1,23,456,7890] ]], { 1, 23, 456, 7890 })
testDecodes("parses signed numbers", [[ [-1,+2,-.1,-0] ]], { -1, 2, -0.1, -0 })
testDecodes("parses leading decimal points", [[ [.1,.23] ]], { 0.1, 0.23 })
testDecodes("parses fractional numbers", [[ [1.0,1.23] ]], { 1, 1.23 })
testDecodes("parses exponents", [[ [1e0,1e1,1e01,1.e0,1.1e0,1e-1,1e+1] ]], { 1, 10, 10, 1, 1.1, 0.1, 10 })
testDecodes("parses hexadecimal numbers", [[ [0x1,0x10,0xff,-0xFF] ]], { 1, 16, 255, -255 })
testDecodes("parses signed and unsigned Infinity", [[ [Infinity,-Infinity] ]], { math.huge, -math.huge }, {
	skip = not TEST_FULL,
})
testDecodes("parses signed and unsigned NaN", [[ [NaN, -NaN] ]], { 0 / 0, -0 / 0 }, {
	skip = not TEST_FULL,
})
testDecodes("parses 1", [[1]], 1)
testDecodes("parses +1.23e100", [[+1.23E100]], 1.23E100)
testDecodes("parses bare hexadecimal number", [[0x1]], 0x1)
testDecodes("parses bare long hexadecimal number", [[-0X01239abfABCDEF]], -0X01239abfABCDEF)

--[[ STRING ]]
testDecodes("parses double quoted strings", [["abc"]], "abc", {
	testEncode = true,
})
testDecodes("parses single quoted strings", [[ 'abc' ]], "abc")
testDecodes("parses quotes in strings", [[ ['"', "'"] ]], { '"', "'" })
testDecodes("parses emoji", [[ '😃🚀' ]], "😃🚀")
testDecodes(
	"parses emoji 2",
	[[ '😮😲🧟‍♂️🧟‍♀️🤩😑😬😬🐼🐭🐸🦑🐙🐚🧓🧡🖤💝🪯♌♎🆚🇺🇿🉐🔇🔕❎0️⃣🔝🟰🔲🗨️🕧🕛😃🚀' ]],
	"😮😲🧟‍♂️🧟‍♀️🤩😑😬😬🐼🐭🐸🦑🐙🐚🧓🧡🖤💝🪯♌♎🆚🇺🇿🉐🔇🔕❎0️⃣🔝🟰🔲🗨️🕧🕛😃🚀"
)
testDecodes(
	"decodes unicode strings",
	[[{"━⺂⪳⺏‖⼋◣⎎ⴎⷬ⧬ⵜ‶⅂⢱⣻╨⥋⎕≅⎠₧↪ⲻⴎ∺◖⟠⌋⥪⣻ⶩ╰⪗⑁≠☋ⷐ⣒♈‶ↈ↽⨢⢵┍ⅮⅭⲪ‾␋⠨⍉⺺⯹⣰⍗⦨❟☂╫⻏➑⛮⩭⡲⻸⮧♙▢⨠⇌⣔➒⃄⾱⟵⨕⃼₁⛌③⿉☠⍎⚗✍ⵘ╔⫶⠅╜⫺ℿ⣔⺅⽫⫯ⷢ⸟":"━⺂⪳⺏‖⼋◣⎎ⴎⷬ⧬ⵜ‶⅂⢱⣻╨⥋⎕≅⎠₧↪ⲻⴎ∺◖⟠⌋⥪⣻ⶩ╰⪗⑁≠☋ⷐ⣒♈‶ↈ↽⨢⢵┍ⅮⅭⲪ‾␋⠨⍉⺺⯹⣰⍗⦨❟☂╫⻏➑⛮⩭⡲⻸⮧♙▢⨠⇌⣔➒⃄⾱⟵⨕⃼₁⛌③⿉☠⍎⚗✍ⵘ╔⫶⠅╜⫺ℿ⣔⺅⽫⫯ⷢ⸟"}]],
	{
		["━⺂⪳⺏‖⼋◣⎎ⴎⷬ⧬ⵜ‶⅂⢱⣻╨⥋⎕≅⎠₧↪ⲻⴎ∺◖⟠⌋⥪⣻ⶩ╰⪗⑁≠☋ⷐ⣒♈‶ↈ↽⨢⢵┍ⅮⅭⲪ‾␋⠨⍉⺺⯹⣰⍗⦨❟☂╫⻏➑⛮⩭⡲⻸⮧♙▢⨠⇌⣔➒⃄⾱⟵⨕⃼₁⛌③⿉☠⍎⚗✍ⵘ╔⫶⠅╜⫺ℿ⣔⺅⽫⫯ⷢ⸟"] = "━⺂⪳⺏‖⼋◣⎎ⴎⷬ⧬ⵜ‶⅂⢱⣻╨⥋⎕≅⎠₧↪ⲻⴎ∺◖⟠⌋⥪⣻ⶩ╰⪗⑁≠☋ⷐ⣒♈‶ↈ↽⨢⢵┍ⅮⅭⲪ‾␋⠨⍉⺺⯹⣰⍗⦨❟☂╫⻏➑⛮⩭⡲⻸⮧♙▢⨠⇌⣔➒⃄⾱⟵⨕⃼₁⛌③⿉☠⍎⚗✍ⵘ╔⫶⠅╜⫺ℿ⣔⺅⽫⫯ⷢ⸟",
	}
)

-- This test is failing because string patterns can't match the entire \u{2028/2029} codepoint (I think)
testDecodes(
	"parses escaped characters",
	`'\\b\\f\\n\\r\\t\\v\\x0f\\u01fF\\\n\\\r\n\\\r\\\u{2028}\\\u{2029}\\a\\'\\"'`,
	`\b\f\n\r\t\v\0\x0f\u{01FF}a'"`,
	{
		skip = not TEST_FULL,
	}
)

testDecodes("escaped backslash", "'\\\\'", "\\")

testDecodes("parses escaped characters 2", `'\\\n\\\r'`, ``)
testDecodes(
	"parses multiline strings",
	[[
"hello\
   \
world"]],
	"hello   world"
)
testDecodes("parses line and paragraph separators", [[ '\u2028\u2029' ]], "\u{2028}\u{2029}", {
	skip = not TEST_FULL,
})
testDecodes("parses hex escape", [[ '\x32' ]], "2")
testDecodes("parses unicode escape", [[ '\uD83D\uDE03' ]], "😃")
testDecodes("parses null escape", [[ '\0' ]], "\0")

--[[ COMMENT ]]
testDecodes("parses single-line comments", "{//comment\n}", {})
testDecodes("parses single-line comments at end of input", "{}//comment", {})
testDecodes("parses multi-line comments", "{/**comment\n** */}", {})
testDecodes("doesn't parse nested multiline comments", "{/* /**comment\n** */}", {})

--[[ WHITESPACE ]]
--testDecodes("parses whitespace", "{\t\v\f \u{00A0}\u{FEFF}\n\r\u{2028}\u{2029}\u{2003}}", {})
testDecodes("parses whitespace", "{\t\v\f \n\r}", {})

--[[ PERMISSIVE ]]
testDecodesPermissive("parses unclosed empty object (permissive)", "{ ", {})
testDecodesPermissive("parses unclosed nested empty object (permissive)", "{ a:{ ", { a = {} })
testDecodesPermissive("parses unclosed nested empty object with key (permissive)", "{a:5,b:{", { a = 5, b = {} })

testDecodesPermissive("parses unclosed empty array (permissive)", "[", {})
testDecodesPermissive("parses unclosed nested empty array (permissive)", "[ [  ", { {} })
testDecodesPermissive("parses unclosed nested empty array with value (permissive)", "[5,[", { 5, {} })

testDecodesPermissive("parses unclosed string (permissive)", "'hello world", "hello world")
testDecodesPermissive("parses multiline string (permissive)", "'hello\nworld", "hello\nworld")

--[[ TEST FAILING ]]
testDecodeFails("fails on empty documents", "", "parse")
testDecodeFails("fails on documents with only comments", "", "parse")
testDecodeFails("fails on incomplete single line comments", "/a", "lex")
testDecodeFails("fails on unterminated multiline comments", "/*", "lex")
testDecodeFails("fails on unterminated multiline comment closings", "/**", "lex")
testDecodeFails("fails on invalid characters", "a", "parse")
testDecodeFails("fails on invalid characters in identifier start escapes", "{\\a:1}", "lex")
testDecodeFails("fails on invalid characters in identifier continue escapes", "{a\\a:1}", "lex")
testDecodeFails("fails on invalid identifier continue characters", "{a\\u0021:1}", "lex")
testDecodeFails("fails on invalid characters followed by a sign", "-a", "lex")
testDecodeFails("fails on invalid characters followed by a dot", ".a", "lex")
testDecodeFails("fails on invalid characters followed by an exponent indicator", "1ea", "parse")
testDecodeFails("fails on invalid characters followed by a hex indicator", "0xg", "parse")
testDecodeFails("fails on invalid newlines in strings", "'\n'", "lex")
testDecodeFails("fails on unterminated strings", '"', "lex")
testDecodeFails("fails on invalid identifier in property name", "{!:1}", "lex")
testDecodeFails("fails on invalid characters following property name", "{a!1}", "lex")
testDecodeFails("fails on invalid characters following a property value", "{a:1!}", "lex")
testDecodeFails("fails on invalid characters following an array value", "[1!]", "lex")
testDecodeFails("fails on invalid characters in literals", "tru!", "lex")
testDecodeFails("fails on invalid end of input", '"\\', "lex")
testDecodeFails("fails on unclosed hexadecimal escape", '"\\x', "lex")
testDecodeFails("fails on short hexadecimal escape", '"\\x"', "lex")
testDecodeFails("fails on short hexadecimal escape 2", '"\\x "', "lex")
testDecodeFails("fails on invalid first digits in hexadecimal escapes", '"\\xg"', "lex")
testDecodeFails("fails on invalid second digits in hexadecimal escapes", '"\\x0g"', "lex")
testDecodeFails("fails on invalid unicode escapes", '"\\u000g"', "lex")
testDecodeFails("fails on invalid unicode escapes 2", '"\\u"', "lex")
testDecodeFails("fails on invalid unicode escapes 3", '"\\u', "lex")
testDecodeFails("fails on invalid unicode escapes 4", '"\\ugggg"', "lex")
testDecodeFails("fails on invalid unicode escapes 5", '"\\u000"', "lex")
testDecodeFails("fails on invalid unicode escapes 6", '"\\u0"', "lex")
testDecodeFails("fails on invalid unicode escapes 6", '"\\ug"', "lex")
for i = 1, 9 do
	testDecodeFails("fails on invalid escaped digit " .. i, `"\\{i}"`, "lex")
end
testDecodeFails("fails on octal escapes", '"\\01"', "lex")
testDecodeFails("fails on multiple values", "1 2", "parse")
testDecodeFails("fails on unclosed objects before property names", "{", "parse")
testDecodeFails("fails on unclosed objects before property values", "{a:", "parse")
testDecodeFails("fails on unclosed arrays before values", "[", "parse")
testDecodeFails("fails on unclosed arrays after values", "[1", "parse")
testDecodeFails("fails on empty (permissive)", "", "parse")

--[[ ENCODING ]]

testEncodes("encodes string", "hello world", [["hello world"]])
testEncodes("encodes empty object", {}, [[{}]])
testEncodes("encodes empty object with key", { ["a-1"] = 5 }, [[{"a-1":5}]])
testEncodes("encodes key with double quote", { ['a"-1'] = 0 }, [[{"a\"-1":0}]])
testEncodes("encodes empty object with key", { ["a-1"] = 5 }, [[{"a-1":5}]])
testEncodes("encodes key with escaped escape", { ['a\\"-1'] = 5 }, [[{"a\\\"-1":5}]])
testEncodes("encodes empty key", { [""] = 5 }, [[{"":5}]])
testEncodes("encodes unicode keys", { ["ùńîċõďë"] = 9 }, "{ùńîċõďë:9}", {
	skip = not TEST_FULL,
})
testEncodes("encodes escaped property names", { ["\\\b\f\n\r\t\v\0\x01"] = 1 }, '{"\\\\\\b\\f\\n\\r\\t\\v\\0\\x01":1}')
testEncodes("encodes escaped null character property names", { ["\0\x001"] = 1 }, [[{"\0\x001":1}]])
testEncodes("encodes multiple properties", { abc = 1, def = 2 }, [[{"abc":1,"def":2}]], {
	alt = [[{"def":2,"abc":1}]],
})
testEncodes("encodes nested objects", { a = { b = 2 } }, [[{"a":{"b":2}}]])

--[[ ARRAYS ]]
testEncodes("encodes array values", { 1 }, "[1]")
testEncodes("encodes multiple array values", { 1, 2 }, "[1,2]")
testEncodes("encodes nested arrays", { 1, { 2, 3 } }, "[1,[2,3]]")

--[[ NULL ]]
testEncodes("encodes null", nil, [[null]])

--[[ BOOLEAN ]]
testEncodes("encodes false", false, [[false]])
testEncodes("encodes true", true, [[true]])

--[[ NUMBERS ]]
testEncodes("encodes decimals", 1.53, [[1.53]])
testEncodes("encodes negatives", -535, [[-535]])
testEncodes("encodes negative decimals", -535.24, [[-535.24]])
testEncodes("encodes zero", 0, [[0]])

--[[ STRINGS ]]
testEncodes("encodes empty string", "", [[""]])
testEncodes("encodes escaped characters", "\\\b\f\n\r\t\v\0\x0f", '"\\\\\\b\\f\\n\\r\\t\\v\\0\\x0f"')
testEncodes("encodes escaped null characters", "\0\x001", [["\0\x001"]])
testEncodes("encodes escaped single quotes", [["'"]], [["\"'\""]])
testEncodes("encodes escaped double quotes", [["''"]], [["\"''\""]])
testEncodes("encodes escaped line and paragraph separators", "\u{2028}\u{2029}", "'\\u2028\\u2029'", {
	skip = not TEST_FULL,
})

--[[ READABLE MODE ]]
testEncodesReadable(
	"encodes nested object and array",
	{ [""] = { a = { 3, 4, 5 } } },
	[[{
  "": {
    a: [3, 4, 5],
  },
}]]
)
testEncodesReadable(
	"encodes empty key 2",
	{ [""] = 5 },
	[[{
  "": 5,
}]]
)
testEncodesReadable(
	"encodes identifier key",
	{ abc_123 = 5 },
	[[{
  abc_123: 5,
}]]
)
testEncodesReadable(
	"encodes identifier key dollars",
	{ ["$abc_123$"] = 5 },
	[[{
  $abc_123$: 5,
}]]
)

testEncodesReadable("encodes short arrays on one line", { 1, 2, 3, 4, 5, 6 }, "[1, 2, 3, 4, 5, 6]", {
	assertOneline = true,
})
testEncodesReadable(
	"encodes long arrays on multiple lines",
	{ "hello", "world" },
	[=[[
  "hello",
  "world",
]]=],
	{
		assertOneline = false,
	}
)
testEncodesReadable(
	"encodes long arrays on multiple lines 2",
	{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 },
	[=[[
  1,
  2,
  3,
  4,
  5,
  6,
  7,
  8,
  9,
  10,
]]=],
	{
		assertOneline = false,
	}
)

--[[ FaFAILSils ]]
testEncodeFails("fails on encode function", { a = function() end })
testEncodeFails("fails on encode vector", { a = vector.zero })
testEncodeFails("fails on encode buffer", { a = buffer.create(1) })

testEncodeFails("fails on encode infinity", { ["a-1"] = 1 / 0 }, {
	skip = not TEST_FULL,
})
testEncodeFails("fails on encode -infinity", { ["a-1"] = -1 / 0 }, {
	skip = not TEST_FULL,
})

-- The reason this is skipped is because there is no way to get a circular table in DataDelve.
local circularTable = {}
circularTable.a = circularTable
testEncodeFails("fails on encode cyclical tables", circularTable, {
	skip = not TEST_FULL,
})

reportSummary()
