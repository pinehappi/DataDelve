-- Helper for JSON w/ buffers

-- Does "dumb" parsing of input strings.

local HttpService = game:GetService("HttpService")

local JSONHelper = {}

export type JSONType = "string" | "number" | "array" | "object" | "boolean" | "null" | "buffer"
export type JSONValue = string | number | { [string]: JSONValue } | { JSONValue } | boolean | buffer | nil

-- TODO: this will error if the source string cannot be converted to JSON, like if it had an incorrect encoding issue.
-- The only time this will pop up is with Import from JSON since these malformed strings cannot be stored in a DataStore.
function JSONHelper.escapeString(source: string): string
	return HttpService:JSONEncode(source)
	--[[return source
		:gsub("\\", "\\\\")
		:gsub("\n", "\\n")
		:gsub("\f", "\\f")
		:gsub("\b", "\\b")
		:gsub("\t", "\\t")
		:gsub("\"", "\\\"")]]
end

function JSONHelper.encode(value: any): string
	return HttpService:JSONEncode(value)
end

-- THIS IS NOT FOR PARSING JSON
-- It's for parsing user input when they type in a JSONValue in an input field
function JSONHelper.parseInputString(text: string): (JSONType, JSONValue)
	local trimmed = text:gsub("^%s+", ""):gsub("%s+$", "")
	local lowered = trimmed:lower()

	if trimmed:sub(1, 1) == '"' then
		if trimmed:sub(-1, -1) == '"' then
			return "string", trimmed:sub(2, -2)
		end
		return "string", trimmed:sub(2)
	elseif trimmed:sub(1, 1) == "'" then
		if trimmed:sub(-1, -1) == "'" then
			return "string", trimmed:sub(2, -2)
		end
		return "string", trimmed:sub(2)
	elseif lowered == "null" or lowered == "nil" then
		return "null", nil
	elseif lowered == "true" then
		return "boolean", true
	elseif lowered == "false" then
		return "boolean", false
	else
		local number = tonumber(trimmed)
		if number then
			return "number", number
		end

		local noSpaces = trimmed:gsub("%s+", "")
		if noSpaces == "{}" or noSpaces == "}" or noSpaces == "{" then
			return "object", {}
		elseif noSpaces == "[]" or noSpaces == "]" or noSpaces == "[" then
			return "array", {}
		else
			return "string", text
		end
	end
end

function JSONHelper.toInputString(value: JSONValue, type: JSONType | string): string
	if type == "number" or type == "boolean" then
		return tostring(value)
	elseif type == "null" then
		return "null"
	elseif type == "array" then
		-- Constructing non-empty arrays from input string not supported
		return "[]"
	elseif type == "object" then
		-- Constructing non-empty objects from input string not support
		return "{}"
	elseif type == "string" then
		if JSONHelper.looksDumb(value) then
			local parsedType, parsedValue = JSONHelper.parseInputString(value :: string)
			if (parsedType ~= type) or (parsedType == "string" and parsedValue ~= value) then
				return `"{value}"`
			else
				return tostring(value)
			end
		else
			return JSONHelper.escapeString(value)
		end
	elseif type == "buffer" then
		-- Buffer cannot be turned into string.
		return ""
	end

	return ""
end

local JSON5_PATTERN = [=[^%s*[%[%{"']]=]
local SPECIAL_CHARACTER_PATTERNS =
	"[\x00\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c\x0d\x0e\x0f\x10\x11\x12\x13\x14\x15\x16\x17\x18\x19\x1a\x1b\x1c\x1d\x1e\x1f\x7f]"
-- Here "dumb" means it looks like they are not trying to type in a JSON object/array
function JSONHelper.looksDumb(source: string): boolean
	return not source:match(JSON5_PATTERN) and (not source:match(SPECIAL_CHARACTER_PATTERNS))
end

return JSONHelper
