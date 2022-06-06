module("tasks", package.seeall)
_G.chatsounds.tasks = _M

function run_task(name, fn)
	hook.Add("Think", name, fn)
end

function resolve_task(name)
	hook.Remove("Think", name)
end

function reject_task(name, err_str)
	hook.Remove("Think", name)
	error(err_str)
end

local iter = 0
function try_yield()
	if not coroutine.running() then return end

	if iter >= 10 then
		coroutine.yield()
		iter = 0
	else
		iter = iter + 1
	end
end