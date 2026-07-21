local MODIFIER = {}

MODIFIER.Name = "loop"
MODIFIER.DefaultValue = -1 -- no argument means loop forever

local MAX_LOOPS = 100 -- keep a single sound from hogging the whole message

-- an endless sound cannot be waited on, so it is kept alive for this long at most,
-- `stopsound`/`sh` still clears it earlier
local MAX_INFINITE_LOOP_DURATION = 30

function MODIFIER:ParseArgs(args)
	local n = tonumber(args)
	if not n or n < 0 then return self.DefaultValue end

	return math.min(math.floor(n), MAX_LOOPS)
end

function MODIFIER:GetValue()
	if not self.Value or isfunction(self.ExpressionFn) then return self.DefaultValue end
	return self.Value
end

function MODIFIER:OnStreamInit(stream)
	local loop_count = self:GetValue()
	if loop_count == 0 then
		stream:SetMaxLoopCount(false)
		return
	end

	-- `true` is infinity for webaudio, anything else is an actual amount of playbacks
	stream:SetMaxLoopCount(loop_count < 0 and true or loop_count)

	if loop_count < 0 then
		-- the sound never ends on its own, let the rest of the message play over it
		stream.Overlap = true
		stream.Lifetime = MAX_INFINITE_LOOP_DURATION
	else
		-- multiplying instead of assigning keeps modifiers that scale the duration
		-- (pitch, cutoff, ...) working regardless of the order they are applied in
		stream.Duration = stream.Duration * loop_count
	end
end

return MODIFIER
