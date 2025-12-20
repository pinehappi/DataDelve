local Oklab = {}

function Oklab.fromLinearSrgb(c: vector): vector
	local l = 0.4122214708 * c.x + 0.5363325363 * c.y + 0.0514459929 * c.z
	local m = 0.2119034982 * c.x + 0.6806995451 * c.y + 0.1073969566 * c.z
	local s = 0.0883024619 * c.x + 0.2817188376 * c.y + 0.6299787005 * c.z

	local l_ = l ^ (1 / 3)
	local m_ = m ^ (1 / 3)
	local s_ = s ^ (1 / 3)

	return vector.create(
		0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_,
		1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_,
		0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_
	)
end

function Oklab.toLinearSrgb(c: vector): vector
	local l_ = c.x + 0.3963377774 * c.y + 0.2158037573 * c.z
	local m_ = c.x - 0.1055613458 * c.y - 0.0638541728 * c.z
	local s_ = c.x - 0.0894841775 * c.y - 1.2914855480 * c.z

	local l = l_ ^ 3
	local m = m_ ^ 3
	local s = s_ ^ 3

	return vector.create(
		4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
		-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
		-0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s
	)
end

local function linearizeComponent(x: number): number
	if x >= 0.04045 then
		return ((x + 0.055) / (1 + 0.055)) ^ 2.4
	else
		return x / 12.92
	end
end

local function inverseLinearizeComponent(x: number): number
	if x >= 0.0031308 then
		return 1.055 * x ^ (1.0 / 2.4) - 0.055
	else
		return 12.92 * x
	end
end

function Oklab.fromColor3(c: Color3)
	return Oklab.fromLinearSrgb(
		vector.create(linearizeComponent(c.R), linearizeComponent(c.G), linearizeComponent(c.B))
	)
end

function Oklab.toColor3(c: vector)
	local srgb = Oklab.toLinearSrgb(c)
	return Color3.new(
		math.clamp(inverseLinearizeComponent(srgb.x), 0, 1),
		math.clamp(inverseLinearizeComponent(srgb.y), 0, 1),
		math.clamp(inverseLinearizeComponent(srgb.z), 0, 1)
	)
end

function Oklab.oklab(l: number, a: number, b: number): Color3
	return Oklab.toColor3(vector.create(l, a, b))
end

function Oklab.oklch(l: number, c: number, h: number): Color3
	return Oklab.toColor3(vector.create(l, c * math.cos(math.rad(h)), c * math.sin(math.rad(h))))
end

return Oklab
