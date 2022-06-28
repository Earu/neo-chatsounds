local data = chatsounds.Module("Data")

data.Repositories = data.Repositories or {}
data.Lookup = data.Lookup or {
	List = {
		["sh"] = {} -- needed for stopping sounds
	},
	Dynamic = {},
}

function data.CacheRepository(repo, branch, path)
	if not file.Exists("chatsounds/repos", "DATA") then
		file.CreateDir("chatsounds/repos")
	end

	local json = chatsounds.Json.encode(data.Repositories[("%s/%s/%s"):format(repo, branch, path)])
	file.Write("chatsounds/repos/" .. util.SHA1(repo .. branch .. path) .. ".json", json)
end

function data.LoadCachedRepository(repo, branch, path)
	local repo_cache_path = "chatsounds/repos/" .. util.SHA1(repo .. branch .. path) .. ".json"

	if not file.Exists(repo_cache_path, "DATA") then return end

	local json = file.Read(repo_cache_path, "DATA")
	data.Repositories[("%s/%s/%s"):format(repo, branch, path)] = chatsounds.Json.decode(json)
end

local function update_loading_state()
	if data.Loading then
		data.Loading.Current = data.Loading.Current + 1

		local cur_perc = math.max(0, math.min(100, math.Round((data.Loading.Current / math.max(1, data.Loading.Target)) * 100)))
		if cur_perc % 10 == 0 and cur_perc ~= data.Loading.LastLoggedPercent and (CLIENT or (SERVER and game.IsDedicated())) then
			data.Loading.LastLoggedPercent = cur_perc
			chatsounds.Log((data.Loading.Text):format(cur_perc))
		end
	end
end

local function handle_rate_limit(http_res, base_task, task_fn, ...)
	if http_res.Status == 429 or http_res.Status == 503 or http_res.Status == 403 then
		local delay = tonumber(http_res.Headers["Retry-After"] or http_res.Headers["retry-after"])
		if not delay then
			base_task:reject("Github API rate limit exceeded")
			return true
		end

		local args = { ... }
		timer.Simple(delay + 1, function()
			task_fn(unpack(args)):next(function(...)
				base_task:resolve(...)
			end, function(err)
				base_task:reject(err)
			end)
		end)

		chatsounds.Log(("Github API rate limit exceeded, retrying in %s seconds"):format(delay))
		return true
	end

	return false
end

local function check_cache_validity(body, repo, path, branch)
	local hash = util.SHA1(body)
	local cache_path = ("chatsounds/repos/%s.json"):format(util.SHA1(repo .. branch .. path))
	if file.Exists(cache_path, "DATA") then
		chatsounds.Log(("Found cached repository for %s/%s/%s, validating content..."):format(repo, branch, path))

		local cache_contents = file.Read(cache_path, "DATA")
		local cached_repo = chatsounds.Json.decode(cache_contents)
		local cached_hash = cached_repo.Hash
		return cached_hash == hash, hash
	end

	return false, hash
end

