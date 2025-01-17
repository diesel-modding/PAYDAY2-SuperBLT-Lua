_G.NetworkHelper = _G.NetworkHelper or {}
_G.LuaNetworking = _G.NetworkHelper
NetworkHelper.HiddenChannel = 4
NetworkHelper.AllPeers = "GNAP"
NetworkHelper.AllPeersString = "%s/%s/%s"
NetworkHelper.SinglePeer = "GNSP"
NetworkHelper.SinglePeerString = "%s/%s/%s/%s"
NetworkHelper.ExceptPeer = "GNEP"
NetworkHelper.ExceptPeerString = "%s/%s/%s/%s"
NetworkHelper.Split = "[/]"
NetworkHelper._receive_hooks = {}

-- Technically we don't need the message identifiers anymore cause we're only sending to the peers we want to send to anyways
-- For backwards compatibility, we'll keep them for now and they can be phased out at a later date
-- For sending messages we will only use the AllPeers identifier to avoid unneccessary message processing

---Checks if the game is in a multiplayer state, and has an active multiplayer session
---@return table|false @The active multiplayer session, or `false`
function NetworkHelper:IsMultiplayer()
	return managers.network and managers.network:session() or false
end

---Checks if the local player is the host of the multiplayer game session  
---Functionally identical to `Network:is_server()`
---@return boolean @`true` if a multiplayer session is running and the local player is the host of it, or `false`
function NetworkHelper:IsHost()
	return Network and Network:is_server()
end

---Checks if the local player is a client of the multiplayer game session  
---Functionally identical to `Network:is_client()`
---@return boolean @`true` if a multiplayer session is running and the local player is not the host of it, or `false`
function NetworkHelper:IsClient()
	return Network and Network:is_client()
end

---Returns the peer ID of the local player
---@return integer @Peer ID of the local player or `0` if no multiplayer session is active
function NetworkHelper:LocalPeerID()
	local local_peer = managers.network and managers.network:session() and managers.network:session():local_peer()
	return local_peer and local_peer:id() or 0
end

---Returns the name of the player associated with the specified peer ID
---@param id integer @Peer ID of the player to get the name from
---@return string @Name of the player with peer ID `id`, or `"No Name"` if the player could not be found
function NetworkHelper:GetNameFromPeerID(id)
	local peer
	if id == self:LocalPeerID() then
		peer = managers.network and managers.network:session() and managers.network:session():local_peer()
	else
		peer = self:GetPeers()[id]
	end
	return peer and peer:name() or "No Name"
end

---Returns an accessor for the session peers table
---@return table @Table of all players in the current multiplayer session
function NetworkHelper:GetPeers()
	return managers.network and managers.network:session() and managers.network:session():peers() or {}
end

---Returns the number of players in the multiplayer session
---@return integer @Number of players in the current session
function NetworkHelper:GetNumberOfPeers()
	return table.size(self:GetPeers())
end

---Sends networked data with a message id to all connected players
---@param id string @Unique name of the data to send
---@param data string @Data to send
function NetworkHelper:SendToPeers(id, data)
	local message = NetworkHelper.AllPeersString:format(NetworkHelper.AllPeers, id, data)
	self:SendStringThroughChat(message, self:GetPeers())
end

---Sends networked data with a message id to a specific player
---@param peer_id integer @Peer ID of the player to send the data to
---@param id string @Unique name of the data to send
---@param data string @Data to send
function NetworkHelper:SendToPeer(peer_id, id, data)
	local message = NetworkHelper.AllPeersString:format(NetworkHelper.AllPeers, id, data)
	self:SendStringThroughChat(message, { self:GetPeers()[peer_id] })
end

---Sends networked data with a message id to all connected players except specific ones
---@param peer_id integer|integer[] @Peer ID or table of peer IDs of the player(s) to exclude
---@param id string @Unique name of the data to send
---@param data string @Data to send
function NetworkHelper:SendToPeersExcept(peer_id, id, data)
	local except = type(peer_id) == "table" and table.list_to_set(peer_id) or { [peer_id] = true }
	local message = NetworkHelper.AllPeersString:format(NetworkHelper.AllPeers, id, data)
	self:SendStringThroughChat(message, table.filter(self:GetPeers(), function (peer) return except[peer:id()] == nil end))
end

function NetworkHelper:SendStringThroughChat(message, receivers)
	for _, peer in pairs(receivers or self:GetPeers()) do
		if peer:ip_verified() then
			peer:send("send_chat_message", NetworkHelper.HiddenChannel, message)
		end
	end

	local local_peer = managers.network and managers.network:session() and managers.network:session():local_peer()
	BLT:Log(LogLevel.INFO, string.format("[NetworkHelper] %s: %s", local_peer and local_peer:name() or "", message))
end

---Registers a function to be called when network data with a specific message id is received
---@param message_id string @The message id to hook to
---@param hook_id string @A unique name for this hook
---@param func fun(data: string, sender: integer) @Function to be called when network data for that specific message id is received
function NetworkHelper:AddReceiveHook(message_id, hook_id, func)
	self._receive_hooks[message_id] = self._receive_hooks[message_id] or {}

	for k, v in pairs(self._receive_hooks[message_id]) do
		if v.id == id then
			return
		end
	end

	table.insert(self._receive_hooks[message_id], {
		id = hook_id,
		func = func
	})
