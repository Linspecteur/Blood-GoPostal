-- Réglages modifiés depuis le menu admin, profils des livreurs et historique,
-- sauvegardés dans data/*.json (prioritaires sur config.lua, qui ne sert plus que de valeurs par défaut)
GoPostal = GoPostal or {}

local RES = GetCurrentResourceName()
local SETTINGS_FILE = 'data/settings.json'
local HISTORY_FILE = 'data/history.json'
local PLAYERS_FILE = 'data/players.json'
local STATS_FILE = 'data/stats.json'
local HISTORY_MAX = 300

GoPostal.enabled = true
GoPostal.history = {}
GoPostal.players = {}
GoPostal.stats = {}

local function v3(t) return vector3(t.x + 0.0, t.y + 0.0, t.z + 0.0) end
local function v4(t) return vector4(t.x + 0.0, t.y + 0.0, t.z + 0.0, (t.w or 0) + 0.0) end
local function ser(v) return { x = v.x, y = v.y, z = v.z, w = v.w } end
GoPostal.ser = ser

local function readJson(file)
    local raw = LoadResourceFile(RES, file)
    if not raw or raw == '' then return nil end
    local ok, data = pcall(json.decode, raw)
    return ok and data or nil
end

local function writeJson(file, data)
    SaveResourceFile(RES, file, json.encode(data), -1)
end

-- --- RÉGLAGES ---
function GoPostal.getSettings()
    return {
        enabled = GoPostal.enabled,
        deposit = Config.Deposit,
        payMultiplier = Config.Pay.multiplier,
        xpMultiplier = Config.Pay.xpMultiplier,
        perKm = Config.Pay.perKm,
        presentChance = math.floor(Config.Customer.presentChance * 100 + 0.5),
        tipChance = math.floor(Config.Customer.tipChance * 100 + 0.5),
        cooldown = math.floor(Config.Cooldown / 60),
        maxActive = Config.MaxActive,
        capPerHour = Config.Cap.perHour,
        capRate = math.floor(Config.Cap.overRate * 100 + 0.5),
        reward1 = Config.WeeklyRewards[1] or 0,
        reward2 = Config.WeeklyRewards[2] or 0,
        reward3 = Config.WeeklyRewards[3] or 0,
        nightBonus = math.floor(Config.Night.payBonus * 100 + 0.5),
        premiumRating = Config.Premium.minRating
    }
end

local function clampNum(v, min, max, default)
    v = tonumber(v)
    if not v then return default end
    return math.max(min, math.min(max, v))
end

function GoPostal.applySettings(s)
    if type(s) ~= 'table' then return end
    if s.enabled ~= nil then GoPostal.enabled = s.enabled == true end
    Config.Deposit = math.floor(clampNum(s.deposit, 0, 1000000, Config.Deposit))
    Config.Pay.multiplier = clampNum(s.payMultiplier, 0.1, 10.0, Config.Pay.multiplier)
    Config.Pay.xpMultiplier = clampNum(s.xpMultiplier, 0.1, 10.0, Config.Pay.xpMultiplier)
    Config.Pay.perKm = math.floor(clampNum(s.perKm, 0, 10000, Config.Pay.perKm))
    Config.Customer.presentChance = clampNum(s.presentChance, 0, 100, Config.Customer.presentChance * 100) / 100
    Config.Customer.tipChance = clampNum(s.tipChance, 0, 100, Config.Customer.tipChance * 100) / 100
    Config.Cooldown = math.floor(clampNum(s.cooldown, 0, 1440, Config.Cooldown / 60) * 60)
    Config.MaxActive = math.floor(clampNum(s.maxActive, 1, 100, Config.MaxActive))
    Config.Cap.perHour = math.floor(clampNum(s.capPerHour, 0, 10000000, Config.Cap.perHour))
    Config.Cap.overRate = clampNum(s.capRate, 0, 100, Config.Cap.overRate * 100) / 100
    for i = 1, 3 do
        Config.WeeklyRewards[i] = math.floor(clampNum(s['reward' .. i], 0, 10000000, Config.WeeklyRewards[i] or 0))
    end
    Config.Night.payBonus = clampNum(s.nightBonus, 0, 500, Config.Night.payBonus * 100) / 100
    Config.Premium.minRating = clampNum(s.premiumRating, 1, 5, Config.Premium.minRating)
end

-- --- POSITIONS ---
function GoPostal.getPositions()
    local addresses = {}
    for _, a in ipairs(Config.Addresses) do
        addresses[#addresses + 1] = { label = a.label or '', zone = a.zone, coords = ser(a.coords) }
    end
    local vanSpawns = {}
    for i, s in ipairs(Config.VanSpawns) do vanSpawns[i] = ser(s) end
    return {
        npc = ser(Config.Npc.coords),
        vanSpawns = vanSpawns,
        returnPoint = ser(Config.Return.coords),
        addresses = addresses
    }
end

function GoPostal.applyPositions(p)
    if type(p) ~= 'table' then return end
    if p.npc and p.npc.x then Config.Npc.coords = v4(p.npc) end
    if type(p.vanSpawns) == 'table' and #p.vanSpawns > 0 then
        local list = {}
        for _, s in ipairs(p.vanSpawns) do
            if s.x then list[#list + 1] = v4(s) end
        end
        if #list > 0 then Config.VanSpawns = list end
    elseif p.vanSpawn and p.vanSpawn.x then
        Config.VanSpawns = { v4(p.vanSpawn) } -- ancienne sauvegarde à une seule place
    end
    if p.returnPoint and p.returnPoint.x then Config.Return.coords = v3(p.returnPoint) end
    if type(p.addresses) == 'table' and #p.addresses > 0 then
        local list = {}
        for _, a in ipairs(p.addresses) do
            if a.coords and a.coords.x and Config.Zones[a.zone] then
                list[#list + 1] = { label = tostring(a.label or ''), zone = a.zone, coords = v3(a.coords) }
            end
        end
        if #list > 0 then Config.Addresses = list end
    end
end

function GoPostal.saveSettings()
    writeJson(SETTINGS_FILE, { settings = GoPostal.getSettings(), positions = GoPostal.getPositions() })
end

-- --- PROFILS DES LIVREURS ---
function GoPostal.weekKey()
    return os.date('%Y-%W')
end

function GoPostal.levelFor(xp)
    local idx = 1
    for i, l in ipairs(Config.Levels) do
        if xp >= l.xp then idx = i end
    end
    return idx, Config.Levels[idx], Config.Levels[idx + 1]
end

function GoPostal.getProfile(identifier, name)
    -- Le classement de la semaine passée doit être récompensé avant toute remise à zéro
    if GoPostal.checkWeek then GoPostal.checkWeek() end
    local p = GoPostal.players[identifier]
    if not p then
        p = { name = name or '?', xp = 0, delivered = 0, tours = 0, earned = 0, tips = 0,
              ratingSum = 0, ratingCount = 0, week = '', weekDelivered = 0, weekEarned = 0, levelPaid = 1 }
        GoPostal.players[identifier] = p
    end
    -- Profils d'avant les primes de niveau : pas de rattrapage sur les niveaux déjà atteints
    if p.levelPaid == nil then p.levelPaid = GoPostal.levelFor(p.xp); GoPostal.playersDirty = true end
    -- Profils d'avant les succès : compteurs repris des totaux existants
    if not p.counters and GoPostal.counters then GoPostal.counters(p) end
    if name and p.name ~= name then p.name = name; GoPostal.playersDirty = true end
    local wk = GoPostal.weekKey()
    if p.week ~= wk then
        p.week, p.weekDelivered, p.weekEarned = wk, 0, 0
        GoPostal.playersDirty = true
    end
    return p
end

-- --- SATISFACTION ---
-- Notes des dernières livraisons (fenêtre glissante de Config.Premium.window)
function GoPostal.addRecentRating(p, stars)
    p.recent = p.recent or {}
    table.insert(p.recent, stars)
    while #p.recent > (Config.Premium.window or 50) do table.remove(p.recent, 1) end
end

function GoPostal.satisfaction(p)
    local list = p.recent or {}
    if #list == 0 then return nil, 0 end
    local sum = 0
    for _, s in ipairs(list) do sum = sum + s end
    return sum / #list, #list
end

function GoPostal.premiumOk(p)
    local avg, n = GoPostal.satisfaction(p)
    return avg ~= nil and n >= Config.Premium.minRatings and avg >= Config.Premium.minRating
end

-- Profil formaté pour l'UI
function GoPostal.profileView(p)
    local idx, lvl, nextLvl = GoPostal.levelFor(p.xp)
    return {
        name = p.name,
        level = idx,
        maxLevel = #Config.Levels,
        title = lvl.title,
        mult = lvl.mult,
        xp = p.xp,
        xpFrom = lvl.xp,
        xpNext = nextLvl and nextLvl.xp or nil,
        delivered = p.delivered,
        tours = p.tours,
        earned = p.earned,
        tips = p.tips,
        rating = p.ratingCount > 0 and (p.ratingSum / p.ratingCount) or nil,
        weekDelivered = p.weekDelivered,
        weekEarned = p.weekEarned,
        perks = GoPostal.perksFor and GoPostal.perksFor(idx) or {},
        plate = p.plate,
        satisfaction = (GoPostal.satisfaction(p)),
        satisfactionCount = select(2, GoPostal.satisfaction(p)),
        premium = GoPostal.premiumOk(p),
        streak = GoPostal.streakDays and {
            days = GoPostal.streakDays(p),
            bonus = GoPostal.streakBonus(p),
            best = p.streak and p.streak.best or 0,
            today = p.streak and p.streak.day == os.date('%Y-%m-%d') and p.streak.count or 0,
            validated = p.streak ~= nil and p.streak.last == os.date('%Y-%m-%d')
        } or nil
    }
end

function GoPostal.leaderboard(limit, meIdentifier)
    local wk = GoPostal.weekKey()
    local list = {}
    for id, p in pairs(GoPostal.players) do
        if p.week == wk and p.weekDelivered > 0 then
            list[#list + 1] = { name = p.name, delivered = p.weekDelivered, earned = p.weekEarned, me = id == meIdentifier }
        end
    end
    table.sort(list, function(a, b)
        if a.delivered ~= b.delivered then return a.delivered > b.delivered end
        return a.earned > b.earned
    end)
    local out = {}
    for i = 1, math.min(limit or 10, #list) do out[i] = list[i] end
    return out
end

-- --- HISTORIQUE ---
function GoPostal.addHistory(entry)
    table.insert(GoPostal.history, 1, entry)
    while #GoPostal.history > HISTORY_MAX do table.remove(GoPostal.history) end
    GoPostal.historyDirty = true
end

-- --- STATISTIQUES PAR JOUR ---
-- stats[YYYY-MM-DD] = { tours, success, partial, cancel, fail, parcels, paid, duration, team,
--                       couriers = { [identifier] = true }, byTour = { [id] = { n, success, paid, parcels } }, reasons = { [raison] = n } }
local STATS_DAYS = 60

function GoPostal.recordStats(e)
    local day = os.date('%Y-%m-%d')
    local d = GoPostal.stats[day]
    if not d then
        d = { tours = 0, success = 0, partial = 0, cancel = 0, fail = 0, parcels = 0, paid = 0, duration = 0, team = 0,
              couriers = {}, byTour = {}, reasons = {} }
        GoPostal.stats[day] = d
    end
    d.tours = d.tours + 1
    d[e.result] = (d[e.result] or 0) + 1
    d.parcels = d.parcels + (e.delivered or 0)
    d.paid = d.paid + (e.paid or 0)
    d.duration = d.duration + (e.duration or 0)
    if (e.team or 1) > 1 then d.team = d.team + 1 end
    for _, id in ipairs(e.identifiers or {}) do d.couriers[id] = true end
    local bt = d.byTour[e.tourId] or { n = 0, success = 0, paid = 0, parcels = 0 }
    bt.n = bt.n + 1
    if e.result == 'success' then bt.success = bt.success + 1 end
    bt.paid = bt.paid + (e.paid or 0)
    bt.parcels = bt.parcels + (e.delivered or 0)
    d.byTour[e.tourId] = bt
    if e.result == 'fail' or e.result == 'cancel' then
        local r = e.reason or e.result
        d.reasons[r] = (d.reasons[r] or 0) + 1
    end

    -- Ménage : on ne garde que les derniers jours
    local limit = os.date('%Y-%m-%d', os.time() - STATS_DAYS * 86400)
    for k in pairs(GoPostal.stats) do
        if k < limit then GoPostal.stats[k] = nil end
    end
    GoPostal.statsDirty = true
end

-- Les `days` derniers jours, du plus ancien au plus récent (jours vides compris)
function GoPostal.statsRange(days)
    local list = {}
    for i = days - 1, 0, -1 do
        local key = os.date('%Y-%m-%d', os.time() - i * 86400)
        local d = GoPostal.stats[key]
        local couriers = 0
        if d then for _ in pairs(d.couriers or {}) do couriers = couriers + 1 end end
        list[#list + 1] = {
            day = key,
            tours = d and d.tours or 0,
            success = d and d.success or 0,
            partial = d and d.partial or 0,
            cancel = d and d.cancel or 0,
            fail = d and d.fail or 0,
            parcels = d and d.parcels or 0,
            paid = d and d.paid or 0,
            duration = d and d.duration or 0,
            team = d and d.team or 0,
            couriers = couriers,
            byTour = d and d.byTour or {},
            reasons = d and d.reasons or {}
        }
    end
    return list
end

local function flush()
    if GoPostal.statsDirty then
        GoPostal.statsDirty = false
        writeJson(STATS_FILE, GoPostal.stats)
    end
    if GoPostal.historyDirty then
        GoPostal.historyDirty = false
        writeJson(HISTORY_FILE, GoPostal.history)
    end
    if GoPostal.playersDirty then
        GoPostal.playersDirty = false
        writeJson(PLAYERS_FILE, GoPostal.players)
    end
end

CreateThread(function()
    while true do
        Wait(30000)
        flush()
    end
end)

AddEventHandler('onResourceStop', function(name)
    if name == RES then flush() end
end)

-- --- CHARGEMENT AU DÉMARRAGE ---
do
    local saved = readJson(SETTINGS_FILE)
    if saved then
        GoPostal.applySettings(saved.settings)
        GoPostal.applyPositions(saved.positions)
        print('[bl_gopostal] Réglages chargés depuis ' .. SETTINGS_FILE)
    end
    GoPostal.history = readJson(HISTORY_FILE) or {}
    GoPostal.players = readJson(PLAYERS_FILE) or {}
    GoPostal.stats = readJson(STATS_FILE) or {}
end
