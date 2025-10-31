--!strict

export type ShortcutType = "normal" | "escapedNormal" | "mention"
export type ShortcutPiece = {
	type: ShortcutType,
	content: string,

	-- "escapedNormal" will always start with \\ which should be ignored
	-- "mention" will always start with @ which should be ignored
}
export type ShortcutsString = { ShortcutPiece }

local validGraphemes = {
	a = true,
	b = true,
	c = true,
	d = true,
	e = true,
	f = true,
	g = true,
	h = true,
	i = true,
	j = true,
	k = true,
	l = true,
	m = true,
	n = true,
	o = true,
	p = true,
	q = true,
	r = true,
	s = true,
	t = true,
	u = true,
	v = true,
	w = true,
	x = true,
	y = true,
	z = true,
	A = true,
	B = true,
	C = true,
	D = true,
	E = true,
	F = true,
	G = true,
	H = true,
	I = true,
	J = true,
	K = true,
	L = true,
	M = true,
	N = true,
	O = true,
	P = true,
	Q = true,
	R = true,
	S = true,
	T = true,
	U = true,
	V = true,
	W = true,
	X = true,
	Y = true,
	Z = true,
	["1"] = true,
	["2"] = true,
	["3"] = true,
	["4"] = true,
	["5"] = true,
	["6"] = true,
	["7"] = true,
	["8"] = true,
	["9"] = true,
	["0"] = true,
	["_"] = true,
}

-- Probably a better way to do this...
local function isValidUsernameGrapheme(grapheme: string): boolean
	return validGraphemes[grapheme] or false
end

return function(source: string): ShortcutsString
	local lastGrapheme: string

	local pieces: ShortcutsString = {}

	local pieceType: ShortcutType = "normal"
	local pieceContent = table.create(16)

	local function insertCurrentPiece()
		if #pieceContent > 0 then
			table.insert(pieces, {
				type = pieceType,
				content = table.concat(pieceContent, nil),
			})
		end
	end

	local function startPiece(type: ShortcutType)
		pieceType = type
		pieceContent = table.create(16)
	end

	for first, last in utf8.graphemes(source) do
		local grapheme = source:sub(first, last)
		if grapheme == "@" or grapheme == "$" then
			if lastGrapheme == "\\" then
				lastGrapheme = ""

				insertCurrentPiece()
				startPiece("escapedNormal")

				table.insert(pieceContent, "\\")
				table.insert(pieceContent, grapheme)

				insertCurrentPiece()
				startPiece("normal")
				continue
			elseif lastGrapheme == "@" or lastGrapheme == "$" then
				if pieceType == "mention" then
					insertCurrentPiece()
					startPiece("normal")
				end
				table.insert(pieceContent, lastGrapheme)
			end
		elseif grapheme == "\\" then
			if lastGrapheme == "\\" then
				lastGrapheme = ""

				insertCurrentPiece()
				startPiece("escapedNormal")

				table.insert(pieceContent, "\\\\")

				insertCurrentPiece()
				startPiece("normal")

				continue
			end
		else
			if pieceType == "mention" then
				if (lastGrapheme == "\\") or (not isValidUsernameGrapheme(grapheme)) then
					insertCurrentPiece()
					startPiece("normal")
				end
			end

			if lastGrapheme == "\\" then
				table.insert(pieceContent, "\\")
			elseif lastGrapheme == "@" or lastGrapheme == "$" then
				if isValidUsernameGrapheme(grapheme) then
					insertCurrentPiece()
					startPiece("mention")
				end
				table.insert(pieceContent, lastGrapheme)
			end
			table.insert(pieceContent, grapheme)
		end

		lastGrapheme = grapheme
	end

	if lastGrapheme == "\\" then
		if pieceType == "normal" then
			table.insert(pieceContent, "\\")
		else
			insertCurrentPiece()
			startPiece("normal")
			table.insert(pieceContent, "\\")
		end
	elseif lastGrapheme == "@" or lastGrapheme == "$" then
		if pieceType == "normal" then
			table.insert(pieceContent, lastGrapheme)
		else
			insertCurrentPiece()
			startPiece("normal")
			table.insert(pieceContent, lastGrapheme)
		end
	end
	insertCurrentPiece()

	return pieces
end