function data.BuildFromGitHubMsgPack(repo, branch, base_path, force_recompile)
	branch = branch or "master"

	local msg_pack_url = ("https://raw.githubusercontent.com/%s/%s/%s/list.msgpack"):format(repo, branch, base_path)
	local t = chatsounds.Tasks.new()
	chatsounds.Http.Get(msg_pack_url):next(function(res)
		local rate_limited = handle_rate_limit(res, t, data.BuildFromGitHubMsgPack, repo, branch, base_path, force_recompile)
		if rate_limited then return end

		local is_cache_valid, hash = check_cache_validity(res.Body, repo, base_path, branch)
		if is_cache_valid and not force_recompile then
			chatsounds.Log(("%s/%s/%s is up to date, not re-compiling lists"):format(repo, branch, base_path))
			data.LoadCachedRepository(repo, branch, base_path)
			t:resolve(false)

			return
		else
			chatsounds.Log(("Cached repository for %s/%s/%s is out of date, re-compiling..."):format(repo, branch, base_path))
		end

		local contents = chatsounds.MsgPack.unpack(res.Body)
		if data.Loading then
			data.Loading.Target = data.Loading.Target + #contents
		end

		local start_time = SysTime()
		local sound_count = 0
		local repo_key = ("%s/%s/%s"):format(repo, branch, base_path)
		if not data.Repositories[repo_key] then
			data.Repositories[repo_key] = {
				Hash = hash,
				List = {},
			}
		end

		chatsounds.Runners.Execute(function()
			for i, raw_sound_data in pairs(contents) do
				chatsounds.Runners.Yield()

				update_loading_state()

				sound_count = sound_count + 1

				local realm = raw_sound_data[1]:lower()
				local sound_key = raw_sound_data[2]:lower():gsub("%.ogg$", ""):gsub("[%_%-]", " "):gsub("[%s\t\n\r]+", " ")
				local path = raw_sound_data[3]

				if #sound_key == 0 then continue end

				if not data.Repositories[repo_key].List[sound_key] then
					data.Repositories[repo_key].List[sound_key] = {}
				end

				local url = ("https://raw.githubusercontent.com/%s/%s/%s/%s"):format(repo, branch, base_path, path):gsub("%s", "%%20")
				local sound_path = ("chatsounds/cache/%s/%s.ogg"):format(realm, util.SHA1(url))
				local sound_data = {
					Url = url,
					Realm = realm,
					Path = sound_path,
				}

				table.insert(data.Repositories[repo_key].List[sound_key], sound_data)
			end

			data.CacheRepository(repo, branch, base_path)
			t:resolve(true)
			chatsounds.Log(("Compiled %d sounds from %s/%s/%s in %s second(s)"):format(sound_count, repo, branch, base_path, tostring(SysTime() - start_time)))
		end):next(nil, function(err) t:reject(err) end)
	end, function(err) t:reject(err) end)

	return t
end

function data.BuildFromGithub(repo, branch, base_path, force_recompile)
	branch = branch or "master"

	local api_url = ("https://api.github.com/repos/%s/git/trees/%s?recursive=1"):format(repo, branch)
	local t = chatsounds.Tasks.new()
	chatsounds.Http.Get(api_url):next(function(res)
		local rate_limited = handle_rate_limit(res, t, data.BuildFromGithub, repo, branch, base_path, force_recompile)
		if rate_limited then return end

		local is_cache_valid, hash = check_cache_validity(res.Body, repo, base_path, branch)
		if is_cache_valid and not force_recompile then
			chatsounds.Log(("%s/%s/%s is up to date, not re-compiling lists"):format(repo, branch, base_path))
			data.LoadCachedRepository(repo, branch, base_path)
			t:resolve(false)

			return
		else
			chatsounds.Log(("Cached repository for %s/%s/%s is out of date, re-compiling..."):format(repo, branch, base_path))
		end

		local resp = chatsounds.Json.decode(res.Body)
		if not resp or not resp.tree then
			t:reject("Invalid response from GitHub:\n" .. chatsounds.Json.encode(resp))
			return
		end

		if data.Loading then
			data.Loading.Target = data.Loading.Target + #resp.tree
		end

		local start_time = SysTime()
		local sound_count = 0
		local repo_key = ("%s/%s/%s"):format(repo, branch, base_path)
		if not data.Repositories[repo_key] then
			data.Repositories[repo_key] = {
				Hash = hash,
				List = {},
			}
		end

		chatsounds.Runners.Execute(function()
			for i, file_data in pairs(resp.tree) do
				chatsounds.Runners.Yield()

				update_loading_state()

				if file_data.path:GetExtensionFromFilename() ~= "ogg" then continue end

				sound_count = sound_count + 1

				local path = file_data.path:gsub("^" .. base_path:PatternSafe(), "")
				local path_chunks = path:Split("/")
				local realm = path_chunks[2]:lower()
				local sound_key = path_chunks[3]:lower():gsub("%.ogg$", ""):gsub("[%_%-]", " "):gsub("[%s\t\n\r]+", " "):Trim()

				if #sound_key == 0 then continue end

				if not data.Repositories[repo_key].List[sound_key] then
					data.Repositories[repo_key].List[sound_key] = {}
				end

				local url = ("https://raw.githubusercontent.com/%s/%s/%s"):format(repo, branch, file_data.path):gsub("%s", "%%20")
				local sound_path = ("chatsounds/cache/%s/%s.ogg"):format(realm, util.SHA1(url))
				local sound_data = {
					Url = url,
					Realm = realm,
					Path = sound_path,
				}

				table.insert(data.Repositories[repo_key].List[sound_key], sound_data)
			end

			data.CacheRepository(repo, branch, base_path)
			t:resolve(true)
			chatsounds.Log(("Compiled %d sounds from %s/%s/%s in %s second(s)"):format(sound_count, repo, branch, base_path, tostring(SysTime() - start_time)))
		end):next(nil, function(err) t:reject(err) end)
	end, function(err) t:reject(err) end)

	return t
