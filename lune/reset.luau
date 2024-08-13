--> Resets directories used in syncing so they are empty.

local process = require("@lune/process")

if process.os == "windows" then
	error("Does not work on Windows.")
end

print(process.spawn("bash", { "-c", "rm -r src/* assets/* tests/*" }))
print(process.spawn("mkdir", { "assets/tests" }))
