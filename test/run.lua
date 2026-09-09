-- Behavioural tests for PB's Omikuji.
--
--   lua test/run.lua        (from the add-on folder; any Lua 5.1+)
--
-- What is worth testing here is everything that decides which slip you get and when: the two
-- clocks and the timezone arithmetic over them, the calendar date computed by hand because the
-- client has no GetDate(), the hash that has to be stable and has to spread over 365 buckets,
-- and the rule that a zone change is not a login. None of that needs a game running, and every
-- one of these checks is a PS5 session not spent finding out the same thing.

local HERE = (debug.getinfo(1, "S").source:match("^@(.*)/") or ".")
ADDON_DIR = HERE .. "/.."
dofile(HERE .. "/harness.lua")

local failures = 0
local function check(label, got, want)
	local ok = got == want
	if not ok then failures = failures + 1 end
	print(string.format("%s %-58s got=%s want=%s", ok and "PASS" or "FAIL", label,
		tostring(got), tostring(want)))
end

local function checkContains(label, haystack, needle)
	local ok = type(haystack) == "string" and haystack:find(needle, 1, true) ~= nil
	if not ok then failures = failures + 1 end
	print(string.format("%s %-58s in=%s", ok and "PASS" or "FAIL", label, tostring(haystack)))
end

local function checkBetween(label, got, low, high)
	local ok = type(got) == "number" and got >= low and got <= high
	if not ok then failures = failures + 1 end
	print(string.format("%s %-58s got=%s want=%s..%s", ok and "PASS" or "FAIL", label,
		tostring(got), tostring(low), tostring(high)))
end

print("\n== 1. load ==")
Fire(EVENT_ADD_ON_LOADED, "PBsOmikuji")
local addon = PBS_OMIKUJI
-- Not a literal: the version is read out of the manifest's Title line by the add-on and out
-- of its Version line by the test, so this also catches the release mistake of editing one of
-- those two adjacent lines and not the other.
check("version read from manifest", addon.version, ManifestLine("Version"))
check("and there is a version to read", (ManifestLine("Version") or ""):match("^%d"), "1")
check("slash command registered", type(SLASH_COMMANDS["/omikuji"]), "function")
check("short slash registered", type(SLASH_COMMANDS["/pbomi"]), "function")
check("shipped scope", addon:Scope(), "CHARACTER")
check("shipped: draws at login", addon:Enabled(), true)
check("shipped: every login, not just the first", addon:OncePerDay(), false)