end

-- Dynamically expanding table, this took me a while to figure out so I'll try to explain it.
-- Because the lookup for the sound key of chatsounds is that large, its not appropriate to iterate over it for suggestions.
-- The time complexity would be O(n) and essentially the game would freeze for 5/10 seconds each time you type a character.
-- The idea here is to subdivide the sound keys into recursive chunks of 1000 sounds MAX each.
-- They can be then indexed by the depth marked at first level of the table e.g (lookup.Dynamic['g'].__depth or 1).
-- Depending on the depth we may have something like: lookup.Dynamic = { ['g'] = { __depth = 2, ['a'] = { "im looking at gay porno", "gay porno", "gay" } } }
-- By diving sound keys into chunks we ensure that the time complexity needed to build a suggestion list is minimal because accessing a table with a hash key is O(1),
-- that brings the total time complexity to somewhere around O(d + n) where d is the depth and n the amount of sound keys at that depth.
-- Building this kind of lookup however is very expensive, which is why it should only be done ONCE, and then CACHED if possible.
local MAX_DYN_CHUNK_CHUNK_SIZE = 1000
local function build_dynamic_lookup(dyn_lookup, sound_key, existing_node_sounds)
	local words = sound_key:Split(" ")

	if data.Loading then
		data.Loading.Target = data.Loading.Target + #words
	end

	for _, word_key in ipairs(words) do
		chatsounds.Runners.Yield()

		local first_char = word_key[1]
		if not dyn_lookup[first_char] then
			dyn_lookup[first_char] = {
				Sounds = {},
				Keys = {},
			}
		end

		local root_node = dyn_lookup[first_char]
		local cur_node = dyn_lookup[first_char]
		if root_node.__depth then
			for i = 2, #word_key do
				local char = word_key[i]
				if not cur_node.Keys[char] then break end

				cur_node = cur_node.Keys[char]
			end
		end

		if not existing_node_sounds[cur_node] then
			existing_node_sounds[cur_node] = {}
		end

		if not existing_node_sounds[cur_node][sound_key] then
			existing_node_sounds[cur_node][sound_key] = true
			table.insert(cur_node.Sounds, sound_key)
		end

		if #cur_node.Sounds >= MAX_DYN_CHUNK_CHUNK_SIZE then
			local depth = root_node.__depth or 1
			for sound_key_index, chunked_sound_key in ipairs(cur_node.Sounds) do
				local target_node = cur_node
				for i = depth, #chunked_sound_key do
					chatsounds.Runners.Yield()

					local char = chunked_sound_key[i]
					if not char then break end

					if not cur_node.Keys[char] then
						cur_node.Keys[char] = {
							Sounds = {},
							Keys = {},
						}
					end

					target_node = cur_node.Keys[char]
				end

				if target_node == cur_node then continue end

				if not existing_node_sounds[target_node] then
					existing_node_sounds[target_node] = {}
				end

				if not existing_node_sounds[target_node][sound_key] then
					existing_node_sounds[target_node][sound_key] = true
					table.insert(target_node.Sounds, sound_key)
				end

				table.remove(cur_node.Sounds, sound_key_index)
			end

			root_node.__depth = depth + 1
		end

		update_loading_state()
	end
end

local function compute_dynamic_lookup_hash()
	return util.SHA1(table.concat(table.GetKeys(data.Repositories), ";"))
end

