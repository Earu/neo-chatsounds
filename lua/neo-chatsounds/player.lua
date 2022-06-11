if not CLIENT then return end

local cs_player = chatsounds.Module("Player")

local function play_group_async(ply, sound_group)
	if sound_group.type ~= "group" then return end

	for _, sn in pairs(sound_group.sounds) do
		local existing_sounds = chatsounds.data.lookup[sn.text]
		local sound_data = existing_sounds[math.random(#existing_sounds)]
		local sound_task = chatsounds.Tasks.new()
		sound.PlayURL(sound_data.url, "3d", function(channel)
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
		task_queue = task_queue:next(function() return play_group_async(ply, child_grp) end, chatsounds.Error)
	end

	return task_queue
end

function cs_player.PlayAsync(ply, str)
	local t = chatsounds.Tasks.new()
	chatsounds.Parser.ParseAsync(str):next(function(sound_group)
		PrintTable(sound_group)
		play_group_async(ply, sound_group):next(function()
			t:resolve()
		end, chatsounds.Error)
	end, chatsounds.Error)

	return t
end

hook.Add("OnPlayerChat", "chatsounds.Player", function(ply, text)
	local start_time = SysTime()
	cs_player.PlayAsync(ply, text):next(function()
		chatsounds.Log("parsed and played sounds in " .. (SysTime() - start_time) .. "s")
	end)
end)