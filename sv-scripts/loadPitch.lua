-- Runs on selected groups, the current group, or selected notes.

-- Control point density equals to `dx` from the Pitch file, i.e. 184 point/s.
-- As a reference, it's roughly 5 times sparser than Hataori's setting.0001.
-- UNKOWN: I feel OK with this density. But is there improvement by providing
-- more interpolated points for automation:simplify to select?
local SIMPLITY_THRESHOLD = 0.001
-- As a reference, SV's default smoothing is 0.002; Hataori's setting was 0.0001.
-- It's recommended to use 'Cosine' InterpolationMethod.
-- UNKOWN: Does automation:simplify take InterpolationMethod into account?

function getClientInfo()
	return {
		name = SV:T("Load Pitch"),
		author = "Atterrno Amora",
		category = "Real Voice 2.0",
		versionNumber = 5,
		minEditorVersion = 0x010001 -- 1.0.1
	}
end


local convert_from_utf8 = require("utf8_filenames")

-------------------- PraatPitch class
local PraatPitch = {} -- class
PraatPitch.__index = PraatPitch

function PraatPitch.open(fname) -- constructor
	local fi = io.open(fname)
	assert(fi, "Can't open file: "..convert_from_utf8(fname))
	assert(fi:read("l") == "Pitch", "Pitch file format error: "..convert_from_utf8(fname))
	local nx, dx, x1 = fi:read("n", "n", "n", "l")

	return setmetatable({
		fi=fi, nx=nx, dx=dx, x1=x1,
		pitchStart=fi:seek(), cursor=1
	}, PraatPitch)
end

setmetatable(PraatPitch, {__call = PraatPitch.open})

function PraatPitch:close()
	self.fi:close()
end

function PraatPitch:_get(pos)
	assert(1 <= pos and pos <= self.nx, "PraatPitch._get() out of range")
	if not self[pos] then
		if self.cursor <= pos and pos < self.cursor + 20 then
			for i = self.cursor, pos do
				self[i] = self.fi:read("n")
			end
		else
			self.fi:seek('set', self.pitchStart + 18 * (pos - 1))
			self[pos] = self.fi:read("n")
		end
		self.cursor = pos + 1
	end
	return self[pos]
end

function PraatPitch:get(pos)
	if pos <= 1 then return self:_get(1) end
	if pos >= self.nx then return self:_get(self.nx) end
	local i = math.tointeger(pos)
	if i then return self:_get(i) end
	-- Interpolate if necessary.
	i = math.floor(pos)
	return self:_get(i) + (pos - i) * (self:_get(i+1) - self:_get(i))
end

function PraatPitch:getByTime(time)
	return self:get(1 + (time - self.x1) / self.dx)
end