local function merge_repos(rebuild_dynamic_lookup)
	local should_build_dynamic = false
	if CLIENT then
		if rebuild_dynamic_lookup or not file.Exists("chatsounds/dyn_lookup.json", "DATA") then
			should_build_dynamic = true
		end

		if
			not rebuild_dynamic_lookup
			and file.Exists("chatsounds/dyn_lookup.json", "DATA")
			and compute_dynamic_lookup_hash() ~= cookie.GetString("chatsounds_dyn_lookup")
		then
			should_build_dynamic = true
		end
	end

	return chatsounds.Runners.Execute(function()
		local lookup = {
			List = {
				["sh"] = {} -- needed for stopping sounds
			},
			Dynamic = {},
		}

		if not should_build_dynamic then
			local json = file.Read("chatsounds/dyn_lookup.json", "DATA")
			if not json then
				should_build_dynamic = true
			else
				lookup.Dynamic = chatsounds.Json.decode(json)
			end
		end

		local existing_node_sounds = {}
		for _, repo in pairs(data.Repositories) do
			for sound_key, sound_list in pairs(repo.List) do
				if not lookup.List[sound_key] then
					lookup.List[sound_key] = {}
				end

				local urls = {}
				for _, sound_data in pairs(sound_list) do
					chatsounds.Runners.Yield()

					if urls[sound_data.Url] then continue end
					table.insert(lookup.List[sound_key], sound_data)
					urls[sound_data.Url] = true

					update_loading_state()
				end

				table.sort(lookup.List[sound_key], function(a, b) return a.Url < b.Url end) -- preserve indexes unless a new sound is added

				if should_build_dynamic then
					build_dynamic_lookup(lookup.Dynamic, sound_key, existing_node_sounds)
				end
			end
		end

		if should_build_dynamic then
			local json = chatsounds.Json.encode(lookup.Dynamic)
			file.Write("chatsounds/dyn_lookup.json", json)
			cookie.Set("chatsounds_dyn_lookup", compute_dynamic_lookup_hash())
		end

		data.Lookup = lookup
	end)
end

local function prepare_default_config()
	local default_config = {}
	local valve_folders = { "csgo", "css", "ep1", "ep2", "hl1", "hl2", "l4d", "l4d2", "portal", "tf2" }
	for _, valve_folder in ipairs(valve_folders) do
		table.insert(default_config, {
			Repo = "PAC3-Server/chatsounds-valve-games",
			Branch = "master",
			BasePath = valve_folder,
			UseMsgPack = true,
		})
	end

	return default_config, SERVER and chatsounds.Json.encode(default_config) or nil
end

if SERVER then
	util.AddNetworkString("chatsounds_repos")

	local STR_NETWORKING_LIMIT = 60000
	local function load_custom_config()
		if not file.Exists("chatsounds/repo_config.json", "DATA") then
			file.CreateDir("chatsounds")

			local default_config, default_json = prepare_default_config()
			file.Write("chatsounds/repo_config.json", default_json)

			return default_config, default_json
		end

		local custom_json = file.Read("chatsounds/repo_config.json", "DATA") or ""
		if #custom_json > STR_NETWORKING_LIMIT then
			chatsounds.Error("Failed to load repo_config.json: Your config file is too big!")
			return prepare_default_config()
		end

		local success, err = pcall(chatsounds.Json.decode, custom_json)
		if not success then
			chatsounds.Error("Failed to load repo_config.json: " .. err)
			return prepare_default_config()
		end

		return err, custom_json
	end

	local custom_config, custom_json = load_custom_config()
	data.RepoConfig = custom_config
	data.RepoConfigJson = custom_json

	hook.Add("Initialize", "chatsounds.Data", function()
		data.CompileLists()
	end)

	-- hack to know when we are able to broadcast the config to clients
	hook.Add("PlayerInitialSpawn", "chatsounds.Data.PlayerFullLoad", function(ply)
		hook.Add("SetupMove", ply, function(self, ply, _, cmd)
			if self == ply and not cmd:IsForced() then
				hook.Run("PlayerFullLoad", self)
				hook.Remove("SetupMove", self)
			end
		end)
	end)

	hook.Add("PlayerFullLoad", "chatsounds.Data.Config", function(ply)
		-- wait a bit before networking the config to mitigate config not being received by clients
		timer.Simple(2, function()
			net.Start("chatsounds_repos")
				net.WriteString(data.RepoConfigJson)
			net.Send(ply)
		end)
	end)
end

if CLIENT then
	data.RepoConfig = data.RepoConfig or prepare_default_config()

	net.Receive("chatsounds_repos", function()
		chatsounds.Log("Received server repo config!")

		local json = net.ReadString()
		data.RepoConfig = chatsounds.Json.decode(json)
		data.CompileLists()
	end)