print("\n== 2. the slips ==")
local draw = addon.draw
check("365 fortunes, as advertised", draw:PatternCount(), 365)
check("seven ranks", #addon.RANKS, 7)

local expectedCounts = {
	{ "大吉", 50 }, { "中吉", 60 }, { "小吉", 60 }, { "吉", 60 },
	{ "末吉", 60 }, { "凶", 45 }, { "大凶", 30 },
}
local counted = 0
for index, expected in ipairs(expectedCounts) do
	local rank = addon.RANKS[index]
	check("rank " .. index .. " is " .. expected[1], rank.name, expected[1])
	check("  and has " .. expected[2] .. " fortunes", #addon.MESSAGES[rank.key], expected[2])
	counted = counted + #addon.MESSAGES[rank.key]
end
check("the counts add up to the total", counted, 365)

local seen, duplicates, empties, straySpecifiers = {}, 0, 0, 0
for index = 1, draw:PatternCount() do
	local text = draw:PatternAt(index).message
	if seen[text] then duplicates = duplicates + 1 end
	seen[text] = true
	if text == "" then empties = empties + 1 end
	-- A % in a fortune would be eaten by string.format the day somebody routes one of these
	-- through a formatted line. There is no reason for one to be there.
	if text:find("%%") then straySpecifiers = straySpecifiers + 1 end
end
check("no fortune is written twice", duplicates, 0)
check("no fortune is empty", empties, 0)
check("no fortune carries a format specifier", straySpecifiers, 0)

check("every rank has a colour", (function()
	for _, rank in ipairs(addon.RANKS) do
		if not tostring(rank.colour):match("^%x%x%x%x%x%x$") then return rank.key end
	end
	return "all"
end)(), "all")

print("\n== 3. the calendar, computed by hand ==")
local function dateOf(day)
	local y, m, d = draw:CivilFromDays(day)
	return string.format("%d-%02d-%02d", y, m, d)
end
check("day 0 is the epoch", dateOf(0), "1970-01-01")
check("the day before the epoch", dateOf(-1), "1969-12-31")
check("end of 1999", dateOf(10956), "1999-12-31")
check("2000 was a leap year", dateOf(11016), "2000-02-29")
check("and the day after it", dateOf(11017), "2000-03-01")
check("2024 leap day", dateOf(19782), "2024-02-29")
check("a plain date", dateOf(20706), "2026-09-10")
-- 2100 is the century that is NOT a leap year, which is the case a hand-written date
-- conversion gets wrong if it was written from memory.
check("2100 is not a leap year", dateOf(47540), "2100-02-28")
check("so March follows the 28th", dateOf(47541), "2100-03-01")

print("\n== 4. weekdays ==")
check("the epoch was a Thursday", draw:WeekdayName(0), "Thu")
check("1999-12-31 was a Friday", draw:WeekdayName(10956), "Fri")
check("2000-02-29 was a Tuesday", draw:WeekdayName(11016), "Tue")
check("2026-09-10 is a Thursday", draw:WeekdayName(20706), "Thu")
check("2100-02-28 is a Sunday", draw:WeekdayName(47540), "Sun")

print("\n== 5. which day it is, from two clocks ==")
-- The whole point. Nine in the evening in Japan is noon UTC on the SAME date, but nine in the
-- morning in Japan is midnight UTC -- a naive floor(GetTimeStamp()/86400) rolls the fortune
-- over right there, in the middle of somebody's day.
SetLocalTime(20706, 9, 0, 9)   -- 2026-09-10 09:00 JST
check("09:00 JST is the 10th", dateOf(draw:DayKey()), "2026-09-10")
SetLocalTime(20706, 8, 59, 9)
check("08:59 JST is still the 10th", dateOf(draw:DayKey()), "2026-09-10")
SetLocalTime(20706, 0, 0, 9)
check("midnight JST is the 10th", dateOf(draw:DayKey()), "2026-09-10")
SetLocalTime(20706, 23, 59, 9)
check("23:59 JST is still the 10th", dateOf(draw:DayKey()), "2026-09-10")
SetLocalTime(20707, 0, 1, 9)
check("00:01 JST is the 11th", dateOf(draw:DayKey()), "2026-09-11")

-- Every zone anybody plays from, at both ends of the local day.
-- Every zone anybody plays from, at both ends of the local day and across the boundary.
local zones = {
	{ "UTC", 0 }, { "JST +9", 9 }, { "CET +1", 1 }, { "MSK +3", 3 }, { "IST +5:30", 5.5 },
	{ "NPT +5:45", 5.75 }, { "ACST +9:30", 9.5 }, { "AEDT +11", 11 }, { "EST -5", -5 },
	{ "PST -8", -8 }, { "AKDT -8", -8 }, { "HST -10", -10 }, { "NZST +12", 12 },
	{ "CHAST +12:45", 12.75 }, { "NZDT +13", 13 },
}
for _, zone in ipairs(zones) do
	local name, offset = zone[1], zone[2]
	for _, moment in ipairs({ { 0, 0, "00:00" }, { 0, 1, "00:01" }, { 12, 0, "noon" },
		{ 23, 59, "23:59" } }) do
		SetLocalTime(20706, moment[1], moment[2], offset)
		check("  " .. name .. " at " .. moment[3], dateOf(draw:DayKey()), "2026-09-10")
	end
	SetLocalTime(20707, 0, 0, offset)
	check("  " .. name .. " rolls over at local midnight", dateOf(draw:DayKey()), "2026-09-11")
end

-- The known limitation, asserted rather than left to be discovered. A wall clock reading is
-- ambiguous between UTC-11 and UTC+13 and the client has no timezone call to break the tie,
-- so the band is set for the side more people are on -- and the other side is a whole day out,
-- not an hour. Written down here so that anyone who moves the band finds out what it costs.
for _, zone in ipairs({ { "SST -11", -11 }, { "CHADT +13:45", 13.75 }, { "LINT +14", 14 } }) do
	SetLocalTime(20706, 12, 0, zone[2])
	local got = dateOf(draw:DayKey())
	check("  " .. zone[1] .. " reads a neighbouring day (known)", got ~= "2026-09-10", true)
end

-- The two clocks are different clocks and disagree by seconds. Without the snap, a login a
-- few seconds either side of local midnight has a UTC day one behind the local one and hands
-- out a second fortune for the same day.
for _, offset in ipairs({ 0, 9, -8, 5.5, 12, -5 }) do
	for _, moment in ipairs({ { 0, 0 }, { 23, 59 } }) do
		SetLocalTime(20706, moment[1], moment[2], offset)
		local want = draw:DayKey()
		local stamp, since = GetTimeStamp(), GetSecondsSinceMidnight()
		for _, drift in ipairs({ 7, -11, 59, -59, 240, -240 }) do
			SetClock(stamp + drift, since)
			check(string.format("  %+g h, %02d:%02d, drift %+ds", offset, moment[1], moment[2],
				drift), draw:DayKey(), want)
		end
	end
end

-- If GetTimeStamp() were local rather than UTC on some platform, the implied offset is zero
-- and the answer has to come out the same.
SetClock(20706 * 86400 + 21 * 3600, 21 * 3600)
check("a server clock that is already local still works", dateOf(draw:DayKey()), "2026-09-10")

print("\n== 6. the same day is the same slip ==")
SetLocalTime(20706, 21, 0, 9)
SetCharacter("1000000001", "Bosmer Bunbun")
local first = draw:Today()
check("a slip came back", first ~= nil, true)
local again = draw:Today()
check("asking twice gives the same number", again.index, first.index)
check("and the same rank", again.rank.name, first.rank.name)

-- The claim the whole design rests on: SavedVariables is a convenience, not the fortune.
ForgetSavedVars()
check("losing SavedVariables changes nothing", draw:Today().index, first.index)

-- Reading it must not mark it as shown, or /omikuji status would silence the next login.
ForgetSavedVars()
draw:Today()
addon:PrintStatus()
check("asking does not count as having seen it", draw:SeenToday(draw:Today()), false)
addon.draw:Record(draw:Today())
check("recording it does", draw:SeenToday(draw:Today()), true)

print("\n== 7. different days, different characters ==")
SetCharacter("2000000002", "Altmer Alt")
local otherCharacter = draw:Today()
check("another character gets its own slip", otherCharacter.index ~= first.index, true)

SetCharacter("1000000001", "Bosmer Bunbun")
SetLocalTime(20707, 21, 0, 9)
check("tomorrow is a different slip", draw:Today().index ~= first.index, true)
SetLocalTime(20706, 21, 0, 9)
check("and going back gives the first one again", draw:Today().index, first.index)

-- Account scope draws for the account, so every character shares the day's slip.
addon:SetScope("ACCOUNT")
local accountSlip = draw:Today()
SetCharacter("3000000003", "Nord Nord")
check("account scope: same slip on every character", draw:Today().index, accountSlip.index)
addon:SetScope("CHARACTER")
SetCharacter("1000000001", "Bosmer Bunbun")

print("\n== 8. the hash spreads ==")
-- 20000 consecutive days through one identity. Every one of the 365 slips has to be reachable,
-- and none of them may be hoarding days -- a hash that fails this quietly turns the add-on
-- into a five-fortune add-on and nobody would notice for months.
local buckets, hit = {}, 0
for day = 1, 20000 do
	local index = draw:IndexFor(day, "1000000001")
	if not buckets[index] then hit = hit + 1 end
	buckets[index] = (buckets[index] or 0) + 1
end
check("every one of the 365 slips can come up", hit, 365)
local low, high = math.huge, 0
for index = 1, 365 do
	low = math.min(low, buckets[index])
	high = math.max(high, buckets[index])
end
-- 20000 draws over 365 buckets expects 54.8 each; these bounds are wide enough that a fair
-- hash will never trip them and narrow enough to catch one that is not.
checkBetween("the least-drawn slip is not starved", low, 20, 100)
checkBetween("the most-drawn slip is not hogging", high, 25, 120)

-- And the ranks come out in the proportions Fortunes.lua documents, because that IS the
-- balance of the add-on.
local rankHits = {}
for day = 1, 20000 do
	local pattern = draw:PatternAt(draw:IndexFor(day, "1000000001"))
	rankHits[pattern.rank.key] = (rankHits[pattern.rank.key] or 0) + 1
end
for _, rank in ipairs(addon.RANKS) do
	local expected = #addon.MESSAGES[rank.key] / 365 * 20000
	checkBetween("  " .. rank.name .. " comes up about as often as it should",
		rankHits[rank.key], math.floor(expected * 0.85), math.ceil(expected * 1.15))
end

-- Consecutive days are the one input guaranteed to be nearly identical every time, so they
-- are the ones a weak hash sticks on.
local distinct, run = {}, 0
for day = 20700, 20799 do
	local index = draw:IndexFor(day, "1000000001")
	if not distinct[index] then run = run + 1 end
	distinct[index] = true
end
checkBetween("100 days in a row are not the same few slips", run, 75, 100)

print("\n== 9. login, and what is not a login ==")
Chat = {}
SetLocalTime(20706, 21, 0, 9)
ForgetSavedVars()
Fire(EVENT_PLAYER_ACTIVATED)
check("logging in says two lines", #Chat, 2)
checkContains("the first names the add-on", Chat[1], "Omikuji")
checkContains("and carries the date", PlainChat(1), "2026-09-10")
local slip = draw:Today()
checkContains("the second carries the rank", PlainChat(2), slip.rank.name)
checkContains("and the fortune itself", PlainChat(2), slip.message)
check("the panel was built", Panel ~= nil, true)

Chat = {}
Fire(EVENT_PLAYER_ACTIVATED)
check("a zone change says nothing", #Chat, 0)
Fire(EVENT_PLAYER_ACTIVATED)
Fire(EVENT_PLAYER_ACTIVATED)
check("nor do the next two", #Chat, 0)

print("\n== 10. only the first login of the day ==")
Chat = {}
addon:SetOncePerDay(true)
ForgetSavedVars()
check("the first one prints", addon:PrintFortune(false), true)
check("the second one does not", addon:PrintFortune(false), false)
check("so only two lines were said", #Chat, 2)
check("but typing the command still answers", addon:PrintFortune(true), true)
check("which is two more lines", #Chat, 4)
SetLocalTime(20707, 21, 0, 9)
Chat = {}
check("and a new day prints again", addon:PrintFortune(false), true)
addon:SetOncePerDay(false)
SetLocalTime(20706, 21, 0, 9)

print("\n== 11. the master switch ==")
Chat = {}
addon:SetEnabled(false)
check("off is off", addon:Enabled(), false)
-- The switch is read by the activation handler, not by PrintFortune, so that a command typed
-- with the add-on switched off still answers the person who typed it.
check("but /omikuji still answers", addon:PrintFortune(true), true)
addon:SetEnabled(true)

print("\n== 12. the slash command ==")
local function Command(text)
	Chat = {}
	SLASH_COMMANDS["/omikuji"](text)
	return Chat
end

check("bare /omikuji says the fortune", #Command(""), 2)
checkContains("status reports the total", table.concat(Command("status"), "\n"), "365")
check("ranks lists all seven, under a header", #Command("ranks"), 8)
checkContains("ranks names 大凶", table.concat(Command("ranks"), "\n"), "大凶")
Command("scope account")
check("scope account took", addon:Scope(), "ACCOUNT")
Command("scope character")
check("scope character took", addon:Scope(), "CHARACTER")
checkContains("a bad scope is refused", table.concat(Command("scope goblin"), "\n"),
	GetString(SI_PBSOMI_ERROR_SCOPE))
check("scope did not change", addon:Scope(), "CHARACTER")
Command("once on")
check("once on took", addon:OncePerDay(), true)
Command("once off")
check("once off took", addon:OncePerDay(), false)
checkContains("once needs on or off", table.concat(Command("once maybe"), "\n"),
	GetString(SI_PBSOMI_ERROR_ON_OR_OFF))
Command("date off")
check("date off took", addon:ShowDate(), false)
local dateless = draw:Compose(draw:Today())
check("it is still two lines", #dateless, 2)
check("but the date is gone", dateless[1]:find("2026", 1, true) == nil, true)
checkContains("and the add-on still names itself", dateless[1], "Omikuji")
Command("date on")
check("date on took", addon:ShowDate(), true)
checkContains("and the date is back", draw:Compose(draw:Today())[1], "2026")
Command("off")
check("/omikuji off took", addon:Enabled(), false)
Command("on")
check("/omikuji on took", addon:Enabled(), true)
checkContains("an unknown verb says so", table.concat(Command("bogus"), "\n"), "bogus")
check("and follows it with the help", #Command("bogus") > 5, true)
check("help on its own", #Command("help") > 5, true)

addon:SetScope("ACCOUNT")
addon:SetOncePerDay(true)
Command("reset")
check("reset puts the scope back", addon:Scope(), "CHARACTER")
check("reset puts once-per-day back", addon:OncePerDay(), false)
check("reset empties the record", next(addon.sv.records) == nil, true)

print("\n== 13. the panel ==")
check("the panel has rows", Panel and #Panel.rows > 0, true)
check("the panel is titled with the version", Panel.title, addon.title)
local showRow = Panel.byLabel[GetString(SI_PBSOMI_DRAW_NOW)]
check("there is a show-today button", showRow ~= nil, true)
Chat = {}
showRow.clickHandler()
check("pressing it says the fortune", #Chat, 2)
local enabledRow = Panel.byLabel[GetString(SI_PBSOMI_ENABLED)]
enabledRow.setFunction(false)
check("the checkbox writes through", addon:Enabled(), false)
check("and reads back", enabledRow.getFunction(), false)
enabledRow.setFunction(true)

print("\n== 14. the translation is complete ==")
-- A missing line falls back to English and is merely untidy; a line whose %s count does not
-- match the English one is a crash in somebody's chat window the first time it is printed.
local function ReadStrings(path)
	local file = assert(io.open(ADDON_DIR .. path, "r"))
	local found = {}
	for line in file:lines() do
		local id, value = line:match("^%s*(SI_PBSOMI_[A-Z0-9_]+)%s*=%s*\"(.*)\",%s*$")
		if id then found[id] = value end
	end
	file:close()
	return found
end
local function Specifiers(text)
	local n = 0
	for _ in tostring(text):gmatch("%%[%-%+ #0]*%d*%.?%d*[diouxXeEfgGqscp]") do n = n + 1 end
	return n
end

local english = ReadStrings("/lang/strings.lua")
local japanese = ReadStrings("/lang/jp.lua")
local englishCount = 0
for _ in pairs(english) do englishCount = englishCount + 1 end
checkBetween("the English file has strings in it", englishCount, 40, 200)

local missing, mismatched = {}, {}
for id, text in pairs(english) do
	if japanese[id] == nil then
		missing[#missing + 1] = id
	elseif Specifiers(japanese[id]) ~= Specifiers(text) then
		mismatched[#mismatched + 1] = id
	end
end
check("nothing is untranslated", #missing == 0 and "none" or table.concat(missing, ","), "none")
check("every translation takes the same arguments",
	#mismatched == 0 and "none" or table.concat(mismatched, ","), "none")

local orphans = {}
for id in pairs(japanese) do
	if english[id] == nil then orphans[#orphans + 1] = id end
end
check("no translation of a string that no longer exists",
	#orphans == 0 and "none" or table.concat(orphans, ","), "none")

local function WeekdayCount(text)
	local n = 0
	for _ in tostring(text):gmatch("[^,]+") do n = n + 1 end
	return n
end
check("seven English weekdays", WeekdayCount(english.SI_PBSOMI_WEEKDAYS), 7)
check("seven Japanese weekdays", WeekdayCount(japanese.SI_PBSOMI_WEEKDAYS), 7)

print("")
if failures == 0 then
	print("all checks passed")
else
	print(failures .. " FAILED")
end
os.exit(failures == 0 and 0 or 1)
