-- this is a EC module because SayLocal is not vanilla, and is implemented in EC,
-- alos EC has a spam protection which will mitigate the spam this can generate

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

local function pick_realm(realm)
	if not realm or #realm:Trim() == 0 then
		realm_sounds = {}
		chatsounds.Log("Shat realm was reset")
		return
	end

	realm_sounds = {}
	for sound_key, sounds in pairs(chatsounds.Data.Lookup.List) do
		for index, sound_data in ipairs(sounds) do
			if sound_data.Realm == realm then
				table.insert(realm_sounds, #sounds == 1 and sound_key or { Key = sound_key, Index = index })
			end
		end
	end


	chatsounds.Log(("Shat switched to realm: %s\nFound %d sounds"):format(realm, #realm_sounds))
end

local existing_realms = {}
for sound_key, sounds in pairs(chatsounds.Data.Lookup.List) do
	for index, sound_data in ipairs(sounds) do
		existing_realms[sound_data.Realm] = true
	end
end

concommand.Add("shat", function(_, _, _, str_args)
	str_args = str_args:Trim()
	pick_realm(str_args)
end, function(_, str_args)
	local suggestions = {}
	local args = str_args:Trim():Split(" ")
	if #args == 1 or #str_args:Trim() == 0 then
		for realm, _ in pairs(existing_realms) do
			if realm:match(args[1]) then
				table.insert(suggestions, "shat " .. realm)
			end
		end
	end

	return suggestions
end)

concommand.Add("shat_say", function()
	say_rand_sound()
end)