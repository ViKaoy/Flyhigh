NoteMods = require "funkin.gameplay.notefield.notemods"
Receptor = require "funkin.gameplay.notefield.receptor"
Note = require "funkin.gameplay.notefield.note"

local Notefield = ActorGroup:extend("Notefield")

Notefield.ratings = {
	-- { name = "perfect", ms = 12.5, mod = 1, splash = true},
	{ name = "sick", ms = 45,  mod = 1, splash = true },
	{ name = "good", ms = 90,  mod = 0.7 },
	{ name = "bad",  ms = 135, mod = 0.4 },
	{ name = "shit", ms = -1,  mod = 0.2 }
}

Notefield.ranks = {
	{ name = "FC",    cond = function(s) return s.misses < 1 and (s.bads > 0 or s.shits > 0) end },
	{ name = "GFC",   cond = function(s) return s.misses < 1 and s.goods > 0 end },
	{ name = "SFC",   cond = function(s) return s.misses < 1 and s.sicks > 0 end },
	-- { name = "PFC",   cond = function(s) return s.misses < 1 and s.perfects > 0 end },
	{ name = "FC",    cond = function(s) return s.misses < 1 end },
	{ name = "Clear", cond = function(s) return s.misses >= 10 end },
	{ name = "SDM",   cond = function(s) return s.misses > 0 end }
}

Notefield.safeZoneOffset = 1 / 6

Notefield.hitScore = 350
Notefield.hitSustainScore = 150
Notefield.missScore = -150

-- code cancer dont touch

function Notefield:new(x, y, keys, skin, character, vocals, speed, parent)
	Notefield.super.new(self, x, y)

	self.noteWidth, self.height = 160 * 0.7, 514
	self.keys, self.skin, self.bgAlpha = keys, paths.getSkin(skin), 0
	self.time, self.offsetTime, self.beat = 0, 0, 0
	self.drawSize, self.drawSizeOffset = game.height * 2 + self.noteWidth, 0

	self.downscroll, self.bot, self.speed = false, true, speed or 1
	self.canSpawnSplash, self.lastSustain = true
	self.character, self.vocals = character, vocals
	self.score, self.combo, self.misses = 0, 0, 0

	for _, r in ipairs(Notefield.ratings) do
		self[r.name .. "s"] = 0
	end
	self.totalPlayed, self.totalHit, self.totalExactHit = 0, 0, 0
	self.accuracy, self.complexAccuracy, self.rank = "0%", "0%", "NR" -- no rank

	self.modifiers, self.recentPresses = {}, {}
	self.lanes, self.receptors, self.notes, self.overlays = {}, {}, {}, Group()

	self.onNoteHit, self.onSustainHit, self.onNoteMiss, self.onNoteMash =
		Signal(), Signal(), Signal(), Signal()

	self.offsetX = -self.noteWidth / 2 - (self.noteWidth * keys / 2)
	for i = 1, keys do self:makeLane(i).x = self.offsetX + self.noteWidth * i end
	self.offsetX = self.offsetX / (1 + 1 / keys)
	self:add(self.overlays)

	self:getWidth()

	if parent then
		self.parent = parent

		if parent.goodNoteHit then self.onNoteHit:add(bind(parent, parent.goodNoteHit)) end
		if parent.goodSustainHit then self.onSustainHit:add(bind(parent, parent.goodSustainHit)) end
		if parent.miss then self.onNoteMiss:add(bind(parent, parent.miss)) end
		self.onNoteMash:add(function()
			if parent.health then parent.health = parent.health - 0.09 end
		end)
	end
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
	self.overlays:add(lane.receptor.covers)
	self.overlays:add(lane.receptor.splashes)
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

function Notefield:setNotes(noteTable)
	for _, n in ipairs(noteTable) do
		local sustainTime = n.l or 0
		if sustainTime > 0 then
			sustainTime = math.max(sustainTime / 1000, 0.125)
		end
		local note = self:makeNote(n.t / 1000, n.d, sustainTime, n.k)
		if n.gf then note.character = game.getState().gf end
	end
