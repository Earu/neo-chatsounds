local cs_player = DEFINE_CHATSOUND_MODULE("player")

local function play_group_async(ply, sound_group)
	if sound_group.type ~= "group" then return end

	local sound_task = chatsounds.tasks.new()
	timer.Simple(1, function() sound_task:resolve() end)

	local task_queue = sound_task
	for _, child_grp in ipairs(sound_group.children) do
		task_queue = task_queue:next(function() return play_group_async(ply, child_grp) end)
	end

	return task_queue
end

function cs_player.play_async(ply, str)
	return chatsounds.parser.parse_async(str):next(function(res)
		return play_group_async(ply, res)
	end)
end

hook.Add("OnPlayerChat", "chatsounds_player", function(ply, text)
	local start_time = SysTime()
	cs_player.play_async(ply, text):next(function()
		print("[CS DEBUG]: PARSED AND PLAYED SOUNDS IN " .. (SysTime() - start_time) .. " SECONDS")
	end)
end)