function PraatPitch:time2Pos(time)
	-- Return the nearest data point just before `time` (in seconds)
	-- Remember to check if the result is in range [1, #self]
	return 1 + (time - self.x1) // self.dx
end

function PraatPitch:pos2Time(pos)
	return self.x1 + self.dx * (pos - 1)
end
-------------------- end PraatPitch class


-- Naming convention: in following codes, `attr` means noteAttributes, you can treat them as the note

local function getAttr(note, groupRef, timeAxis)
	-- Also converting seconds to blicks
	local attr = {}
	if timeAxis and groupRef then -- If not passing these arguments, return only simple attributes.
		local bpm = timeAxis:getTempoMarkAt(groupRef:getTimeOffset() + note:getOnset()).bpm
		local default = groupRef:getVoice()
		attr = note:getAttributes()
		for key, val in pairs(attr) do
			if val ~= val then -- is NaN
				attr[key] = default[key] or 0
			end
			if key:sub(1,1) == 't' then -- convert seconds to blicks
				attr[key] = SV:seconds2Blick(attr[key], bpm)
			end
		end
		if not attr.tF0Offset then attr.tF0Offset = 0 end -- This item could be missing.
	end
	-- The following entries are in blicks natively.
	-- Notice that tOnset and tEnd are still relative to groupRef
	attr.pitch = note:getPitch()
	attr.tOnset = note:getOnset()
	attr.tEnd = note:getEnd()
	attr.tDur = note:getDuration()
	return attr
end

local function simpleTransition(attr1, attr2, blick)
	-- Return the modification from the neighboring note in semitones
	-- Assuming tF0Offset, tF0Left, tF0Right, dF0Left, dF0Right, dF0Vbr are all 0.
	blick = blick - attr2.tOnset
	if math.abs(blick) > 15000000 or attr1.tEnd ~= attr2.tOnset then return 0 end
	-- At 15000000 blicks away, influence is usually <= 34semitones * e^-8.142 = 1cent
	if blick < 0 then
		return (attr2.pitch - attr1.pitch) / (1 + math.exp(-blick / (SV.QUARTER / 384)))
	else
		return (attr1.pitch - attr2.pitch) / (1 + math.exp(blick / (SV.QUARTER / 384)))
	end
end

local function intrinsicPitch(attr_l, attr, attr_r, blick)
	-- Not counting global pitch in groupRef and pitch contour in automation
	-- This function is usually used inside a loop over `blick`;
	-- for performance, you should get attr in advance outside the loop over blicks.
	local result = attr.pitch
	if attr_l then
		result = result + simpleTransition(attr_l, attr, blick)
	end
	if attr_r then
		result = result + simpleTransition(attr, attr_r, blick)
	end
	return result
end


local function doNote(pitchData, timeAxis, tOffset, pOffset, pitchAm, group, i)
	local note = group:getNote(i)
	local attr = getAttr(note)

	note:setAttributes({tF0Offset=0, tF0Left=0, tF0Right=0, dF0Left=0, dF0Right=0, dF0Vbr=0})
	pitchAm:remove(attr.tOnset, attr.tEnd)

	local lyrics = note:getLyrics()
	if lyrics:match('br%d?') == lyrics then return end -- clear br notes

	local attr_l = i > 1 and getAttr(group:getNote(i-1))
	local attr_r = i < group:getNumNotes() and getAttr(group:getNote(i+1))

	local blick = attr.tOnset
	local target = pitchData:getByTime(timeAxis:getSecondsFromBlick(tOffset + blick))
	pitchAm:add(blick, (target - (intrinsicPitch(attr_l, attr, attr_r, blick) + pOffset)) * 100)

	local posl = pitchData:time2Pos(timeAxis:getSecondsFromBlick(tOffset + attr.tOnset))
	local posr = pitchData:time2Pos(timeAxis:getSecondsFromBlick(tOffset + attr.tEnd))
	for t = posl+1, posr do -- Control point density = pitchData.dx, i.e. 184 point/s
		blick = timeAxis:getBlickFromSeconds(pitchData:pos2Time(t)) - tOffset
		pitchAm:add(blick, (pitchData:get(t) - (intrinsicPitch(attr_l, attr, attr_r, blick) + pOffset)) * 100)
	end

	blick = attr.tEnd
	target = pitchData:getByTime(timeAxis:getSecondsFromBlick(tOffset + blick))
	pitchAm:add(blick, (target - (intrinsicPitch(attr_l, attr, attr_r, blick) + pOffset)) * 100)

	pitchAm:simplify(attr.tOnset, attr.tEnd, SIMPLITY_THRESHOLD)
end

function main()
	local project = SV:getProject()
	local projectFileName = project:getFileName()
	if not projectFileName then return end
	projectFileName = projectFileName:sub(1,-5)
	local pitchData = PraatPitch.open(projectFileName.."_Pitch.txt")

	local wavOffset = 0 -- determine offset by aligning with a instrumental track with one of these names
	for i = 1, project:getNumTracks() do
		local track = project:getTrack(i)
		local name = track:getName()
		local groupRef = track:getGroupReference(1)
		if groupRef:isInstrumental() and (name == 'vocal' or name == 'human' or name == 'original') then
			wavOffset = groupRef:getTimeOffset()
			break
		end
	end

	-- determine targets
	local timeAxis = SV:getProject():getTimeAxis()
	local selection = SV:getMainEditor():getSelection()
	if selection:hasUnfinishedEdits() then return end
	if selection:hasSelectedGroups() then
		for _, groupRef in ipairs(selection:getSelectedGroups()) do
			local group = groupRef:getTarget()
			if group then -- is nil if it's instrumental
				local tOffset, pOffset = groupRef:getTimeOffset() - wavOffset, groupRef:getPitchOffset()
				local pitchAm = group:getParameter("pitchDelta")
				for i = 1, group:getNumNotes() do
					doNote(pitchData, timeAxis, tOffset, pOffset, pitchAm, group, i)
				end
			end
		end
	else
		local groupRef = SV:getMainEditor():getCurrentGroup()
		local group = groupRef:getTarget()
		if group then -- is nil if it's instrumental
			local tOffset, pOffset = groupRef:getTimeOffset() - wavOffset, groupRef:getPitchOffset()
			local pitchAm = group:getParameter("pitchDelta")
			if selection:hasSelectedNotes() then
				for _, note in ipairs(selection:getSelectedNotes()) do
					doNote(pitchData, timeAxis, tOffset, pOffset, pitchAm, group, note:getIndexInParent())
				end
			else
				for i = 1, group:getNumNotes() do
					doNote(pitchData, timeAxis, tOffset, pOffset, pitchAm, group, i)
				end
			end
		end
	end
	SV:finish()
end