end

function Notefield:getNotes(time, direction, sustainLoop)
	local notes = self.notes
	if #notes == 0 then return {} end

	local safeZoneOffset, hitNotes, i, started, hasSustain,
	forceHit, noteTime, hitTime, prev, prevIdx = self.safeZoneOffset, {}, 1
	for _, note in ipairs(notes) do
		noteTime = note.time
		if not note.tooLate
			and not note.ignoreNote
			and (direction == nil or note.direction == direction)
			and (note.lastPress
				or (noteTime > time - safeZoneOffset * note.lateHitMult
					and noteTime < time + safeZoneOffset * note.earlyHitMult)) then
			forceHit = sustainLoop and not note.wasGoodSustainHit and note.sustain
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

function Notefield:fadeInReceptors()
	local tween = self.parent and (function(...)
		self.parent.tween:tween(...)
	end) or Tween.tween

	for i = 1, #self.lanes do
		local receptor = self.lanes[i].receptor
		receptor.y = receptor.y - 10
		receptor.alpha = 0

		tween(receptor, {y = receptor.y + 10, alpha = 1}, 1, {
			ease = "circOut",
			startDelay = (0.2 * i)
		})
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

function Notefield:getRank()
	for _, rank in ipairs(self.ranks) do
		if rank.cond(self) then return rank.name end
	end
	return "NR"
end

function Notefield:getAccuracy(complex)
	return math.min(1, math.max(0, (complex and self.totalExactHit or self.totalHit)
		/ self.totalPlayed))
end

function Notefield:updateAccuracy()
	self.accuracy = math.truncate(self:getAccuracy() * 100, 2) .. "%"
	self.complexAccuracy = math.truncate(self:getAccuracy(true) * 100, 2) .. "%"
end

function Notefield:getExactAccuracy(a, b)
	local diff = math.abs(a - b)
	return math.max(0, 1 - (diff / self.safeZoneOffset))
end

function Notefield:getRating(a, b)
	local diff = math.abs(a - b) * 1000
	for _, r in ipairs(self.ratings) do
		if diff <= (r.ms < 0 and self.safeZoneOffset or r.ms) then
			return r
		else
			if r.ms < 0 then
				return r
			end
		end
	end
end

function Notefield:update(dt)
	Notefield.super.update(self, dt)

	for _, lane in ipairs(self.lanes) do
		for _, note in ipairs(lane.renderedNotes) do
			note:update(dt)
		end
	end

	local time = (PlayState.conductor.time - ClientPrefs.data.songOffset) / 1000
	local missOffset = time - self.safeZoneOffset / 1.25

	if PlayState.conductor.time < 0 or game.sound.music:isPlaying() then
		self.time, self.beat = time, PlayState.conductor.currentBeatFloat
	end

	local isPlayer, sustainHitOffset, noSustainHit, sustainTime,
	noteTime, lastPress, dir, fullyHeld, char, input =
		not self.bot, 0.25 / self.speed

	for _, note in ipairs(self:getNotes(time, nil, true)) do
		noteTime, lastPress, dir, noSustainHit, char =
			note.time, note.lastPress, note.direction,
			not note.wasGoodSustainHit, note.character or self.character

		input = not isPlayer or controls:down(PlayState.keysControls[dir])

		if note.wasGoodHit then
			sustainTime = note.sustainTime

			lastPress = input and time or note.lastPress
			note.lastPress = input and time or note.lastPress

			if not note.wasGoodSustainHit and lastPress ~= nil then
				if noteTime + sustainTime - sustainHitOffset <= lastPress then
					-- end of sustain hit
					fullyHeld = noteTime + sustainTime <= lastPress
					if fullyHeld or not input then
						self:hitSustain(note, fullyHeld)
						noSustainHit = false
					end
				elseif not input and isPlayer and noteTime <= time then
					-- early end of sustain hit (no full score)
					self:hitSustain(note)
					noSustainHit, note.tooLate = false, true
				end
			end

			if noSustainHit and input and char then
				char.lastHit = PlayState.conductor.time
			end
		elseif isPlayer then
			if not note.wasGoodSustainHit and (lastPress or noteTime) <= missOffset then
				self.lastSustain = nil
				self:missNote(note)
			end

		elseif noteTime <= time then self:hitNote(note) end
	end

	for _, mod in pairs(self.modifiers) do mod:update(self.beat) end
