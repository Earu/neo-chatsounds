local runners = chatsounds.Module("Runners")

local is_sync = false
function runners.SetSynchronous(should_run_sync)
	is_sync = should_run_sync
end

local runner_id = 0
function runners.Execute(fn, ...)
	local args = { ... }

	local co = coroutine.create(function() fn(unpack(args)) end)
	local t = chatsounds.Tasks.new()

	if is_sync then
		while coroutine.status(co) ~= "dead" do
			local status, result = coroutine.resume(co)
			if not status then
				t:reject(result)
				break
			end

			if result or coroutine.status(co) == "dead" then
				t:resolve(result)
				break
			end
		end
	else
		local runner_name = ("chatsounds.Runner[%d]"):format(runner_id)
		runner_id = runner_id + 1

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
	end

	return t
end

local CS_RUNNER_INTERVAL = CreateConVar(
	"chatsounds_runner_interval", "2500", FCVAR_ARCHIVE,
	"The interval in iterations between each runner yield, can lower or increase perfs",
	10, 999999
)

local iter = 0
function runners.Yield(max_iters)
	if is_sync then return end
	if not coroutine.running() then return end

	if iter >= (max_iters or CS_RUNNER_INTERVAL:GetInt()) then
		coroutine.yield()
		iter = 0
	else
		iter = iter + 1
	end
end

function runners.PushValue(value)
	if is_sync then return value end
	if not coroutine.running() then return value end

	return coroutine.yield(value)
end