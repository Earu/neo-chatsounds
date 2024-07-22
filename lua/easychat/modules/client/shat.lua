-- this is a EC module because SayLocal is not vanilla, and is implemented in EC,
-- also EC has a spam protection which will mitigate the spam this can generate

local realm_sounds = {}
local function say_rand_sound()
	if #realm_sounds == 0 or LocalPlayer():KeyDown(IN_WALK) then
		local sounds, sound_key = table.Random(chatsounds.Data.Lookup.List)
		if #sounds == 1 then
			SayLocal(sound_key)
		else
			SayLocal(("%s:select(%d)"):format(sound_key, math.random(#sounds)))
		end
	else
		local rand_sound = table.Random(realm_sounds)
		local to_output = isstring(rand_sound) and rand_sound or ("%s:select(%d)"):format(rand_sound.Key, rand_sound.Index)
		SayLocal(to_output)
	end
end

local function pick_realm(realms)
	if not realms or #realms:Trim() == 0 then
		realm_sounds = {}
		chatsounds.Log("Shat realm was reset")
		return
	end

	realms = realms:Split(",")
	for i = 1, #realms do
		realms[realms[i]] = i
	end

	realm_sounds = {}
	for sound_key, sounds in pairs(chatsounds.Data.Lookup.List) do
		for index, sound_data in ipairs(sounds) do
			if realms[sound_data.Realm] then
				table.insert(realm_sounds, #sounds == 1 and sound_key or { Key = sound_key, Index = index })
			end
		end
	end


	chatsounds.Log(("Shat switched to realm(s): %s\nFound %d sounds"):format(table.concat(realms, ", "), #realm_sounds))
end

local existing_realms
local function refresh_realms()
	existing_realms = {}
	for sound_key, sounds in pairs(chatsounds.Data.Lookup.List) do
		for index, sound_data in ipairs(sounds) do
			existing_realms[sound_data.Realm] = true
		end
	end
end

refresh_realms()
hook.Add("ChatsoundsInitialized", "shatrealms", refresh_realms)

concommand.Add("shat", function(_, _, _, str_args)
	str_args = str_args:Trim()
	pick_realm(str_args)
end, function(_, str_args)
	local suggestions = {}
	local args = str_args:gsub(" ",""):gsub(",,",","):Trim():Split(",")
	for i = 1, math.max(#args - 1, 1) do
		args[args[i]] = i
	end
	local endres = table.Copy(args)
	if #args > 0 or #str_args:Trim() == 0 then
		for realm, _ in pairs(existing_realms) do
			if realm:match(args[#args]) and not (#args > 1 and args[realm]) then
				endres[#args] = realm
				table.insert(suggestions, string.format("shat %s", table.concat(endres, ","))) -- "shat " .. realm)
			end
		end
	end

	return suggestions
end, "Pick realms to shat_say from, separate with comma")

concommand.Add("shat_say", function()
	say_rand_sound()
end)

return "Shat"