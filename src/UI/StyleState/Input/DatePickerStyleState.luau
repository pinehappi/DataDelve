--!strict

-- This wraps over TextBox
-- Maybe later, can adjust for other locales.
-- Also could add a calender popup.

-- Use :getValue to get the value (unix timestamp milliseconds)

-- Valid Formats:
--	MM/DD/YY
--	MM-DD-YY
--	Month Day, Year
--	Month Day
--	ISO 8601

local TextBoxStyleState = require(script.Parent.TextBoxStyleState)

local DatePickerStyleState = setmetatable({}, { __index = TextBoxStyleState })
DatePickerStyleState.__index = DatePickerStyleState

-- Date stuff
type Timestamp = number
type Date = Timestamp | DateTime

-- NOTE: Is it ethical to support mispelling for better user experience?
local monthNames = {
	jan = 1,
	january = 1,
	janury = 1,
	feb = 2,
	february = 2,
	febuary = 2,
	feburary = 2,
	mar = 3,
	march = 3,
	apr = 4,
	april = 4,
	may = 5,
	jun = 6,
	june = 6,
	jul = 7,
	july = 7,
	aug = 8,
	august = 8,
	sep = 9,
	september = 9,
	sept = 9,
	oct = 10,
	october = 10,
	octo = 10,
	octob = 10,
	nov = 11,
	november = 11,
	novem = 11,
	nove = 11,
	dec = 12,
	december = 12,
	christmas = 12,
}

local function isValidMonth(month: number?): boolean
	return (typeof(month) == "number") and (math.floor(month) == month) and (1 <= month) and (month <= 12)
end

local function isValidYear(year: number?): boolean
	return (typeof(year) == "number") and (1400 <= year) and (year <= 9999)
end

local function isLeapYear(year: number): boolean
	return ((year % 4 == 0) and (year % 100 ~= 0)) or (year % 400 == 0)
end

local function getDaysInMonth(month: number, year: number): number
	if month == 2 then
		return if isLeapYear(year) then 29 else 28
	elseif month == 4 or month == 6 or month == 9 or month == 11 then
		return 30
	else
		return 31
	end
end

local function isValidDay(day: number?, month: number, year: number): boolean
	return (typeof(day) == "number") and (1 <= day) and (day <= getDaysInMonth(month, year))
end

local function tryGetDate(text: string, upToEndOfDay: boolean): (DateTime?, string?)
	-- Format: month
	do
		local month = monthNames[text:lower()]
		if month then
			local now = DateTime.now():ToUniversalTime()
			if upToEndOfDay then
				return DateTime.fromUniversalTime(now.Year, month, getDaysInMonth(month, now.Year), 23, 59, 59, 999)
			else
				return DateTime.fromUniversalTime(now.Year, month, 1)
			end
		end
	end

	-- Format: MM/DD/YYYY
	local parts = text:split("/")
	if #parts ~= 3 then
		-- Format: MM-DD-YY
		parts = text:split("-")
		if #parts ~= 3 then
			-- Format: Jan 12, 2024
			parts = text:gsub(";", ""):gsub(",", ""):split(" ")
			if #parts == 3 or #parts == 2 then
				local month = monthNames[parts[1]:lower()]
				if not month then
					return nil, "Invalid month. Format: month day, year or MM/DD/YYYY."
				else
					parts[1] = month
				end

				if #parts == 2 then
					-- Auto-fill the year
					parts[3] = tostring(DateTime.now():ToUniversalTime().Year)
				end
			else
				return nil, "Invalid format."
			end
		end
	end

	local month = tonumber(parts[1])
	if not isValidMonth(month) then
		return nil, "Invalid month. Format: month day, year or MM/DD/YYYY."
	end

	local year = tonumber(parts[3])
	if not isValidYear(year) then
		return nil, "Invalid year. Format: month day, year or MM/DD/YYYY."
	end

	local day = tonumber(parts[2])
	if not isValidDay(day, month :: number, year :: number) then
		return nil, "Invalid day. Format: month day, year or MM/DD/YYYY."
	end

	if upToEndOfDay then
		return DateTime.fromUniversalTime(year :: number, month :: number, day :: number, 23, 59, 59, 999)
	else
		return DateTime.fromUniversalTime(year :: number, month :: number, day :: number)
	end
end

local function tryGetTimestamp(text: string): (Timestamp?, string?)
	local timestamp = tonumber(text)
	if not timestamp then
		return nil, "Invalid date. Format: month day, year or MM/DD/YYYY."
	end

	return timestamp
end

local function tryGetTime(text: string, upToEndOfDay: boolean): (Date?, string?)
	local date, err = tryGetDate(text, upToEndOfDay)
	if date == nil and err == "Invalid format." then
		local iso = DateTime.fromIsoDate(text)
		if iso then
			return iso
		end

		local timestamp, err = tryGetTimestamp(text)
		if err then
			return nil, err
		else
			return timestamp
		end
	elseif err then
		return nil, err
	else
		return date
	end
end

-- Main style stuff

type DatePickerOptions = {
	upToEndOfDay: boolean?, -- If use types in May 31, 2024, if this is true, the timestmap returned will be May 31 2024 23:59pm instead of 00:00
}
function DatePickerStyleState.from(theme, textBox: TextBox & { UIStroke: UIStroke }, options: DatePickerOptions?)
	local options: DatePickerOptions = options or {}

	local self = setmetatable(TextBoxStyleState.from(theme, textBox), DatePickerStyleState)

	self._time = nil :: Date?

	self._datePickerConnections = {
		textBox:GetPropertyChangedSignal("Text"):Connect(function()
			local trimmed = textBox.Text:gsub("^%s+", ""):gsub("%s$", "")
			if trimmed == "" then
				self._time = nil
				self:setError(nil):update("veryFast")
				return
			end

			local time, err = tryGetTime(trimmed, options.upToEndOfDay or false)
			if err then
				self._time = nil
				self:setError(err):update("veryFast")
			else
				self._time = time
				self:setError(nil):update("veryFast")
			end
		end),
	}

	return self
end

-- Second value is if it has an error
function DatePickerStyleState:getValue(): Timestamp?
	if self._time then
		if typeof(self._time) == "DateTime" then
			return self._time.UnixTimestampMillis, false
		else
			return self._time, false
		end
	end
	return nil
end

function DatePickerStyleState:destroy(completely: boolean)
	for _, connection in self._datePickerConnections do
		connection:Disconnect()
	end
	TextBoxStyleState.destroy(self, completely)
end

return DatePickerStyleState
