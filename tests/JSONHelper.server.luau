local JSONHelper = require(script.Parent.Parent.JSONHelper)

assert(JSONHelper.toInputString({}, "array") == "[]")
assert(JSONHelper.toInputString({ 1, 2, 3, 4, 5, 6 }, "array") == "[]")

assert(JSONHelper.toInputString({}, "object") == "{}")
assert(JSONHelper.toInputString({ hey = "world" }, "object") == "{}")

assert(JSONHelper.toInputString(nil, "null") == "null")

assert(JSONHelper.toInputString("", "string") == "")
assert(JSONHelper.toInputString("hello world", "string") == "hello world")
assert(JSONHelper.toInputString(`"`, "string") == [["\""]])
assert(JSONHelper.toInputString(`'`, "string") == [["'"]])
assert(JSONHelper.toInputString(`"""""""""`, "string") == [["\"\"\"\"\"\"\"\"\""]])
assert(JSONHelper.toInputString("[]", "string") == `"[]"`)
assert(JSONHelper.toInputString("{}", "string") == '"{}"')
assert(JSONHelper.toInputString("[1, 2, 3]", "string") == [["[1, 2, 3]"]])

assert(JSONHelper.toInputString(buffer.create(1), "buffer") == "")
