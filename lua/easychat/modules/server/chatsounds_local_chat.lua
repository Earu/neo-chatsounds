hook.Add("ChatsoundsCanPlayerHear", "chatsounds_local_chat", function(speaker, text, listener, _, is_local)
	if not IsValid(listener) or not IsValid(speaker) then
		return false
	end

	if is_local and listener:GetPos():Distance(speaker:GetPos()) > speaker:GetInfoNum("easychat_local_msg_distance", 150) then
		return false
	end

	if IsValid(listener) and IsValid(speaker) and EasyChat.IsBlockedPlayer(listener, speaker:SteamID()) then
		return false
	end
end)

return "Chatsounds Local Chat Compat"