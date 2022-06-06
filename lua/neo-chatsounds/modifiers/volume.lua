return {
	name = "volume",
	legacy_syntax = "^",
	default_value = 1,
	parse_args = function(args)
		local volume = tonumber(args)
		if volume then return math.abs(volume) end

		return 1
	end,
	legacy_parse_args = function(args)
		local volume = tonumber(args)
		if volume then return math.abs(volume / 100) end

		return 1
	end,
}
