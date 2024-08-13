-- Rich-Text ForMaT
-- Convience functions for wrapping things in rich text tags.

local rfmt = {}

function rfmt.code(s: string): string
	return `<font face="RobotoMono">{s}</font>`
end

return rfmt
