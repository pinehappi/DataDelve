export type Colors = {
	plain: Color3,

	background: Color3,
	hoverBackground: Color3,
	selectBackground: Color3,

	mainAccent: Color3,

	root: Color3,
	key: Color3,
	key2: Color3, -- Used when the setting "UseAlternatingKeyColors" is on
	key3: Color3, -- Used when the setting "UseAlternatingKeyColors" is on
	index: Color3,

	array: Color3,
	object: Color3,
	boolean: Color3,
	number: Color3,
	string: Color3,
	null: Color3,

	disabled: Color3,

	selectText: Colors,
}

local Settings = require(script.Parent.Parent.Parent.Settings)

local function invertColor(a: Color3): Color3
	return Color3.new(1 - a.R, 1 - a.G, 1 - a.B)
end

local textColors = {
	"plain",
	"root",
	"key",
	"index",
	"array",
	"object",
	"boolean",
	"number",
	"string",
	"null",
	"disabled",
}

return function(theme)
	local highlightColors = Settings.get("highlightColors")
	local colors
	if highlightColors == "Default" then
		colors = table.clone(theme.colors.syntaxHighlight)
		colors.plain = theme.colors.text
		colors.background = theme.colors.background
		colors.hoverBackground = theme.colors.button.transparent.baseColor:Lerp(
			theme.colors.background,
			theme.colors.button.transparent.hover
		)
		colors.selectBackground = theme.colors.button.transparent.baseColor:Lerp(
			theme.colors.background,
			theme.colors.button.transparent.select
		)
		colors.mainAccent = theme.colors.mainAccent
		colors.disabled = theme.colors.disabledText
	elseif highlightColors == "Script Editor" then
		local studio = settings().Studio
		colors = {
			plain = studio["Text Color"],

			background = studio["Background Color"],
			hoverBackground = studio["Selection Background Color"]:Lerp(studio["Background Color"], 0.75),
			selectBackground = studio["Selection Background Color"]:Lerp(studio["Background Color"], 0.5),

			mainAccent = if theme.getContrastRatio(theme.colors.mainAccent, studio["Background Color"]) < 4.5
				then invertColor(studio["Background Color"]):lerp(theme.colors.mainAccent, 0.25)
				else theme.colors.mainAccent,

			root = studio["Keyword Color"],
			key = studio["Property Color"],
			key2 = studio["Built-in Function Color"],
			key3 = studio['"self" Color'],
			index = studio["Built-in Function Color"],

			array = studio["Comment Color"],
			object = studio["Comment Color"],
			boolean = studio["Bool Color"],
			number = studio["Number Color"],
			string = studio["String Color"],
			null = studio['"nil" Color'],

			disabled = theme.colors.disabledText,
		}
	end

	local moveTowardsColor = if theme.getContrastRatio(colors.selectBackground, Color3.new(0, 0, 0))
			< theme.getContrastRatio(colors.selectBackground, Color3.new(1, 1, 1))
		then Color3.new(1, 1, 1)
		else Color3.new(0, 0, 0)

	colors.selectText = table.clone(colors)

	-- Adjusted selected colors
	for _, color in textColors do
		local ratio = theme.getContrastRatio(colors.selectText[color], colors.selectBackground)
		local originalColor = colors.selectText[color]
		if ratio < 4.5 then
			for i = 1, 10 do
				colors.selectText[color] = originalColor:lerp(moveTowardsColor, i / 10)
				if theme.getContrastRatio(colors.selectText[color], colors.selectBackground) >= 4.5 then
					break
				end
			end
		end
	end

	return colors
end
