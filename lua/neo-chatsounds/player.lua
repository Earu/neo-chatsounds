local cs_player = DEFINE_CHATSOUND_MODULE("player")

local function play_group_async(ply, sound_group)
	if sound_group.type ~= "group" then return end

	local t = chatsounds.tasks.new()
	timer.Simple(time, function() t:resolve() end)

	return t:next(function()
		for _, child_grp in ipairs(sound_group.children) do
			play_group_async(ply, child_grp)
		end
	end)
end

function cs_player.play_async(ply, strd)
	return chatsounds.parser.parse_async(str):next(function(res)

	end)
end

hook.Add("OnPlayerChat", "chatsounds_player", function(ply, text)
	local start_time = SysTime()
	cs_player.play_async(ply, text):next(function()
		print("[CS DEBUG]: PARSED AND PLAYED SOUNDS IN " .. (SysTime() - start_time) .. " SECONDS")
	end)
end)