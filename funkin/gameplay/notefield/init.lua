NoteMods = require "funkin.gameplay.notefield.notemods"
Receptor = require "funkin.gameplay.notefield.receptor"
Note = require "funkin.gameplay.notefield.note"

local Notefield = ActorGroup:extend("Notefield")

Notefield.ratings = {
	-- {name = "perfect", time = 0.0125, score = 400, splash = true,  mod = 1},
	{name = "sick",    time = 0.045,  score = 350, splash = true,  mod = 1},
	{name = "good",    time = 0.090,  score = 200, splash = false, mod = 0.7},
	{name = "bad",     time = 0.135,  score = 100, splash = false, mod = 0.4},
	{name = "shit",    time = -1,     score = 50,  splash = false, mod = 0.2}
}
Notefield.safeZoneOffset = 1 / 6

-- code cancer dont touch

function Notefield:new(x, y, keys, skin, character, vocals, speed)
	Notefield.super.new(self, x, y)

	self.noteWidth = (160 * 0.7)
	self.height = 514
	self.keys = keys
	self.skin = paths.getSkin(skin)

	self.time = 0
	self.beat = 0
	self.offsetTime = 0
	self.speed = speed or 1
	self.drawSize = game.height * 2 + self.noteWidth
	self.drawSizeOffset = 0
	self.downscroll = false
	self.canSpawnSplash = true
	self.lastSustain = nil

	self.character = character
	self.vocals = vocals
	self.bot = true

	self.score = 0
	self.combo = 0
	self.misses = 0

	for _, r in ipairs(Notefield.ratings) do
		self[r.name .. "s"] = 0
	end

	self.modifiers = {}
	self.lanes = {}
	self.receptors = {}
	self.notes = {}
	self.recentPresses = {}

	self.onNoteHit = Signal()
	self.onSustainHit = Signal()
	self.onNoteMiss = Signal()
	self.onNoteMash = Signal()

	self.__topSprites = Group()
	self.__offsetX = -self.noteWidth / 2 - (self.noteWidth * keys / 2)
	for i = 1, keys do self:makeLane(i).x = self.__offsetX + self.noteWidth * i end
	self.__offsetX = self.__offsetX / (1 + 1 / keys)
	self:add(self.__topSprites)

	self:getWidth()
end

function Notefield:generateInputSignals()
	self.onKeyPress, self.onKeyRelease = Signal(), Signal()

	self.onKeyPress:add(bind(self, self.keyPress))
	self.onKeyRelease:add(bind(self, self.keyRelease))
	return self.onKeyPress, self.onKeyRelease
end

function Notefield:makeLane(direction, y)
	local lane = ActorGroup(0, 0, 0, false)
	lane.receptor = Receptor(0, y or -self.height / 2, direction - 1, self.skin)
	lane.renderedNotes, lane.renderedNotesI = {}, {}
	lane.currentNoteI = 1
	lane.drawSize, lane.drawSizeOffset = 1, 0
	lane.speed = 1

	lane:add(lane.receptor)
	lane.receptor.lane = lane
	lane.receptor.parent = self

	self.receptors[direction] = lane.receptor
	self.lanes[direction] = lane
	self:add(lane)
	self.__topSprites:add(lane.receptor.covers)
	self.__topSprites:add(lane.receptor.splashes)
	return lane
end

function Notefield:makeNote(time, column, sustain, type, skin)
	local note = Note(time, column, sustain, type, skin or self.skin)
	self:addNote(note)
	return note
end

function Notefield:addNote(note)
	note.parent = self
	table.insert(self.notes, note)
	return note
end

function Notefield:fadeInReceptors()
	for i = 1, #self.lanes do
		local receptor = self.lanes[i].receptor
		receptor.y = receptor.y - 10
		receptor.alpha = 0

		Tween.tween(receptor, {y = receptor.y + 10, alpha = 1}, 1, {
			ease = "circOut",
			startDelay = 0.16 + (0.2 * i)
		})
	end
end

function Notefield:copyNotesFromNotefield(notefield)
	for i, note in ipairs(self.notes) do
		local parent, grp = note.parent, note.group
		note.parent, note.group = nil

		local noteClone = note:clone()
		noteClone.parent = self

		note.parent, note.group = parent, grp

		table.insert(self.notes, noteClone)
	end

	table.sort(self.notes, Conductor.sortByTime)
