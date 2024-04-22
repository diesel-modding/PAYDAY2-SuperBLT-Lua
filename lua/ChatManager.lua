Hooks:RegisterHook("ChatManagerOnSendMessage")
Hooks:PreHook(ChatManager, "send_message", "BLT.ChatManager.send_message", function(self, channel_id, sender, message)
	Hooks:Call("ChatManagerOnSendMessage", channel_id, sender, message)
end)

Hooks:RegisterHook("ChatManagerOnReceiveMessage")
Hooks:PreHook(ChatManager, "_receive_message", "BLT.ChatManager._receive_message", function(self, channel_id, name, message, color, icon)
	Hooks:Call("ChatManagerOnReceiveMessage", channel_id, name, message, color, icon)
end)

Hooks:RegisterHook("ChatManagerOnReceiveMessageByPeer")
Hooks:PreHook(ChatManager, "receive_message_by_peer", "BLT.ChatManager.receive_message_by_peer", function(self, channel_id, peer, message)
	Hooks:Call("ChatManagerOnReceiveMessageByPeer", channel_id, peer, message)
end)
