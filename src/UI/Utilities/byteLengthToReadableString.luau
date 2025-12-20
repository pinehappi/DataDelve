--!strict

local giga = 10 ^ 9
local mega = 10 ^ 6
local kilo = 10 ^ 3

return function(bytes: number)
	return tostring(bytes):reverse():gsub("(%d%d%d)", "%1,"):gsub(",$", ""):reverse()
end
