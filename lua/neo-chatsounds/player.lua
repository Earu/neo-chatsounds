local cs_player = DEFINE_CHATSOUND_MODULE("player")

local function play_group_async(ply, sound_group)
	if sound_group.type ~= "group" then return end

	PrintTable(sound_group)

	for _, sn in pairs(sound_group.sounds) do
		local existing_sounds = chatsounds.data.lookup[sn.text]
		local sound_metadata = existing_sounds[math.random(#existing_sounds)]
		local sound_data = sound_metadata.sounds[math.random(#sound_metadata.sounds)]
		local sound_url = sound_metadata.list_url .. "sound/" .. sound_data.path
		local sound_task = chatsounds.tasks.new()
		sound.PlayURL(sound_url, "3d", function(channel)
			if not IsValid(channel) then
				sound_task:resolve()
				return
			end

			timer.Simple(sound_data.length, function() sound_task:resolve() end)

			channel:SetPos(ply:GetPos())
			channel:Play()
		end)
	end


	local task_queue = sound_task
	for _, child_grp in ipairs(sound_group.children) do
		task_queue = task_queue:next(function() return play_group_async(ply, child_grp) end, chatsounds.error)
	end

	return task_queue
end

function cs_player.play_async(ply, str)
	local t = chatsounds.tasks.new()
	chatsounds.parser.parse_async(str):next(function(sound_group)
		play_group_async(ply, sound_group):next(function()
			t:resolve()
		end, chatsounds.error)
	end, chatsounds.error)

	return t
end

hook.Add("OnPlayerChat", "chatsounds_player", function(ply, text)
	local start_time = SysTime()
	cs_player.play_async(ply, text):next(function()
		chatsounds.log("parsed and played sounds in " .. (SysTime() - start_time) .. "s")
	end)
end)