--!strict
--!native
--!optimize 2

-- == Public Interface  ==

export type TokenKind =
	| "blockComment"
	| "comma"
	| "doubleQuotedString"
	| "false"
	| "identifier"
	| "leftCurlyBracket"
	| "leftSquareBracket"
	| "lineComment"
	| "null"
	| "number"
	| "hexNumber"
	| "rightCurlyBracket"
	| "rightSquareBracket"
	| "singleQuotedString"
	| "escapeEscape"
	| "hexEscape"
	| "unicodeEscape"
	| "characterEscape"
	| "true"
	| "whitespace"
	| "colon"
	| "equals"

export type ErrorToken = {
	kind: "error",
	start: number,
	length: number,
	startLine: number,
	startColumn: number,

	message: string,
}
export type NormalToken = {
	kind: TokenKind,
	start: number,
	length: number,
	startLine: number,
	startColumn: number,
}
export type Token = ErrorToken | NormalToken

export type Object = { [string]: Json }
export type Array = { Json }
export type Json = | string | number | boolean | Object | Array | nil

-- "permissive" allows for omitting closing delimiters
export type DecodeMode = "strict" | "permissive"
export type DecodeOptions = {
	mode: DecodeMode,

	-- Default false. Whether or not to collect the tokens in the result.
	collectTokens: boolean?,
}

export type DecodeError =
	| { kind: "parse", message: string, token: Token?, openingToken: Token?, traceback: string }
	| { kind: "lex", message: string, token: ErrorToken }
export type DecodeResult = | {
	kind: "failure",
	errors: { DecodeError },
	tokens: { Token }?,
} | {
	kind: "success",
	json: Json,
	isArray: boolean,
	tokens: { Token }?,
}

export type EncodeOptions = CompactOptions | ReadableOptions
export type CompactOptions = {
	mode: "compact",
}
export type ReadableOptions = {
	mode: "readable",
	tabSize: number,
}

-- == Implementation ==

type ComplexPattern = {
	pattern: string,
	extra: string | ((string) -> (string?, string?)) | nil,
	error: string?, -- If the condition fails and this is not nil, change the token to an error with this message.
	condition: (string) -> boolean,
}

type RangePattern = {
	start: string,
	finish: string,
	include: { string },
	multiline: boolean,
}

type TokenPattern = | string | ComplexPattern | RangePattern

local tokenPatterns: { [string]: TokenPattern } = {
	whitespace = "^%s+",
	["true"] = "^true",
	["false"] = "^false",
	["null"] = "^null",
	leftCurlyBracket = "^%{",
	rightCurlyBracket = "^%}",
	leftSquareBracket = "^%[",
	rightSquareBracket = "^%]",
	identifier = "^[A-Za-z_%$][%w_%$]*",
	number = {
		pattern = "^[%+%-]?%d*%.?%d*",
		extra = "^[Ee]?[%+%-]?%d+",
		condition = function(got)
			return not not tonumber(got)
		end,
	},
	hexNumber = {
		pattern = "^[%-%+]?0[Xx][0-9a-fA-F]+",
		condition = function(got)
			return not not tonumber(got)
		end,
	},
	comma = ",",
	colon = ":",
	equals = "=",
	doubleQuotedString = {
		start = '^"',
		finish = '"',
		include = { "escapeEscape", "hexEscape", "unicodeEscape", "characterEscape" },
		multiline = false,
	},
	singleQuotedString = {
		start = "^'",
		finish = "'",
		include = { "escapeEscape", "hexEscape", "unicodeEscape", "characterEscape" },
		multiline = false,
	},
	escapeEscape = "\\\\",
	hexEscape = {
		pattern = "\\x[0-9A-Fa-f]?[0-9A-Fa-f]?",
		error = "invalid hexadecimal escape sequence",
		condition = function(got)
			return #got == 4 and (not not tonumber("0" .. got:sub(2)))
		end,
	},
	unicodeEscape = {
		pattern = "\\u[0-9A-Fa-f]?[0-9A-Fa-f]?[0-9A-Fa-f]?[0-9A-Fa-f]?",
		error = "invalid unicode escape sequence",
		condition = function(got)
			return #got == 6 and (not not tonumber("0x" .. got:sub(3)))
		end,
	},
	characterEscape = {
		pattern = "\\.",
		extra = function(got)
			if got == "\\\r" then
				return "^\n"
			elseif got == "\\0" then
				return "^[0-7]+", "octal escape sequences not supported"
			end
			return nil
		end,
		error = "invalid escape",
		condition = function(got)
			return got == "\\0" or not tonumber(got:sub(2, 2))
		end,
	},
	lineComment = "^//.*\n",
	blockComment = {
		start = "^/%*",
		finish = "%*/",
		include = {},
		multiline = true,
	},
}

