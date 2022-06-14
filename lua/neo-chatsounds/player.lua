if not CLIENT then return end

local cs_player = chatsounds.Module("Player")

local function get_wanted_sound(sound_data)
	local matching_sounds = chatsounds.Data.Lookup.List[sound_data.Key]

	local index = math.random(#matching_sounds)
	for _, modifier in ipairs(sound_data.Modifiers) do
		if modifier.OnSelection then
			index, matching_sounds = modifier:OnSelection(index, matching_sounds)
		end
	end

	return matching_sounds[math.min(math.max(1, index), #matching_sounds)]
end

local function wait_all_tasks_in_order(tasks, callback)
	local i = 1
	local finished_task = chatsounds.Tasks.new()
	local function next_task()
		local task = tasks[i]
		if not task then
			finished_task:resolve()
			return
		end

		task:next(function()
			i = i + 1
			next_task()
		end, function(err)
			finished_task:reject(err)
		end)

		if callback then
			local succ, err = pcall(callback, task)
			if not succ then
				finished_task:reject(err)
				return
			end
		end
	end

	next_task()
	return finished_task
end

local function get_all_modifiers(sound_group, ret)
	ret = ret or {}

	for _, modifier in ipairs(sound_group.Modifiers or {}) do
		table.insert(ret, modifier)
	end

	if sound_group.Parent then
		get_all_modifiers(sound_group.Parent, ret)
	end

	return ret
end

local function play_sound_group_async(ply, sound_group)
	if sound_group.Type ~= "group" then return end

	local download_tasks = {}
	local sound_tasks = {}
	for _, sound_data in pairs(sound_group.Sounds) do
		if sound_data.Key == "sh" and ply == LocalPlayer() then
			chatsounds.WebAudio.Panic()
			continue
		end

		local _sound = get_wanted_sound(sound_data)
		local sound_dir_path = _sound.Path:GetPathFromFilename()
		if not file.Exists(sound_dir_path, "DATA") then
			file.CreateDir(sound_dir_path)
		end

		if not file.Exists(_sound.Path, "DATA") then
			chatsounds.Log("Downloading %s", _sound.Url)

			local download_task = chatsounds.Tasks.new()
			table.insert(download_tasks, download_task)

			chatsounds.Http.Get(_sound.Url):next(function(res)
				if res.Status ~= 200 then
					download_task:reject(("Failed to download %s: %d"):format(_sound.Url, res.Status))
					return
				end

				file.Write(_sound.Path, res.Body)
				chatsounds.Log("Downloaded %s", _sound.Url)
				download_task:resolve()
			end, chatsounds.Error)
		end

		local sound_task = chatsounds.Tasks.new()
		sound_task.Callback = function()
			local modifiers = table.Merge(get_all_modifiers(sound_group), sound_data.Modifiers)
			local stream = chatsounds.WebAudio.CreateStream("data/" .. _sound.Path)
			local started = false
			hook.Add("Think", stream, function()
				if not stream:IsReady() then return end

				if not started then
					stream:SetSourceEntity(ply)
					stream:Set3D(true)
					stream.Duration = stream:GetLength()

					for _, modifier in ipairs(modifiers) do
						if modifier.OnStreamInit then
							modifier:OnStreamInit(stream)
						end
					end

					timer.Simple(stream.Duration, function()
						if IsValid(stream) then
							stream:Remove()
						end

						sound_task:resolve()
					end)

					stream:Play()
					started = true
				end

				for _, modifier in ipairs(modifiers) do
					if modifier.OnStreamThink then
						modifier:OnStreamThink(stream)
					end
				end
			end)
		end

		table.insert(sound_tasks, sound_task)
	end

	local finished_task = chatsounds.Tasks.new()
	wait_all_tasks_in_order(download_tasks):next(function()
		wait_all_tasks_in_order(sound_tasks, function(task)
			task.Callback()
		end):next(function()
			finished_task:resolve()
		end, function(err) finished_task:reject(err) end)
	end, function(err) finished_task:reject(err) end)

	return finished_task
end

function cs_player.PlayAsync(ply, str)
	local t = chatsounds.Tasks.new()
	chatsounds.Parser.ParseAsync(str):next(function(sound_group)
		play_sound_group_async(ply, sound_group):next(function()
			t:resolve()
		end, chatsounds.Error)
	end, chatsounds.Error)

	return t
end

local CONTEXT_SEPARATOR = ";"
hook.Add("OnPlayerChat", "chatsounds.Player", function(ply, text)
	if text[1] == CONTEXT_SEPARATOR then return end

	local text_chunks = text:Split(CONTEXT_SEPARATOR)
	for _, chunk in ipairs(text_chunks) do
		cs_player.PlayAsync(ply, chunk)
	end
end)