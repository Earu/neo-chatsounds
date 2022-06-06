return {
	name = "duration",
	legacy_syntax = "=",
	default_value = 0,
	parse_args = function(args)
		local duration = tonumber(args)
		if not duration then return 0 end

		return math.max(0, duration)
	end,
}