local codename = {name = "Codename"}

local function set(tbl, key, v) if v ~= nil then tbl[key] = v end end

local function getStuff(data, eventData, chart)
	local dad, bf, events =
		{}, {}, {}

	if eventData then
		for i, e in ipairs(eventData.events) do
			local eevent = e.name
			if eevent == "Camera Movement" then eevent = "FocusCamera" end

			table.insert(events, {
				t = e.time,
				e = eevent,
				v = e.params,
				codename = true
			})
		end
	end

	for _, s in ipairs(data.strumLines) do
		local toAdd, gfNotes = bf
		if s.position == "dad" then
			toAdd = dad
			gfNotes = false
			set(chart, "player2", s.characters[1])
		elseif s.position == "girlfriend" then
			toAdd = dad
			gfNotes = true
			set(chart, "gfVersion", s.characters[1])
		elseif s.position == "boyfriend" then
			toAdd = bf
			gfNotes = false
			set(chart, "player1", s.characters[1])
		end

		for _, n in ipairs(s.notes) do
			local newNote = {
				t = n.time,
				d = n.id % 4,
				l = n.sLen,
				k = n.type,
				gf = gfNotes
			}
			table.insert(toAdd, newNote)
		end
	end

	return {enemy = dad, player = bf}, events
end

function codename.parse(data, events, meta, diff)
	local chart = table.clone(codename.base)

	if meta then codename.getFromMeta(meta, chart) end

	set(chart, "stage", data.stage)
	set(chart, "speed", data.scrollSpeed)

	chart.notes, chart.events = getStuff(data, events, chart)

	return chart
end

function codename.getFromMeta(meta, tbl)
	local data = meta

	if data then
		set(tbl, "song", data.displayName or data.name)
		set(tbl, "skin", data.skin)

		set(tbl, "difficulties", data.difficulties)
		set(tbl, "bpm", data.bpm)
	end

	return data
end

return codename
