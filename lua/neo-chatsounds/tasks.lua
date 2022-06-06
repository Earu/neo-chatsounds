local tasks = DEFINE_CHATSOUND_MODULE("tasks")

function tasks.run(name, fn)
	hook.Add("Think", name, fn)
end

function tasks.resolve(name)
	hook.Remove("Think", name)
end

function tasks.reject(name, err_str)
	hook.Remove("Think", name)
	error(err_str)
end

local iter = 0
function tasks.try_yield()
	if not coroutine.running() then return end

	if iter >= 10 then
		coroutine.yield()
		iter = 0
	else
		iter = iter + 1
	end
end