local data = chatsounds.Module("Data")

data.Repositories = data.Repositories or {}
data.Lookup = data.Lookup or {
	List = {
		["sh"] = {} -- needed for stopping sounds
	},
	Dynamic = {},
}

function data.CacheRepository(repo, branch, path)
	if not file.Exists("chatsounds/repositories", "DATA") then
		file.CreateDir("chatsounds/repositories")
	end

	local json = chatsounds.Json.encode(data.Repositories[("%s/%s/%s"):format(repo, branch, path)])
	file.Write("chatsounds/repositories/" .. util.SHA1(repo .. branch .. path) .. ".json", json)
end

function data.LoadCachedRepository(repo, branch, path)
	local repo_cache_path = "chatsounds/repositories/" .. util.SHA1(repo .. branch .. path) .. ".json"

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
	local cache_path = ("chatsounds/repositories/%s.json"):format(util.SHA1(repo .. branch .. path))
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
		if rate_limited then return t end

		local is_cache_valid, hash = check_cache_validity(res.Body, repo, base_path, branch)
		if is_cache_valid and not force_recompile then
			chatsounds.Log(("%s/%s/%s is up to date, not re-compiling lists"):format(repo, branch, base_path))
			data.LoadCachedRepository(repo, branch, base_path)
			t:resolve(false)

			return t
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

				if #sound_key > 0 then
					if not data.Repositories[repo_key].List[sound_key] then
						data.Repositories[repo_key].List[sound_key] = {}
					end

					local url = ("https://raw.githubusercontent.com/%s/%s/%s/%s"):format(repo, branch, base_path, path)
					local sound_path = ("chatsounds/cache/%s/%s.ogg"):format(realm, util.SHA1(url))
					local sound_data = {
						Url = url,
						Realm = realm,
						Path = sound_path,
					}

					table.insert(data.Repositories[repo_key].List[sound_key], sound_data)
				end
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
		if rate_limited then return t end

		local is_cache_valid, hash = check_cache_validity(res.Body, repo, base_path, branch)
		if is_cache_valid and not force_recompile then
			chatsounds.Log(("%s/%s/%s is up to date, not re-compiling lists"):format(repo, branch, base_path))
			data.LoadCachedRepository(repo, branch, base_path)
			t:resolve(false)
			return t
		else
			chatsounds.Log(("Cached repository for %s/%s/%s is out of date, re-compiling..."):format(repo, branch, base_path))
		end

		local resp = chatsounds.Json.decode(res.Body)
		if not resp or not resp.tree then
			t:reject("Invalid response from GitHub:\n" .. chatsounds.Json.encode(resp))
			return t
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

				if file_data.path:GetExtensionFromFilename() == "ogg" then
					sound_count = sound_count + 1

					local path = file_data.path:gsub("^" .. base_path:PatternSafe(), "")
					local path_chunks = path:Split("/")
					local realm = path_chunks[2]:lower()
					local sound_key = path_chunks[3]:lower():gsub("%.ogg$", ""):gsub("[%_%-]", " "):gsub("[%s\t\n\r]+", " "):Trim()

					if #sound_key > 0 then
						if not data.Repositories[repo_key].List[sound_key] then
							data.Repositories[repo_key].List[sound_key] = {}
						end

						local url = ("https://raw.githubusercontent.com/%s/%s/%s"):format(repo, branch, file_data.path)
						local sound_path = ("chatsounds/cache/%s/%s.ogg"):format(realm, util.SHA1(url))
						local sound_data = {
							Url = url,
							Realm = realm,
							Path = sound_path,
						}

						table.insert(data.Repositories[repo_key].List[sound_key], sound_data)
					end
				end
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
local MAX_DYN_CHUNK_CHUNK_SIZE = 2e999 --1000
-- TODO: fix completion breaking when deeper nodes
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

				if target_node ~= cur_node then
					if not existing_node_sounds[target_node] then
						existing_node_sounds[target_node] = {}
					end

					if not existing_node_sounds[target_node][sound_key] then
						existing_node_sounds[target_node][sound_key] = true
						table.insert(target_node.Sounds, sound_key)
					end

					table.remove(cur_node.Sounds, sound_key_index)
				end
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
		for repo_name, repo in pairs(data.Repositories) do
			for sound_key, sound_list in pairs(repo.List) do
				if not lookup.List[sound_key] then
					lookup.List[sound_key] = {}
				end

				local urls = {}
				for _, sound_data in pairs(sound_list) do
					chatsounds.Runners.Yield()

					if not urls[sound_data.Url] then
						sound_data.Repository = repo_name
						table.insert(lookup.List[sound_key], sound_data)
						urls[sound_data.Url] = true

						update_loading_state()
					end
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
	local ply_to_network = {}
	hook.Add("PlayerInitialSpawn", "chatsounds.Data.RepoNetworking", function(ply)
		ply_to_network[ply] = true
	end)

	hook.Add("SetupMove", "chatsounds.Data.RepoNetworking", function(ply, _, cmd)
		if ply_to_network[ply] and not cmd:IsForced() then
			-- wait a bit before networking the config to mitigate config not being received by clients
			timer.Simple(2, function()
				if not IsValid(ply) then return end

				net.Start("chatsounds_repos")
					net.WriteString(data.RepoConfigJson)
				net.Send(ply)
			end)

			ply_to_network[ply] = nil
		end
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

local function delete_folder_recursive(path)
	local files, folders = file.Find(path .. "/*", "DATA")

	for _, f in ipairs(files) do
		file.Delete(path .. "/" .. f)
	end

	for _, folder in ipairs(folders) do
		delete_folder_recursive(path .. "/" .. folder, "DATA")
	end

	file.Delete(path)
end

concommand.Add("chatsounds_recompile_lists", function()
	delete_folder_recursive("chatsounds/cache")
	data.CompileLists()
end, nil, "Recompiles chatsounds lists lazily")

concommand.Add("chatsounds_recompile_lists_full", function()
	delete_folder_recursive("chatsounds/cache")
	delete_folder_recursive("chatsounds/repositories")
	data.CompileLists(true)
end, nil, "Fully recompile all chatsounds lists")

concommand.Add("chatsounds_clear_cache", function()
	delete_folder_recursive("chatsounds/cache")
	chatsounds.Log("Cleared cache!")
end, nil, "Clears the chatsounds sounds cache")