end

function Notefield:keyPress(key, time)
	if self.bot then return end

	local offset = (time - love.timer.getTime()) * game.sound.music:getActualPitch()

	time = self.time + offset
	local hitNotes, hasSustain = self:getNotes(time, key - 1)
	local l = #hitNotes

	if ClientPrefs.data.ghostTap and l > 0 then
		for i = #self.recentPresses, 1, -1 do
			if time - self.recentPresses[i] > 0.12 then
				table.remove(self.recentPresses, i)
			end
		end
		for _ = 1, #self.recentPresses do
			self.onNoteMash:dispatch()
		end
	elseif ClientPrefs.data.ghostTap then
		table.insert(self.recentPresses, time)
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

		self:hitNote(firstNote)
	end
end

function Notefield:keyRelease(key)
	if not self.bot then
		self:resetStroke(key)
		self.lastSustain = nil
	end
end

function Notefield:hitNote(note)
	local time = self.bot and note.time or self.time
	local rating = self:getRating(note.time, time)
	local timing = self:getExactAccuracy(note.time, time)

	self.totalPlayed, self.totalHit = self.totalPlayed + 1, self.totalHit + rating.mod

	-- notes hit within 5ms early or late should give 1, otherwise timing based
	local ms = math.floor((time - note.time) * 1000)
	self.totalExactHit = self.totalExactHit + (math.abs(ms) <= 5 and 1 or timing)

	self:updateAccuracy()

	local score = math.floor(self.hitScore * timing)
	self.score, self.combo = self.score + score, math.max(self.combo, 0) + 1
	self:recalculateRatings(rating.name)

	self.rank = self:getRank()

	note.lastPress = time

	self.onNoteHit:dispatch(note, rating, ms)
end

function Notefield:hitSustain(note, full)
	local time, stime = self.time, note.sustainTime

	if full then
		self.score = self.score + self.hitSustainScore
		self.totalPlayed, self.totalHit = self.totalPlayed + 1, self.totalHit + 1
		self.totalExactHit = self.totalExactHit + 1
	else
		local htime = math.min(time - note.lastPress + self.safeZoneOffset, stime)
		local acc = 1 - math.max(0, math.min(1, (note.time + stime - time) / stime))

		local score = math.floor(self.hitSustainScore * acc)
		self.score = self.score + score
		self.totalPlayed, self.totalHit = self.totalPlayed + 1, self.totalHit + acc
		self.totalExactHit = self.totalExactHit + acc
	end
	self:updateAccuracy()
	self.lastSustain = nil

	self.onSustainHit:dispatch(note, full)
end

function Notefield:missNote(noteOrNF, key)
	self.totalPlayed = self.totalPlayed + 1
	self:updateAccuracy()

	self.score, self.misses, self.combo =
		self.score + self.missScore, self.misses + 1, math.min(self.combo, 0) - 1
	self.lastSustain = nil

	self.rank = self:getRank()

	self.onNoteMiss:dispatch(noteOrNF, key)
end

