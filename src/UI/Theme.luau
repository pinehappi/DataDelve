--!strict

local StudioSettings = settings().Studio

local Theme = {}
Theme.__index = Theme

Theme.accentHues = {
	red = 0,
	orange = 21,
	yellow = 42,
	yellowGreen = 72,
	green = 115,
	greenBlue = 140,
	seaGreen = 165,
	cyan = 190,
	blue = 220,
	purpleBlue = 235,
	purple = 265,
	pink = 295,
	redPink = 330,
	neutral = 0, -- Special case
}

local defaultIcons = {
	export = "rbxassetid://18872446140",
	import = "rbxassetid://18872442909",
	lookup = "rbxassetid://18872448764",
	edit = "rbxassetid://18872450875",
	delete = "rbxassetid://18872454033",
	storage = "rbxassetid://18872458094",
	insert = "rbxassetid://18872509789",
	pin = "rbxassetid://18886260860",
	unpin = "rbxassetid://18886277155",
	rename = "rbxassetid://18901732408",
	maximize = "rbxassetid://18962414864",
	minimize = "rbxassetid://18962422050",
	fill = "rbxassetid://84916176036418",
	select = "rbxassetid://127081818194911",
	downArrow = "rbxassetid://17650880752",
	rightArrow = "rbxassetid://17650877462",
	upArrow = "rbxassetid://18557565597",
	externalLink = "rbxassetid://107795554941527",
	hex = "rbxassetid://89135486788434",
	script = "rbxassetid://91274876240645",
	tree = "rbxassetid://122537027737334",
	circle = "rbxassetid://134783631811707",
	brackets = "rbxassetid://114949690827797",
	error = "rbxassetid://18829614103",
	warn = "rbxassetid://18829786614",
	success = "rbxassetid://18829818279",
}

-- Reference: https://stackoverflow.com/questions/596216/formula-to-determine-perceived-brightness-of-rgb-color
function Theme.srgbToLinear(colorChannel: number)
	if colorChannel <= 0.03928 then
		return colorChannel / 12.92
	else
		return ((colorChannel + 0.055) / 1.055) ^ 2.4
	end
end

function Theme.getLuminance(color: Color3): number
	return 0.2126 * Theme.srgbToLinear(color.R)
		+ 0.7152 * Theme.srgbToLinear(color.G)
		+ 0.0722 * Theme.srgbToLinear(color.B)
end

function Theme.getContrastRatio(L1: Color3, L2: Color3): number
	local luminance1 = Theme.getLuminance(L1)
	local luminance2 = Theme.getLuminance(L2)
	local lightest = math.max(luminance1, luminance2)
	local darkest = math.min(luminance1, luminance2)
	return (lightest + 0.05) / (darkest + 0.05)
end

function Theme.improveContrast(color: Color3, backgroundColor: Color3)
	local moveTowardsColor = if Theme.getContrastRatio(backgroundColor, Color3.new(0, 0, 0))
			< Theme.getContrastRatio(backgroundColor, Color3.new(1, 1, 1))
		then Color3.new(1, 1, 1)
		else Color3.new(0, 0, 0)
	local ratio = Theme.getContrastRatio(color, backgroundColor)
	local originalColor = color

	if ratio < 6 then
		for i = 1, 10 do
			color = originalColor:Lerp(moveTowardsColor, i / 10)
			if Theme.getContrastRatio(color, backgroundColor) >= 4.5 then
				return color
			end
		end
	end

	return originalColor
end

function Theme.new(): Theme
	local self = setmetatable({
		accent = "red",
		preset = "dark",
	}, Theme) :: Theme
	self.colors = Theme.generatePreset(self.preset, self.accent)
	self.icons = table.clone(defaultIcons)

	self._colorsChanged = Instance.new("BindableEvent")
	self.colorsChanged = self._colorsChanged.Event

	return self
end

