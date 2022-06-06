local data = DEFINE_CHATSOUND_MODULE("data")

data.lookup = {}
data.ready = false

local repos = {
	{
		url = "https://github.com/Metastruct/garrysmod-chatsounds",
		msgpack = false,
	},
}

hook.Add("InitPostEntity", "chatsounds_data", function()
	local tasks = {}
	for _, repo_data in ipairs(repos) do
		local task = chatsounds.tasks.new()
		http.Fetch(repo_data.url, function(...) task:resolve(...) end, function(...) task:reject(...) end)
		table.insert(tasks, task)
	end

	chatsounds.tasks.all(tasks):next(function()

	end, function()

	end)
end)