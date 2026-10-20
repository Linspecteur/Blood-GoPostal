-- Pont vers le framework : ESX, QBCore, Qbox ou ox_core.
-- Tout le job passe par ces fonctions pour l'argent, l'identité et le métier du joueur.
Bridge = {}

local fw, core = nil, nil

local function started(res) return GetResourceState(res) == 'started' end

local function detect()
    local want = Config.Framework or 'auto'
    local function wants(name) return want == 'auto' or want == name end

    if wants('esx') and started('es_extended') then
        local ok, obj = pcall(function() return exports['es_extended']:getSharedObject() end)
        if not (ok and obj) then
            TriggerEvent('esx:getSharedObject', function(o) obj = o end)
        end
        if obj then return 'esx', obj end
    end
    if wants('qbx') and started('qbx_core') then return 'qbx', nil end
    if wants('qb') and started('qb-core') then
        local ok, obj = pcall(function() return exports['qb-core']:GetCoreObject() end)
        if ok and obj then return 'qb', obj end
    end
    if wants('ox') and started('ox_core') then return 'ox', nil end
end

CreateThread(function()
    local warned = false
    while not fw do
        fw, core = detect()
        if fw then
            print(('[bl_gopostal] Framework détecté : %s'):format(fw))
        else
            if not warned and GetGameTimer() > 30000 then
                warned = true
                print(('[bl_gopostal] Aucun framework trouvé (Config.Framework = %s). ESX, QBCore, Qbox ou ox_core requis.'):format(tostring(Config.Framework)))
            end
            Wait(500)
        end
    end
end)

function Bridge.ready() return fw ~= nil end
function Bridge.name() return fw end

-- --- ACCÈS AUX JOUEURS ---
local function esxPlayer(src) return core and core.GetPlayerFromId(src) end

local function qbPlayer(src)
    if fw == 'qbx' then
        local ok, p = pcall(function() return exports.qbx_core:GetPlayer(src) end)
        return ok and p or nil
    end
    return core and core.Functions.GetPlayer(src)
end

local function oxPlayer(src)
    local ok, p = pcall(function() return exports.ox_core:GetPlayer(src) end)
    return ok and p or nil
end

local function oxCall(src, method, ...)
    local args = { ... }
    local ok, r = pcall(function() return exports.ox_core:CallPlayer(src, method, table.unpack(args)) end)
    if ok then return r end
end

-- Compte bancaire du personnage ox_core
local function oxAccount(src)
    local p = oxPlayer(src)
    if not p or not p.charId then return nil end
    local ok, acc = pcall(function() return exports.ox_core:GetCharacterAccount(p.charId) end)
    return ok and acc or nil
end

local function oxAccountCall(acc, method, ...)
    local args = { ... }
    local ok, r = pcall(function() return exports.ox_core:CallAccount(acc.accountId, method, table.unpack(args)) end)
    if ok then return r end
end

-- 'cash' / 'money' : chaque framework a son nom pour le liquide
local function accountName(account)
    if fw == 'esx' then return account == 'cash' and 'money' or account end
    return account == 'money' and 'cash' or account
end

local function isCash(account) return account == 'cash' or account == 'money' end

function Bridge.hasPlayer(src)
    if fw == 'esx' then return esxPlayer(src) ~= nil end
    if fw == 'qb' or fw == 'qbx' then return qbPlayer(src) ~= nil end
    if fw == 'ox' then local p = oxPlayer(src); return p ~= nil and p.charId ~= nil end
    return false
end

-- Identifiant stable du personnage (clé des profils de livreur)
function Bridge.identifier(src)
    if fw == 'esx' then
        local x = esxPlayer(src)
        if x and x.identifier then return x.identifier end
    elseif fw == 'qb' or fw == 'qbx' then
        local p = qbPlayer(src)
        if p and p.PlayerData and p.PlayerData.citizenid then return p.PlayerData.citizenid end
    elseif fw == 'ox' then
        local p = oxPlayer(src)
        if p and p.charId then return 'ox:' .. p.charId end
    end
    return GetPlayerIdentifierByType(src, 'license') or tostring(src)
end

function Bridge.playerName(src)
    if fw == 'esx' then
        local x = esxPlayer(src)
        if x and x.getName then
            local ok, n = pcall(x.getName)
            if ok and n and n ~= '' then return n end
        end
    elseif fw == 'qb' or fw == 'qbx' then
        local p = qbPlayer(src)
        local ci = p and p.PlayerData and p.PlayerData.charinfo
        if ci and ci.firstname then return ('%s %s'):format(ci.firstname, ci.lastname or '') end
    elseif fw == 'ox' then
        local first, last = oxCall(src, 'get', 'firstName'), oxCall(src, 'get', 'lastName')
        if first then return ('%s %s'):format(first, last or '') end
    end
    return GetPlayerName(src) or ('ID ' .. src)
