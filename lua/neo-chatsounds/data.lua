local data = DEFINE_CHATSOUND_MODULE("data")

data.lookup = {}

local function http_get(url)
	local t = chatsounds.tasks.new()
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

	local json = util.TableToJSON(data.lookup)
	file.Write("chatsounds/lookup.json", json)
end

local function load_lookup()
	if not file.Exists("chatsounds/lookup.json", "DATA") then return end

	local json = file.Read("chatsounds/lookup.json", "DATA")
	data.lookup = util.JSONToTable(json)
end

local function build_from_meta_github()
	local api_url = "https://api.github.com/repos/Metastruct/garrysmod-chatsounds/git/trees/master?recursive=1"
	local t = chatsounds.tasks.new()
	http_get(api_url):next(function(body)
		local hash = util.CRC(body)
		if cookie.GetString("chatsounds_meta_hash") == hash then
			chatsounds.log("Meta chatsounds, no changes detected, not re-compiling lists")
			--t:resolve(false)
			--return
		end

		local resp = util.JSONToTable(body)
		if not resp or not resp.tree then
			t:reject("Invalid response from GitHub")
			return
		end

		chatsounds.tasks.execute_runner(function()
			local http_requests = {}
			for i, file_data in pairs(resp.tree) do
				chatsounds.tasks.yield_runner(1000)

				if not file_data.path:match("^lua%/chatsounds%/lists%_nosend%/.*%.lua") then continue end

				local list_url = "https://raw.githubusercontent.com/Metastruct/garrysmod-chatsounds/master/" .. file_data.path
				local http_t = chatsounds.tasks.new()
				table.insert(http_requests, http_t)

				http_get(list_url):next(function(lua)
					local fn = CompileString(lua, "chatsounds_list: " .. file_data.path, false)
					if isstring(fn) then
						local err = "Failed to compile list: " .. fn
						chatsounds.error(err)
						http_t:resolve()
						return
					end

					local list_lookup = {}
					local list_name = "unknown"
					setfenv(fn, {
						c = {
							StartList = function(name)
								list_name = name
								chatsounds.log("Compiling list: " .. name)
							end,
							EndList = function()
								chatsounds.log("Done compiling: " .. list_name)
							end,
						},
						L = list_lookup
					})

					local success, err = pcall(fn)
					if not success then
						local err_msg = ("Error compiling chatsounds list \'%s\': %s"):format(list_name, err)
						chatsounds.error(err_msg)
						http_t:resolve()
						return
					end

					for sound_key, sound_data in pairs(list_lookup) do
						if #sound_data == 0 then continue end

						if not data.lookup[sound_key] then
							data.lookup[sound_key] = {}
						end

						table.insert(data.lookup[sound_key], {
							list = list_name,
							list_url = "https://raw.githubusercontent.com/Metastruct/garrysmod-chatsounds/master/",
							sounds = sound_data
						})
					end

					http_t:resolve()
				end, chatsounds.error)
			end

			chatsounds.tasks.all(http_requests):next(function(res) t:resolve(true) end)
		end)
	end)

	return t
end

local function build_source_sounds_github(repo)
end

hook.Add("InitPostEntity", "chatsounds_data_builder", function()
	load_lookup() -- always load the cache for the lookup, it will get overriden later if necessary

	chatsounds.tasks.all({
		build_from_meta_github(),
		build_source_sounds_github("Metastruct/garrysmod-chatsounds")
	}):next(function(results)
		for _, recompiled in pairs(results) do
			if recompiled then
				cache_lookup()
				break
			end
		end

		chatsounds.log("Done compiling lists from meta")
	end, function(errors)
		for _, err in pairs(errors) do
			chatsounds.error(err)
		end
	end)
end)