local tokenPatternsOrder = {
	"whitespace",
	"true",
	"false",
	"null",
	"leftCurlyBracket",
	"rightCurlyBracket",
	"leftSquareBracket",
	"rightSquareBracket",
	"identifier",
	"hexNumber",
	"number",
	"comma",
	"colon",
	"equals",
	"doubleQuotedString",
	"singleQuotedString",
	"lineComment",
	"blockComment",
}

local function getTokenContent(source: string, token: Token): string
	return source:sub(token.start, token.start + token.length - 1)
end

local function tokenToString(source: string, token: Token): string
	local s = `[{token.kind}:{token.startLine}:{token.startColumn}] '{getTokenContent(source, token)}'`
	if token.kind == "error" then
		s ..= ` - {token.message}`
	end
	return s
end

local function printToken(source: string, token: Token)
	print(tokenToString(source, token))
end

local FINISH_SENTINEL: any = {}
local function iterLex(source: string, options: DecodeOptions?): () -> Token?
	options = options or {
		mode = "strict",
	}

	assert(options, "???")

	local isPermissive = (options.mode == "permissive")

	local lines = source:split("\n")
	local total = #source
	local totalLines = #lines
	local current = 1
	local currentLine = 1
	local currentColumn = 1

	local currentRange: RangePattern?
	local currentRangeName: string?
	local currentRangeStart: number?

	local queuedToken: Token? = nil
	local done = false

	local function matchPattern(
		patternName: string,
		line: string,
		atStart: boolean
	): (string?, number?, number?, string?)
		local pattern = tokenPatterns[patternName]
		if typeof(pattern) == "string" then
			local start, finish = line:find(pattern, currentColumn)
			if start and finish and (not atStart or start == currentColumn) then
				return patternName, start, finish
			end
		elseif (pattern :: any).pattern then
			local complexPattern = pattern :: ComplexPattern
			local start, finish = line:find(complexPattern.pattern, currentColumn)
			if start and finish and (not atStart or start == currentColumn) then
				if complexPattern.condition(line:sub(start, finish)) then
					local extra: any, extraErrorMessage: string? = complexPattern.extra, nil
					if typeof(extra) == "function" then
						extra, extraErrorMessage = extra(line:sub(start, finish))
					end

					if extra then
						local extraStart, extraFinish = line:find(extra, finish + 1)
						if extraStart and extraFinish then
							finish = extraFinish
							if extraErrorMessage then
								return "error", start, extraFinish, extraErrorMessage
							end
						end
					end

					return patternName, start, finish
				elseif complexPattern.error then
					return "error", start, finish, complexPattern.error
				end
			end
		elseif (pattern :: any).start then
			local rangePattern = pattern :: RangePattern
			local start, finish = line:find(rangePattern.start, currentColumn)
			if start and finish and (not atStart or start == currentColumn) then
				currentRange = rangePattern
				currentRangeName = patternName
				currentRangeStart = start

				return patternName, start, finish
			end
		end

		return nil
	end

	return function()
		if done then
			return nil
		end

		if
			(current > total)
			or (currentLine > totalLines)
			or (currentLine == totalLines and currentColumn > #lines[currentLine])
		then
			done = true
			if currentRange and not isPermissive then
				return {
					kind = "error",
					start = current,
					startLine = currentLine,
					startColumn = currentColumn,
					length = 0,
					message = `expected end of {currentRangeName}`,
				}
			else
				return nil
			end
		end

		local line = lines[currentLine] .. "\n"
		local token: Token
		if queuedToken then
			token = queuedToken
			queuedToken = nil
		elseif currentRange then
			assert(currentRangeName and currentRangeStart, "why")

			type FoundInfo = {
				name: string,
				start: number,
				finish: number,
				errorMessage: string?,
			}
			local found: { FoundInfo } = {}

			local finishStart, finishFinish = line:find(currentRange.finish, currentColumn)
			if finishStart and finishFinish then
				table.insert(found, { name = FINISH_SENTINEL, start = finishStart, finish = finishFinish })
			end

			for _, includedPatternName in currentRange.include do
				local name, start, finish, errorMessage = matchPattern(includedPatternName, line, false)
				if name then
					assert(start and finish, "howwww")
					table.insert(found, {
						name = name,
						start = start,
						finish = finish,
						errorMessage = errorMessage,
					})
				end
			end

			local firstFound: FoundInfo? = nil
			for _, info in found do
				if not firstFound then
					firstFound = info
				elseif info.start < firstFound.start then
					firstFound = info
				end
			end

			if not firstFound then
				token = {
					kind = currentRangeName :: TokenKind,
					start = current,
					startLine = currentLine,
					startColumn = currentColumn,
					length = #line - currentColumn + (if currentRange.multiline or isPermissive then 1 else 0),
				}

				if (not currentRange.multiline) and not isPermissive then
					queuedToken = {
						kind = "error",
						start = current + (#line - currentColumn),
						startLine = currentLine,
						startColumn = #line - 1,
						length = 1,
						message = `{currentRangeName} cannot span multiple lines`,
					}
				end
			else
				if firstFound.name == FINISH_SENTINEL then
					token = {
						kind = currentRangeName :: TokenKind,
						start = current,
						startLine = currentLine,
						startColumn = currentColumn,
						length = firstFound.finish - currentColumn + 1,
					}

					currentRange = nil
					currentRangeName = nil
					currentRangeStart = nil
				else
					if firstFound.start == currentColumn then
						token = {
							kind = firstFound.name :: TokenKind,
							start = current,
							startLine = currentLine,
							startColumn = currentColumn,
							length = firstFound.finish - currentColumn + 1,
							message = firstFound.errorMessage,
						}
					else
						token = {
							kind = currentRangeName :: TokenKind,
							start = current,
							startLine = currentLine,
							startColumn = currentColumn,
							length = firstFound.start - currentColumn,
						}

						queuedToken = {
							kind = firstFound.name :: TokenKind,
							start = current + (firstFound.start - currentColumn),
							startLine = currentLine,
							startColumn = firstFound.start,
							length = firstFound.finish - firstFound.start + 1,
							message = firstFound.errorMessage,
						}
					end
				end
			end
		else
			local tokenStart: number?, tokenFinish: number?
			local tokenPattern: string?
			local errorMessage: string?
			for _, patternName in tokenPatternsOrder do
				tokenPattern, tokenStart, tokenFinish, errorMessage = matchPattern(patternName, line, true)
				if tokenPattern then
					break
				end
			end

			if not tokenPattern then
				token = {
					kind = "error",
					start = current,
					startLine = currentLine,
					startColumn = currentColumn,
					length = 1,
					message = `unexpected character: {source:sub(current, current)}`,
				}
			else
				assert(tokenStart and tokenFinish, "why???")
				token = {
					kind = tokenPattern :: TokenKind,
					start = current,
					startLine = currentLine,
					startColumn = currentColumn,
					length = tokenFinish - tokenStart + 1,

					-- `nil` except when there is a complex pattern with its conditioned fail and it has an error message.
					message = errorMessage,
				}
			end
		end

		current += token.length
		currentColumn += token.length

		if currentColumn == #line + 1 then
			currentLine += 1
			currentColumn = 1
		end

		return token
	end
end

local function lex(source: string, options: DecodeOptions): { Token }
	options = options or {
		mode = "strict",
	}

	assert(options, "???")

	local tokens = table.create(32)
	for token in iterLex(source) do
		table.insert(tokens, token)
	end
	return tokens
end

local function decode(source: string, options: DecodeOptions?): DecodeResult
	options = options or {
		mode = "strict",
	}

	assert(options, "why")

	local isPermissive = (options.mode == "permissive")
	local firstValueIsArray = false
	local parsingFirstValue = true

	-- Only used if the `collectTokens` option is used.
	local tokens = table.create(8)

	local _nextToken = iterLex(source, options)
	local _latestToken: Token? = nil
	local openingTokens: { Token } = {}

	local NULL: any = newproxy()

	-- This is used for errors when `expectToken` fails
	local function pushOpeningToken(token: Token)
		table.insert(openingTokens, token)
	end
	local function popOpeningToken()
		table.remove(openingTokens)
	end

	local function wrappedError(message: string, wasExpectClosing: boolean?)
		error({ kind = "parse", message = message, traceback = debug.traceback(), wasExpectClosing = wasExpectClosing })
	end

	local function nextToken(dontError: "DONT_ERROR"?): Token?
		local last = _latestToken
		_latestToken = _nextToken()

		if options.collectTokens and _latestToken then
			table.insert(tokens, _latestToken)
		end

		if _latestToken and _latestToken.kind == "error" then
			if not dontError then
				error({ kind = "lex", token = _latestToken })
			end
		end

		return last
	end

	local function peekToken(): Token?
		return _latestToken
	end

	local function expectToken(kind: string, isClosing: "isClosing"?)
		if isClosing and isPermissive then
			local got = peekToken()
			if got and (got.kind ~= kind) then
				wrappedError(("expected %s, got %s"):format(kind, got.kind), not not isClosing)
			else
				nextToken()
			end
		else
			local got = nextToken()
			if not got then
				wrappedError(("expected %s"):format(kind), not not isClosing)
			elseif got.kind ~= kind then
				wrappedError(("expected %s, got %s"):format(kind, got.kind), not not isClosing)
			end
		end
	end

	local function skip()
		while true do
			local got = peekToken()
			if got and (got.kind == "whitespace" or got.kind == "lineComment" or got.kind == "blockComment") then
				nextToken()
			else
				break
			end
		end
	end

	local function string2(): string?
		skip()

		local got = peekToken()
		if got and (got.kind == "doubleQuotedString" or got.kind == "singleQuotedString") then
			local stringTokenKind = got.kind
			local tokens: { Token } = table.create(2)
			while true do
				local got2 = peekToken()
				if
					got2
					and (
						(got2.kind == stringTokenKind)
						or (got2.kind == "escapeEscape")
						or (got2.kind == "characterEscape")
						or (got2.kind == "hexEscape")
						or (got2.kind == "unicodeEscape")
					)
				then
					table.insert(tokens, nextToken() :: Token)
				else
					break
				end
			end

			local builder = table.create(#tokens)
			local i = 1
			while i <= #tokens do
				local token = tokens[i]

				if token.kind ~= stringTokenKind then
					-- It's an escape
					if token.kind == "escapeEscape" then
						table.insert(builder, "\\")
					elseif token.kind == "characterEscape" then
						local escaped = source:sub(token.start + 1, token.start + 1)
						local insert = escaped
						if escaped == "b" then
							insert = "\b"
						elseif escaped == "f" then
							insert = "\f"
						elseif escaped == "n" then
							insert = "\n"
						elseif escaped == "r" then
							insert = "\r"
						elseif escaped == "t" then
							insert = "\t"
						elseif escaped == "v" then
							insert = "\v"
						elseif escaped == "0" then
							insert = "\0"
							-- NOTE: no unicode support at the moment, so this path never gets reached
							--elseif escaped == "\u{2028}" or escaped == "\u{2029}" then
							--i += 1
							--continue
						elseif escaped == "\n" then
							i += 1
							continue
						elseif escaped == "\r" or escaped == "\r\n" then
							i += 1
							continue
						end
						table.insert(builder, insert)
					elseif token.kind == "hexEscape" then
						table.insert(
							builder,
							string.char(tonumber(getTokenContent(source, token):sub(3, 4), 16) :: number)
						)
					elseif token.kind == "unicodeEscape" then
						local numeric = getTokenContent(source, token):sub(3, 6)
						local value = tonumber(numeric, 16) :: number

						-- Surrogate pair
						if 0xD800 <= value and value <= 0xDBFF then
							local gotStringToken = tokens[i + 1]
							if gotStringToken and gotStringToken.kind == "unicodeEscape" then
								local numeric2 = getTokenContent(source, gotStringToken):sub(3, 6)
								local low = tonumber(numeric2, 16) :: number
								if 0xDC00 <= low and low <= 0xDFFF then
									local high = value
									local s = ((high - 0xD800) * 0x400) + (low - 0xDC00) + 0x10000
									table.insert(builder, utf8.char(s))

									i += 2
									continue
								end
							end
						end

						if not (value == 2028 or value == 2029) then
							table.insert(builder, utf8.char(value))
						end
					end
				elseif i == 1 then
					if token.length > 1 then
						-- Ignore the starting quote
						table.insert(builder, source:sub(token.start + 1, token.start + token.length - 1))
					end
				elseif i == #tokens then
					if token.length > 1 then
						-- Ignore the ending quote
						table.insert(builder, source:sub(token.start, token.start + token.length - 2))
					end
				else
					table.insert(builder, getTokenContent(source, token))
				end

				i += 1
			end

			return table.concat(builder, "")

			-- Permissive mode lets you use identifier as string
		elseif isPermissive and got and got.kind == "identifier" then
			nextToken()
			-- NOTE: hack to get string syntax highlighting
			if options.collectTokens then
				(got :: any).kind = "doubleQuotedString"
			end
			return getTokenContent(source, got)
		end
		return nil
	end

	local function number(): number?
		skip()

		local got = peekToken()
		if got and (got.kind == "number" or got.kind == "hexNumber") then
			nextToken()
			return tonumber(getTokenContent(source, got))
		end
		return nil
	end

	local function boolean(): boolean?
		skip()

		local got = peekToken()
		if got and got.kind == "true" then
			nextToken()
			return true
		elseif got and got.kind == "false" then
			nextToken()
			return false
		end

		return nil
	end

	-- Make sure to convert to `nil` when using
	local function null(): any?
		skip()

		local got = peekToken()
		if got and got.kind == "null" then
			nextToken()
			return NULL
		end

		return nil
	end

	local object: () -> Object?
	local array: () -> Array?

	-- Make sure to handle `NULL` properly
	local function value(): Json?
		local pass1 = number() or string2() or object() or array()
		parsingFirstValue = false

		if pass1 then
			return pass1
		else
			local b = boolean()
			if b ~= nil then
				return b
			else
				return null()
			end
		end
	end

	type Pair = {
		key: string,
		value: Json,
	}
	local function pair(): Pair?
		skip()

		local got = peekToken()
		local k: string?
		if got and got.kind == "identifier" then
			nextToken()
			k = getTokenContent(source, got)
		else
			k = string2()
		end

		if k then
			skip()

			if isPermissive then
				local expectedToken = peekToken()
				if (not expectedToken) or (expectedToken.kind ~= "colon" and expectedToken.kind ~= "equals") then
					if expectedToken then
						wrappedError(("expected colon, got %s"):format(expectedToken.kind))
					else
						wrappedError("expected colon")
					end
				else
					nextToken()
				end
			else
				expectToken("colon")
			end

			local v = value()
			if v == nil then
				wrappedError("expected value")
			end

			if v == NULL then
				v = nil
			end

			return { key = k, value = v }
		end

		return nil
	end

	function object()
		skip()

		local got = peekToken()
		if got and got.kind == "leftCurlyBracket" then
			nextToken()
			pushOpeningToken(got)

			local o = {}
			while true do
				local pair = pair()
				if pair then
					o[pair.key] = pair.value
				else
					break
				end

				skip()

				local got2 = peekToken()
				if not (got2 and got2.kind == "comma") then
					break
				end

				nextToken()
			end

			skip()
			expectToken("rightCurlyBracket", "isClosing")
			popOpeningToken()

			return o
		end

		return nil
	end

	function array()
		skip()

		local got = peekToken()
		if got and got.kind == "leftSquareBracket" then
			nextToken()
			pushOpeningToken(got)

			if parsingFirstValue then
				firstValueIsArray = true
			end

			local a = {}
			local i = 1
			while true do
				local v = value()
				if v == nil then
					break
				end

				if v == NULL then
					v = nil
				end

				a[i] = v

				skip()

				local got2 = peekToken()
				if not (got2 and got2.kind == "comma") then
					break
				end

				nextToken()

				i += 1
			end

			skip()
			expectToken("rightSquareBracket", "isClosing")
			popOpeningToken()

			return a
		end

		return nil
	end

	local result = nil
	local errors: any = {}
	local firstLoop = true
	repeat
		local expectedEnd = false
		local success, err = pcall(function()
			-- So you can peek the fisrt character
			if firstLoop then
				firstLoop = false
				nextToken()
			end

			result = value()

			if result == nil then
				wrappedError("expected value")
			end

			if result == NULL then
				result = nil
			end

			skip()

			expectedEnd = true
			if peekToken() then
				wrappedError("expected end")
			end
		end)

		if not success then
			if typeof(err) == "table" then
				if err.kind == "parse" then
					table.insert(errors, {
						kind = "parse",
						traceback = err.traceback,
						message = err.message,
						token = peekToken(),
						openingToken = if err.wasExpectClosing then openingTokens[#openingTokens] else nil,
					})
				else
					table.insert(errors, {
						kind = "lex",
						token = err.token,
					})
				end

				-- Find good spot to recover
				if not expectedEnd then
					openingTokens = {}
					while true do
						nextToken("DONT_ERROR")
						local got = peekToken()
						if
							not got
							or got.kind == "leftCurlyBracket"
							or got.kind == "rightCurlyBracket"
							or got.kind == "leftSquareBracket"
							or got.kind == "rightSquareBracket"
						then
							break
						elseif got.kind == "error" then
							table.insert(errors, {
								kind = "lex",
								token = got,
							})
						end
					end
				end
			else
				error(err)
			end
		end
	until peekToken() == nil

	if #errors == 0 then
		return {
			kind = "success",
			json = result,
			isArray = firstValueIsArray,
			tokens = if options.collectTokens then tokens else nil,
		}
	else
		return {
			kind = "failure",
			errors = errors,
			tokens = if options.collectTokens then tokens else nil,
		}
	end
end

local function encodeNumber(builder: { string }, number: number)
	table.insert(builder, tostring(number))
end

local function isAsciiDigit(code: number): boolean
	return 48 <= code and code <= 57
end

local function encodeString(builder: { string }, string: string)
	local escaped = string:gsub("\\", "\\\\")
	local b = buffer.fromstring(escaped)

	table.insert(builder, '"')
	for i = 0, buffer.len(b) - 1 do
		local got = buffer.readu8(b, i)
		if got < 32 then
			if got == 0 and ((i + 1 == buffer.len(b)) or (not isAsciiDigit(buffer.readu8(b, i + 1)))) then
				table.insert(builder, "\\0")
			elseif got == 8 then
				table.insert(builder, "\\b")
			elseif got == 9 then
				table.insert(builder, "\\t")
			elseif got == 10 then
				table.insert(builder, "\\n")
			elseif got == 11 then
				table.insert(builder, "\\v")
			elseif got == 12 then
				table.insert(builder, "\\f")
			elseif got == 13 then
				table.insert(builder, "\\r")
			else
				table.insert(builder, ("\\x%02x"):format(got))
			end
		elseif got == 34 then
			table.insert(builder, '\\"')
		else
			table.insert(builder, string.char(got))
		end
	end
	table.insert(builder, '"')
end

local encodeInternal: (builder: { string }, value: Json, depth: number, EncodeOptions) -> ()

local function tabs(depth: number, options: EncodeOptions)
	return string.rep(" ", depth * (options :: ReadableOptions).tabSize)
end

local function encodeObject(builder: { string }, object: Object, depth: number, options: EncodeOptions)
	if options.mode == "compact" then
		table.insert(builder, "{")

		local inserted = false
		for k, v in object do
			inserted = true
			encodeString(builder, k)
			table.insert(builder, ":")
			encodeInternal(builder, v, depth, options)
			table.insert(builder, ",")
		end

		-- Remove extraneous comma
		if inserted then
			table.remove(builder)
		end

		table.insert(builder, "}")
	elseif options.mode == "readable" then
		if next(object) == nil then
			table.insert(builder, "{}")
			return
		end

		table.insert(builder, "{\n")

		local keys = {}
		for k in object do
			table.insert(keys, k)
		end

		table.sort(keys)

		for _, k in keys do
			local v = object[k]
			table.insert(builder, tabs(depth + 1, options))
			if select(2, k:find(tokenPatterns.identifier :: string)) == #k then
				table.insert(builder, k)
			else
				encodeString(builder, k)
			end
			table.insert(builder, ": ")
			encodeInternal(builder, v, depth, options)
			table.insert(builder, ",\n")
		end

		table.insert(builder, tabs(depth, options))
		table.insert(builder, "}")
	end
end

local function encodeArray(builder: { string }, array: Array, depth: number, options: EncodeOptions)
	if options.mode == "compact" then
		table.insert(builder, "[")

		local inserted = false
		for _, v in array do
			inserted = true
			encodeInternal(builder, v, depth, options)
			table.insert(builder, ",")
		end

		-- Remove extraneous comma
		if inserted then
			table.remove(builder)
		end

		table.insert(builder, "]")
	elseif options.mode == "readable" then
		-- Handling "probably short" arrays. Make it all on one line
		if #array <= 8 then
			local probablyShort = true
			for _, v in array do
				if not (typeof(v) == "boolean" or typeof(v) == "number") then
					probablyShort = false
					break
				end
			end

			if probablyShort then
				table.insert(builder, "[")

				local inserted = false
				for _, v in array do
					inserted = true
					encodeInternal(builder, v, depth, options)
					table.insert(builder, ", ")
				end

				-- Remove extraneous comma
				if inserted then
					table.remove(builder)
				end

				table.insert(builder, "]")
				return
			end
		end

		-- Normal big arrays
		table.insert(builder, "[\n")

		for _, v in array do
			table.insert(builder, tabs(depth + 1, options))
			encodeInternal(builder, v, depth, options)
			table.insert(builder, ",\n")
		end

		table.insert(builder, tabs(depth, options))
		table.insert(builder, "]")
	end
end

function encodeInternal(builder: { string }, value: Json, depth: number, options: EncodeOptions)
	local valueAny = value :: any

	if typeof(valueAny) == "table" then
		if #valueAny == 0 then
			return encodeObject(builder, valueAny, depth + 1, options)
		else
			return encodeArray(builder, valueAny, depth + 1, options)
		end
	elseif typeof(valueAny) == "string" then
		return encodeString(builder, valueAny)
	elseif typeof(valueAny) == "number" then
		return encodeNumber(builder, valueAny)
	elseif valueAny == true then
		table.insert(builder, "true")
	elseif valueAny == false then
		table.insert(builder, "false")
	elseif valueAny == nil then
		table.insert(builder, "null")
	else
		error(`unexpected type {typeof(value)}`)
	end
end

local function encode(json: Json, options: EncodeOptions?): string
	local builder = table.create(128)

	encodeInternal(builder, json, -1, options or {
		mode = "compact",
	})

	return table.concat(builder, "")
end

return {
	iterLex = iterLex,
	lex = lex,

	decode = decode,
	encode = encode,

	getTokenContent = getTokenContent,

	-- Debug
	tokenToString = tokenToString,
	printToken = printToken,
}
