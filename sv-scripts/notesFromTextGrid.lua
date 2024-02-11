SCRIPT_TITLE = "RV Notes from TextGrid"
-- Ver.1 - loads notes from Pratt textGrid object, pitch is quantized from pitch object
-- Ver.2 - added support for loading a pitch encoded in the textGrid lyrics (without pitch quantization),
--	 encoding can be generated by "RV Notes to TextGrid"
--	 the pitch is encoded as MIDI's note index minus 69 offset (ie 0 = A4)

function getClientInfo()
	return {
		name = SV:T(SCRIPT_TITLE),
		author = "Hataori@protonmail.com",
		category = "Real Voice",
		versionNumber = 2,
		minEditorVersion = 65537
	}
end

local inputForm = {
	title = SV:T("Notes from Praat TextGrid and Pitch"),
	message = SV:T("Timing and pitch to be loaded as notes into current track"),
	buttons = "OkCancel",
	widgets = { {
			name = "scale", type = "ComboBox",
			label = SV:T("Scale (Maj/Min)"),
			choices = {"chroma", "C/a", "C#/Db/bb", "D/b", "Eb/c", "E/c#", "F/d", "F#/Gb/d#/eb", "G/e", "Ab/f", "A/f#", "Bb/g", "B/Cb/g#"},
			default = 0
		}, {
			name = "loadPitchCheck", type = "CheckBox",
			text = SV:T("Load pitch automation"),
			default = false
		}
	}
}

-------------------- PraatPitch class
local PraatPitch = {} -- class
PraatPitch.__index = PraatPitch

function PraatPitch.open(fname) -- constructor
	local fi = io.open(fname)
	assert(fi, "Can't open file: "..fname)
	assert(fi:read("l") == "Pitch", "Pitch file format error: "..fname)
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

function PraatPitch:getByTime(time, pos)
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

-------------------- PraatTextGrid class
local PraatTextGrid = {} -- class
PraatTextGrid.__index = PraatTextGrid

do

local TextGridHeader = {
{n="File_type", v="File type = \"ooTextFile\"", t="del"},
{n="Object_class", v="Object class = \"TextGrid\"", t="del"},
{t="del"},
{n="xmin", t="num"},
{n="xmax", t="num"},
{v="<exists>", t="del"},
{n="tireCnt", t="num"},
{n="tireType", v="\"IntervalTier\""},
{n="tireName"},
{n="txmin", t="num"},
{n="txmax", t="num"},
{n="nx", t="num"},
}
-- TextGrid files are not preprocessed, because they're almost one-time usage, unlike Pitch files.
function PraatTextGrid.open(fname) -- constructor
	local fi = io.open(fname)
	assert(fi, "Can't open file: "..fname)
	assert(fi:read("l") == 'File type = "ooTextFile"', "TextGrid file format error: "..fname)
	assert(fi:read("l") == 'Object class = "TextGrid"', "TextGrid file format error: "..fname)
	local _ = fi:read("n", "n", "l") -- xmin, xmax of the whole file
	assert(fi:read("l") == "<exists>", "TextGrid is empty: "..fname)
	_ = fi:read("n") -- size (number of tiers, following data are per tier, but we only read the first one)
	assert(fi:read("l") == '"IntervalTier"', 'Wrong type of TextGrid tier, need "IntervalTier": '..fname)
					-- class (other possible values are: "TextTier")
	_ = fi:read("n")

	local data, header = {}, {}

	local fi = io.open(fnam)
	for i = 1, #TextGridHeader do
		local lin = fi:read("*l")
		local h = TextGridHeader[i]

		if h.v then
			assert(lin == h.v)
		elseif h.t == "num" then
			lin = tonumber(lin)
		end

		if h.n and h.t ~= "del" then
			header[h.n] = lin
		end
	end

	header["fileType"] = "ooTextFile"
	header["objectClass"] = "TextGrid"
	assert(header.nx)

	for i = 1, header.nx do
		local interval = {}

		local time_from = fi:read("*n", "*l")
		local time_to = fi:read("*n", "*l")
		local txt = fi:read("*l")
		txt = txt:match("\"([^\"]+)\"") or ""

		table.insert(data, {
			fr = time_from,
			to = time_to,
			tx = txt
		})
	end;
	fi:close()

	o.header = header
	o.data = data
	return o
end

setmetatable(PraatTextGrid, {__call = PraatTextGrid.open})

end -- end PraatTextGrid class


