--!strict
export type Validator = (any) -> (boolean, string?) -- return 1: success, return 2: reason
local Validators = {}

local function isValidInteger(str: unknown): boolean
	local number = tonumber(str)
	if number then
		local isValidInteger = (number == math.floor(number)) and number == number and (math.abs(number) ~= math.huge)
		return isValidInteger
	end
	return false
end

Validators.empty = function(_): (boolean, string?)
	return true, nil
end
Validators.integer = function(a: any): (boolean, string?)
	if isValidInteger(a) then
		return true, nil
	else
		return false, "Must be an integer."
	end
end
Validators.dataStoreKey = function(text: string): (boolean, string?)
	if #text > 50 then
		return false, "Key name must be under 50 characters."
	else
		return true, nil
	end
end
Validators.orderedDataStoreValue = function(text: string): (boolean, string?)
	if not isValidInteger(text) then
		return false, "Value must be an integer."
	else
		return true, nil
	end
end
Validators.userId = function(text: unknown): (boolean, string?)
	if isValidInteger(text) then
		local number = tonumber(text)
		if number > 0 then
			return true, nil
		else
			return false, "UserId must be a positive integer."
		end
	else
		return false, "UserId must be a positive integer."
	end
end
Validators.allScopesKey = function(text: string): (boolean, string?)
	local split = text:split("/")
	if #split < 2 then
		return false, "AllScopes keys must be in the format scope/key."
	else
		local scope = split[1]
		local key = table.concat(split, "", 2)
		if scope == "" then
			return false, "Scope must be provided. Default scope is global."
		elseif key == "" then
			return false, "Key cannot be empty."
		else
			return true, nil
		end
	end
end

return Validators
