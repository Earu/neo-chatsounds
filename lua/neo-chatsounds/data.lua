local data = chatsounds.Module("Data")

data.Lookup = {}

local function http_get(url)
	local t = chatsounds.Tasks.new()
	http.Fetch(url, function(...)
		t:resolve(...)
	end, function(err)
		t:reject(err)
	end)

	return t
end

local function cache_lookup()
	if not file.Exists("chatsounds", "DATA") then
		file.CreateDir("chatsounds")
	end

	local json = util.TableToJSON(data.Lookup)
	file.Write("chatsounds/lookup.json", json)
end

local function load_lookup()
	if not file.Exists("chatsounds/lookup.json", "DATA") then return end

	local json = file.Read("chatsounds/lookup.json", "DATA")
	data.Lookup = util.JSONToTable(json)
end

local function build_from_meta_github()
	local api_url = "https://api.github.com/repos/Metastruct/garrysmod-chatsounds/git/trees/master?recursive=1"
	local t = chatsounds.Tasks.new()
	http_get(api_url):next(function(body)
		local hash = util.CRC(body)
		if cookie.GetString("chatsounds_meta_hash") == hash then
			chatsounds.Log("Meta chatsounds, no changes detected, not re-compiling lists")
			--t:resolve(false)
			--return
		end

		local resp = util.JSONToTable(body)
		if not resp or not resp.tree then
			t:reject("Invalid response from GitHub")
			return
		end

		chatsounds.Runners.Execute(function()
			local http_requests = {}
			for i, file_data in pairs(resp.tree) do
				chatsounds.Runners.Yield(1000)

				if not file_data.path:match("^lua%/chatsounds%/lists%_nosend%/.*%.lua") then continue end

				local list_url = "https://raw.githubusercontent.com/Metastruct/garrysmod-chatsounds/master/" .. file_data.path
				local http_t = chatsounds.Tasks.new()
				table.insert(http_requests, http_t)

				http_get(list_url):next(function(lua)
					local fn = CompileString(lua, "chatsounds_list: " .. file_data.path, false)
					if isstring(fn) then
						local err = "Failed to compile list: " .. fn
						chatsounds.Error(err)
						http_t:resolve()
						return
					end

					local list_lookup = {}
					local list_name = "unknown"
					setfenv(fn, {
						c = {
							StartList = function(name)
								list_name = name
								chatsounds.Log("Compiling list: " .. name)
							end,
							EndList = function()
								chatsounds.Log("Done compiling: " .. list_name)
							end,
						},
						L = list_lookup
					})

					local success, err = pcall(fn)
					if not success then
						local err_msg = ("Error compiling chatsounds list \'%s\': %s"):format(list_name, err)
						chatsounds.Error(err_msg)
						http_t:resolve()
						return
					end

					for sound_key, sound_data in pairs(list_lookup) do
						if #sound_data == 0 then continue end

						if not data.Lookup[sound_key] then
							data.Lookup[sound_key] = {}
						end

						table.insert(data.Lookup[sound_key], {
							list = list_name,
							list_url = "https://raw.githubusercontent.com/Metastruct/garrysmod-chatsounds/master/",
							sounds = sound_data
						})
					end

					http_t:resolve()
				end, chatsounds.Error)
			end

			chatsounds.Tasks.all(http_requests):next(function(res) t:resolve(true) end)
		end)
	end)

	return t
end

local function build_source_sounds_github(repo)
end

hook.Add("InitPostEntity", "chatsounds.Data", function()
	load_lookup() -- always load the cache for the lookup, it will get overriden later if necessary

	chatsounds.Tasks.all({
		build_from_meta_github(),
		build_source_sounds_github("Metastruct/garrysmod-chatsounds")
	}):next(function(results)
		for _, recompiled in pairs(results) do
			if recompiled then
				cache_lookup()
				break
			end
		end

		chatsounds.Log("Done compiling lists from meta")
	end, function(errors)
		for _, err in pairs(errors) do
			chatsounds.Error(err)
		end
	end)
end)