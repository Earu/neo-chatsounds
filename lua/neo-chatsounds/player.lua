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

local function wait_for_all_tasks(tasks, callback)
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

		if callback then callback(task) end
	end

	next_task()
	return finished_task
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
					download_task:reject("Failed to download %s: %d", _sound.Url, res.Status)
					return
				end

				file.Write(_sound.Path, res.Body)
				chatsounds.Log("Downloaded %s", _sound.Url)
				download_task:resolve()
			end, chatsounds.Error)
		end

		local sound_task = chatsounds.Tasks.new()
		sound_task.Callback = function()
			local stream = chatsounds.WebAudio.CreateStream("data/" .. _sound.Path)
			hook.Add("Think", stream, function()
				if not stream:IsReady() then return end

				timer.Simple(stream:GetLength(), function()
					stream:Remove()
					sound_task:resolve()
				end)

				stream:Play()
				hook.Remove("Think", stream)
			end)
		end

		table.insert(sound_tasks, sound_task)
	end

	local finished_task = chatsounds.Tasks.new()
	wait_for_all_tasks(download_tasks):next(function()
		wait_for_all_tasks(sound_tasks, function(task)
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

	local start_time = SysTime()
	local text_chunks = text:Split(CONTEXT_SEPARATOR)
	for _, chunk in ipairs(text_chunks) do
		cs_player.PlayAsync(ply, chunk):next(function()
			chatsounds.Log("parsed and played sounds in " .. (SysTime() - start_time) .. "s")
		end)
	end
end)