end

function Notefield:removeNoteFromIndex(idx)
	local note = self.notes[idx]
	if not note then
		print("note not found at index", idx)
		return
	end

	if self.lastSustain == note then
		self.lastSustain = nil
	end

	note.parent, note.lastPress = nil, nil

	local lane = note.group
	if lane then
		note.group, lane.renderedNotesI[note] = nil, nil
		lane:remove(note)

		for i = #lane.renderedNotes, 1, -1 do
			if lane.renderedNotes[i] == note then
				table.remove(lane.renderedNotes, i)
				break
			end
		end
	end

	return table.remove(self.notes, idx)
end

function Notefield:removeNote(note)
	local idx = table.find(self.notes, note)
	if idx then
		return self:removeNoteFromIndex(idx)
	else
		print("note not found in notefield notes")
	end
end

function Notefield:setSkin(skin)
	if self.skin.skin == skin then return end

	skin = skin and paths.getSkin(skin) or paths.getSkin("default")
	self.skin = skin

	for _, receptor in ipairs(self.receptors) do
		receptor:setSkin(skin)
	end
	for _, note in ipairs(self.notes) do
		note:setSkin(skin)
	end
end

function Notefield:getNotes(time, direction, sustainLoop)
	local notes = self.notes
	if #notes == 0 then return {} end

	local safeZoneOffset, hitNotes, i, started, hasSustain,
	forceHit, noteTime, hitTime, prev, prevIdx = Notefield.safeZoneOffset, {}, 1
	for _, note in ipairs(notes) do
		noteTime = note.time
		if not note.tooLate
			and not note.ignoreNote
			and (direction == nil or note.direction == direction)
			and (note.lastPress
				or (noteTime > time - safeZoneOffset * note.lateHitMult
					and noteTime < time + safeZoneOffset * note.earlyHitMult)) then
			forceHit = sustainLoop and not note.wasBomSustainHit and note.sustain
			if forceHit then hasSustain = true end
			if not note.wasGoodHit or forceHit then
				prevIdx = i - 1
				prev = hitNotes[prevIdx]
				if prev and noteTime - prev.time <= 0.001 and note.sustainTime > prev.sustainTime then
					hitNotes[i] = prev
					hitNotes[prevIdx] = note
				else
					hitNotes[i] = note
				end
				i = i + 1
				started = true
			elseif started then
				break
			end
		end
	end

	return hitNotes, hasSustain
end

function Notefield:getRating(a, b)
	local diff = math.abs(a - b)
	for _, r in ipairs(Notefield.ratings) do
		if diff <= (r.time < 0 and Notefield.safeZoneOffset or r.time) then return r end
	end
end

function Notefield:update(dt)
	Notefield.super.update(self, dt)

	local time = PlayState.conductor.time / 1000
	local missOffset = time - Notefield.safeZoneOffset / 1.25

	if self.character then
		self.character.waitReleaseAfterSing = not self.bot
	end

	self.time, self.beat = time, PlayState.conductor.currentBeatFloat

	local isPlayer, sustainHitOffset, noSustainHit, sustainTime,
	noteTime, lastPress, dir, fullyHeld, char, input, resetVolume =
		not self.bot, 0.25 / self.speed

	for _, note in ipairs(self:getNotes(time, nil, true)) do
		noteTime, lastPress, dir, noSustainHit, char =
			note.time, note.lastPress, note.direction,
			not note.wasGoodSustainHit, note.character or self.character

		input = not isPlayer or controls:down(PlayState.keysControls[dir])

		if note.wasGoodHit then
			sustainTime = note.sustainTime

			lastPress = input and time or note.lastPress
			note.lastPress, resetVolume = input and time or note.lastPress, input

			if not note.wasGoodSustainHit and lastPress ~= nil then
				if noteTime + sustainTime - sustainHitOffset <= lastPress then
					-- end of sustain hit
					fullyHeld = noteTime + sustainTime <= lastPress
					if fullyHeld or not input then
						self:hitSustain(note, time, fullyHeld)
						noSustainHit = false
					end
				elseif not input and isPlayer and noteTime <= time then
					-- early end of sustain hit (no full score)
					self:hitSustain(note, time)
					noSustainHit, note.tooLate = false, true
				end
			end

			if noSustainHit and input and char then
				char.lastHit = PlayState.conductor.time
			end
		elseif isPlayer then
			if noSustainHit and (lastPress or noteTime) <= missOffset then
				self.lastSustain = nil
				self:missNote(note)
			end

		elseif noteTime <= time then self:hitNote(note, time) end
	end

	if resetVolume then
		local vocals = self.vocals
		if vocals then vocals:setVolume(ClientPrefs.data.vocalVolume / 100) end
	end

	for _, mod in pairs(self.modifiers) do mod:update(self.beat) end
