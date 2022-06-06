return {
	name = "repeat",
	legacy_syntax = "*",
	default_value = 1,
	parse_args = function(args)
		local rep = tonumber(args)
		if not rep then return 1 end

		return math.max(1, rep)
	end,
}