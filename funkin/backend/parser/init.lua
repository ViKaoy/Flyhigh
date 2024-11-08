local chart = require "funkin.backend.parser.chart"
-- local character = require "funkin.backend.parser.character"

local Parser = {}

local function sortByTime(a, b) return a.t < b.t end

function Parser.getChart(songName, diff)
	songName = paths.formatToSongPath(songName)

	local data, path = chart.get(songName, diff and diff:lower() or "normal")

	if data then
		local parsed =
			chart.getParser(data).parse(data, paths.getJSON(path .. "events")
			or (data.song and data.song.events or data.events),
			paths.getJSON(path .. "meta") or paths.getJSON(path .. "metadata"),
			diff)

		table.sort(parsed.notes.enemy, sortByTime)
		table.sort(parsed.notes.player, sortByTime)
		table.sort(parsed.events, sortByTime)

		return parsed
	else
		return table.clone(chart.base)
	end
end

function Parser.getCharacter(charName)
end

return Parser
