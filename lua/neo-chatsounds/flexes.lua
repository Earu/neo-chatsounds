if not CLIENT then return end

local flexes = chatsounds.Module("Flexes")

local amplitudes = {}
flexes.Amplitudes = amplitudes

local function compute_amplitude(buffer)
	local sum = 0
	for i = 1, #buffer do
		buffer[i] = buffer[i] * buffer[i]
		sum = sum + buffer[i]
	end

	return math.sqrt(sum / #buffer)
end

function flexes.PushStreamBuffer(ply, stream_id, buffer)
	local amplitude = compute_amplitude(buffer)

	if not amplitudes[ply] then
		amplitudes[ply] = {
			TargetAmplitude = amplitude,
		}
	end

	amplitudes[ply][stream_id] = amplitude
end

local function compute_max_amplitude(ply)
	local max = 0
	for key, amplitude in pairs(amplitudes[ply]) do
		if key == "CurrentAmplitude" or key == "TargetAmplitude" then continue end

		if amplitude > max then
			max = amplitude
		end
	end

	return max
end

function flexes.MarkForDeletion(ply, stream_id)
	if not IsValid(ply) then
		amplitudes[ply] = nil
		return
	end

	if not amplitudes[ply] then return end

	amplitudes[ply][stream_id] = nil

	if compute_max_amplitude(ply) == 0 then
		amplitudes[ply] = nil
	end
end

-- GRIN
-- right_upper_raiser 1
-- left_upper_raiser 1
-- right_corner_puller 1
-- left_corner_puller 1

-- right_part 1
-- left_part 1

-- right_stretcher 1
-- left_stretcher 1

-- jaw_drop 1
-- smile 1
-- lower_lip 1

-- SMILE
-- right_upper_raiser 1
-- left_upper_raiser 1
-- right_corner_puller 1
-- left_corner_puller 1

-- right_part 0
-- left_part 0

-- right_stretcher 1
-- left_stretcher 1

-- jaw_drop 0
-- smile 0
-- lower_lip 0

local moving_flexes = {
	["right_funneler"] = 1.0,
	["left_funneler"] = 1.0,
	["jaw_drop"] = -1,
	["right_mouth_drop"] = -1,
	["left_mouth_drop"] = -1,
}
local function process_flex(ply, target_amplitude)
	if target_amplitude == 0 then return end

	local flex_amplitude = (1 + target_amplitude) * (1 + target_amplitude)

	for flex_name, value in pairs(moving_flexes) do
		local id = ply:GetFlexIDByName(flex_name)
		if id then
			ply:SetFlexWeight(id, value ~= -1 and value or target_amplitude)
		end
	end

	ply:SetFlexScale(flex_amplitude)
end

local next_update = 0
hook.Add("Think", "chatsounds.Flexes", function()
	if not chatsounds.Enabled then return end

	local should_update = CurTime() >= next_update
	if should_update then
		next_update = CurTime() + 0.1
	end

	for ply, amplitude_data in pairs(amplitudes) do
		if not IsValid(ply) then
			amplitudes[ply] = nil
			continue
		end

		if should_update then
			amplitude_data.TargetAmplitude = compute_max_amplitude(ply)
			process_flex(ply, amplitude_data.TargetAmplitude)
		end
	end
end)