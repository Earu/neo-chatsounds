local expressions = DEFINE_CHATSOUND_MODULE("expressions")

local lua_str_env = {
	PI = math.pi,
	pi = math.pi,
	rand = math.random,
	random = math.random,
	randomf = math.randomf,
	abs = math.abs,
	sgn = function (x)
		if x < 0 then return -1 end
		if x > 0 then return  1 end
		return 0
	end,

	acos = math.acos,
	asin = math.asin,
	atan = math.atan,
	atan2 = math.atan2,
	ceil = math.ceil,
	cos = math.cos,
	cosh = math.cosh,
	deg = math.deg,
	exp = math.exp,
	floor = math.floor,
	frexp = math.frexp,
	ldexp = math.ldexp,
	log = math.log,
	log10 = math.log10,
	max = math.max,
	min = math.min,
	rad = math.rad,
	sin = math.sin,
	sinc = function(x)
		if x == 0 then return 1 end
		return math.sin(x) / x
	end,
	sinh = math.sinh,
	sqrt = math.sqrt,
	tanh = math.tanh,
	tan = math.tan,

	clamp = math.clamp,
	pow = math.pow,
	clock = os.clock,
}

local blacklisted_syntax = { "repeat", "until", "function", "end", "\"", "\'", "%[=*%[", "%]=*%]", ":" }

function expressions.compile(lua_str, identifier)
	for _, syntax in pairs(blacklisted_syntax) do
		if lua_str:find("[%p%s]" .. syntax) or lua_str:find(syntax .. "[%p%s]") then
			return nil
		end
	end

	local env = table.Copy(lua_str_env)

	local start_time = SysTime()
	env.t = function() return SysTime() - start_time end
	env.time = t
	env.select = select

	lua_str = "local input = select(1, ...) return " .. lua_str

	local fn = CompileString(lua_str, identifier, false)
	if isfunction(fn) then
		setfenv(fn, env)
		return fn
	end

	return nil
end