local MODIFIER = {}

MODIFIER.Name = "legacy_pitch"
MODIFIER.LegacySyntax = "%%"
MODIFIER.OnlyLegacy = true
MODIFIER.DefaultValue = { 100, 100 }

function MODIFIER:ParseArgs(args)
	local str_args = args:Split(".")
	local pitch_start = math.min(math.max(1, tonumber(str_args[1]) or self.DefaultValue[1]), 255)
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

function MODIFIER:GetValue()
	if not self.Value then return self.DefaultValue end
	if isfunction(self.ExpressionFn) then
		local _, ret = pcall(self.ExpressionFn)
		if not istable(ret) then return self.DefaultValue end

		if not isnumber(ret[1]) then
			ret[1] = self.DefaultValue[1]
		else
			ret[1] = math.min(255, math.max(1, ret[1]))
		end

		if not isnumber(ret[2]) then
			ret[2] = self.DefaultValue[2]
		else
			ret[2] = math.min(255, math.max(1, ret[2]))
		end

		return ret
	end

	return self.Value
end

function MODIFIER:OnStreamThink(stream)
	local value = self:GetValue()
	local f = (SysTime() - self.StartTime) / stream.Duration
	local pitch = lerp(f, value[1], value[2]) / 100

	stream:SetPlaybackRate(pitch)

	if stream.Overlap and f >= 1 then
		stream:Stop()
	end
end

return MODIFIER