-- returns HSV
function Theme.getAccentComponents(preset: string, accent: string): (number, number, number)
	local StudioTheme = StudioSettings.Theme :: StudioTheme
	if preset == "studio" then
		return StudioTheme:GetColor(Enum.StudioStyleGuideColor.DialogMainButton, Enum.StudioStyleGuideModifier.Default)
			:ToHSV()
	elseif preset == "light" then
		if accent == "neutral" then
			return 0, 0, 0
		end
		return Theme.accentHues[accent] / 360, 0.8, 0.8
	else --if preset == "dark" then
		if accent == "neutral" then
			return 0, 0, 1
		end
		return Theme.accentHues[accent] / 360, 0.55, 0.9
	end
end

function Theme.getAccentColor(preset: string, accent: string)
	return Color3.fromHSV(Theme.getAccentComponents(preset, accent))
end

local function areColorsSimilar(a: Color3, b: Color3): boolean
	return math.abs(a.R - b.R) <= 0.01 and math.abs(a.B - b.B) <= 0.01 and math.abs(a.G - b.G) <= 0.01
end

function Theme.generatePreset(preset: string, accent: string)
	local accentHue, accentSaturation, accentValue = Theme.getAccentComponents(preset, accent)
	local accentColor = Theme.getAccentColor(preset, accent)

	local selectedText = if Theme.getContrastRatio(accentColor, Color3.fromRGB(20, 20, 20))
			>= Theme.getContrastRatio(accentColor, Color3.fromRGB(230, 230, 230))
		then Color3.fromRGB(20, 20, 20)
		else Color3.fromRGB(230, 230, 230)

	if preset == "dark" then
		local colors = {
			button = {
				primary = if accent == "neutral"
					then {
						text = {
							select = selectedText,
							disable = Color3.new(0.25, 0.25, 0.25),
							default = selectedText,
							hover = selectedText,
							press = selectedText,
						},
						body = {
							select = accentColor,
							disable = Color3.new(0.4, 0.4, 0.4),
							default = accentColor,
							hover = Color3.new(0.9, 0.9, 0.9),
							press = Color3.new(0.8, 0.8, 0.8),
						},
						outline = {
							select = accentColor,
							disable = Color3.new(0.4, 0.4, 0.4),
							default = accentColor,
							hover = Color3.new(0.9, 0.9, 0.9),
							press = Color3.new(0.8, 0.8, 0.8),
						},
					}
					else {
						text = {
							select = selectedText,
							disable = Color3.fromHSV(accentHue, 100 / 255, 100 / 255),
							default = selectedText,
							hover = selectedText,
							press = selectedText,
						},
						body = {
							select = accentColor,
							disable = Color3.fromHSV(accentHue, 62 / 255, 62 / 255),
							default = accentColor,
							hover = Color3.fromHSV(accentHue, 0.85 * accentSaturation, 1.1 * accentValue),
							press = Color3.fromHSV(accentHue, 0.7 * accentSaturation, accentValue),
						},
						outline = {
							select = accentColor,
							disable = Color3.fromHSV(accentHue, 62 / 255, 62 / 255),
							default = accentColor,
							hover = Color3.fromHSV(accentHue, 0.85 * accentSaturation, 1.1 * accentValue),
							press = Color3.fromHSV(accentHue, 0.7 * accentSaturation, accentValue),
						},
					},
				secondary = {
					text = {
						select = selectedText,
						disable = Color3.fromRGB(80, 80, 80),
						default = Color3.fromRGB(220, 220, 220),
						hover = Color3.fromRGB(220, 220, 220),
						press = Color3.fromRGB(220, 220, 220),
					},
					body = {
						select = accentColor,
						disable = Color3.fromRGB(52, 52, 52),
						default = Color3.fromRGB(32, 32, 32),
						hover = Color3.fromRGB(32, 32, 32),
						press = Color3.fromRGB(45, 45, 45),
					},
					outline = {
						select = accentColor,
						disable = Color3.fromRGB(63, 63, 63),
						default = Color3.fromRGB(62, 62, 62),
						hover = Color3.fromRGB(135, 135, 135),
						press = Color3.fromRGB(105, 105, 105),
					},
				},
				transparent = {
					baseColor = if accent == "neutral" then accentColor else Color3.fromHSV(accentHue, 0.9, 1),
					selectColor = if accent == "neutral" then accentColor else Color3.fromHSV(accentHue, 0.9, 1),

					select = 0.7,
					disable = 1,
					default = 1,
					hover = 0.8,
					press = 0.6,
				},
				dormant = {
					select = Color3.fromRGB(240, 240, 240),
					disable = Color3.fromRGB(85, 85, 85),
					default = Color3.fromRGB(170, 170, 170),
					hover = Color3.fromRGB(200, 200, 200),
					press = Color3.fromRGB(220, 220, 220),
				},
			},

			message = {
				text = Color3.fromRGB(220, 220, 220),
				background = Color3.fromRGB(16, 16, 16),
				outline = Color3.fromRGB(50, 50, 50),
			},

			floatingAction = {
				background = Color3.fromRGB(40, 40, 40),
				outline = Color3.fromRGB(62, 62, 62),
			},

			error = Color3.fromRGB(209, 13, 13),
			warn = Color3.fromRGB(186, 138, 15),
			success = Color3.fromRGB(20, 182, 66),

			text = Color3.fromRGB(220, 220, 220),
			disabledText = Color3.fromRGB(100, 100, 100),

			headerBackground = Color3.fromRGB(26, 26, 26),

			background = Color3.fromRGB(26, 26, 26), --Color3.fromRGB(40, 40, 40),
			backgroundOutline = Color3.fromRGB(62, 62, 62),

			popupBackground = Color3.fromRGB(40, 40, 40),
			popupBackgroundOutline = Color3.fromRGB(62, 62, 62),

			scrollbar = Color3.fromRGB(150, 150, 150),

			scrimTransparency = 0.75,

			imageBackground = Color3.fromRGB(60, 60, 60),
			imageBackgroundOutline = Color3.fromRGB(70, 70, 70),

			separator = Color3.fromRGB(72, 72, 72),

			mainAccent = accentColor,

			syntaxHighlight = {
				root = Color3.fromRGB(247, 17, 255),
				key = Color3.fromRGB(90, 223, 106),
				key2 = Color3.fromRGB(171, 96, 225),
				key3 = Color3.fromRGB(107, 123, 230),
				index = Color3.fromRGB(171, 96, 225),

				array = Color3.fromRGB(116, 116, 116),
				object = Color3.fromRGB(116, 116, 116),
				boolean = Color3.fromRGB(243, 45, 88),
				number = Color3.fromRGB(241, 190, 36),
				string = Color3.fromRGB(78, 199, 243),
				null = Color3.fromRGB(243, 243, 243),
				buffer = Color3.fromRGB(223, 99, 28),
			},
		}
		colors.button.input = {
			text = table.clone(colors.button.secondary.text),
			body = table.clone(colors.button.secondary.body),
			outline = table.clone(colors.button.secondary.outline),
		}
		colors.button.input.outline.select = accentColor
		colors.button.input.body.select = colors.button.secondary.body.default
		colors.button.input.text.select = colors.button.secondary.text.default
		return colors
	elseif preset == "light" then
		local colors = {
			button = {
				primary = if accent == "neutral"
					then {
						text = {
							select = selectedText,
							disable = Color3.new(0.6, 0.6, 0.6),
							default = selectedText,
							hover = selectedText,
							press = selectedText,
						},
						body = {
							select = accentColor,
							disable = Color3.new(0.4, 0.4, 0.4),
							default = accentColor,
							hover = Color3.new(0.1, 0.1, 0.1),
							press = Color3.new(0.2, 0.2, 0.2),
						},
						outline = {
							select = accentColor,
							disable = Color3.new(0.4, 0.4, 0.4),
							default = accentColor,
							hover = Color3.new(0.1, 0.1, 0.1),
							press = Color3.new(0.2, 0.2, 0.2),
						},
					}
					else {
						text = {
							select = selectedText,
							disable = Color3.fromHSV(accentHue, 0.15, 0.6 * accentValue),
							default = selectedText,
							hover = selectedText,
							press = selectedText,
						},
						body = {
							select = accentColor,
							disable = Color3.fromHSV(accentHue, 0.15, accentValue),
							default = accentColor,
							hover = Color3.fromHSV(accentHue, 0.85 * accentSaturation, 1.1 * accentValue),
							press = Color3.fromHSV(accentHue, 0.7 * accentSaturation, accentValue),
						},
						outline = {
							select = accentColor,
							disable = Color3.fromHSV(accentHue, 0.15, accentValue),
							default = accentColor,
							hover = Color3.fromHSV(accentHue, 0.85 * accentSaturation, 1.1 * accentValue),
							press = Color3.fromHSV(accentHue, 0.7 * accentSaturation, accentValue),
						},
					},
				secondary = {
					text = {
						select = selectedText,
						disable = Color3.fromRGB(150, 150, 150),
						default = Color3.fromRGB(20, 20, 20),
						hover = Color3.fromRGB(20, 20, 20),
						press = Color3.fromRGB(20, 20, 20),
					},
					body = {
						select = accentColor,
						disable = Color3.fromRGB(210, 210, 210),
						default = Color3.fromRGB(236, 236, 236),
						hover = Color3.fromRGB(236, 236, 236),
						press = Color3.fromRGB(204, 204, 204),
					},
					outline = {
						select = accentColor,
						disable = Color3.fromRGB(190, 190, 190),
						default = Color3.fromRGB(200, 200, 200),
						hover = Color3.fromRGB(160, 160, 160),
						press = Color3.fromRGB(130, 130, 130),
					},
				},
				transparent = {
					baseColor = if accent == "neutral" then accentColor else Color3.fromHSV(accentHue, 0.9, 0.7),
					selectColor = if accent == "neutral" then accentColor else Color3.fromHSV(accentHue, 0.9, 0.7),

					select = 0.7,
					disable = 1,
					default = 1,
					hover = 0.8,
					press = 0.6,
				},
				dormant = {
					select = Color3.fromRGB(15, 15, 15),
					disable = Color3.fromRGB(200, 200, 200),
					default = Color3.fromRGB(110, 110, 110),
					hover = Color3.fromRGB(85, 85, 85),
					press = Color3.fromRGB(65, 65, 65),
				},
			},

			message = {
				text = Color3.fromRGB(20, 20, 20),
				background = Color3.fromRGB(240, 240, 240),
				outline = Color3.fromRGB(205, 205, 205),
			},

			floatingAction = {
				background = Color3.fromRGB(238, 238, 238),
				outline = Color3.fromRGB(170, 170, 170),
			},

			error = Color3.fromRGB(209, 13, 13),
			warn = Color3.fromRGB(186, 138, 15),
			success = Color3.fromRGB(20, 182, 66),

			text = Color3.fromRGB(20, 20, 20),
			disabledText = Color3.fromRGB(120, 120, 120),

			headerBackground = Color3.fromRGB(246, 246, 246),

			background = Color3.fromRGB(246, 246, 246),
			backgroundOutline = Color3.fromRGB(170, 170, 170),

			popupBackground = Color3.fromRGB(238, 238, 238),
			popupBackgroundOutline = Color3.fromRGB(170, 170, 170),

			scrollbar = Color3.fromRGB(120, 120, 120),

			scrimTransparency = 0.75,

			imageBackground = Color3.fromRGB(210, 210, 210),
			imageBackgroundOutline = Color3.fromRGB(190, 190, 190),

			separator = Color3.fromRGB(180, 180, 180),

			mainAccent = accentColor,

			syntaxHighlight = {
				root = Color3.fromRGB(152, 11, 159),
				key = Color3.fromRGB(60, 124, 65),
				key2 = Color3.fromRGB(105, 42, 157),
				key3 = Color3.fromRGB(45, 63, 135),
				index = Color3.fromRGB(105, 42, 157),

				array = Color3.fromRGB(95, 95, 95),
				object = Color3.fromRGB(95, 95, 95),
				boolean = Color3.fromRGB(141, 26, 53),
				number = Color3.fromRGB(147, 116, 22),
				string = Color3.fromRGB(44, 113, 138),
				null = Color3.fromRGB(29, 29, 29),
				buffer = Color3.fromRGB(157, 83, 18),
			},
		}
		colors.button.input = {
			text = table.clone(colors.button.secondary.text),
			body = table.clone(colors.button.secondary.body),
			outline = table.clone(colors.button.secondary.outline),
		}
		colors.button.input.outline.select = accentColor
		colors.button.input.body.select = colors.button.secondary.body.default
		colors.button.input.text.select = colors.button.secondary.text.default
		return colors
	elseif preset == "studio" then
		local StudioTheme = StudioSettings.Theme :: StudioTheme
		local isDark = Theme.getLuminance(StudioTheme:GetColor(Enum.StudioStyleGuideColor.MainBackground)) < 0.5

		-- if it's the old colors
		local isOld = if isDark
			then areColorsSimilar(
				StudioTheme:GetColor(Enum.StudioStyleGuideColor.MainButton),
				Color3.fromRGB(0, 162, 255)
			)
			else areColorsSimilar(
				StudioTheme:GetColor(Enum.StudioStyleGuideColor.MainButton),
				Color3.fromRGB(228, 238, 254)
			)

		return {
			button = {
				primary = {
					text = {
						select = StudioTheme:GetColor(
							Enum.StudioStyleGuideColor.DialogMainButtonText,
							Enum.StudioStyleGuideModifier.Selected
						),
						disable = StudioTheme:GetColor(
							Enum.StudioStyleGuideColor.DialogMainButtonText,
							Enum.StudioStyleGuideModifier.Disabled
						),
						default = StudioTheme:GetColor(
							Enum.StudioStyleGuideColor.DialogMainButtonText,
							Enum.StudioStyleGuideModifier.Default
						),
						hover = StudioTheme:GetColor(
							Enum.StudioStyleGuideColor.DialogMainButtonText,
							Enum.StudioStyleGuideModifier.Hover
						),
						press = StudioTheme:GetColor(
							Enum.StudioStyleGuideColor.DialogMainButtonText,
							Enum.StudioStyleGuideModifier.Pressed
						),
					},
					body = {
						select = StudioTheme:GetColor(
							Enum.StudioStyleGuideColor.DialogMainButton,
							Enum.StudioStyleGuideModifier.Selected
						),
						disable = StudioTheme:GetColor(
							Enum.StudioStyleGuideColor.DialogMainButton,
							Enum.StudioStyleGuideModifier.Disabled
						),
						default = StudioTheme:GetColor(
							Enum.StudioStyleGuideColor.DialogMainButton,
							Enum.StudioStyleGuideModifier.Default
						),
						hover = StudioTheme:GetColor(
							Enum.StudioStyleGuideColor.DialogMainButton,
							Enum.StudioStyleGuideModifier.Hover
						),
						press = StudioTheme:GetColor(
							Enum.StudioStyleGuideColor.DialogMainButton,
							Enum.StudioStyleGuideModifier.Pressed
						),
					},
					outline = {
						select = StudioTheme:GetColor(
							Enum.StudioStyleGuideColor.DialogMainButton,
							Enum.StudioStyleGuideModifier.Selected
						),
						disable = StudioTheme:GetColor(
							Enum.StudioStyleGuideColor.DialogMainButton,
							Enum.StudioStyleGuideModifier.Disabled
						),
						default = StudioTheme:GetColor(
							Enum.StudioStyleGuideColor.DialogMainButton,
							Enum.StudioStyleGuideModifier.Default
						),
						hover = StudioTheme:GetColor(
							Enum.StudioStyleGuideColor.DialogMainButton,
							Enum.StudioStyleGuideModifier.Hover
						),
						press = StudioTheme:GetColor(
							Enum.StudioStyleGuideColor.DialogMainButton,
							Enum.StudioStyleGuideModifier.Pressed
						),
					},
				},
				secondary = {
					text = {
						select = StudioTheme:GetColor(
							Enum.StudioStyleGuideColor.ButtonText,
							Enum.StudioStyleGuideModifier.Selected
						),
						disable = StudioTheme:GetColor(
							Enum.StudioStyleGuideColor.ButtonText,
							Enum.StudioStyleGuideModifier.Disabled
						),
						default = StudioTheme:GetColor(
							Enum.StudioStyleGuideColor.ButtonText,
							Enum.StudioStyleGuideModifier.Default
						),
						hover = StudioTheme:GetColor(
							Enum.StudioStyleGuideColor.ButtonText,
							Enum.StudioStyleGuideModifier.Hover
						),
						press = StudioTheme:GetColor(
							Enum.StudioStyleGuideColor.ButtonText,
							Enum.StudioStyleGuideModifier.Pressed
						),
					},
					body = {
						select = StudioTheme:GetColor(
							Enum.StudioStyleGuideColor.Button,
							Enum.StudioStyleGuideModifier.Selected
						),
						disable = StudioTheme:GetColor(
							Enum.StudioStyleGuideColor.Button,
							Enum.StudioStyleGuideModifier.Disabled
						),
						default = if isDark and isOld
							then Color3.fromRGB(69, 69, 69)
							else StudioTheme:GetColor(
								Enum.StudioStyleGuideColor.Button,
								Enum.StudioStyleGuideModifier.Default
							),
						hover = if isDark and isOld
							then Color3.fromRGB(77, 77, 77)
							elseif isOld then StudioTheme:GetColor(
								Enum.StudioStyleGuideColor.Button,
								Enum.StudioStyleGuideModifier.Selected
							)
							else StudioTheme:GetColor(
								Enum.StudioStyleGuideColor.Button,
								Enum.StudioStyleGuideModifier.Hover
							),
						press = StudioTheme:GetColor(
							Enum.StudioStyleGuideColor.Button,
							Enum.StudioStyleGuideModifier.Pressed
						),
					},
					outline = {
						select = StudioTheme:GetColor(
							Enum.StudioStyleGuideColor.ButtonBorder,
							Enum.StudioStyleGuideModifier.Selected
						),
						disable = StudioTheme:GetColor(
							Enum.StudioStyleGuideColor.ButtonBorder,
							Enum.StudioStyleGuideModifier.Disabled
						),
						default = StudioTheme:GetColor(
							Enum.StudioStyleGuideColor.ButtonBorder,
							Enum.StudioStyleGuideModifier.Default
						),
						hover = StudioTheme:GetColor(
							Enum.StudioStyleGuideColor.ButtonBorder,
							Enum.StudioStyleGuideModifier.Hover
						),
						press = StudioTheme:GetColor(
							Enum.StudioStyleGuideColor.ButtonBorder,
							Enum.StudioStyleGuideModifier.Pressed
						),
					},
				},
				input = {
					text = {
						select = StudioTheme:GetColor(
							Enum.StudioStyleGuideColor.ButtonText,
							Enum.StudioStyleGuideModifier.Selected
						),
						disable = StudioTheme:GetColor(
							Enum.StudioStyleGuideColor.ButtonText,
							Enum.StudioStyleGuideModifier.Disabled
						),
						default = StudioTheme:GetColor(
							Enum.StudioStyleGuideColor.ButtonText,
							Enum.StudioStyleGuideModifier.Default
						),
						hover = StudioTheme:GetColor(
							Enum.StudioStyleGuideColor.ButtonText,
							Enum.StudioStyleGuideModifier.Hover
						),
						press = StudioTheme:GetColor(
							Enum.StudioStyleGuideColor.ButtonText,
							Enum.StudioStyleGuideModifier.Pressed
						),
					},
					body = {
						select = StudioTheme:GetColor(
							Enum.StudioStyleGuideColor.InputFieldBackground,
							Enum.StudioStyleGuideModifier.Selected
						),
						disable = StudioTheme:GetColor(
							Enum.StudioStyleGuideColor.InputFieldBackground,
							Enum.StudioStyleGuideModifier.Disabled
						),
						default = StudioTheme:GetColor(
							Enum.StudioStyleGuideColor.InputFieldBackground,
							Enum.StudioStyleGuideModifier.Default
						),
						hover = StudioTheme:GetColor(
							Enum.StudioStyleGuideColor.InputFieldBackground,
							Enum.StudioStyleGuideModifier.Hover
						),
						press = StudioTheme:GetColor(
							Enum.StudioStyleGuideColor.InputFieldBackground,
							Enum.StudioStyleGuideModifier.Pressed
						),
					},
					outline = {
						select = StudioTheme:GetColor(
							Enum.StudioStyleGuideColor.InputFieldBorder,
							Enum.StudioStyleGuideModifier.Selected
						),
						disable = StudioTheme:GetColor(
							Enum.StudioStyleGuideColor.InputFieldBorder,
							Enum.StudioStyleGuideModifier.Disabled
						),
						default = StudioTheme:GetColor(
							Enum.StudioStyleGuideColor.InputFieldBorder,
							Enum.StudioStyleGuideModifier.Default
						),
						hover = StudioTheme:GetColor(
							Enum.StudioStyleGuideColor.InputFieldBorder,
							Enum.StudioStyleGuideModifier.Hover
						),
						press = StudioTheme:GetColor(
							Enum.StudioStyleGuideColor.InputFieldBorder,
							Enum.StudioStyleGuideModifier.Pressed
						),
					},
				},
				transparent = {
					baseColor = StudioTheme:GetColor(Enum.StudioStyleGuideColor.MainText),
					selectColor = StudioTheme:GetColor(
						Enum.StudioStyleGuideColor.DialogMainButton,
						Enum.StudioStyleGuideModifier.Selected
					),

					select = 0.5,
					disable = 1,
					default = 1,
					hover = 0.95,
					press = 0.85,
				},
				dormant = if isDark
					then {
						select = Color3.new(1, 1, 1),
						disable = Color3.new(0.35, 0.35, 0.35),
						default = Color3.new(0.6, 0.6, 0.6),
						hover = Color3.new(0.7, 0.7, 0.7),
						press = Color3.new(0.8, 0.8, 0.8),
					}
					else {
						select = Color3.new(0, 0, 0),
						disable = Color3.new(0.75, 0.75, 0.75),
						default = Color3.new(0.4, 0.4, 0.4),
						hover = Color3.new(0.3, 0.3, 0.3),
						press = Color3.new(0.2, 0.2, 0.2),
					},
			},

			message = if isOld
				then {
					text = Color3.fromRGB(250, 250, 250),
					background = Color3.fromRGB(24, 24, 24),
					outline = Color3.fromRGB(24, 24, 24),
				}
				else {
					text = Color3.fromRGB(250, 250, 250),
					background = Color3.fromRGB(24, 24, 24),
					outline = Color3.fromRGB(43, 43, 43),
				},

			floatingAction = {
				background = StudioTheme:GetColor(
					Enum.StudioStyleGuideColor.Button,
					Enum.StudioStyleGuideModifier.Default
				),
				outline = StudioTheme
					:GetColor(Enum.StudioStyleGuideColor.MainBackground, Enum.StudioStyleGuideModifier.Default)
					:Lerp(Color3.new(0, 0, 0), if isDark then 0 else 0.15),
			},

			error = StudioTheme:GetColor(Enum.StudioStyleGuideColor.ErrorText, Enum.StudioStyleGuideModifier.Default),
			warn = StudioTheme:GetColor(Enum.StudioStyleGuideColor.WarningText, Enum.StudioStyleGuideModifier.Default),
			success = accentColor,

			text = StudioTheme:GetColor(Enum.StudioStyleGuideColor.MainText, Enum.StudioStyleGuideModifier.Default),
			disabledText = StudioTheme:GetColor(
				Enum.StudioStyleGuideColor.DimmedText,
				Enum.StudioStyleGuideModifier.Default
			),

			headerBackground = StudioTheme:GetColor(
				Enum.StudioStyleGuideColor.Titlebar,
				Enum.StudioStyleGuideModifier.Default
			),

			background = StudioTheme:GetColor(
				Enum.StudioStyleGuideColor.MainBackground,
				Enum.StudioStyleGuideModifier.Default
			),
			backgroundOutline = StudioTheme:GetColor(
				Enum.StudioStyleGuideColor.MainBackground,
				Enum.StudioStyleGuideModifier.Default
			),

			popupBackground = StudioTheme:GetColor(
				Enum.StudioStyleGuideColor.MainBackground,
				Enum.StudioStyleGuideModifier.Default
			),
			popupBackgroundOutline = StudioTheme:GetColor(
				Enum.StudioStyleGuideColor.MainBackground,
				Enum.StudioStyleGuideModifier.Default
			):Lerp(Color3.new(0, 0, 0), if isDark then 0.3 else 0.12),

			scrollbar = StudioTheme:GetColor(Enum.StudioStyleGuideColor.DimmedText),

			scrimTransparency = 0.6,

			imageBackground = StudioTheme:GetColor(
				Enum.StudioStyleGuideColor.ViewPortBackground,
				Enum.StudioStyleGuideModifier.Default
			),
			imageBackgroundOutline = StudioTheme:GetColor(
				Enum.StudioStyleGuideColor.ViewPortBackground,
				Enum.StudioStyleGuideModifier.Default
			),

			separator = StudioTheme:GetColor(Enum.StudioStyleGuideColor.Border, Enum.StudioStyleGuideModifier.Default),

			mainAccent = accentColor,

			syntaxHighlight = if isDark
				then {
					root = Color3.fromRGB(248, 109, 124),
					key = Color3.fromRGB(97, 161, 241),
					key2 = Color3.fromRGB(172, 111, 247),
					key3 = Color3.fromRGB(132, 214, 247),
					index = Color3.fromRGB(132, 214, 247),

					array = Color3.fromRGB(102, 102, 102),
					object = Color3.fromRGB(102, 102, 102),
					boolean = Color3.fromRGB(253, 251, 172),
					number = Color3.fromRGB(255, 198, 0),
					string = Color3.fromRGB(173, 241, 149),
					null = Color3.fromRGB(204, 204, 204),
					buffer = Color3.fromRGB(253, 160, 129),
				}
				else {
					root = Color3.fromRGB(0, 0, 127),
					key = Color3.fromRGB(72, 92, 142),
					key2 = Color3.fromRGB(116, 72, 189),
					key3 = Color3.fromRGB(0, 116, 189),
					index = Color3.fromRGB(0, 116, 189),

					array = Color3.fromRGB(127, 127, 127),
					object = Color3.fromRGB(127, 127, 127),
					boolean = Color3.fromRGB(0, 127, 9),
					number = Color3.fromRGB(0, 127, 127),
					string = Color3.fromRGB(127, 0, 127),
					null = Color3.fromRGB(127, 127, 0),
					buffer = Color3.fromRGB(127, 63, 0),
				},
		}
	else
		error(`{preset} is not valid theme reset`, 2)
	end
end

function Theme:_updateColors()
	self.colors = Theme.generatePreset(self.preset, self.accent)

	self._colorsChanged:Fire()
end

-- Interface

function Theme:setAccent(accent: string)
	self.accent = accent
	self:_updateColors()
end

function Theme:setPreset(presetName: string)
	self.preset = presetName
	self:_updateColors()
end

Theme.global = Theme.new()

StudioSettings.ThemeChanged:Connect(function()
	if Theme.global.preset == "studio" then
		Theme.global:_updateColors()
	end
end)

export type Theme = typeof(setmetatable({
	accent = "red",
	preset = "dark",
	colors = Theme.generatePreset("red", "dark"),
	icons = defaultIcons,
	_colorsChanged = Instance.new("BindableEvent"),
	colorsChanged = Instance.new("BindableEvent").Event,
}, Theme))

return Theme
