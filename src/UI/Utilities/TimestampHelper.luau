--!strict

local TimestampHelper = {}

-- Guesses what time of timestamp a number is, or nil if it doesn't look like a timestamp
-- The second parameter is if the guess should be conservative and guess it's not a timestamp
-- more often.
function TimestampHelper.guessTimestampType(n: number, conservative: "conservative"?): "seconds" | "milliseconds" | nil
	local s = tostring(n)

	if #s < 2 then
		return nil
	else
		if conservative then
			local firstTwo = tonumber(s:sub(1, 2)) or 0
			-- This should cover a few years.
			if not (17 <= firstTwo and firstTwo <= 21) then
				return nil
			end
		end

		if #s == 13 or ((not conservative) and #s == 12) then
			return "milliseconds"
		elseif #s == 10 then
			return "seconds"
		else
			return nil
		end
	end
end

-- Converts a number into a DateTime with a best-guess of what kind of timestamp it is
function TimestampHelper.bestGuessIntoDateTime(n: number): DateTime
	local timestampType = TimestampHelper.guessTimestampType(n)
	if timestampType == "milliseconds" then
		return DateTime.fromUnixTimestampMillis(n)
	elseif timestampType == "seconds" then
		return DateTime.fromUnixTimestamp(n)
	else
		return DateTime.fromUnixTimestamp(n)
	end
end

return TimestampHelper
