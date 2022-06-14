local MODIFIER = {}

MODIFIER.Name = "legacy_volume"
MODIFIER.LegacySyntax = "^^"
MODIFIER.OnlyLegacy = true
MODIFIER.DefaultValue = { 100, 100 }

function MODIFIER:ParseArgs(args)
	local str_args = args:Split(".")
	local volume_start = math.max(1, tonumber(str_args[1]) or 100)
	local volume_end = math.max(1, tonumber(str_args[2]) or volume_start)

	return { volume_start, volume_end }
end

function MODIFIER:OnStreamInit(stream)
	self.StartTime = SysTime()
end

local function lerp(m, a, b)
	return (b - a) * m + a
end

function MODIFIER:OnStreamThink(stream)
	local f = (SysTime() - self.StartTime) / stream.duration
	local vol = lerp(f, self.Value[1], self.Value[2]) / 100

	stream:SetVolume(vol)
end

return MODIFIER