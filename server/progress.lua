-- Missions quotidiennes / hebdo, récompenses de niveau, récompenses du classement
-- et plafond de gains horaire.
GoPostal = GoPostal or {}

local RES = GetCurrentResourceName()
local STATE_FILE = 'data/state.json'

-- --- MISSIONS ---
local function dayKey() return os.date('%Y-%m-%d') end

-- Tirage identique pour tout le monde : graine tirée de la date
local function seeded(key)
    local h = 0
    for i = 1, #key do h = (h * 31 + key:byte(i)) % 2147483647 end
    return function(n)
        h = (h * 1103515245 + 12345) % 2147483648
        return h % n + 1
    end
end

local picked = {}
local function pickMissions(kind, key)
    local cacheKey = kind .. key
    if picked[cacheKey] then return picked[cacheKey] end
    local pool = Config.Missions[kind] or {}
    local count = Config.Missions[kind == 'daily' and 'dailyCount' or 'weeklyCount'] or 3
    local idx = {}
    for i = 1, #pool do idx[i] = i end
    local rnd = seeded(kind .. key)
    for i = #idx, 2, -1 do
        local j = rnd(i)
        idx[i], idx[j] = idx[j], idx[i]
    end
    local list = {}
    for i = 1, math.min(count, #idx) do list[i] = pool[idx[i]] end
    picked[cacheKey] = list
    return list
end

-- Progression du joueur pour la période en cours (remise à zéro au changement de jour / semaine)
local function missionState(profile, kind)
    local key = kind == 'daily' and dayKey() or GoPostal.weekKey()
    local st = profile.missions and profile.missions[kind]
    if not st or st.key ~= key then
        profile.missions = profile.missions or {}
        st = { key = key, progress = {}, done = {} }
        profile.missions[kind] = st
        GoPostal.playersDirty = true
    end
    return st, pickMissions(kind, key)
end

function GoPostal.missionsView(profile)
    local out = {}
    for _, kind in ipairs({ 'daily', 'weekly' }) do
        local st, list = missionState(profile, kind)
        local rows = {}
        for i, mi in ipairs(list) do
            rows[i] = {
                label = mi.label, goal = mi.goal, cash = mi.cash, xp = mi.xp,
                progress = math.min(mi.goal, st.progress[mi.id] or 0),
                done = st.done[mi.id] == true
            }
        end
        out[kind] = rows
    end
    return out
end

-- --- COMPTEURS À VIE ET SUCCÈS ---
-- Mêmes clés que les stats des missions, cumulées depuis le début (records pour fragileStreak et streak)
local function counters(profile)
    if not profile.counters then
        profile.counters = { deliver = profile.delivered or 0, tour = profile.tours or 0, earn = profile.earned or 0 }
        GoPostal.playersDirty = true
    end
    return profile.counters
end
GoPostal.counters = counters

-- Record : garde la plus grande valeur atteinte
function GoPostal.setRecord(profile, stat, value)
    local c = counters(profile)
    if value > (c[stat] or 0) then
        c[stat] = value
        GoPostal.playersDirty = true
    end
end

function GoPostal.checkAchievements(src, profile)
    local c = counters(profile)
    profile.achievements = profile.achievements or {}
    for _, a in ipairs(Config.Achievements or {}) do
        if not profile.achievements[a.id] and (c[a.stat] or 0) >= a.goal then
            profile.achievements[a.id] = os.time()
            profile.xp = profile.xp + (a.xp or 0)
            GoPostal.addMoney(src, a.cash or 0)
            GoPostal.playersDirty = true
            TriggerClientEvent('bl_gopostal:mission', src, {
                label = a.label, cash = a.cash or 0, xp = a.xp or 0, kind = 'Succès', achievement = true
            })
        end
    end
end

function GoPostal.achievementsView(profile)
    local c = counters(profile)
    local got = profile.achievements or {}
    local list = {}
    for i, a in ipairs(Config.Achievements or {}) do
        list[i] = {
            label = a.label, desc = a.desc, goal = a.goal, cash = a.cash or 0, xp = a.xp or 0,
            progress = math.min(a.goal, c[a.stat] or 0), done = got[a.id] ~= nil, at = got[a.id]
        }
    end
    return list
end

-- stats : { deliver = 1, fragile = 1, ... } ajoutés à la progression
function GoPostal.missionProgress(src, profile, stats)
    local c = counters(profile)
    for stat, add in pairs(stats) do
        if add and add > 0 then c[stat] = (c[stat] or 0) + add end
    end
    GoPostal.playersDirty = true
    for _, kind in ipairs({ 'daily', 'weekly' }) do
        local st, list = missionState(profile, kind)
        for _, mi in ipairs(list) do
            local add = stats[mi.stat]
            if add and add > 0 and not st.done[mi.id] then
                st.progress[mi.id] = (st.progress[mi.id] or 0) + add
                if st.progress[mi.id] >= mi.goal then
                    st.done[mi.id] = true
                    profile.xp = profile.xp + (mi.xp or 0)
                    GoPostal.addMoney(src, mi.cash or 0)
                    TriggerClientEvent('bl_gopostal:mission', src, {
                        label = mi.label, cash = mi.cash or 0, xp = mi.xp or 0,
                        kind = kind == 'daily' and 'Mission du jour' or 'Mission de la semaine'
                    })
                end
                GoPostal.playersDirty = true
            end
        end
    end
    GoPostal.checkAchievements(src, profile)
end

-- --- SÉRIE DE JOURS ---
local function dayOffset(d) return os.date('%Y-%m-%d', os.time() + d * 86400) end

-- Jours consécutifs validés (la série tient tant que la dernière journée validée est aujourd'hui ou hier)
function GoPostal.streakDays(profile)
    local s = profile.streak
    if not s or not Config.Streak or not Config.Streak.enabled then return 0 end
    if s.last == dayOffset(0) or s.last == dayOffset(-1) then return s.days or 0 end
    return 0
end

function GoPostal.streakBonus(profile)
    local S = Config.Streak
    if not S or not S.enabled then return 0 end
    return math.min(S.max or 0, (S.perDay or 0) * GoPostal.streakDays(profile))
end

-- Un colis de plus aujourd'hui : la journée est validée au bout de minParcels colis
function GoPostal.streakDeliver(src, profile)
    local S = Config.Streak
    if not S or not S.enabled then return end
    local today = dayOffset(0)
    local s = profile.streak or {}
    profile.streak = s
    if s.day ~= today then s.day, s.count = today, 0 end
    s.count = s.count + 1
    if s.count >= (S.minParcels or 1) and s.last ~= today then
        s.days = (s.last == dayOffset(-1)) and (s.days or 0) + 1 or 1
        s.last = today
        s.best = math.max(s.best or 0, s.days)
        GoPostal.setRecord(profile, 'streak', s.days)
        local bonus = math.floor(GoPostal.streakBonus(profile) * 100 + 0.5)
        TriggerClientEvent('bl_gopostal:notify', src, s.days > 1
            and ('Série de %d jours d\'affilée : paie des colis +%d %% !'):format(s.days, bonus)
            or ('Journée validée : reviens demain pour lancer une série (+%d %% par jour).'):format(math.floor(S.perDay * 100 + 0.5)), 'success')
    end
    GoPostal.playersDirty = true
end

-- --- RÉCOMPENSES DE NIVEAU ---
-- Prime versée une seule fois par niveau atteint
function GoPostal.checkLevelRewards(src, profile)
    local idx = GoPostal.levelFor(profile.xp)
    profile.levelPaid = profile.levelPaid or idx
    while profile.levelPaid < idx do
        profile.levelPaid = profile.levelPaid + 1
        local l = Config.Levels[profile.levelPaid]
        if l and (l.cash or 0) > 0 then
            GoPostal.addMoney(src, l.cash)
            TriggerClientEvent('bl_gopostal:notify', src, ('Prime de promotion « %s » : +%d $'):format(l.title, l.cash), 'success')
        end
        GoPostal.playersDirty = true
    end
end

-- Avantages débloqués à un niveau donné (cumulés)
function GoPostal.perksFor(levelIdx)
    local perks = { van = nil, outfit = false, plate = false }
    for i = 1, levelIdx do
        local l = Config.Levels[i]
        if l then
            if l.van then perks.van = l.van end
            if l.outfit then perks.outfit = true end
            if l.plate then perks.plate = true end
        end
    end
    return perks
end

-- --- PLAFOND DE GAINS ---
local earnings = {}   -- [identifier] = { { t, amount }, ... }

function GoPostal.earnedLastHour(identifier)
    local list = earnings[identifier]
    if not list then return 0 end
    local now, sum = os.time(), 0
    for i = #list, 1, -1 do
        if now - list[i][1] > 3600 then table.remove(list, i) else sum = sum + list[i][2] end
    end
    return sum
end

-- Applique le plafond à un gain, l'enregistre, et renvoie le montant réellement versé
function GoPostal.capEarn(identifier, amount)
    if amount <= 0 or not Config.Cap or (Config.Cap.perHour or 0) <= 0 then return amount, false end
    local before = GoPostal.earnedLastHour(identifier)
    -- Pendant un événement, le plafond suit le multiplicateur de paie
    local rush = GoPostal.rushActive()
    local room = math.max(0, Config.Cap.perHour * math.max(1.0, rush and rush.pay or 1.0) - before)
    local paid = amount
    if amount > room then
        paid = room + math.floor((amount - room) * (Config.Cap.overRate or 0))
    end
    earnings[identifier] = earnings[identifier] or {}
    table.insert(earnings[identifier], { os.time(), paid })
    return paid, paid < amount
end

-- --- RÉCOMPENSES DU CLASSEMENT HEBDO ---
local state = {}
do
    local raw = LoadResourceFile(RES, STATE_FILE)
    local ok, data = pcall(json.decode, raw or '')
    state = ok and type(data) == 'table' and data or {}
end
local function saveState() SaveResourceFile(RES, STATE_FILE, json.encode(state), -1) end

-- Verse les récompenses en attente d'un joueur en ligne
function GoPostal.payPending(src, identifier)
    local p = GoPostal.players[identifier]
    if not p or not p.pendingReward then return end
    local r = p.pendingReward
    p.pendingReward = nil
    GoPostal.playersDirty = true
    GoPostal.addMoney(src, r.amount)
    TriggerClientEvent('bl_gopostal:notify', src,
        ('Classement de la semaine : tu as fini %de ! Récompense de %d $ versée.'):format(r.rank, r.amount), 'success')
end

function GoPostal.checkWeek()
    local wk = GoPostal.weekKey()
    if not state.week then state.week = wk; saveState(); return end
    if state.week == wk then return end

    local old = state.week
    state.week = wk
    saveState()

    -- Classement de la semaine écoulée (les profils ne sont remis à zéro qu'à leur prochain accès)
    local list = {}
    for id, p in pairs(GoPostal.players) do
        if p.week == old and (p.weekDelivered or 0) > 0 then
            list[#list + 1] = { id = id, p = p }
        end
    end
    table.sort(list, function(a, b)
        if a.p.weekDelivered ~= b.p.weekDelivered then return a.p.weekDelivered > b.p.weekDelivered end
        return a.p.weekEarned > b.p.weekEarned
    end)

    local lines = {}
    for rank, amount in ipairs(Config.WeeklyRewards or {}) do
        local e = list[rank]
        if not e then break end
        if amount > 0 then
            e.p.pendingReward = { amount = amount + ((e.p.pendingReward and e.p.pendingReward.amount) or 0), rank = rank, week = old }
            lines[#lines + 1] = ('%d. %s (%d colis) : %d $'):format(rank, e.p.name, e.p.weekDelivered, amount)
        end
    end
    GoPostal.playersDirty = true
    if #lines > 0 then
        print('[bl_gopostal] Récompenses du classement ' .. old .. ' :\n  ' .. table.concat(lines, '\n  '))
        if GoPostal.webhook then GoPostal.webhook('Classement de la semaine ' .. old, lines, 16766720) end
    end

    -- Joueurs en ligne : versement immédiat
    for _, s in ipairs(GetPlayers()) do
        local src = tonumber(s)
        GoPostal.payPending(src, GoPostal.getIdentifier(src))
    end
end

CreateThread(function()
    Wait(5000)
    while true do
        GoPostal.checkWeek()
        Wait(60000)
    end
end)

-- --- ÉVÉNEMENTS (RUSH) ---
-- state.rush = { label, pay, xp, parcels, endsAt, by } : survit à un redémarrage de la ressource
function GoPostal.rushActive()
    local r = state.rush
    if r and os.time() < (r.endsAt or 0) then return r end
    return nil
end

function GoPostal.rushView()
    local r = GoPostal.rushActive()
    if not r then return nil end
    return { label = r.label, pay = r.pay, xp = r.xp, parcels = r.parcels, endsIn = r.endsAt - os.time(), by = r.by }
end

local function announceRush(view, endedLabel)
    if Config.Rush and Config.Rush.announce == false then return end
    TriggerClientEvent('bl_gopostal:rush', -1, view or { ended = true, label = endedLabel })
end

function GoPostal.startRush(def, minutes, by)
    state.rush = {
        label = def.label,
        pay = def.pay,
        xp = def.xp,
        parcels = def.parcels,
        endsAt = os.time() + math.floor(minutes * 60),
        by = by
    }
    saveState()
    announceRush(GoPostal.rushView())
    if GoPostal.webhook then
        GoPostal.webhook('Événement lancé · ' .. def.label, {
            ('Paie x%.2f · XP x%.2f · colis x%.2f pendant %d min.'):format(def.pay, def.xp, def.parcels, minutes),
            by and ('Lancé par %s.'):format(by) or nil
        }, 16766720)
    end
end

function GoPostal.stopRush()
    local r = state.rush
    if not r then return end
    state.rush = nil
    saveState()
    announceRush(nil, r.label)
end

CreateThread(function()
    while true do
        Wait(10000)
        if state.rush and os.time() >= (state.rush.endsAt or 0) then GoPostal.stopRush() end
    end
end)

-- Récompense en attente versée à la connexion
Bridge.onPlayerLoaded(function(src)
    SetTimeout(5000, function()
        if GetPlayerName(src) then GoPostal.payPending(src, GoPostal.getIdentifier(src)) end
    end)
end)
