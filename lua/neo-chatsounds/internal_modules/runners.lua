local runners = chatsounds.Module("Runners")

local runner_id = 0
function runners.Execute(fn, ...)
	local args = { ... }

	local co = coroutine.create(function() fn(unpack(args)) end)
	local runner_name = ("chatsounds.Runner[%d]"):format(runner_id)

	runner_id = runner_id + 1

	local t = chatsounds.Tasks.new()
	hook.Add("Think", runner_name, function()
		local status, result = coroutine.resume(co)
		if not status then
			hook.Remove("Think", runner_name)
			t:reject(result)
		end

		if result or coroutine.status(co) == "dead" then
			hook.Remove("Think", runner_name)
			t:resolve(result)
		end
	end)

	return t
end

local CS_RUNNER_INTERVAL = CreateConVar(
	"chatsounds_runner_interval", "2500", FCVAR_ARCHIVE,
	"The interval in iterations between each runner yield, can lower or increase perfs",
	10, 999999
)

local iter = 0
function runners.Yield(max_iters)
	if not coroutine.running() then return end

	if iter >= (max_iters or CS_RUNNER_INTERVAL:GetInt()) then
		coroutine.yield()
		iter = 0
	else
		iter = iter + 1
	end
end