end

function data.CompileLists(force_recompile)
	data.Loading = {
		Current = 0,
		Target = 0,
		Text = "Loading chatsounds... %d%%",
		DisplayPerc = true,
	}

	local repo_tasks = {}
	for _, repo_data in ipairs(data.RepoConfig) do
		if repo_data.UseMsgPack then
			table.insert(repo_tasks, data.BuildFromGitHubMsgPack(
				repo_data.Repo,
				repo_data.Branch,
				repo_data.BasePath,
				force_recompile
			))
		else
			table.insert(repo_tasks, data.BuildFromGithub(
				repo_data.Repo,
				repo_data.Branch,
				repo_data.BasePath,
				force_recompile
			))
		end
	end

	--[[
		data.BuildFromGithub("Metastruct/garrysmod-chatsounds", "master", "sound/chatsounds/autoadd", force_recompile),
		data.BuildFromGithub("PAC3-Server/chatsounds", "master", "sounds/chatsounds", force_recompile),

		data.BuildFromGitHubMsgPack("PAC3-Server/chatsounds-valve-games", "master", "csgo", force_recompile),
		data.BuildFromGitHubMsgPack("PAC3-Server/chatsounds-valve-games", "master", "css", force_recompile),
		data.BuildFromGitHubMsgPack("PAC3-Server/chatsounds-valve-games", "master", "ep1", force_recompile),
		data.BuildFromGitHubMsgPack("PAC3-Server/chatsounds-valve-games", "master", "ep2", force_recompile),
		data.BuildFromGitHubMsgPack("PAC3-Server/chatsounds-valve-games", "master", "hl1", force_recompile),
		data.BuildFromGitHubMsgPack("PAC3-Server/chatsounds-valve-games", "master", "hl2", force_recompile),
		data.BuildFromGitHubMsgPack("PAC3-Server/chatsounds-valve-games", "master", "l4d", force_recompile),
		data.BuildFromGitHubMsgPack("PAC3-Server/chatsounds-valve-games", "master", "l4d2", force_recompile),
		data.BuildFromGitHubMsgPack("PAC3-Server/chatsounds-valve-games", "master", "portal", force_recompile),
		data.BuildFromGitHubMsgPack("PAC3-Server/chatsounds-valve-games", "master", "tf2", force_recompile),
	]]--

	local repo_processing = false
	local function process_repos(rebuild_dynamic_lookup)
		if repo_processing then return end

		repo_processing = true

		data.Loading.Current = 0
		data.Loading.Text = "Merging chatsounds repositories... %d%%"

		merge_repos(rebuild_dynamic_lookup):next(function()
			data.Loading = nil
			chatsounds.Log("Done compiling all lists")
			hook.Run("ChatsoundsInitialized")
		end, function(err)
			data.Loading = nil
			chatsounds.Error(err)
			hook.Run("ChatsoundsInitialized")
		end)
	end

	local time_in_secs = 0
	timer.Create("chatsounds_repos", 1, 0, function()
		if not data.Loading then
			timer.Remove("chatsounds_repos")
			return
		end

		if data.Loading.Target <= data.Loading.Current then
			process_repos(false)
			timer.Remove("chatsounds_repos")
		end

		time_in_secs = time_in_secs + 1
		if time_in_secs >= 60 * 5 then
			process_repos(false)
			timer.Remove("chatsounds_repos")
		end
	end)

	chatsounds.Tasks.all(repo_tasks):next(function(results)
		local rebuild_dynamic_lookup = force_recompile
		if not force_recompile then
			for _, recompiled in ipairs(results) do
				if recompiled then
					rebuild_dynamic_lookup = true
					break
				end
			end
		end

		process_repos(rebuild_dynamic_lookup)
	end, function(errors)
		for _, err in ipairs(errors) do
			chatsounds.Error(err)
		end

		process_repos(false)
	end)
end

if not concommand.GetTable().chatsounds_recompile_lists then
	data.Loading = {
		Current = -1,
		Target = -1,
		Text = "Initializing chatsounds...",
		DisplayPerc = false,
	}
end

concommand.Add("chatsounds_recompile_lists", function()
	data.CompileLists()
end)

concommand.Add("chatsounds_recompile_lists_full", function()
	data.CompileLists(true)
end)

