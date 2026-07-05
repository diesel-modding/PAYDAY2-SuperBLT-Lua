_G.json = {}

---Converts a JSON string to a Lua table
---@param data string @String to decode
---@return any @Decoded data
function json.decode(data)
	local passed, value = pcall(json10.decode, data)
	return passed and value or nil
end

---Converts a Lua table to a JSON string
---@param data table @Data to encode
---@return string @Encoded data
function json.encode(data)
	return json10.encode(data)
end
