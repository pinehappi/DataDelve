export type Colors = {
	plain: Color3,

	background: Color3,
	hoverBackground: Color3,
	selectBackground: Color3,

	mainAccent: Color3,

	root: Color3,
	key: Color3,
	index: Color3,

	array: Color3,
	object: Color3,
	boolean: Color3,
	number: Color3,
	string: Color3,
	null: Color3,

	disabled: Color3,
}

local Settings = require(script.Parent.Parent.Parent.Settings)

local function colorDistance(a: Color3, b: Color3): number
	return math.sqrt((a.R - b.R) ^ 2 + (a.G - b.G) ^ 2 + (a.B - b.G) ^ 2)
end

local function invertColor(a: Color3): Color3
	return Color3.new(1 - a.R, 1 - a.G, 1 - a.B)
end

return function(theme)
	local highlightColors = Settings.get("highlightColors")
	if highlightColors == "Default" then
		local colors = table.clone(theme.colors.syntaxHighlight)
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
		return colors
	elseif highlightColors == "Script Editor" then
		local studio = settings().Studio
		return {
			plain = studio["Text Color"],

			background = studio["Background Color"],
			hoverBackground = studio["Selection Background Color"]:Lerp(studio["Background Color"], 0.75),
			selectBackground = studio["Selection Background Color"]:Lerp(studio["Background Color"], 0.5),

			mainAccent = if colorDistance(theme.colors.mainAccent, studio["Background Color"]) < 0.6
				then invertColor(studio["Background Color"]):lerp(theme.colors.mainAccent, 0.25)
				else theme.colors.mainAccent,

			root = studio["Keyword Color"],
			key = studio["Property Color"],
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
end