if CLIENT then
	surface.CreateFont("chatsounds.Completion", {
		font = "Roboto",
		size = 20,
		weight = 500,
		antialias = true,
		additive = false,
		extended = true,
		shadow = true,
	})

	surface.CreateFont("chatsounds.Completion.Shadow", {
		font = "Roboto",
		size = 20,
		weight = 500,
		antialias = true,
		additive = false,
		blursize = 1,
		extended = true,
		shadow = true,
	})

	local SHADOW_COLOR = Color(0, 0, 0, 255)
	local surface_SetFont = surface.SetFont
	local surface_SetTextPos = surface.SetTextPos
	local surface_SetTextColor = surface.SetTextColor
	local surface_DrawText = surface.DrawText
	local function draw_shadowed_text(text, x, y, r, g, b, a)
		surface_SetFont("chatsounds.Completion.Shadow")
		surface_SetTextColor(SHADOW_COLOR)

		for _ = 1, 5 do
			surface_SetTextPos(x, y)
			surface_DrawText(text)
		end

		surface_SetFont("chatsounds.Completion")
		surface_SetTextColor(r, g, b, a)
		surface_SetTextPos(x, y)
		surface_DrawText(text)
	end

	hook.Add("HUDPaint", "chatsounds.Data.Loading", function()
		if not data.Loading then return end
		if not LocalPlayer():IsTyping() then return end
		if not chatsounds.Enabled then return end

		local chat_x, chat_y = chat.GetChatBoxPos()
		local _, chat_h = chat.GetChatBoxSize()
		if data.Loading.DisplayPerc then
			local text = (data.Loading.Text):format(math.max(0, math.min(100, math.Round((data.Loading.Current / data.Loading.Target) * 100))))
			draw_shadowed_text(text, chat_x, chat_y + chat_h + 5, 255, 255, 255, 255)
		else
			draw_shadowed_text(data.Loading.Text, chat_x, chat_y + chat_h + 5, 255, 255, 255, 255)
		end
	end)

	data.Suggestions = data.Suggestions or {}
	data.SuggestionsIndex = -1
	hook.Add("ChatTextChanged", "chatsounds.Data.Completion", function(text)
		if not chatsounds.Enabled then return end

		data.BuildCompletionSuggestions(text)
	end)

	hook.Add("OnChatTab", "chatsounds.Data.Completion", function(text)
		if not chatsounds.Enabled then return end

		local scroll = (input.IsButtonDown(KEY_LSHIFT) or input.IsButtonDown(KEY_RSHIFT) or input.IsKeyDown(KEY_LCONTROL)) and -1 or 1
		data.SuggestionsIndex = (data.SuggestionsIndex + scroll) % #data.Suggestions

		return data.Suggestions[data.SuggestionsIndex + 1]
	end)

	local function add_nested_suggestions(node, text, nested_suggestions, added_suggestions)
		for _, sound_key in ipairs(node.Sounds) do
			if sound_key:find(text, 1, true) and not added_suggestions[sound_key] then
				table.insert(nested_suggestions, sound_key)
				added_suggestions[sound_key] = true
			end
		end

		for key, child_node in pairs(node.Keys) do
			add_nested_suggestions(child_node, text, nested_suggestions, added_suggestions)
		end
	end

	function data.BuildCompletionSuggestions(text)
		text = text:gsub("[%s\n\r\t]+"," "):gsub("[\"\']", ""):Trim()

		if #text == 0 then
			data.Suggestions = {}
			data.SuggestionsIndex = -1
			return
		end

		local suggestions = {}
		local added_suggestions = {}

		local search_words = text:Split(" ")
		local last_word = search_words[#search_words]

		local MODIFIER_PATTERN = ":([%w_]+)[%[%]%(%w%s,%.]*$"
		local modifier = text:match(MODIFIER_PATTERN)
		local arguments = text:match(":[%w_]+%(([%[%]%w%s,%.]*)$")
		if modifier then
			local without_modifier = text:gsub(MODIFIER_PATTERN, "")
			if not arguments then
				for name, _ in pairs(chatsounds.Modifiers) do
					if not name:StartWith(modifier) or added_suggestions[name] then continue end

					suggestions[#suggestions + 1] = without_modifier .. ":" .. name
					added_suggestions[name] = true
				end
			else
				local mod = chatsounds.Modifiers[modifier]
				if not mod then
					data.SuggestionsIndex = -1
					data.Suggestions = suggestions
					return
				end

				local suggest_arguments = arguments
				local split_args = arguments:Split(",")

				if type(mod.DefaultValue) == "table" then
					local types = {}
					local current_amount = 0
					local append_comma = true
					for _, v in ipairs(split_args) do
						local is_empty = v:Trim():len() == 0
						append_comma = not is_empty and append_comma
						current_amount = current_amount + (is_empty and 0 or 1)
					end

					for i, value in ipairs(mod.DefaultValue) do
						local comma = append_comma and i == current_amount + 1
						types[math.max(i - current_amount, 1)] = (comma and ", " or "") .. "[" .. type(value) .. "]"
					end

					if #mod.DefaultValue ~= current_amount then
						suggest_arguments = suggest_arguments .. table.concat(types, ", "):sub(1, -1)
					end
				elseif split_args[1]:Trim():len() == 0 then
					suggest_arguments = suggest_arguments ..
						"[" .. type(mod.DefaultValue) .. "]"
				end

				suggestions[#suggestions + 1] = without_modifier .. ":" .. modifier .. "(" .. suggest_arguments .. ")"
			end

			data.SuggestionsIndex = -1
			data.Suggestions = suggestions
			return
		end

		local sounds = {}
		local node = data.Lookup.Dynamic[last_word[1]]
		if node then
			if node.__depth then
				for i = 2, #last_word do
					if not last_word[i] then break end

					local next_node = node.Keys[last_word[i]]
					if not next_node then break end

					node = next_node
				end

				sounds = node.Sounds

				for _, child_node in pairs(node.Keys) do
					add_nested_suggestions(child_node, text, suggestions, added_suggestions)
				end
			else
				sounds = node.Sounds
			end
		end

		for _, sound_key in ipairs(sounds) do
			if sound_key:find(text, 1, true) and not added_suggestions[sound_key] then
				table.insert(suggestions, sound_key)
				added_suggestions[sound_key] = true
			end
		end

		table.sort(suggestions, function(a, b)
			if #a ~= #b then
				return #a < #b
			end
			return a < b
		end)

		data.SuggestionsIndex = -1
		data.Suggestions = suggestions
	end

	local FONT_HEIGHT = 20
	local COMPLETION_SEP = "=================="
	hook.Add("HUDPaint", "chatsounds.Data.Completion", function()
		if data.Loading then return end
		if #data.Suggestions == 0 then return end
		if not chatsounds.Enabled then return end
		if not LocalPlayer():IsTyping() then return end

		local chat_x, chat_y = chat.GetChatBoxPos()
		local _, chat_h = chat.GetChatBoxSize()

		local i = 1
		local base_x, base_y = chat_x, chat_y + chat_h + 5
		for index = data.SuggestionsIndex + 1, #data.Suggestions + (#data.Suggestions - data.SuggestionsIndex + 1) do
			local suggestion = data.Suggestions[index]
			if not suggestion then continue end

			local x, y = base_x, base_y + (i - 1) * FONT_HEIGHT
			if y > ScrH() then return end

			draw_shadowed_text(("%03d."):format(index), x, y, 200, 200, 255, 255)

			if index == data.SuggestionsIndex + 1 then
				draw_shadowed_text(suggestion, x + 50, y, 255, 0, 0, 255)
			else
				draw_shadowed_text(suggestion, x + 50, y, 255, 255, 255, 255)
			end

			i = i + 1
		end

		if data.SuggestionsIndex + 1 ~= 1 then
			draw_shadowed_text(COMPLETION_SEP, base_x, base_y + (i - 1) * FONT_HEIGHT, 180, 180, 255, 255)
			i = i + 1
		end

		for j = 1, data.SuggestionsIndex do
			local suggestion = data.Suggestions[j]
			if not suggestion then continue end

			local x, y = base_x, base_y + (i - 1) * FONT_HEIGHT
			if y > ScrH() then return end

			draw_shadowed_text(("%03d."):format(j), x, y, 200, 200, 255, 255)
			draw_shadowed_text(suggestion, x + 50, y, 255, 255, 255, 255)

			i = i + 1
		end
	end)
end