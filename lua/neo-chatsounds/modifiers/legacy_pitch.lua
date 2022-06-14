local MODIFIER = {}

MODIFIER.Name = "legacy_pitch"
MODIFIER.LegacySyntax = "%%"
MODIFIER.OnlyLegacy = true
MODIFIER.DefaultValue = { 100, 100 }

function MODIFIER:ParseArgs(args)
	local str_args = args:Split(".")
	local pitch_start = math.min(math.max(1, tonumber(str_args[1]) or 100), 255)
	local pitch_end = math.min(math.max(1, tonumber(str_args[2]) or pitch_start), 255)

	return { pitch_start, pitch_end }
end

function MODIFIER:OnStreamInit(stream)
	stream.Duration = stream.Duration / (math.abs(self.Value[1]) / 100)
	stream:SetMaxLoopCount(true)

	self.StartTime = SysTime()
end

local function lerp(m, a, b)
	return (b - a) * m + a
end

function MODIFIER:OnStreamThink(stream)
	local f = (SysTime() - self.StartTime) / self.Duration
	local pitch = lerp(f, self.Value[1], self.Value[2]) / 100

	stream:SetPlaybackRate(pitch)

	if stream.Overlap and f >= 1 then
		stream:Stop()
	end
end

return MODIFIER