-- Menu admin du job GoPostal : compatible avec n'importe quel système d'admin.
-- L'accès est accordé si UNE des sources activées dans Config.Admin le permet.
local function started(res) return GetResourceState(res) == 'started' end

function GoPostal.isAdmin(src)
    local A = Config.Admin
    if src == 0 then return true end

    -- 1. Permission ace (txAdmin, server.cfg, la plupart des menus admin)
    if A.ace and IsPlayerAceAllowed(src, A.ace) then return true end

    -- 2. Groupe ESX
    if A.esxGroups then
        local group = Bridge.group(src)
        if group then
            for _, g in ipairs(A.esxGroups) do
                if g == group then return true end
            end
        end
    end

    -- 3. BloodAdmin (permission par grade, réglable dans l'onglet Permissions)
    if A.bloodAdmin then
        for _, res in ipairs(A.bloodAdmin.resources) do
            if started(res) then
                local ok, allowed = pcall(function() return exports[res]:HasPermission(src, A.bloodAdmin.permission) end)
                if ok and allowed then return true end
            end
        end
    end

    -- 4. QBCore
    if A.qbPermissions and started('qb-core') then
        local ok, QB = pcall(function() return exports['qb-core']:GetCoreObject() end)
        if ok and QB and QB.Functions and QB.Functions.HasPermission then
            for _, perm in ipairs(A.qbPermissions) do
                if QB.Functions.HasPermission(src, perm) then return true end
            end
        end
    end

    return false
end

-- --- Synchro des clients (PNJ, palette, zone de retour, état) ---
function GoPostal.syncClients(target)
    TriggerClientEvent('bl_gopostal:sync', target or -1, {
        npc = Config.Npc.coords,
        vanSpawns = Config.VanSpawns,
        returnPoint = Config.Return.coords,
        enabled = GoPostal.enabled
    })
end

RegisterNetEvent('bl_gopostal:requestSync', function()
    GoPostal.syncClients(source)
end)

-- --- Données affichées dans le menu ---
local function snapshot()
    local now = os.time()
    local list = {}
    for src, m in pairs(GoPostal.tours) do
        local d = 0
        for _, p in ipairs(m.parcels) do if p.delivered then d = d + 1 end end
        list[#list + 1] = {
            src = src,
            name = m.name,
            tour = m.tour.label,
            plate = m.plate,
            phase = m.phase,
            loaded = m.loaded,
            delivered = d,
            total = #m.parcels,
            earned = m.earned + m.tips,
            since = now - m.createdAt
        }
        if #m.members > 1 then
            local names = {}
            for i = 2, #m.members do names[#names + 1] = m.members[i].name end
            list[#list].team = names
        end
    end

    -- Statistiques sur les dernières 24 h
    local day = { total = 0, success = 0, parcels = 0, paid = 0 }
    for _, h in ipairs(GoPostal.history) do
        if now - (h.t or 0) <= 86400 then
            day.total = day.total + 1
            day.parcels = day.parcels + (h.delivered or 0)
            day.paid = day.paid + (h.paid or 0)
            if h.result == 'success' then day.success = day.success + 1 end
        end
    end

    local hist = {}
    for i = 1, math.min(60, #GoPostal.history) do hist[i] = GoPostal.history[i] end

    -- Livreurs, par expérience
    local players = {}
    for id, p in pairs(GoPostal.players) do
        local idx, lvl = GoPostal.levelFor(p.xp)
        players[#players + 1] = {
            identifier = id, name = p.name, level = idx, title = lvl.title, xp = p.xp,
            delivered = p.delivered, tours = p.tours, earned = p.earned,
            rating = p.ratingCount > 0 and (p.ratingSum / p.ratingCount) or nil
        }
    end
    table.sort(players, function(a, b) return a.xp > b.xp end)
    while #players > 100 do table.remove(players) end

    local levels = {}
    for i, l in ipairs(Config.Levels) do levels[i] = { title = l.title, xp = l.xp } end

    local tourLabels = {}
    for _, t in ipairs(Config.Tours) do tourLabels[t.id] = t.label end

    return {
        tours = list,
        settings = GoPostal.getSettings(),
        positions = GoPostal.getPositions(),
        zones = Config.Zones,
        history = hist,
        players = players,
        levels = levels,
        stats = day,
        daily = GoPostal.statsRange(30),
        tourLabels = tourLabels,
        rush = GoPostal.rushView(),
        rushPresets = Config.Rush and Config.Rush.presets or {},
        now = now
    }
end

local function send(src, extra)
    local data = snapshot()
    if extra then data.toast = extra end
    TriggerClientEvent('bl_gopostal:admin:data', src, data)
end

-- Explique en console pourquoi un joueur est refusé
local function explainDenied(src)
    local A = Config.Admin
    local lines = { ('[bl_gopostal] Accès refusé à %s (ID %d) :'):format(GetPlayerName(src) or '?', src) }
    lines[#lines + 1] = ('  ace %s : %s'):format(tostring(A.ace), tostring(A.ace and IsPlayerAceAllowed(src, A.ace)))
    local group = Bridge.name() == 'esx' and tostring(Bridge.group(src)) or ('framework ' .. tostring(Bridge.name()))
    lines[#lines + 1] = ('  groupe ESX : %s (autorisés : %s)'):format(group, table.concat(A.esxGroups or {}, ', '))
    if A.bloodAdmin then
        for _, res in ipairs(A.bloodAdmin.resources) do
            if started(res) then
                local ok, allowed = pcall(function() return exports[res]:HasPermission(src, A.bloodAdmin.permission) end)
                lines[#lines + 1] = ('  %s : HasPermission(%s) = %s'):format(res, A.bloodAdmin.permission,
                    ok and tostring(allowed) or ('erreur : ' .. tostring(allowed)))
            else
                lines[#lines + 1] = ('  %s : %s'):format(res, GetResourceState(res))
            end
        end
    end
    print(table.concat(lines, '\n'))
end

RegisterCommand(Config.Admin.command, function(src)
    if src == 0 then return print('[bl_gopostal] Commande à utiliser en jeu.') end
    if not GoPostal.isAdmin(src) then
        explainDenied(src)
        return TriggerClientEvent('bl_gopostal:notify', src, ('Tu n\'as pas accès au menu %s.'):format(Config.Brand.name), 'error')
    end
    TriggerClientEvent('bl_gopostal:admin:open', src)
    send(src)
end, false)

RegisterNetEvent('bl_gopostal:admin:refresh', function()
    local src = source
    if GoPostal.isAdmin(src) then send(src) end
end)

-- --- Actions ---
local function myPosition(src)
    local ped = GetPlayerPed(src)
    return GetEntityCoords(ped), GetEntityHeading(ped)
end

local function round1(n) return math.floor(n * 10 + 0.5) / 10 end
local function cleanLabel(s) return tostring(s or ''):gsub('^%s+', ''):gsub('%s+$', ''):sub(1, 40) end

local actions = {}

actions.cancel = function(src, p)
    local target = tonumber(p.src)
    if not target or not GoPostal.tours[target] then return 'Tournée introuvable.' end
    TriggerClientEvent('bl_gopostal:notify', target, 'Ta tournée a été annulée par un admin. Caution rendue.', 'error')
    local m = GoPostal.tours[target]
    if m.deposit > 0 then GoPostal.addMoney(target, m.deposit) end
    GoPostal.endTour(target, 'cancel', 'admin', { refund = m.deposit })
    return 'Tournée annulée, caution rendue au joueur.'
end

actions.teleport = function(src, p)
    local target = tonumber(p.src)
    if target and GoPostal.tours[target] then
        TriggerClientEvent('bl_gopostal:admin:tp', src, GetEntityCoords(GetPlayerPed(target)))
        return nil
    end
    if p.coords and p.coords.x then
        TriggerClientEvent('bl_gopostal:admin:tp', src, vector3(p.coords.x + 0.0, p.coords.y + 0.0, p.coords.z + 0.0))
    end
end

actions.resetCooldowns = function()
    GoPostal.resetCooldowns()
    return 'Délais remis à zéro.'
end

actions.saveSettings = function(src, p)
    GoPostal.applySettings(p.settings)
    GoPostal.saveSettings()
    GoPostal.syncClients()
    return 'Réglages enregistrés.'
end

actions.toggle = function()
    GoPostal.enabled = not GoPostal.enabled
    GoPostal.saveSettings()
    GoPostal.syncClients()
    return GoPostal.enabled and 'Recrutement ouvert.' or 'Recrutement fermé.'
end

actions.setNpc = function(src)
    local c, h = myPosition(src)
    Config.Npc.coords = vector4(round1(c.x), round1(c.y), round1(c.z), round1(h))
    GoPostal.saveSettings()
    GoPostal.syncClients()
    return 'Le responsable a été déplacé à ta position.'
end

actions.addVanSpawn = function(src)
    local c, h = myPosition(src)
    Config.VanSpawns[#Config.VanSpawns + 1] = vector4(round1(c.x), round1(c.y), round1(c.z), round1(h))
    GoPostal.saveSettings()
    GoPostal.syncClients()
    return ('Place de van n°%d ajoutée (dans ta direction actuelle).'):format(#Config.VanSpawns)
end

actions.moveVanSpawn = function(src, p)
    local i = tonumber(p.index)
    if not i or not Config.VanSpawns[i] then return end
    local c, h = myPosition(src)
    Config.VanSpawns[i] = vector4(round1(c.x), round1(c.y), round1(c.z), round1(h))
    GoPostal.saveSettings()
    GoPostal.syncClients()
    return ('Place de van n°%d recalée (dans ta direction actuelle).'):format(i)
end

actions.removeVanSpawn = function(src, p)
    local i = tonumber(p.index)
    if not i or not Config.VanSpawns[i] then return end
    if #Config.VanSpawns <= 1 then return 'Il faut garder au moins une place de van.' end
    table.remove(Config.VanSpawns, i)
    GoPostal.saveSettings()
    GoPostal.syncClients()
    return 'Place de van supprimée.'
end

actions.setReturn = function(src)
    local c = myPosition(src)
    Config.Return.coords = vector3(round1(c.x), round1(c.y), round1(c.z))
    GoPostal.saveSettings()
    GoPostal.syncClients()
    return 'Zone de retour déplacée à ta position.'
end

actions.addAddress = function(src, p)
    local label = cleanLabel(p.label)
    if not Config.Zones[p.zone] then return 'Zone inconnue.' end
    local c = myPosition(src)
    Config.Addresses[#Config.Addresses + 1] = { label = label, zone = p.zone, coords = vector3(round1(c.x), round1(c.y), round1(c.z)) }
    GoPostal.saveSettings()
    return label ~= '' and ('Adresse « %s » ajoutée.'):format(label) or 'Adresse ajoutée (nom de rue automatique).'
end

actions.moveAddress = function(src, p)
    local i = tonumber(p.index)
    local a = i and Config.Addresses[i]
    if not a then return end
    local c = myPosition(src)
    a.coords = vector3(round1(c.x), round1(c.y), round1(c.z))
    GoPostal.saveSettings()
    return 'Adresse recalée sur ta position.'
end

actions.removeAddress = function(src, p)
    local i = tonumber(p.index)
    if not i or not Config.Addresses[i] then return end
    local zone = Config.Addresses[i].zone
    local left = 0
    for _, a in ipairs(Config.Addresses) do if a.zone == zone then left = left + 1 end end
    if left <= 1 then return 'Il faut garder au moins une adresse dans cette zone.' end
    table.remove(Config.Addresses, i)
    GoPostal.saveSettings()
    return 'Adresse supprimée (les tournées en cours ne sont pas touchées).'
end

actions.resetPlayer = function(src, p)
    local id = tostring(p.identifier or '')
    if not GoPostal.players[id] then return 'Livreur introuvable.' end
    local name = GoPostal.players[id].name
    GoPostal.players[id] = nil
    GoPostal.playersDirty = true
    return ('Progression de %s remise à zéro.'):format(name)
end

-- Niveau réglé à la main : l'XP est placée au seuil du niveau. Les primes des niveaux
-- sautés ne sont pas versées (pas d'argent créé par une correction admin).
actions.setLevel = function(src, p)
    local id = tostring(p.identifier or '')
    local profile = GoPostal.players[id]
    if not profile then return 'Livreur introuvable.' end
    local level = math.floor(tonumber(p.level) or 0)
    local l = Config.Levels[level]
    if not l then return 'Niveau invalide.' end
    profile.xp = l.xp
    profile.levelPaid = level
    GoPostal.playersDirty = true
    for _, s in ipairs(GetPlayers()) do
        local target = tonumber(s)
        if GoPostal.getIdentifier(target) == id then
            GoPostal.notify(target, ('Un responsable a réglé ton niveau : %d · %s.'):format(level, l.title), 'info')
            break
        end
    end
    print(('[bl_gopostal] %s (%d) a réglé le niveau de %s sur %d'):format(GetPlayerName(src) or '?', src, profile.name, level))
    return ('%s passe niveau %d · %s.'):format(profile.name, level, l.title)
end

-- Événement : multiplicateurs bornés pour éviter une faute de frappe ruineuse
actions.rushStart = function(src, p)
    local label = cleanLabel(p.label)
    if label == '' then return 'Donne un nom à l\'événement.' end
    local def = {
        label = label,
        pay = math.max(0.5, math.min(5.0, tonumber(p.pay) or 1.0)),
        xp = math.max(0.5, math.min(5.0, tonumber(p.xp) or 1.0)),
        parcels = math.max(0.5, math.min(3.0, tonumber(p.parcels) or 1.0))
    }
    local minutes = math.max(1, math.min(24 * 60, math.floor(tonumber(p.minutes) or 30)))
    GoPostal.startRush(def, minutes, GetPlayerName(src))
    return ('Événement « %s » lancé pour %d min.'):format(label, minutes)
end

actions.rushStop = function()
    if not GoPostal.rushActive() then return 'Aucun événement en cours.' end
    GoPostal.stopRush()
    return 'Événement arrêté.'
end

actions.clearHistory = function()
    for i = #GoPostal.history, 1, -1 do GoPostal.history[i] = nil end
    GoPostal.historyDirty = true
    return 'Historique vidé.'
end

RegisterNetEvent('bl_gopostal:admin:action', function(name, payload)
    local src = source
    if not GoPostal.isAdmin(src) then return end
    local fn = actions[name]
    if not fn then return end
    local msg = fn(src, type(payload) == 'table' and payload or {})
    send(src, msg)
    if Config.Debug then print(('[bl_gopostal] admin %s (%d) : %s'):format(GetPlayerName(src) or '?', src, name)) end
end)

-- Synchro initiale (après le chargement des réglages)
CreateThread(function()
    Wait(1000)
    GoPostal.syncClients()
end)