end

function Notefield:keyPress(key, time, lastTick)
	local offset = (time - lastTick) * game.sound.music:getActualPitch()
	if self.character then
		self.character.waitReleaseAfterSing = not self.bot
	end
	if self.bot then return end

	time = self.time + offset
	local hitNotes, hasSustain = self:getNotes(time, key - 1)
	local l = #hitNotes

	if ClientPrefs.data.ghostTap and l > 0 then
		table.insert(self.recentPresses, {key = key, time = time, hit = true})

		for i = #self.recentPresses, 1, -1 do
			if time - self.recentPresses[i].time > 0.07 then
				table.remove(self.recentPresses, i)
			end
		end

		for _, press in ipairs(self.recentPresses) do
			if press.key ~= key and math.abs(press.time - time) < 0.07 then
				if not press.hit then
					-- print("antimash triggered")
					self.onNoteMash:dispatch()
				end
			end
		end
	elseif ClientPrefs.data.ghostTap then
		table.insert(self.recentPresses, {key = key, time = time, hit = false})
	end

	if l == 0 then
		local receptor = self.receptors[key]
		if receptor then
			receptor:play(hasSustain and "confirm" or "pressed")
		end
		if not hasSustain and not ClientPrefs.data.ghostTap then
			self:missNote(self, key - 1)
		end
	else
		-- remove stacked notes (this is dedicated to spam songs)
		local i, firstNote, note = 2, hitNotes[1]
		while i <= l do
			note = hitNotes[i]
			if note and math.abs(note.time - firstNote.time) < 0.01 then
				self:removeNote(note)
			else break end; i = i + 1
		end

		self:hitNote(firstNote, time)
	end
end

function Notefield:hitNote(note, time)
	local rating = self:getRating(note.time, time)
	self.score, self.combo = self.score + rating.score, math.max(self.combo, 0) + 1
	self:recalculateRatings(rating.name)

	self.onNoteHit:dispatch(note, time, rating)
end

function Notefield:hitSustain(note, time, full)
	if full then
		self.score = self.score + note.sustainTime * 1000
	else
		self.score = self.score +
			math.min(time - note.lastPress + Notefield.safeZoneOffset, note.sustainTime) * 1000
	end
	self.lastSustain = nil

	self.onSustainHit:dispatch(note, time, full)
end

function Notefield:missNote(noteOrNF, key)
	self.score, self.misses, self.combo =
		self.score - 100, self.misses + 1, math.min(self.combo, 0) - 1
	self.lastSustain = nil

	self.onNoteMiss:dispatch(noteOrNF, key)
end

function Notefield:keyRelease(key)
	if not self.bot then
		self:resetStroke(key)
		self.lastSustain = nil
	end
end

function Notefield:resetStroke(dir, doPress)
	local receptor = self.receptors[dir]
	if receptor then
		receptor:play((doPress and not self.bot)
			and "pressed" or "static")
	end
end

function Notefield:recalculateRatings(rating)
	local field = rating .. "s"
	self[field] = (self[field] or 0) + 1
end

function Notefield:screenCenter(axes)
	if axes == nil then axes = "xy" end
	if axes:find("x") then self.x = (game.width - self.width) / 2 end
	if axes:find("y") then self.y = game.height / 2 end
	if axes:find("z") then self.z = 0 end
	return self
end

function Notefield:getWidth()
	self.width = self.noteWidth * self.keys
	return self.width
end

function Notefield:getHeight()
	return self.height
end

