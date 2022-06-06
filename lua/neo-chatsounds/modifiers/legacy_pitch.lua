return {
	name = "legacy_pitch",
	legacy_syntax = "%%",
	only_legacy = true,
	default_value = { 100, 100 },
	parse_args = function(args)
		local str_args = args:Split(".")
		local pitch_start = math.min(math.max(1, tonumber(str_args[1]) or 100), 255)
		local pitch_end = math.min(math.max(1, tonumber(str_args[2]) or 100), 255)

		return { pitch_start, pitch_end }
	end,
}