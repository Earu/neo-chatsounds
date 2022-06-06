return {
	name = "pitch",
	legacy_syntax = "%",
	default_value = 100,
	parse_args = function(args)
		local pitch = tonumber(args)
		if not pitch then return 100 end

		return math.min(math.max(1, pitch), 255)
	end,
}