local NOTES = {'C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'Bb', 'B'}

local SCALES = {
	['chroma'] = 'C-C#-D-D#-E-F-F#-G-G#-A-Bb-B-',
	['C/a'] = 'C-D-E-F-G-A-B-',
	['C#/Db/bb'] = 'C#-D#-F-F#-G#-Bb-C-',
	['D/b'] = 'D-E-F#-G-A-B-C#-',
	['Eb/c'] = 'D#-F-G-G#-Bb-C-D-',
	['E/c#'] = 'E-F#-G#-A-B-C#-D#-',
	['F/d'] = 'F-G-A-Bb-C-D-E-',
	['F#/Gb/d#/eb'] = 'F#-G#-Bb-B-C#-D#-F-',
	['G/e'] = 'G-A-B-C-D-E-F#-',
	['Ab/f'] = 'G#-Bb-C-C#-D#-F-G-',
	['A/f#'] = 'A-B-C#-D-E-F#-G#-',
	['Bb/g'] = 'Bb-C-D-D#-F-G-A-',
	['B/Cb/g#'] = 'B-C#-D#-E-F#-G#-Bb-'
}

local function inScale(pitch, scale)
	local name = NOTES[pitch % 12 + 1]
	return scale:find(name.."-", 1, true)
end

local function quantize(pitch, scale)
	-- quantize to scale
	local rounded = math.floor(pitch + 0.5)
	if inScale(rounded, scale) then return rounded end
	-- If i isn't in scale, i-1 and i+1 must both be in scale.
	return pitch < rounded and rounded - 1 or rounded + 1
end


local function process()
	-- pitch and grid files in project folder
	local projectFileName = SV:getProject():getFileName()
	if not projectFileName then
		error(SV:T("project name not found, save your project first"))
		return
	end
	local grid = PraatTextGrid(projectFileName.."_TextGrid.txt") -- textgrid instance
	local pitch = PraatPitch(projectFileName.."_Pitch.txt") -- pitch instance

	-- TODO: 设计思路：若当前group内存在与新加音符时间重叠的音符，让用户选择：跳过重复音符，删除重叠的旧音符，清空整组，添加为新的组，取消

	local lackPitchEnc -- if there are notes without pitch encoded
	for _, int in ipairs(grid.data) do
		if int.tx and int.tx ~= "" and not int.tx:find("!", 1, true) and not int.tx:match("%([%d-]+%)") then
			lackPitchEnc = true
			break
		end
	end

	if not lackPitchEnc then table.remove(inputForm.widgets, 1) end -- scale not needed
	-- input dialog
	local dlgResult = SV:showCustomDialog(inputForm)
	if not dlgResult.status then return end -- cancel pressed

	local scaleName = lackPitchEnc and inputForm.widgets[1].choices[dlgResult.answers.scale + 1] or "chroma"
	local scale = SCALES[scaleName]
	assert(scale)

	local timeAxis = SV:getProject():getTimeAxis()
	local groupRef = SV:getMainEditor():getCurrentGroup()
	local group = groupRef:getTarget()
	local vibrAm = group:getParameter("vibratoEnv") -- vibrato envelope for extra events

	local notes, lastNote = {}, nil
	for _, int in ipairs(grid.data) do
		local frb, frt = timeAxis:getBlickFromSeconds(int.fr), timeAxis:getBlickFromSeconds(int.to)
		if int.tx then
			int.tx = int.tx:match("^%s*(.-)%s*$") or "" -- strip spaces
		else
			int.tx = ""
		end

		if int.tx and int.tx:find("!", 1, true) then
			vibrAm:add(frb, 1)
			if lastNote then
				lastNote.en = frt
			end
		elseif int.tx and int.tx ~= "" then
			local txt, pit = int.tx:match("^(.-)%s*%(([%d-]+)%)$")

			if pit then -- pitch encoded in textGrid
				lastNote = {st = frb, en = frt, pitch = tonumber(pit) + 69, lyr = txt}
				table.insert(notes, lastNote)
				vibrAm:add(frb, 1)
			else
				local med, cnt, unvoc = {}, 0, 0
				local t = int.fr
				while t <= int.to do
					local f0 = pitch:getPitch(t)
					if f0 > 50 then
						local qn = quantizeNote(f0, scale)
						table.insert(med, qn)
					else
						unvoc = unvoc + 1
					end

					t = t + 0.001
					cnt = cnt + 1
				end

				if #med > 2 and (#med / cnt) > 0.5 then -- more than 50% voiced length
					table.sort(med)
					med = med[math.floor(#med / 2) + 1] -- pitch median

					lastNote = {st = frb, en = frt, pitch = med + 69, lyr = int.tx}
					table.insert(notes, lastNote)
					vibrAm:add(frb, 1)
				else
					lastNote = {st = frb, en = frt, lyr = int.tx}
					table.insert(notes, lastNote)
					vibrAm:add(frb, 1)
				end
			end -- ind if pitch
		else
			lastNote = nil
		end -- if int.tx
	end -- for
													 -- remove old notes
	local ncnt = group:getNumNotes()
	if ncnt > 0 then
		for i = ncnt, 1, -1 do
			group:removeNote(i)
		end
	end
													 -- create notes
	for i, nt in ipairs(notes) do
		local note = SV:create("Note")
		note:setTimeRange(nt.st, nt.en - nt.st)
		local pitch = nt.pitch
		if not pitch then
			pitch = (i < #notes and notes[i + 1].pitch) or (i > 1 and notes[i - 1].pitch) or 69
		end
		note:setPitch(pitch)
		note:setLyrics(nt.lyr)
		group:addNote(note)
	end
												-- load pitch automation
	if dlgResult.answers.loadPitchCheck then
		local am = group:getParameter("pitchDelta") -- pitch automation
		am:removeAll()

		groupRef:setVoice({
			tF0Left = 0,
			tF0Right = 0,
			dF0Left = 0,
			dF0Right = 0,
			dF0Vbr = 0
		})

		local minblicks, maxblicks = math.huge, 0
		for i = 1, group:getNumNotes() do
			local note = group:getNote(i)
			local npitch = note:getPitch()
			local ncents = 100 * (npitch - 69) -- A4

			local blOnset, blEnd = note:getOnset(), note:getEnd()
			am:remove(blOnset, blEnd)

			local tons = timeAxis:getSecondsFromBlick(blOnset) -- start time
			local tend = timeAxis:getSecondsFromBlick(blEnd) -- end time

			local df, f0
			local t = tons + 0.0005
			while t < tend - 0.0001 do
				f0 = pitch:getPitch(t)
				if f0 > 50 then -- voiced
					df = 1200 * math.log(f0/440)/math.log(2) - ncents -- delta f0 in cents
					am:add(timeAxis:getBlickFromSeconds(t), df)
				end
				t = t + 0.001 -- time step
			end

			local tempo = timeAxis:getTempoMarkAt(blOnset)
			local compensation = tempo.bpm * 6.3417442

			if i > 1 then
				local pnote = group:getNote(i - 1)
				local pnpitch = pnote:getPitch()
				local pncents = 100 * (pnpitch - 69) -- A4
				local pblOnset, pblEnd = pnote:getOnset(), pnote:getEnd()
				local ptons = timeAxis:getSecondsFromBlick(pblOnset) -- start time
				local ptend = timeAxis:getSecondsFromBlick(pblEnd) -- end time

				if pblEnd == blOnset then
					local pts = am:getPoints(blOnset, timeAxis:getBlickFromSeconds(tons + 0.010))
					local pdif = ncents - pncents

					for _, pt in ipairs(pts) do
						local b, v = pt[1], pt[2]
						local t = timeAxis:getSecondsFromBlick(b) - tons
						local cor = 1 - (1 / (1 + math.exp(-compensation * t)))
						am:add(b, v + pdif * cor)
					end
				end
			end

			if i < group:getNumNotes() then
				local pnote = group:getNote(i + 1)
				local pnpitch = pnote:getPitch()
				local pncents = 100 * (pnpitch - 69) -- A4
				local pblOnset, pblEnd = pnote:getOnset(), pnote:getEnd()
				local ptons = timeAxis:getSecondsFromBlick(pblOnset) -- start time
				local ptend = timeAxis:getSecondsFromBlick(pblEnd) -- end time

				if blEnd == pblOnset then
					local pts = am:getPoints(timeAxis:getBlickFromSeconds(tend - 0.010), blEnd - 1)
					local pdif = pncents - ncents

					for _, pt in ipairs(pts) do
						local b, v = pt[1], pt[2]
						local t = timeAxis:getSecondsFromBlick(b) - tend
						local cor = 1 / (1 + math.exp(-compensation * t))
						am:add(b, v - pdif * cor)
					end
				end
			end

			am:simplify(blOnset, blEnd, 0.0001)
		end
	end
end

function main()
	process()
	SV:finish()
end