end

---Removes a receive hook
---@param hook_id string @The unique name of the hook to remove
---@param message_id? string @The message id to remove the hook from, if not specified removes all matching hooks
function NetworkHelper:RemoveReceiveHook(hook_id, message_id)
	if message_id then
		self:RemoveReceiveHookByMessageId(hook_id, message_id)
		return
	end

	for k, v in pairs(self._receive_hooks) do
		self:RemoveReceiveHookByMessageId(hook_id, k)
	end
end

function NetworkHelper:RemoveReceiveHookByMessageId(hook_id, message_id)
	for i, v in pairs(self._receive_hooks[message_id] or {}) do
		if v.id == hook_id then
			table.remove(self._receive_hooks[message_id], i)
			break
		end
	end
end

Hooks:Add("ChatManagerOnReceiveMessageByPeer","ChatManagerOnReceiveMessageByPeer_NetworkHelper", function(channel_id, peer, message)
	if tonumber(channel_id) ~= NetworkHelper.HiddenChannel then
		return
	end

	BLT:Log(LogLevel.INFO, string.format("[NetworkHelper] %s: %s", peer:name(), message))

	local split_data = string.split(message, NetworkHelper.Split, nil, 3)
	local message_type = split_data[1]

	-- Message types other than AllPeers are kept for legacy compatibility
	if message_type == NetworkHelper.AllPeers then
		-- Message data may have contained a separator symbol, we need to correct the additional split
		NetworkHelper:OnDataReceived(peer:id(), split_data[2], split_data[4] and (split_data[3] .. "/" .. split_data[4]) or split_data[3])
	elseif message_type == NetworkHelper.SinglePeer then
		if tonumber(split_data[2]) == NetworkHelper:LocalPeerID() then
			NetworkHelper:OnDataReceived(peer:id(), split_data[3], split_data[4])
		end
	elseif message_type == NetworkHelper.ExceptPeer then
		local exceptedPeers = string.split(split_data[2], "[,]")
		for k, v in pairs(exceptedPeers) do
			if tonumber(v) == NetworkHelper:LocalPeerID() then
				return
			end
		end
		NetworkHelper:OnDataReceived(peer:id(), split_data[3], split_data[4])
	end
end)

Hooks:RegisterHook("NetworkReceivedData")
function NetworkHelper:OnDataReceived(sender, id, data)
	Hooks:Call("NetworkReceivedData", sender, id, data)

	if self._receive_hooks[id] then
		for i, v in pairs(self._receive_hooks[id]) do
			v.func(data, sender)
		end
	end
end

-- Utility functions to convert types into strings

---Creates a string representation of a color
---@param col any
---@return string
function NetworkHelper:ColourToString(col)
	return string.format("r:%.4f|g:%.4f|b:%.4f|a:%.4f", col.r, col.g, col.b, col.a)
end

---Converts a string representation of a color to a color
---@param str string
---@return any
function NetworkHelper:StringToColour(str)
	local r, g, b, a = str:match("r:([0-9.]+)|g:([0-9.]+)|b:([0-9.]+)|a:([0-9.]+)")
	r, g, b, a = tonumber(r), tonumber(g), tonumber(b), tonumber(a)
	if r and g and b and a then
		return Color(a, r, g, b)
	end
end

---Creates a string representation of a Vector3
---@param v Vector3 @The Vector3 to convert to a formatted string
---@return string @A formatted string containing the data of the Vector3
function NetworkHelper:Vector3ToString(v)
	return string.format("%08f,%08f,%08f", v.x, v.y, v.z)
end

---Converts a string representation of a Vector3 to a Vector3
---@param string string @The string to convert to a Vector3
---@return Vector3? @A Vector3 of the converted string or `nil` if no conversion could be made
function NetworkHelper:StringToVector3(string)
	local x, y, z = string:match("([-0-9.]+),([-0-9.]+),([-0-9.]+)")
	x, y, z = tonumber(x), tonumber(y), tonumber(z)
	if x and y and z then
		return Vector3(x, y, z)
	end
end



-- DEPRECATED FUNCTIONALITY --

---@deprecated @Use `NetworkHelper:VectorToString` instead
function Vector3.ToString(v)
	BLT:DeprecationWarning("Vector3.ToString")
	return NetworkHelper:Vector3ToString(v)
end

---@deprecated @Use `NetworkHelper:StringToVector` instead
function string.ToVector3(string)
	BLT:DeprecationWarning("string.ToVector3")
	return NetworkHelper:StringToVector3(string)
end

---@deprecated @Use `json.encode` instead
function NetworkHelper:TableToString(tbl)
	BLT:DeprecationWarning("LuaNetworking.TableToString")
	local str = ""
	for k, v in pairs(tbl) do
		if str ~= "" then
			str = str .. ","
		end
		str = str .. string.format("%s|%s", tostring(k), tostring(v))
	end
	return str
end

---@deprecated @Use `json.decode` instead
function NetworkHelper:StringToTable(str)
	BLT:DeprecationWarning("LuaNetworking.StringToTable")
	local tbl = {}
	local tblPairs = string.split(str, "[,]")
	for k, v in pairs(tblPairs) do
		local pairData = string.split(v, "[|]")
		tbl[pairData[1]] = pairData[2]
	end
	return tbl
end