function Notefield:destroy()
	ActorSprite.destroy(self)

	self.modifiers = nil
	if self.receptors then
		for _, r in ipairs(self.receptors) do r:destroy() end
		self.receptors = nil
	end
	if self.notes then
		for _, n in ipairs(self.notes) do n:destroy() end
		self.notes = nil
	end
	if self.lanes then
		for _, l in ipairs(self.lanes) do
			l:destroy(); if l.receptor then l.receptor:destroy() end
			l.renderedNotes, l.renderedNotesI, l.currentNoteI, l.receptor = nil
		end
	end
end

function Notefield:__prepareLane(direction, lane, time)
	local notes, receptor, speed, drawSize, drawSizeOffset =
		self.notes, lane.receptor,
		self.speed * lane.speed,
		self.drawSize * (lane.drawSize or 1),
		self.drawSizeOffset + (lane.drawSizeOffset or 0)

	local size, renderedNotes, renderedNotesI = #notes, lane.renderedNotes, lane.renderedNotesI
	table.clear(renderedNotesI)

	if size == 0 then
		for _, note in ipairs(renderedNotes) do
			note.group = nil
			lane:remove(note)
			table.delete(renderedNotes, note)
		end
		return
	end

	local repx, repy, repz = receptor.x, receptor.y, receptor.z
	local offset, noteI = (-drawSize / 2) - repy + drawSizeOffset, math.clamp(lane.currentNoteI, 1, size)
	while noteI < size and not notes[noteI].sustain and
		(notes[noteI + 1].direction ~= direction or Note.toPos(notes[noteI + 1].time - time, speed) <= offset)
	do
		noteI = noteI + 1
	end
	while noteI > 1 and (Note.toPos(notes[noteI - 1].time - time, speed) > offset) do noteI = noteI - 1 end

	lane._drawSize, lane._drawSizeOffset = lane.drawSize, lane.drawSizeOffset
	lane.drawSize, lane.drawSizeOffset, lane.currentNoteI = drawSize, drawSizeOffset, noteI
	local reprx, repry, reprz = receptor.noteRotations.x, receptor.noteRotations.y, receptor.noteRotations.z
	local repox, repoy, repoz = repx + receptor.noteOffsets.x, repy + receptor.noteOffsets.y, repz + receptor.noteOffsets.z
	while noteI <= size do
		local note = notes[noteI]
		local y = Note.toPos(note.time - time, speed)
		if note.direction == direction and (y > offset or note.sustain) then
			if y > drawSize / 2 + drawSizeOffset - repy then break end

			renderedNotesI[note] = true
			local prevlane = note.group
			if prevlane ~= lane then
				if prevlane then prevlane:remove(note) end
				table.insert(renderedNotes, note)
				lane:add(note)
				note.group = lane
			end

			-- Notes Render are handled in note.lua
			note._rx, note._ry, note._rz, note._speed = note.rotation.x, note.rotation.y, note.rotation.z, note.speed
			note._targetTime, note.speed, note.rotation.x, note.rotation.y, note.rotation.z =
				time, note._speed * speed, note._rx + reprx, note._ry + repry, note._rz + reprz
		end

		noteI = noteI + 1
	end

	for _, note in ipairs(renderedNotes) do
		if not renderedNotesI[note] then
			note.group = nil
			lane:remove(note)
			table.delete(renderedNotes, note)
		end
	end
end

function Notefield:__render(camera)
	local time = self.time - self.offsetTime
	for i, lane in ipairs(self.lanes) do
		self:__prepareLane(i - 1, lane, time)
	end

	for _, mod in pairs(self.modifiers) do if mod.apply then mod:apply(self) end end
	if self.downscroll then self.scale.y = -self.scale.y end
	self.x = self.x - self.__offsetX
	Notefield.super.__render(self, camera)
	self.x = self.x + self.__offsetX
	if self.downscroll then self.scale.y = -self.scale.y end
	NoteModifier.discard()

	for _, lane in ipairs(self.lanes) do
		lane.drawSize, lane.drawSizeOffset = lane._drawSize, lane._drawSizeOffset
		for _, note in ipairs(lane.renderedNotes) do
			note.speed, note.rotation.x, note.rotation.y, note.rotation.z = note._speed, note._rx, note._ry, note._rz
		end
	end
end

return Notefield