end

-- Le joueur a-t-il un des métiers de la liste ?
function Bridge.inJobs(src, list)
    if not list or #list == 0 then return false end
    local job
    if fw == 'esx' then
        local x = esxPlayer(src)
        job = x and x.job and x.job.name
    elseif fw == 'qb' or fw == 'qbx' then
        local p = qbPlayer(src)
        job = p and p.PlayerData and p.PlayerData.job and p.PlayerData.job.name
    elseif fw == 'ox' then
        return oxCall(src, 'getGroup', list) ~= nil
    end
    for _, j in ipairs(list) do
        if j == job then return true end
    end
    return false
end

-- Groupe admin ESX (les autres frameworks passent par l'ace ou les permissions QBCore)
function Bridge.group(src)
    if fw ~= 'esx' then return nil end
    local x = esxPlayer(src)
    return x and (x.getGroup and x.getGroup() or x.group)
end

-- --- ARGENT ---
function Bridge.getMoney(src, account)
    account = accountName(account)
    if fw == 'esx' then
        local x = esxPlayer(src)
        local acc = x and x.getAccount(account)
        return acc and acc.money or 0
    elseif fw == 'qb' or fw == 'qbx' then
        local p = qbPlayer(src)
        return p and p.PlayerData and p.PlayerData.money and p.PlayerData.money[account] or 0
    elseif fw == 'ox' then
        if isCash(account) then
            local ok, n = pcall(function() return exports.ox_inventory:GetItemCount(src, 'money') end)
            return ok and n or 0
        end
        local acc = oxAccount(src)
        if not acc then return 0 end
        return oxAccountCall(acc, 'get', 'balance') or acc.balance or 0
    end
    return 0
end

function Bridge.addMoney(src, account, amount, reason)
    if amount <= 0 then return end
    account = accountName(account)
    reason = reason or ('Intérim ' .. Config.Brand.name)
    if fw == 'esx' then
        local x = esxPlayer(src)
        if x then x.addAccountMoney(account, amount) end
    elseif fw == 'qb' or fw == 'qbx' then
        local p = qbPlayer(src)
        if p then p.Functions.AddMoney(account, amount, reason) end
    elseif fw == 'ox' then
        if isCash(account) then
            pcall(function() exports.ox_inventory:AddItem(src, 'money', amount) end)
        else
            local acc = oxAccount(src)
            if acc then oxAccountCall(acc, 'addBalance', { amount = amount, message = reason }) end
        end
    end
end

-- Retire la somme si le joueur l'a. Renvoie true si c'est fait.
function Bridge.removeMoney(src, account, amount, reason)
    if amount <= 0 then return true end
    if Bridge.getMoney(src, account) < amount then return false end
    local acc = accountName(account)
    reason = reason or ('Intérim ' .. Config.Brand.name)
    if fw == 'esx' then
        local x = esxPlayer(src)
        if not x then return false end
        x.removeAccountMoney(acc, amount)
        return true
    elseif fw == 'qb' or fw == 'qbx' then
        local p = qbPlayer(src)
        return p ~= nil and p.Functions.RemoveMoney(acc, amount, reason) ~= false
    elseif fw == 'ox' then
        if isCash(acc) then
            local ok, r = pcall(function() return exports.ox_inventory:RemoveItem(src, 'money', amount) end)
            return ok and r ~= false
        end
        local a = oxAccount(src)
        if not a then return false end
        local r = oxAccountCall(a, 'removeBalance', { amount = amount, message = reason, overdraw = false })
        return r == true or (type(r) == 'table' and r.success == true)
    end
    return false
end

-- --- CONNEXION D'UN PERSONNAGE ---
local loadedHandlers = {}
function Bridge.onPlayerLoaded(cb) loadedHandlers[#loadedHandlers + 1] = cb end

local function fireLoaded(src)
    src = tonumber(src)
    if not src then return end
    for _, cb in ipairs(loadedHandlers) do cb(src) end
end

AddEventHandler('esx:playerLoaded', function(src) if fw == 'esx' then fireLoaded(src) end end)
RegisterNetEvent('QBCore:Server:OnPlayerLoaded', function()
    if fw == 'qb' or fw == 'qbx' then fireLoaded(source) end
end)
AddEventHandler('ox:playerLoaded', function(src) if fw == 'ox' then fireLoaded(src) end end)
