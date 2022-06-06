return {
	name = "skip",
	legacy_syntax = "++",
	default_value = 0,
	parse_args = function(args)
		local skip = tonumber(args)
		if not skip then return 0 end

		return math.max(0, skip)
	end,
}