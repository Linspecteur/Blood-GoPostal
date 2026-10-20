-- Intégrations côté client : notifications, ciblage (ox_target / qb-target), clés et carburant.
CBridge = {}

local function started(res) return GetResourceState(res) == 'started' end

-- --- NOTIFICATIONS ---
-- Renvoie true si une autre ressource a affiché la notification (sinon le job utilise la sienne)
local oxTypes = { info = 'inform', success = 'success', warn = 'warning', error = 'error' }
local qbTypes = { info = 'primary', success = 'success', warn = 'primary', error = 'error' }
local okTypes = { info = 'info', success = 'success', warn = 'warning', error = 'error' }

function CBridge.notify(msg, kind)
    local mode = Config.Notify or 'nui'
    kind = kind or 'info'
    if mode == 'ox_lib' and started('ox_lib') then
        TriggerEvent('ox_lib:notify', { title = Config.Brand.name, description = msg, type = oxTypes[kind] or 'inform', duration = 5000 })
        return true
    elseif mode == 'esx' and started('es_extended') then
        TriggerEvent('esx:showNotification', msg, okTypes[kind] or 'info', 5000)
        return true
    elseif mode == 'qb' and (started('qb-core') or started('qbx_core')) then
        TriggerEvent('QBCore:Notify', msg, qbTypes[kind] or 'primary', 5000)
        return true
    elseif mode == 'okok' and started('okokNotify') then
        local ok = pcall(function() exports['okokNotify']:Alert(Config.Brand.name, msg, 5000, okTypes[kind] or 'info') end)
        return ok
    elseif mode == 'custom' and type(Config.CustomNotify) == 'function' then
        local ok = pcall(Config.CustomNotify, msg, kind)
        return ok
    end
    return false
end

-- --- CIBLAGE ---
-- Options communes : { name, label, icon, distance, canInteract = function() -> bool, onSelect = function() }
function CBridge.target()
    local t = Config.Target
    if not t then return nil end
    if (t == 'auto' or t == 'ox_target') and started('ox_target') then return 'ox' end
    if (t == 'auto' or t == 'qb-target') and started('qb-target') then return 'qb' end
    return nil
end

local function check(o)
    return function() return o.canInteract == nil or o.canInteract() == true end
end

local function oxOptions(opts)
    local out = {}
    for i, o in ipairs(opts) do
        out[i] = { name = o.name, label = o.label, icon = o.icon, distance = o.distance or 2.0,
                   canInteract = check(o), onSelect = function() o.onSelect() end }
    end
    return out
end

local function qbOptions(opts)
    local out, dist = {}, 0
    for i, o in ipairs(opts) do
        out[i] = { label = o.label, icon = o.icon, canInteract = check(o), action = function() o.onSelect() end }
        dist = math.max(dist, o.distance or 2.0)
    end
    return { options = out, distance = dist }
end

-- Ajoute des options sur une entité. Renvoie un handle à passer à CBridge.remove (nil sans ciblage).
function CBridge.addEntity(ent, opts)
    local sys = CBridge.target()
    if not sys or not ent or not DoesEntityExist(ent) then return nil end
    local ok
    if sys == 'ox' then
        ok = pcall(function() exports.ox_target:addLocalEntity(ent, oxOptions(opts)) end)
    else
        ok = pcall(function() exports['qb-target']:AddTargetEntity(ent, qbOptions(opts)) end)
    end
    if not ok then return nil end
    local names, labels = {}, {}
    for i, o in ipairs(opts) do names[i], labels[i] = o.name, o.label end
    return { sys = sys, kind = 'entity', ent = ent, names = names, labels = labels }
end

-- Zone sphérique (porte d'une adresse)
local zoneCount = 0
function CBridge.addZone(coords, radius, opts)
    local sys = CBridge.target()
    if not sys then return nil end
    zoneCount = zoneCount + 1
    local name = ('bl_gopostal_%d'):format(zoneCount)
    local ok, id
    if sys == 'ox' then
        ok, id = pcall(function()
            return exports.ox_target:addSphereZone({ coords = coords, radius = radius, debug = Config.Debug, options = oxOptions(opts) })
        end)
    else
        ok = pcall(function()
            exports['qb-target']:AddCircleZone(name, coords, radius, { name = name, debugPoly = Config.Debug, useZ = true }, qbOptions(opts))
        end)
        id = name
    end
    if not ok then return nil end
    return { sys = sys, kind = 'zone', id = id }
end

function CBridge.remove(h)
    if not h then return end
    pcall(function()
        if h.kind == 'entity' then
            if h.sys == 'ox' then exports.ox_target:removeLocalEntity(h.ent, h.names)
            else exports['qb-target']:RemoveTargetEntity(h.ent, h.labels) end
        else
            if h.sys == 'ox' then exports.ox_target:removeZone(h.id)
            else exports['qb-target']:RemoveZone(h.id) end
        end
    end)
end

-- --- CLÉS DU VAN ---
-- Systèmes de clés côté client (ceux côté serveur sont gérés dans server/main.lua)
local function keysOn(res)
    local K = Config.Keys
    if not K or not started(res) then return false end
    if K == 'auto' then return true end
    if type(K) == 'table' then
        for _, r in ipairs(K) do if r == res then return true end end
    end
    return false
end

function CBridge.keys(veh, plate, give)
    local model = veh and GetDisplayNameFromVehicleModel(GetEntityModel(veh)) or nil
    local function try(res, fn) if keysOn(res) then pcall(fn) end end
    if give then
        try('qb-vehiclekeys', function() TriggerEvent('vehiclekeys:client:SetOwner', plate) end)
        try('qs-vehiclekeys', function() exports['qs-vehiclekeys']:GiveKeys(plate, model, true) end)
        try('wasabi_carlock', function() exports.wasabi_carlock:GiveKey(plate) end)
        try('cd_garage', function() TriggerEvent('cd_garage:AddKeys', plate) end)
        if veh then try('MrNewbVehicleKeys', function() exports.MrNewbVehicleKeys:GiveKeys(veh) end) end
    else
        try('qs-vehiclekeys', function() exports['qs-vehiclekeys']:RemoveKeys(plate, model) end)
        try('wasabi_carlock', function() exports.wasabi_carlock:RemoveKey(plate) end)
        if veh then try('MrNewbVehicleKeys', function() exports.MrNewbVehicleKeys:RemoveKeys(veh) end) end
    end
end

-- --- CARBURANT ---
local stateFuel = { ox_fuel = true, ['Renewed-Fuel'] = true }

function CBridge.fill(veh)
    SetVehicleFuelLevel(veh, 100.0)
    for _, res in ipairs(Config.Fuel or {}) do
        if started(res) then
            pcall(function()
                if stateFuel[res] then Entity(veh).state:set('fuel', 100.0, true)
                else exports[res]:SetFuel(veh, 100.0) end
            end)
        end
    end
end
