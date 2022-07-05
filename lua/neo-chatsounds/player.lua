local STR_NETWORKING_LIMIT = 60000
local CONTEXT_SEPARATOR = ";"

if SERVER then
	util.AddNetworkString("chatsounds")
	util.AddNetworkString("chatsounds_cmd")

	local SPAM_STEP = 0.1 -- how many messages can be sent per second after burst
	local SPAM_MAX = 1 -- max amount of messages per burst

	local spam_watch_lookup = {}
	local function get_message_cost(msg, is_same_msg)
		local _, real_msg_len = msg:gsub("[^\128-\193]", "")
		if real_msg_len > 1024 then
			return SPAM_MAX - 1
		else
			local is_same_msg_spam = is_same_msg and real_msg_len > 128
			return is_same_msg_spam and 1 or 0
		end
	end

	local function spam_watch(ply, msg)
		if ply:IsAdmin() then return false end

		local time = RealTime()
		local last_msg = spam_watch_lookup[ply] or { Time = 0, Message = "" }

		-- if the last_msg.Time is inferior to current time it means the player is not
		-- being rate-limited (spamming) update its time to the current one
		if last_msg.Time < time then
			last_msg.Time = time
		end

		local is_same_msg = last_msg.Message == msg
		last_msg.Message = msg

		-- compute what time is appropriate for the current message
		local new_msg_time = last_msg.Time + SPAM_STEP + get_message_cost(msg, is_same_msg)

		-- if the computed time is superior to our limit then its spam, rate-limit the player
		if new_msg_time > time + SPAM_MAX then
			-- we dont want the rate limit to last forever, clamp the max new time
			local max_new_time = time + SPAM_MAX + 1
			if new_msg_time > max_new_time then
				new_msg_time = max_new_time
			end

			spam_watch_lookup[ply] = { Time = new_msg_time, Message = msg }
			return true
		end

		spam_watch_lookup[ply] = { Time = new_msg_time, Message = msg }
		return false
	end

	local function handler(ply, text)
		if #text >= STR_NETWORKING_LIMIT then
			chatsounds.Error("Message too long: " .. #text .. "chars by " .. ply:Nick())
			return
		end

		if spam_watch(ply, text) then
			chatsounds.Error("Message spammer: " .. ply:Nick())
			return
		end

		local ret = hook.Run("ChatsoundsShouldNetwork", ply, text)
		if ret == false then return end

		net.Start("chatsounds")
			net.WriteEntity(ply)
			net.WriteString(text)
		net.SendPAS(ply:WorldSpaceCenter())
	end

	hook.Add("PlayerSay", "chatsounds.Player", handler)

	net.Receive("chatsounds_cmd", function(_, ply)
		local text = net.ReadString()
		handler(ply, text)
	end)
end

if CLIENT then
	local cs_player = chatsounds.Module("Player")

	do
		-- this is a hack to detect stopsound
		hook.Add("InitPostEntity", "chatsounds.Player.StopSoundHack", function()
			local snd = CreateSound(LocalPlayer(), "phx/hmetal1.wav")
			snd:PlayEx(0, 100)

			hook.Add("Think", "chatsounds.Player.StopSoundhack", function()
				if not snd or not snd:IsPlaying() then
					snd = CreateSound(LocalPlayer(), "phx/hmetal1.wav")
					snd:PlayEx(0, 100)

					hook.Run("StopSound")
				end
			end)
		end)
	end

	function cs_player.GetWantedSound(sound_data, last_sound, seed)
		math.randomseed(seed or math.Round(CurTime()))

		local matching_sounds = chatsounds.Data.Lookup.List[sound_data.Key]
		local index = math.random(1, #matching_sounds)
		local ret_a, ret_b = hook.Run("ChatsoundsOnSelection", index, matching_sounds)
		local modified = false

		if isnumber(ret_a) then
			index = ret_a
			modified = true
		end

		if istable(ret_b) then
			matching_sounds = ret_b
			modified = true
		end

		for _, modifier in ipairs(sound_data.Modifiers) do
			chatsounds.Runners.Yield()

			if modifier.OnSelection then
				ret_a, ret_b = modifier:OnSelection(index, matching_sounds)

				if isnumber(ret_a) then
					index = ret_a
					modified = true
				end

				if istable(ret_b) then
					matching_sounds = ret_b
					modified = true
				end
			end
		end

		-- match realms together if we can
		if not modified and last_sound then
			local matching_realm_sounds = {}
			for _, snd in ipairs(matching_sounds) do
				chatsounds.Runners.Yield()

				if snd.Realm == last_sound.Realm then
					table.insert(matching_realm_sounds, snd)
				end
			end

			if #matching_realm_sounds > 0 then
				matching_sounds = matching_realm_sounds
				index = math.random(1, #matching_sounds)
			end
		end

		return matching_sounds[math.min(math.max(1, index), #matching_sounds)]
	end

	local function wait_all_tasks_in_order(tasks)
		local i = 1
		local finished_task = chatsounds.Tasks.new()
		if #tasks == 0 then
			finished_task:resolve()
			return finished_task
		end

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

			if task.Callback then
				local succ, err = pcall(task.Callback, task, i)
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

		if sound_group.Modifiers then
			for _, modifier in ipairs(sound_group.Modifiers) do
				chatsounds.Runners.Yield()

				if not modifier.NoInheritance then
					table.insert(ret, modifier)
				end
			end
		end

		if sound_group.Parent then
			chatsounds.Runners.Yield()
			get_all_modifiers(sound_group.Parent, ret)
		end

		return ret
	end

	local DEFAULT_OPTS = {
		DuplicateCount = 1,
	}

	local function sound_pre_process(grp, is_group)
		if not grp.Modifiers then return DEFAULT_OPTS end

		local opts = table.Copy(DEFAULT_OPTS)
		for _, modifier in ipairs(grp.Modifiers) do
			chatsounds.Runners.Yield()

			if is_group then
				if modifier.OnGroupPreProcess then
					return modifier:OnGroupPreProcess(grp, opts) or DEFAULT_OPTS
				end
			else
				if modifier.OnSoundPreProcess then
					return modifier:OnSoundPreProcess(grp, opts) or DEFAULT_OPTS
				end
			end
		end

		return DEFAULT_OPTS
	end

	local MAX_ITERATIONS = 100
	local function flatten_sounds(sound_group, ret, total_iters)
		ret = ret or {}
		total_iters = total_iters or 0

		local function add_iters(input)
			local iters = math.min(MAX_ITERATIONS, input or 1)
			if total_iters + iters > MAX_ITERATIONS then
				iters = 1
			end

			total_iters = total_iters + iters
			return iters
		end

		for _, child in pairs(sound_group.Children) do
			chatsounds.Runners.Yield()

			if child.Type == "sound" then
				local snd_opts = sound_pre_process(child, false)
				local snd_iters = add_iters(snd_opts.DuplicateCount)
				for _ = 1, snd_iters do
					chatsounds.Runners.Yield()

					child.Modifiers = table.Add(child.Modifiers, get_all_modifiers(child.ParentScope))
					table.insert(ret, child)
				end
			elseif child.Type == "group" then
				local opts = sound_pre_process(child, true)
				local iters = add_iters(opts.DuplicateCount)
				for _ = 1, iters do
					chatsounds.Runners.Yield()

					flatten_sounds(child, ret, total_iters)
				end
			end
		end

		return ret
	end

	local WEBAUDIO_TIMEOUT = 10
	local function prepare_stream(snd, task)
		local stream = chatsounds.WebAudio.CreateStream("data/" .. snd.Path)

		local done = false
		timer.Simple(WEBAUDIO_TIMEOUT, function()
			if done then return end
			if not stream:IsReady() then
				hook.Remove("Think", stream)
				task:reject(("WebAudio Timeout %s\nIf this happens a lot please do chatsounds_reload!"):format(snd.Url))
			end
		end)

		hook.Add("Think", stream, function()
			if not stream:IsReady() then return end

			done = true
			hook.Remove("Think", stream)
			task:resolve()
		end)

		return stream
	end

	cs_player.Streams = {}

	local ignore_next_stop_sound = false
	function cs_player.StopAllSounds(run_stop_sound)
		for k, streams in pairs(cs_player.Streams) do
			for _, stream in pairs(streams) do
				stream:Remove()
			end

			cs_player.Streams[k] = {}
		end

		chatsounds.WebAudio.Panic()

		if run_stop_sound then
			ignore_next_stop_sound = true
			RunConsoleCommand("stopsound")
		end
	end

	hook.Add("StopSound", "chatsounds.Player.StopSound", function()
		if ignore_next_stop_sound then
			ignore_next_stop_sound = false
			return
		end

		cs_player.StopAllSounds(false)
		chatsounds.Log("Cleared all sounds!")
	end)

	local CS_SH_MODE = CreateConVar("chatsounds_sh_mode", "1", FCVAR_ARCHIVE, "0: Disable, 1: Enable only for you, 2: Enable for everyone")
	local function should_sh(ply)
		local mode = CS_SH_MODE:GetInt()
		if mode == 1 then
			return ply == LocalPlayer()
		elseif mode <= 0 then
			return false
		else
			return true
		end
	end

	local SOUND_WHITENOISE_DURATION_APROMIXATION = 0.075
	function cs_player.PlaySoundGroupAsync(ply, sound_group)
		local finished_task = chatsounds.Tasks.new()
		if sound_group.Type ~= "group" then
			finished_task:resolve()
			return finished_task
		end

		chatsounds.Runners.Execute(function()
			local download_tasks = {}
			local sound_tasks = {}
			local sounds = flatten_sounds(sound_group)
			local streams = {}
			local streams_index = table.insert(cs_player.Streams, streams)

			local function reject(err)
				table.remove(cs_player.Streams, streams_index)
				finished_task:reject(err)
			end

			local function resolve()
				table.remove(cs_player.Streams, streams_index)
				finished_task:resolve()
			end

			local last_sound = nil
			for i, sound_data in ipairs(sounds) do
				if sound_data.Key == "sh" and should_sh(ply) then
					cs_player.StopAllSounds(true)
					continue
				end

				local _sound = cs_player.GetWantedSound(sound_data, last_sound, math.Round(CurTime()) + i * 1028)
				last_sound = _sound

				local sound_dir_path = _sound.Path:GetPathFromFilename()

				if not file.Exists(sound_dir_path, "DATA") then
					file.CreateDir(sound_dir_path)
				end

				local download_task = chatsounds.Tasks.new()
				table.insert(download_tasks, download_task)

				if not file.Exists(_sound.Path, "DATA") then
					chatsounds.DebugLog(("Downloading %s"):format(_sound.Url))
					chatsounds.Http.Get(_sound.Url):next(function(res)
						if res.Status ~= 200 then
							download_task:reject(("Failed to download %s: %d"):format(_sound.Url, res.Status))
							return
						end

						file.Write(_sound.Path, res.Body)
						chatsounds.DebugLog(("Downloaded %s"):format(_sound.Url))
						streams[i] = prepare_stream(_sound, download_task)
					end, function(err)
						download_task:reject(("Failed to download %s: %s"):format(_sound.Url, err))
					end)
				else
					streams[i] = prepare_stream(_sound, download_task)
				end

				local sound_task = chatsounds.Tasks.new()
				sound_task.StartTime = CurTime()
				sound_task.Callback = function(_, i)
					local stream = streams[i]
					if not stream then
						sound_task:resolve()
						return
					end

					if not stream.IsValid then
						stream.IsValid = function() return false end
					end

					local started = false
					local hook_name = ("chatsounds_stream_%s"):format(stream:GetId())
					hook.Add("Think", hook_name, function()
						if not IsValid(ply) or not IsValid(stream) then
							if not started then
								sound_task:resolve()
							end

							hook.Remove("Think", hook_name)
							return
						end

						if not started then
							stream:SetSourceEntity(ply)
							stream:Set3D(true)
							stream.Duration = stream:GetLength() - SOUND_WHITENOISE_DURATION_APROMIXATION
							stream.Overlap = true

							local function remove_stream()
								if IsValid(stream) then
									stream:Remove()
								end

								local success, err = pcall(hook.Remove, "Think", hook_name)
								if not success then
									chatsounds.Error("Failed to finish stream " .. hook_name .. ":" .. err)
								end
							end

							for _, modifier in ipairs(sound_data.Modifiers) do
								if modifier.OnStreamInit then
									modifier:OnStreamInit(stream)
								end
							end

							timer.Simple(stream.Duration, function()
								if not stream.Overlap then
									remove_stream()
								end

								sound_task:resolve()
							end)

							if stream.Overlap then
								timer.Simple(stream:GetLength() + 1, remove_stream)
							end

							stream:Play()
							started = true
							hook.Run("ChatsoundsSoundInit", ply, _sound, stream, sound_data)
						end

						for _, modifier in ipairs(sound_data.Modifiers) do
							if modifier.OnStreamThink then
								modifier:OnStreamThink(stream)
							end
						end

						hook.Run("ChatsoundsSoundThink", ply, _sound, stream, sound_data)

						if ply:IsDormant() then
							stream:SetVolume(0)
						end
					end)
				end

				table.insert(sound_tasks, sound_task)
			end

			wait_all_tasks_in_order(download_tasks):next(function()
				if #sound_tasks > 0 then
					wait_all_tasks_in_order(sound_tasks):next(resolve, reject)
				else
					resolve()
				end
			end, reject)
		end, reject)

		return finished_task
	end

	function cs_player.PlayAsync(ply, text)
		if text[1] == CONTEXT_SEPARATOR then
			local t = chatsounds.Tasks.new()
			t:resolve()
			return t
		end

		local tasks = {}
		local text_chunks = text:Split(CONTEXT_SEPARATOR)
		for _, chunk in ipairs(text_chunks) do
			local t = chatsounds.Tasks.new()
			chatsounds.Parser.ParseAsync(chunk):next(function(sound_group)
				local ret = hook.Run("ChatsoundsShouldPlay", ply, chunk, sound_group)
				if ret == false then
					t:resolve()
					return
				end

				cs_player.PlaySoundGroupAsync(ply, sound_group):next(function()
					t:resolve()
				end, function(err)
					t:reject(err)
				end)
			end, function(err)
				t:reject(err)
			end)

			table.insert(tasks, t)
		end

		return chatsounds.Tasks.all(tasks)
	end

	local function handler(ply, text)
		if not chatsounds.Enabled then return end
		if chatsounds.Data.Loading then return end
		if ply ~= LocalPlayer() then return end

		net.Start("chatsounds_cmd")
			net.WriteString(text:sub(1, STR_NETWORKING_LIMIT))
		net.SendToServer()
	end

	concommand.Add("saysound", function(ply, _, _, str)
		handler(ply, str)
	end)

	concommand.Add("chatsounds_say", function(ply, _, _, str)
		handler(ply, str)
	end)

	concommand.Add("chatsounds_local_say", function(ply, _, _, str)
		if not chatsounds.Enabled then return end
		if chatsounds.Data.Loading then return end

		cs_player.PlayAsync(ply, str):next(nil, function(errors)
			for _, err in ipairs(errors) do
				chatsounds.Error(err)
			end
		end)
	end)

	net.Receive("chatsounds", function()
		if not chatsounds.Enabled then return end
		if chatsounds.Data.Loading then return end

		local ply = net.ReadEntity()
		local text = net.ReadString()

		if not IsValid(ply) then return end

		cs_player.PlayAsync(ply, text):next(nil, function(errors)
			for _, err in ipairs(errors) do
				chatsounds.Error(err)
			end
		end)
	end)

	-- this is necessary otherwise when using the first sounds with webaudio it just fails to play
	hook.Add("Initialize", "chatsounds.Player.WebAudio", function()
		chatsounds.WebAudio.Initialize()
	end)
end

if CLIENT then
	local function get_index_pairs(sound_group, ret)
		ret = ret or {}

		for _, child in ipairs(sound_group.Children) do
			if child.Type == "Sound" then
				local end_index = child.EndIndex
				if #child.Modifiers > 0 then
					table.sort(child.Modifiers, function(a, b) return a.StartIndex < b.StartIndex end)
					end_index = child.Modifiers[#child.Modifiers].EndIndex
				end

				table.insert(ret, { child.StartIndex, end_index, #child.Key })
			elseif child.Type == "group" then
				get_index_pairs(child, ret)
			end
		end

		return ret
	end

	local CS_HIDE_TEXT = CreateConVar("chatsounds_hide_text", "0", FCVAR_ARCHIVE, "Hide the chatsounds text in the chat", 0, 1)
	local BIG_CS_THRESHOLD = 200
	local MIN_PERCENTAGE_FOR_HIDING = 95
	function cs_player.ShouldHideMessage(text)
		if not chatsounds.Enabled then return false end
		if chatsounds.Data.Loading then return false end

		if not CS_HIDE_TEXT:GetBool() then return false end
		if #text < BIG_CS_THRESHOLD then return false end

		if text[1] == CONTEXT_SEPARATOR then return false end

		if chatsounds.Data.Lookup.List[text:Trim()] then return true end -- if we can easily tell its just a sound, remove

		local avg = 0
		local text_chunks = text:Split(CONTEXT_SEPARATOR)
		for _, chunk in ipairs(text_chunks) do
			local original_len = #chunk

			-- remove legacy modifiers to keep indexes from changing
			local chunk_without_legacy = chunk
			for _, modifier_base in pairs(chatsounds.Modifiers) do
				if modifier_base.LegacySyntax then
					chunk_without_legacy = chunk_without_legacy:gsub(modifier_base.LegacySyntax:PatternSafe() .. "[0-9%.]+", ""):gsub(modifier_base.LegacySyntax:PatternSafe(), "")
				end
			end

			local actual_text = ""
			local index_pairs = get_index_pairs(chatsounds.Parser.Parse(chunk_without_legacy))
			local prev_index = 1
			for i = 1, #index_pairs do
				actual_text = actual_text .. chunk_without_legacy:sub(prev_index, index_pairs[i][1] - 1)
				prev_index = index_pairs[i][2] + 1

				if index_pairs[i][3] >= BIG_CS_THRESHOLD then
					return true -- spotted a big sound, don't display
				end
			end

			actual_text = actual_text .. chunk_without_legacy:sub(prev_index)
			actual_text = actual_text:gsub("[%(%):]", ""):Trim()

			avg = avg + (#actual_text / original_len * 100)
		end

		avg = avg / #text_chunks
		if avg >= MIN_PERCENTAGE_FOR_HIDING then return true end -- don't display if it's just a bunch of sounds

		return false
	end

	hook.Add("OnPlayerChat", "chatsounds.Player.StripSounds", function(ply, text)
		if cs_player.ShouldHideMessage(text) then
			chat.AddText("Hidden chatsounds message from ", ply)
			return true
		end
	end)
end