function Notefield:resetStroke(dir, doPress)
	if not self.receptors then return end
	local receptor = self.receptors[dir]
	if receptor then
		receptor:play(doPress and "pressed" or "static")
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
		end
		table.clear(renderedNotes)
		return
	end

	local repx, repy, repz = receptor.x, receptor.y, receptor.z
	local offset = (-drawSize / 2) - repy + drawSizeOffset
	local noteI = math.clamp(lane.currentNoteI, 1, size)

	while noteI < size and not notes[noteI].sustain and
		(notes[noteI + 1].direction ~= direction or
			Note.toPos(notes[noteI + 1].time - time, speed) <= offset)
	do
		noteI = noteI + 1
	end

	while noteI > 1 and (Note.toPos(notes[noteI - 1].time - time, speed) > offset) do
		noteI = noteI - 1
	end

	lane._drawSize, lane._drawSizeOffset = lane.drawSize, lane.drawSizeOffset
	lane.drawSize, lane.drawSizeOffset, lane.currentNoteI = drawSize, drawSizeOffset, noteI
	local reprx, repry, reprz = receptor.noteRotations.x, receptor.noteRotations.y,
		receptor.noteRotations.z
	local repox, repoy, repoz = repx + receptor.noteOffsets.x, repy + receptor.noteOffsets.y,
		repz + receptor.noteOffsets.z

	while noteI <= size do
		local note = notes[noteI]
		local y = Note.toPos(note.time - time, speed)
		if (note.direction == direction and (y > offset or note.sustain)) then
			if y > drawSize / 2 + drawSizeOffset - repy then break end

			renderedNotesI[note] = true
			if note.group ~= lane then
				if note.group then note.group:remove(note) end
				table.insert(renderedNotes, note)
				lane:add(note)
				note.group = lane
			end

			note._rx, note._ry, note._rz, note._speed = note.rotation.x, note.rotation.y,
				note.rotation.z, note.speed
			note._targetTime, note.speed, note.rotation.x, note.rotation.y, note.rotation.z =
				time, note._speed * speed, note._rx + reprx, note._ry + repry, note._rz + reprz
		end

		noteI = noteI + 1
	end

	for i = #renderedNotes, 1, -1 do
		local note = renderedNotes[i]
		local y = Note.toPos(note.time - time, speed)
		if (note.tooLate and (y < offset or y > drawSize / 2 + drawSizeOffset - repy)) or
			not renderedNotesI[note] then
			note.group = nil
			lane:remove(note)
			table.remove(renderedNotes, i)
		end
	end
end

function Notefield:__render(camera)
	if self.bgAlpha > 0 then
		-- this FOR SURE wont work with modcharts but whatever!
		local x, y, ox, oy, w, h = self.x, self.y - self.drawSize / 2, self.origin.x, self.origin.y,
			self.width, self.drawSize

		x, y = x + ox - self.offset.x - (camera.scroll.x * self.scrollFactor.x),
			y + oy - self.offset.y - (camera.scroll.y * self.scrollFactor.y)

		love.graphics.push("all")
		love.graphics.setColor(0, 0, 0, self.bgAlpha)
		love.graphics.rectangle("fill", x, y, w, h)
		love.graphics.pop()
	end

	local time = self.time - self.offsetTime
	for i, lane in ipairs(self.lanes) do
		self:__prepareLane(i - 1, lane, time)
	end

	for _, mod in pairs(self.modifiers) do if mod.apply then mod:apply(self) end end
	if self.downscroll then self.scale.y = -self.scale.y end
	self.x = self.x - self.offsetX
	Notefield.super.__render(self, camera)
	self.x = self.x + self.offsetX
	if self.downscroll then self.scale.y = -self.scale.y end
	NoteModifier.discard()

	for _, lane in ipairs(self.lanes) do
		lane.drawSize, lane.drawSizeOffset = lane._drawSize, lane._drawSizeOffset
		for _, note in ipairs(lane.renderedNotes) do
			note.speed, note.rotation.x, note.rotation.y, note.rotation.z = note._speed,
				note._rx, note._ry, note._rz
		end
	end
end

return Notefield
