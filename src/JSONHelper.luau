local HttpService = game:GetService("HttpService")

local JSONHelper = {}

export type JSONType = "string" | "number" | "array"| "object" | "boolean" | "null"
export type JSONValue = string | number | {[string]: JSONValue} | {JSONValue} | boolean | nil

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

-- THIS IS NOT FOR PARSING JSON
-- It's for parsing user input when they type in a JSONValue in an input field
function JSONHelper.parseInputString(text: string): (JSONType, JSONValue)
	local trimmed = text:gsub("^%s+", ""):gsub("%s+$", "")
	local lowered = trimmed:lower()

	if trimmed:sub(1, 1) == "\"" then
		if trimmed:sub(-1, -1) == "\"" then
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

return JSONHelper