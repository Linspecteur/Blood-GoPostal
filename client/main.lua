local tour = nil          -- tournée en cours du joueur (chef ou coéquipier)
local carry = nil         -- colis porté { obj, kind = 'load'|'deliver', parcelId, heavy }
local busy = false        -- animation / réponse serveur en attente
local npcPed = nil
local npcBlip = nil
local npcTarget = nil
local menuOpen = false
local adminOpen = false
local sortOpen = false
local wantOutfit = false
local outfitBackup = nil
local logbookOpen = false -- carnet de tournée déplié sur le HUD
local rush = nil          -- événement en cours { label, pay, xp, parcels, endsAt }

local CARRY_DICT = 'anim@heists@box_carry@'

-- --- OUTILS ---
local function notify(msg, kind)
    if CBridge.notify(msg, kind) then return end
    SendNUIMessage({ action = 'toast', kind = kind or 'info', text = msg })
end

local function helpText(msg)
    BeginTextCommandDisplayHelp('STRING')
    AddTextComponentSubstringPlayerName(msg)
    EndTextCommandDisplayHelp(0, false, true, -1)
end

-- Ciblage actif ? (revérifié toutes les 5 s, une ressource peut démarrer après le job)
local useTarget, targetCheckedAt = false, -10000
local function targeting()
    local now = GetGameTimer()
    if now - targetCheckedAt > 5000 then
        targetCheckedAt = now
        useTarget = CBridge.target() ~= nil
    end
    return useTarget
end

local function loadModel(model)
    local hash = type(model) == 'number' and model or joaat(model)
    if not IsModelInCdimage(hash) then return nil end
    RequestModel(hash)
    local t = GetGameTimer()
    while not HasModelLoaded(hash) do
        if GetGameTimer() - t > 10000 then return nil end
        Wait(10)
    end
    return hash
end

local function loadDict(dict)
    if HasAnimDictLoaded(dict) then return true end
    RequestAnimDict(dict)
    local t = GetGameTimer()
    while not HasAnimDictLoaded(dict) do
        if GetGameTimer() - t > 5000 then return false end
        Wait(10)
    end
    return true
end

-- Nuit en cours ? (heure du jeu ; en mode 'real', le serveur décide et le client affiche ce qu'il a reçu)
local serverNight = false
local function isNight()
    local N = Config.Night
    if not N or not N.enabled then return false end
    if N.clock == 'real' then return serverNight end
    local h = GetClockHours()
    if N.startHour > N.endHour then return h >= N.startHour or h < N.endHour end
    return h >= N.startHour and h < N.endHour
end

-- Météo en cours : nom du type (RAIN, THUNDER...) s'il fait partie de Config.Weather.types
local weatherNames = {}
for key in pairs(Config.Weather and Config.Weather.types or {}) do
    weatherNames[joaat(key) % 4294967296] = key
end
local function currentWeather()
    if not Config.Weather or not Config.Weather.enabled then return nil end
    local a, b, pct = GetWeatherTypeTransition()
    local h = (pct or 0) > 0.5 and b or a
    return h and weatherNames[h % 4294967296] or nil
end
local function weatherLabel()
    local w = currentWeather()
    return w and Config.Weather.types[w].label or nil
end

-- Sol sous un point. On sonde d'abord juste au-dessus de la hauteur enregistrée
-- (sinon on atterrit sur un toit ou un auvent), puis de plus haut en dernier recours.
local function groundZ(x, y, z)
    RequestCollisionAtCoord(x, y, z)
    for _ = 1, 20 do
        for _, h in ipairs({ 2.0, 5.0 }) do
            local ok, gz = GetGroundZFor_3dCoord(x, y, z + h, false)
            if ok and math.abs(gz - z) < 4.0 then return gz end
        end
        Wait(50)
    end
    local ok, gz = GetGroundZFor_3dCoord(x, y, z + 50.0, false)
    if ok and math.abs(gz - z) < 10.0 then return gz end
    return z - 1.0 -- position relevée sur un joueur : le sol est ~1 m plus bas
end

-- Sol juste sous un point (porche, perron) sans remonter sur un toit
local function doorPoint(c)
    for _, h in ipairs({ 1.5, 3.0 }) do
        local ok, gz = GetGroundZFor_3dCoord(c.x, c.y, c.z + h, false)
        if ok and math.abs(gz - c.z) < 3.0 then return vector3(c.x, c.y, gz) end
    end
    return vector3(c.x, c.y, c.z - 1.0)
end

-- Nom de la rue et du quartier, lus dans le jeu
local function streetName(c)
    local s1, s2 = GetStreetNameAtCoord(c.x, c.y, c.z)
    local street = GetStreetNameFromHashKey(s1)
    if (street == nil or street == '') and s2 ~= 0 then street = GetStreetNameFromHashKey(s2) end
    return street ~= '' and street or nil
end

local function zoneOf(c)
    local code = GetNameOfZone(c.x, c.y, c.z)
    local label = GetLabelText(code)
    if label == 'NULL' then label = nil end
    return code, label
end

local function streetLabel(c)
    local street = streetName(c)
    local _, zone = zoneOf(c)
    if street and zone then return street .. ', ' .. zone end
    return street or zone or 'Adresse'
end

local function vehicleLabel(model)
    local name = GetDisplayNameFromVehicleModel(joaat(model))
    local label = GetLabelText(name)
    if label == 'NULL' then label = name end
    return label
end

local function makeBlip(coords, sprite, color, label, scale)
    local blip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(blip, sprite)
    SetBlipColour(blip, color)
    SetBlipScale(blip, scale or 0.8)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(label)
    EndTextCommandSetBlipName(blip)
    return blip
end

local function removeBlip(blip)
    if blip and DoesBlipExist(blip) then RemoveBlip(blip) end
end

local function parcelType(key)
    return Config.Parcels[key] or Config.Parcels.standard
end

local function vanRear(veh)
    local min = GetModelDimensions(GetEntityModel(veh))
    return GetOffsetFromEntityInWorldCoords(veh, 0.0, min.y - 0.7, 0.0)
end

local function setRearDoors(veh, open)
    for _, d in ipairs({ 2, 3, 5 }) do
        if open then SetVehicleDoorOpen(veh, d, false, false) else SetVehicleDoorShut(veh, d, false) end
    end
end

local function onFoot(ped)
    return not IsPedInAnyVehicle(ped, false) and not IsPedRagdoll(ped) and not IsPedFalling(ped)
end

local function shuffle(list)
    for i = #list, 2, -1 do
        local j = math.random(i)
        list[i], list[j] = list[j], list[i]
    end
    return list
end

-- --- TENUE DE TRAVAIL ---
local function applyOutfit(exclusive)
    if not Config.Outfit.enabled then return end
    local ped = PlayerPedId()
    local model = GetEntityModel(ped)
    local src = exclusive and Config.Outfit.exclusive or Config.Outfit
    local set = (model == joaat('mp_m_freemode_01') and src.male)
        or (model == joaat('mp_f_freemode_01') and src.female)
    if not set then return notify('Tenue indisponible pour ce personnage.', 'warn') end

    outfitBackup = { components = {}, props = {} }
    for i = 0, 11 do
        outfitBackup.components[i] = { GetPedDrawableVariation(ped, i), GetPedTextureVariation(ped, i), GetPedPaletteVariation(ped, i) }
    end
    for _, i in ipairs({ 0, 1, 2, 6, 7 }) do
        outfitBackup.props[i] = { GetPedPropIndex(ped, i), GetPedPropTextureIndex(ped, i) }
    end
    for id, v in pairs(set.components or {}) do SetPedComponentVariation(ped, id, v[1], v[2], 0) end
    for id, v in pairs(set.props or {}) do SetPedPropIndex(ped, id, v[1], v[2], true) end
end

local function restoreOutfit()
    if not outfitBackup then return end
    local ped = PlayerPedId()
    for i, v in pairs(outfitBackup.components) do SetPedComponentVariation(ped, i, v[1], v[2], v[3]) end
    for i, v in pairs(outfitBackup.props) do
        if v[1] == -1 then ClearPedProp(ped, i) else SetPedPropIndex(ped, i, v[1], v[2], true) end
    end
    outfitBackup = nil
end

-- --- SUPPRESSION D'OBJETS ---
-- Un objet réseau ne se supprime que si on en a le contrôle : on le reprend avant de supprimer,
-- sinon il resterait sur le serveur pour tout le monde.
local function deleteObject(obj)
    if not obj or not DoesEntityExist(obj) then return end
    if IsEntityAttached(obj) then DetachEntity(obj, true, true) end
    if NetworkGetEntityIsNetworked(obj) and not NetworkHasControlOfEntity(obj) then
        NetworkRequestControlOfEntity(obj)
        local t = GetGameTimer()
        while not NetworkHasControlOfEntity(obj) and GetGameTimer() - t < 1000 do
            Wait(0)
            NetworkRequestControlOfEntity(obj)
        end
    end
    SetEntityAsMissionEntity(obj, true, true)
    DeleteObject(obj)
    if DoesEntityExist(obj) then DeleteEntity(obj) end
end

-- Fondu puis suppression (colis laissé devant une porte)
local function fadeAndDelete(obj, delay)
    SetTimeout(delay or 0, function()
        if not DoesEntityExist(obj) then return end
        for a = 255, 0, -15 do
            if not DoesEntityExist(obj) then return end
            SetEntityAlpha(obj, a, false)
            Wait(30)
        end
        deleteObject(obj)
    end)
end

-- --- PORT DES COLIS ---
local function stopCarry()
    if not carry then return end
    local obj = carry.obj
    carry = nil
    StopAnimTask(PlayerPedId(), CARRY_DICT, 'idle', 1.0)
    if obj and DoesEntityExist(obj) then
        if NetworkHasControlOfEntity(obj) or not NetworkGetEntityIsNetworked(obj) then
            DetachEntity(obj, true, true)
            DeleteObject(obj)
            if DoesEntityExist(obj) then DeleteEntity(obj) end
        end
        -- Contrôle perdu ou suppression refusée : on réessaie dans un thread (peut attendre le réseau)
        if DoesEntityExist(obj) then CreateThread(function() deleteObject(obj) end) end
    end
end

local function startCarry(kind, typeKey, parcelId)
    if carry then return end
    local t = parcelType(typeKey)
    local ped = PlayerPedId()
    if not loadDict(CARRY_DICT) then return end
    local hash = loadModel(t.prop) or loadModel('prop_cs_cardbox_01')
    if not hash then return end

    local c = GetEntityCoords(ped)
    local obj = CreateObject(hash, c.x, c.y, c.z + 0.2, true, true, false)
    SetModelAsNoLongerNeeded(hash)
    -- Pas de collision avec le joueur ou le van, et pas de migration vers un autre client
    SetEntityCollision(obj, false, false)
    if NetworkGetEntityIsNetworked(obj) then SetNetworkIdCanMigrate(ObjToNet(obj), false) end
    AttachEntityToEntity(obj, ped, GetPedBoneIndex(ped, 60309), 0.025, 0.08, 0.255, -145.0, 290.0, 0.0, true, true, false, true, 1, true)
    TaskPlayAnim(ped, CARRY_DICT, 'idle', 8.0, -8.0, -1, 49, 0, false, false, false)
    carry = { obj = obj, kind = kind, parcelId = parcelId, heavy = t.heavy == true, typeKey = typeKey }

    CreateThread(function()
        while carry do
            local p = PlayerPedId()
            if IsEntityDead(p) then stopCarry(); break end
            if not IsEntityPlayingAnim(p, CARRY_DICT, 'idle', 3) and not busy then
                TaskPlayAnim(p, CARRY_DICT, 'idle', 8.0, -8.0, -1, 49, 0, false, false, false)
            end
            DisableControlAction(0, 22, true)   -- saut
            DisableControlAction(0, 23, true)   -- monter dans un véhicule
            DisableControlAction(0, 24, true)   -- attaque
            DisableControlAction(0, 25, true)   -- visée
            DisableControlAction(0, 37, true)   -- roue des armes
            DisableControlAction(0, 44, true)   -- couverture
            DisableControlAction(0, 140, true)
            DisableControlAction(0, 141, true)
            DisableControlAction(0, 142, true)
            if carry and carry.heavy then DisableControlAction(0, 21, true) end -- sprint
            Wait(0)
        end
    end)
end

local function playOnce(dict, anim, ms, flag)
    if not loadDict(dict) then return end
    TaskPlayAnim(PlayerPedId(), dict, anim, 8.0, -8.0, ms, flag or 48, 0, false, false, false)
    Wait(ms)
end

-- --- LE RESPONSABLE DU DÉPÔT ---
local function talkToNpc()
    if menuOpen or carry then return end
    TriggerServerEvent('bl_gopostal:requestMenu', GetClockHours())
end

local function removeNpc()
    CBridge.remove(npcTarget)
    npcTarget = nil
    if npcPed then DeleteEntity(npcPed); npcPed = nil end
end

local function spawnNpc()
    local c = Config.Npc.coords
    local hash = loadModel(Config.Npc.model)
    if not hash then return end
    local z = groundZ(c.x, c.y, c.z)
    npcPed = CreatePed(4, hash, c.x, c.y, z, c.w, false, true)
    SetEntityInvincible(npcPed, true)
    FreezeEntityPosition(npcPed, true)
    SetBlockingOfNonTemporaryEvents(npcPed, true)
    if Config.Npc.scenario then TaskStartScenarioInPlace(npcPed, Config.Npc.scenario, 0, true) end
    SetModelAsNoLongerNeeded(hash)
    npcTarget = CBridge.addEntity(npcPed, {
        { name = 'bl_gopostal_npc', label = ('Parler au %s'):format(Config.Npc.name:lower()), icon = 'fa-solid fa-box',
          distance = Config.Npc.interactDistance + 0.5,
          canInteract = function() return not menuOpen and not carry end, onSelect = talkToNpc }
    })
end

local function createNpcBlip()
    removeBlip(npcBlip)
    npcBlip = nil
    if not Config.Npc.blip.enabled then return end
    local b = Config.Npc.blip
    npcBlip = makeBlip(Config.Npc.coords, b.sprite, b.color, b.label, b.scale)
    SetBlipAsShortRange(npcBlip, true)
end

-- Réglages poussés par le serveur (positions modifiées depuis le menu admin)
RegisterNetEvent('bl_gopostal:sync', function(data)
    if type(data) ~= 'table' then return end
    if type(data.vanSpawns) == 'table' and #data.vanSpawns > 0 then Config.VanSpawns = data.vanSpawns end
    if data.returnPoint then Config.Return.coords = data.returnPoint end
    if data.npc then
        local old = Config.Npc.coords
        if #(vector3(data.npc.x, data.npc.y, data.npc.z) - vector3(old.x, old.y, old.z)) > 0.05 or math.abs(data.npc.w - old.w) > 0.5 then
            Config.Npc.coords = data.npc
            removeNpc()
            createNpcBlip()
        end
    end
end)

CreateThread(function()
    createNpcBlip()
    TriggerServerEvent('bl_gopostal:requestSync')
    SendNUIMessage({ action = 'brand', data = Config.Brand })

    while true do
        local sleep = 1000
        local c = Config.Npc.coords
        local dist = #(GetEntityCoords(PlayerPedId()) - vector3(c.x, c.y, c.z))

        if dist < 80.0 and not npcPed then spawnNpc() end
        if dist > 100.0 and npcPed then removeNpc() end

        if npcPed and not targeting() and dist < Config.Npc.interactDistance + 1.0 and not menuOpen and not carry then
            sleep = 0
            helpText(('~INPUT_CONTEXT~ Parler au %s'):format(Config.Npc.name:lower()))
            if IsControlJustReleased(0, 38) then talkToNpc() end
        end
        Wait(sleep)
    end
end)

-- --- MENU ---
RegisterNetEvent('bl_gopostal:openMenu', function(data)
    menuOpen = true
    SetNuiFocus(true, true)
    for _, t in ipairs(data.tours) do t.vehicleLabel = vehicleLabel(t.vehicle) end
    data.npcName = Config.Npc.name
    if data.night then serverNight = data.night.active == true end
    SendNUIMessage({ action = 'menu', data = data })
end)

local function closeMenu()
    menuOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'closeMenu' })
end

RegisterNUICallback('close', function(_, cb)
    closeMenu()
    cb('ok')
end)

local function pickOutfit(value)
    wantOutfit = (value == 'standard' or value == 'exclusive') and value or false
end

RegisterNUICallback('start', function(data, cb)
    cb('ok')
    closeMenu()
    if tour then return end
    local free = false
    for _, s in ipairs(Config.VanSpawns) do
        if not IsAnyVehicleNearPoint(s.x, s.y, s.z, 3.0) then free = true; break end
    end
    if not free then
        return notify('Toutes les places de van sont occupées, libère le parking avant de commencer.', 'error')
    end
    pickOutfit(data.outfit)
    TriggerServerEvent('bl_gopostal:startTour', tostring(data.tourId or ''))
end)

RegisterNUICallback('setPlate', function(data, cb)
    cb('ok')
    TriggerServerEvent('bl_gopostal:setPlate', tostring(data.plate or ''))
end)

RegisterNUICallback('cancelTour', function(_, cb)
    cb('ok')
    closeMenu()
    TriggerServerEvent('bl_gopostal:cancel')
end)

RegisterNUICallback('invite', function(data, cb)
    cb('ok')
    TriggerServerEvent('bl_gopostal:invite', tonumber(data.id))
end)

RegisterNUICallback('inviteAnswer', function(data, cb)
    cb('ok')
    closeMenu()
    if data.accept then pickOutfit(data.outfit) end
    TriggerServerEvent('bl_gopostal:inviteAnswer', data.accept == true)
end)

-- --- TOURNÉE ---
local function nearestPending(from)
    local best, bestDist = nil, math.huge
    for _, p in pairs(tour.parcels) do
        if not p.delivered and not p.dropped then
            local d = #(from - p.coords)
            if d < bestDist then best, bestDist = p, d end
        end
    end
    return best, bestDist
end

-- GPS vers l'adresse restante la plus proche
local function routeNearest()
    if not tour then return end
    local from = GetEntityCoords(PlayerPedId())
    local target = nearestPending(from)
    for _, p in pairs(tour.parcels) do
        if p.blip and DoesBlipExist(p.blip) then SetBlipRoute(p.blip, p == target) end
    end
    if target and target.blip then SetBlipRouteColour(target.blip, 5) end
    tour.target = target and target.id or nil
end

local function removeVanTarget()
    if tour then
        CBridge.remove(tour.vanTarget)
        tour.vanTarget, tour.vanTargetEnt = nil, nil
    end
end

local function cleanupTour()
    if not tour then return end
    stopCarry()
    for _, p in pairs(tour.parcels) do
        removeBlip(p.blip)
        CBridge.remove(p.zone)
    end
    removeVanTarget()
    CBridge.remove(tour.palletTarget)
    removeBlip(tour.vehBlip)
    removeBlip(tour.returnBlip)
    if tour.palletObj and DoesEntityExist(tour.palletObj) then DeleteEntity(tour.palletObj) end
    for _, obj in ipairs(tour.leftBoxes or {}) do deleteObject(obj) end
    if sortOpen then
        sortOpen = false
        SetNuiFocus(false, false)
        SendNUIMessage({ action = 'sortClose' })
    end
    tour = nil
    busy = false
end

local function setReturnPhase()
    tour.phase = 'return'
    removeBlip(tour.returnBlip)
    tour.returnBlip = makeBlip(tour.returnPos, 478, 5, 'Retour au dépôt', 0.9)
    SetBlipRoute(tour.returnBlip, true)
    SetBlipRouteColour(tour.returnBlip, 5)
end

local function spawnVan(data)
    local hash = loadModel(data.model)
    if not hash then
        notify('Véhicule introuvable : ' .. data.model, 'error')
        return nil
    end
    -- Première place libre parmi celles que le serveur n'a pas attribuées à un autre livreur
    local s, spot
    for _, c in ipairs(data.spawns) do
        if not IsAnyVehicleNearPoint(c.coords.x, c.coords.y, c.coords.z, 3.0) then s, spot = c.coords, c.index; break end
    end
    if not s then
        notify('Toutes les places de van sont occupées, libère le parking avant de commencer.', 'error')
        return nil
    end
    local z = groundZ(s.x, s.y, s.z)
    local veh = CreateVehicle(hash, s.x, s.y, z + 0.3, s.w, true, false)
    local t = GetGameTimer()
    while not DoesEntityExist(veh) and GetGameTimer() - t < 5000 do Wait(10) end
    if not DoesEntityExist(veh) then return nil end
    SetEntityAsMissionEntity(veh, true, true)
    SetVehicleNumberPlateText(veh, data.plate)
    SetVehicleOnGroundProperly(veh)
    SetVehicleDoorsLocked(veh, 1)
    SetVehicleEngineOn(veh, false, true, true)
    SetVehicleDirtLevel(veh, 0.0)
    -- Style de la tournée (Config.Tours[].style), sinon celui de tous les vans
    local base, own = Config.VanStyle or {}, {}
    for _, t in ipairs(Config.Tours) do
        if t.id == data.tour.id and t.style then own = t.style end
    end
    local style = { color = own.color or base.color, livery = own.livery or base.livery, extras = own.extras or base.extras }
    if style.color then SetVehicleColours(veh, style.color[1], style.color[2]) end
    if style.livery then
        SetVehicleModKit(veh, 0)
        SetVehicleLivery(veh, style.livery)
        SetVehicleMod(veh, 48, style.livery, false)
    end
    for id, on in pairs(style.extras or {}) do
        if DoesExtraExist(veh, id) then SetVehicleExtra(veh, id, not on) end
    end
    -- Améliorations débloquées par le niveau du livreur
    local mods = data.vanMods
    if mods then
        SetVehicleModKit(veh, 0)
        local function mod(slot, lvl)
            if lvl and lvl > 0 then
                local max = GetNumVehicleMods(veh, slot)
                if max > 0 then SetVehicleMod(veh, slot, math.min(lvl, max) - 1, false) end
            end
        end
        mod(11, mods.engine)
        mod(12, mods.brakes)
        mod(13, mods.transmission)
        if mods.turbo then ToggleVehicleMod(veh, 18, true) end
    end
    CBridge.fill(veh)
    SetModelAsNoLongerNeeded(hash)
    local netId = NetworkGetNetworkIdFromEntity(veh)
    SetNetworkIdCanMigrate(netId, true)
    TriggerServerEvent('bl_gopostal:vehicleSpawned', netId, spot)
    return veh, netId
end

-- Palette posée derrière le van, au niveau de ses roues (jamais sur un toit)
local function spawnPallet(veh)
    local hash = loadModel(Config.Pallet.model) or loadModel('prop_boxpile_07d')
    if not hash then return nil end
    local min = GetModelDimensions(GetEntityModel(veh))
    local o = Config.Pallet.offset or vector2(1.2, 3.0)
    local p = GetOffsetFromEntityInWorldCoords(veh, o.x, min.y - o.y, 0.0)
    local vz = GetEntityCoords(veh).z
    local z = vz + min.z
    local ok, gz = GetGroundZFor_3dCoord(p.x, p.y, vz + 1.0, false)
    if ok and math.abs(gz - z) < 2.0 then z = gz end
    local obj = CreateObject(hash, p.x, p.y, z, false, false, false)
    SetEntityHeading(obj, GetEntityHeading(veh))
    PlaceObjectOnGroundProperly(obj)
    FreezeEntityPosition(obj, true)
    SetModelAsNoLongerNeeded(hash)
    return obj, vector3(p.x, p.y, z)
end

-- Remet le van en référence s'il a changé de propriétaire réseau (ou pour un coéquipier)
local function resolveVan()
    if tour.vehicle and DoesEntityExist(tour.vehicle) then return tour.vehicle end
    if tour.netId and NetworkDoesNetworkIdExist(tour.netId) then
        local v = NetToVeh(tour.netId)
        if v ~= 0 and DoesEntityExist(v) then tour.vehicle = v; return v end
    end
    return nil
end

-- --- ACTIONS (touche E ou ciblage) ---
local act = {}

-- Conditions communes (le ciblage et la touche E testent les mêmes)
local function canAct()
    return tour ~= nil and not busy and not sortOpen and onFoot(PlayerPedId())
end

local function nearRear(veh, maxDist)
    if not veh then return false end
    local rear = vanRear(veh)
    return #(GetEntityCoords(PlayerPedId()).xy - rear.xy) < (maxDist or 2.0)
end

function act.canTakeFromPallet()
    return canAct() and tour.phase == 'loading' and not carry and tour.parcels[tour.loaded + 1] ~= nil
end

function act.takeFromPallet()
    if not act.canTakeFromPallet() then return end
    local nextParcel = tour.parcels[tour.loaded + 1]
    local ped = PlayerPedId()
    busy = true
    TaskTurnPedToFaceCoord(ped, tour.palletPos.x, tour.palletPos.y, tour.palletPos.z, 600)
    Wait(600)
    playOnce('random@domestic', 'pickup_low', 900)
    startCarry('load', nextParcel.type, nextParcel.id)
    busy = false
end

function act.canSort()
    return Config.Sorting.enabled and canAct() and tour.phase == 'loading' and tour.loaded == 0 and not tour.sorted and not carry
end

function act.sort()
    if not act.canSort() then return end
    busy = true
    TriggerServerEvent('bl_gopostal:sortStart')
    SetTimeout(3000, function() if not sortOpen then busy = false end end)
end

function act.canStore(veh)
    return canAct() and tour.phase == 'loading' and carry ~= nil and carry.kind == 'load' and nearRear(veh, 2.5)
end

function act.store(veh)
    if not act.canStore(veh) then return end
    busy = true
    setRearDoors(veh, true)
    playOnce('anim@heists@narcotics@trash', 'throw_b', 700)
    stopCarry()
    TriggerServerEvent('bl_gopostal:load')
    SetTimeout(3000, function() busy = false end)
end

function act.canTakeFromVan(veh)
    if not (canAct() and tour.phase == 'delivering' and not carry and nearRear(veh, 2.5)) then return false end
    local nearest, nd = nearestPending(GetEntityCoords(PlayerPedId()))
    return nearest ~= nil and nd < 70.0
end

function act.takeFromVan(veh)
    if not act.canTakeFromVan(veh) then return end
    local ped = PlayerPedId()
    local nearest = nearestPending(GetEntityCoords(ped))
    busy = true
    setRearDoors(veh, true)
    TaskTurnPedToFaceEntity(ped, veh, 600)
    Wait(600)
    playOnce('mini@repair', 'fixing_a_player', 1300)   -- fouille l'arrière du van
    startCarry('deliver', nearest.type, nearest.id)
    SetTimeout(4000, function() if DoesEntityExist(veh) then setRearDoors(veh, false) end end)
    busy = false
end

function act.canPutBack(veh)
    return canAct() and carry ~= nil and carry.kind == 'deliver' and nearRear(veh, 2.5)
end

function act.putBack(veh)
    if act.canPutBack(veh) then stopCarry() end
end

function act.canRing(p)
    return canAct() and tour.phase == 'delivering' and carry ~= nil and carry.kind == 'deliver' and carry.parcelId == p.id and not p.delivered
end

function act.ring(p)
    if not act.canRing(p) then return end
    local veh = resolveVan()
    local door = p.door or p.coords
    busy = true
    -- Sonne puis frappe à la porte
    PlaySoundFromCoord(-1, 'DOOR_BUZZ', door.x, door.y, door.z + 1.0, 'MP_PLAYER_APARTMENT', false, 0, false)
    playOnce('timetable@jimmy@doorknock@', 'knockdoor_idle', 1800)
    TriggerServerEvent('bl_gopostal:deliver', p.id, veh and GetVehicleBodyHealth(veh) or nil, GetClockHours(), currentWeather())
    -- sécurité si le serveur ne répond pas
    local id = p.id
    SetTimeout(12000, function() if tour and tour.parcels[id] and not tour.parcels[id].delivered then busy = false end end)
end

function act.canPhoto(p)
    return canAct() and not carry and tour.photo == p.id and p.photoUntil and GetGameTimer() < p.photoUntil
end

function act.photo(p)
    if not act.canPhoto(p) then return end
    local ped = PlayerPedId()
    local door = p.door or p.coords
    busy = true
    TaskTurnPedToFaceCoord(ped, door.x, door.y, door.z, 500)
    Wait(500)
    TaskStartScenarioInPlace(ped, 'WORLD_HUMAN_MOBILE_FILM_SHOCKING', 0, true)
    Wait(2000)
    PlaySoundFrontend(-1, 'Camera_Shoot', 'Phone_Soundset_Franklin', true)
    Wait(600)
    ClearPedTasks(ped)
    TriggerServerEvent('bl_gopostal:photo', p.id)
    tour.photo = nil
    busy = false
    -- Photo prise : le colis disparaît peu après
    if p.box then fadeAndDelete(p.box, 3000); p.box = nil end
end

-- Les callbacks du ciblage tournent hors d'un thread : on en crée un pour pouvoir attendre
local function async(fn, ...)
    local args = { ... }
    return function() CreateThread(function() fn(table.unpack(args)) end) end
end

-- Options de ciblage sur le van (ré-enregistrées si l'entité change de handle)
local function targetVan(veh)
    if tour.vanTargetEnt == veh then return end
    removeVanTarget()
    tour.vanTargetEnt = veh
    tour.vanTarget = CBridge.addEntity(veh, {
        { name = 'bl_gopostal_store', label = 'Ranger le colis dans le van', icon = 'fa-solid fa-box', distance = 4.0,
          canInteract = function() return act.canStore(veh) end, onSelect = async(act.store, veh) },
        { name = 'bl_gopostal_take', label = 'Prendre le prochain colis', icon = 'fa-solid fa-box-open', distance = 4.0,
          canInteract = function() return act.canTakeFromVan(veh) end, onSelect = async(act.takeFromVan, veh) },
        { name = 'bl_gopostal_putback', label = 'Remettre le colis dans le van', icon = 'fa-solid fa-rotate-left', distance = 4.0,
          canInteract = function() return act.canPutBack(veh) end, onSelect = async(act.putBack, veh) }
    })
end

-- Zone de ciblage à la porte d'une adresse
local function targetDoor(p)
    if p.zone or p.delivered then return end
    p.zone = CBridge.addZone(p.door or p.coords, 1.6, {
        { name = 'bl_gopostal_ring', label = 'Sonner et livrer le colis', icon = 'fa-solid fa-bell', distance = 2.5,
          canInteract = function() return act.canRing(p) end, onSelect = async(act.ring, p) },
        { name = 'bl_gopostal_photo', label = 'Prendre le colis en photo', icon = 'fa-solid fa-camera', distance = 3.0,
          canInteract = function() return act.canPhoto(p) end, onSelect = async(act.photo, p) }
    })
end

local function placePallet(veh)
    tour.palletObj, tour.palletPos = spawnPallet(veh)
    tour.palletPos = tour.palletPos or vanRear(veh)
    if tour.palletObj then
        tour.palletTarget = CBridge.addEntity(tour.palletObj, {
            { name = 'bl_gopostal_pallet', label = 'Prendre un colis', icon = 'fa-solid fa-box', distance = 2.5,
              canInteract = act.canTakeFromPallet, onSelect = async(act.takeFromPallet) },
            { name = 'bl_gopostal_sort', label = 'Trier les colis (bonus)', icon = 'fa-solid fa-table-cells', distance = 2.5,
              canInteract = act.canSort, onSelect = async(act.sort) }
        })
    end
end

local function hudData(pos, veh)
    local now = GetGameTimer()
    local stops = {}
    for _, p in pairs(tour.parcels) do
        stops[#stops + 1] = {
            id = p.id,
            label = p.label,
            type = p.type,
            typeLabel = parcelType(p.type).label,
            delivered = p.delivered,
            distance = #(pos - p.coords),
            remaining = p.deadlineAt and not p.delivered and (p.deadlineAt - now) / 1000 or nil,
            retry = p.retryAt and not p.delivered and p.retryAt > now and (p.retryAt - now) / 1000 or nil,
            photo = tour.photo == p.id and p.photoUntil and math.max(0, (p.photoUntil - now) / 1000) or nil,
            waiting = p.dropped and not p.delivered and tour.photo ~= p.id or nil,
            cod = p.cod,
            current = p.id == tour.target
        }
    end
    return {
        phase = tour.phase,
        tour = tour.label,
        plate = tour.plate,
        loaded = tour.loaded,
        total = tour.total,
        delivered = tour.delivered,
        earned = tour.earned + tour.tips,
        rating = tour.ratingCount > 0 and tour.ratingSum / tour.ratingCount or nil,
        stops = stops,
        carrying = carry and { label = parcelType(carry.typeKey).label, heavy = carry.heavy } or nil,
        returnDistance = #(pos - tour.returnPos),
        vanFar = veh == nil,
        codCash = tour.codCash or 0,
        night = isNight(),
        weather = weatherLabel(),
        premium = tour.premium,
        team = #tour.team > 1 and tour.team or nil,
        sorted = tour.sorted,
        canSort = Config.Sorting.enabled and tour.loaded == 0 and not tour.sorted,
        rush = rush and rush.endsAt > now and { label = rush.label, left = (rush.endsAt - now) / 1000 } or nil,
        logbook = { open = logbookOpen, compact = Config.Logbook.compactStops or 7, key = Config.Logbook.key }
    }
end

local function handleLoading(ped, pos, veh)
    local sleep = 250
    -- Déjà au volant malgré tout : le van ne roule pas avant la fin du chargement
    if GetVehiclePedIsIn(ped, false) == veh then
        DisableControlAction(0, 71, true)   -- accélérer
        DisableControlAction(0, 72, true)   -- freiner / reculer
        helpText('Charge d\'abord tous les colis avant de partir.')
        return 0
    end
    if not tour.palletPos then return sleep end
    local dPal = #(pos.xy - tour.palletPos.xy)
    local rear = doorPoint(vanRear(veh))
    local dRear = #(pos.xy - rear.xy)

    if not carry and dPal < 30.0 then
        sleep = 0
        DrawMarker(2, tour.palletPos.x, tour.palletPos.y, tour.palletPos.z + 1.6, 0, 0, 0, 180.0, 0, 0, 0.35, 0.35, 0.35, 255, 204, 0, 180, true, true, 2, false, nil, nil, false)
    end
    if carry and dRear < 30.0 then
        sleep = 0
        DrawMarker(1, rear.x, rear.y, rear.z + 0.02, 0, 0, 0, 0, 0, 0, 1.2, 1.2, 0.6, 255, 204, 0, 120, false, false, 2, false, nil, nil, false)
    end
    if targeting() or busy or not onFoot(ped) then return sleep end

    if not carry and dPal < 2.2 and act.canTakeFromPallet() then
        sleep = 0
        local text = ('~INPUT_CONTEXT~ Prendre un colis ~y~(%d/%d)~s~'):format(tour.loaded + 1, tour.total)
        if act.canSort() then text = text .. '~n~~INPUT_DETONATE~ Trier les colis ~g~(bonus)~s~' end
        helpText(text)
        if IsControlJustReleased(0, 38) then act.takeFromPallet()
        elseif act.canSort() and IsControlJustReleased(0, Config.Sorting.key or 47) then act.sort() end
    elseif carry and carry.kind == 'load' and dRear < 2.0 then
        sleep = 0
        helpText('~INPUT_CONTEXT~ Ranger le colis dans le van')
        if IsControlJustReleased(0, 38) then act.store(veh) end
    end
    return sleep
end

local function handleDelivering(ped, pos, veh)
    local sleep = 250
    local nearest, nd = nearestPending(pos)

    -- Recalage de la porte une fois proche (collisions chargées), puis zone de ciblage
    for _, p in pairs(tour.parcels) do
        if not p.delivered and not p.door and #(pos - p.coords) < 150.0 then
            p.door = doorPoint(p.coords)
            targetDoor(p)
        end
    end

    local target = carry and carry.kind == 'deliver' and tour.parcels[carry.parcelId] or nil
    local photo = tour.photo and tour.parcels[tour.photo] or nil
    if photo and (not photo.photoUntil or GetGameTimer() > photo.photoUntil) then
        tour.photo, photo = nil, nil   -- délai écoulé : le serveur valide sans photo
    end
    local markers = { nearest }
    if target and target ~= nearest then markers[#markers + 1] = target end
    if photo then markers[#markers + 1] = photo end
    for _, p in ipairs(markers) do
        if p and p.door and #(pos - p.door) < 60.0 then
            sleep = 0
            local col = p == photo and { 127, 167, 255 } or p.type == 'express' and { 229, 36, 63 } or { 255, 204, 0 }
            DrawMarker(1, p.door.x, p.door.y, p.door.z + 0.02, 0, 0, 0, 0, 0, 0, 1.4, 1.4, 0.5, col[1], col[2], col[3], 120, false, false, 2, false, nil, nil, false)
            DrawMarker(29, p.door.x, p.door.y, p.door.z + 1.3, 0, 0, 0, 0, 0, 0, 0.6, 0.6, 0.6, col[1], col[2], col[3], 170, true, true, 2, false, nil, nil, false)
        end
    end

    if targeting() or busy or not onFoot(ped) then return sleep end

    -- Photo du colis déposé devant la porte
    if photo and not carry then
        local door = photo.door or photo.coords
        if #(pos - door) < 4.0 then
            sleep = 0
            helpText(('~INPUT_CONTEXT~ Prendre le colis en photo ~b~(%d s)~s~'):format(math.ceil((photo.photoUntil - GetGameTimer()) / 1000)))
            if IsControlJustReleased(0, 38) then act.photo(photo) end
            return sleep
        end
    end

    if not veh then return sleep end
    local dRear = #(pos.xy - vanRear(veh).xy)

    if not carry then
        if dRear < 2.0 and nearest and nd < 70.0 then
            sleep = 0
            helpText(('~INPUT_CONTEXT~ Prendre le colis pour ~y~%s~s~'):format(nearest.label))
            if IsControlJustReleased(0, 38) then act.takeFromVan(veh) end
        elseif dRear < 2.0 then
            sleep = 0
            helpText('Aucune adresse à proximité. Suis le GPS.')
        end
    elseif target then
        local door = target.door or target.coords
        local dDoor = math.abs(pos.z - door.z) < 3.0 and #(pos.xy - door.xy) or 99.0
        if dDoor < 1.8 then
            sleep = 0
            helpText('~INPUT_CONTEXT~ Sonner et livrer le colis')
            if IsControlJustReleased(0, 38) then act.ring(target) end
        elseif dRear < 2.0 then
            sleep = 0
            helpText('~INPUT_CONTEXT~ Remettre le colis dans le van')
            if IsControlJustReleased(0, 38) then act.putBack(veh) end
        end
    end
    return sleep
end

local function handleReturn(ped, pos, veh)
    local sleep = 250
    local ret = tour.returnPos
    local d = #(pos.xy - ret.xy)
    if d < 60.0 then
        sleep = 0
        local r = Config.Return.radius
        DrawMarker(1, ret.x, ret.y, ret.z + 0.02, 0, 0, 0, 0, 0, 0, r * 2, r * 2, 0.8, 255, 204, 0, 90, false, false, 2, false, nil, nil, false)
    end
    if busy or not veh or d > Config.Return.radius then return sleep end
    if GetVehiclePedIsIn(ped, false) ~= veh or GetPedInVehicleSeat(veh, -1) ~= ped then return sleep end

    sleep = 0
    if GetEntitySpeed(veh) > 2.0 then
        helpText('Arrête-toi dans la zone pour rendre le van')
        return sleep
    end
    helpText(tour.phase == 'return' and '~INPUT_CONTEXT~ Rendre le van et terminer la tournée'
        or '~INPUT_CONTEXT~ Rendre le van ~r~(fin anticipée, sans prime)~s~')
    if IsControlJustReleased(0, 38) then
        busy = true
        TriggerServerEvent('bl_gopostal:returnVan')
        SetTimeout(3000, function() busy = false end)
    end
    return sleep
end

local function tourLoop()
    local lastHud = 0
    while tour do
        local sleep = 250
        local ped = PlayerPedId()
        local pos = GetEntityCoords(ped)
        local now = GetGameTimer()
        local veh = resolveVan()

        if veh then
            tour.vanLastPos = GetEntityCoords(veh)
            if IsEntityDead(veh) or GetVehicleEngineHealth(veh) <= 0.0 then
                TriggerServerEvent('bl_gopostal:fail', 'destroyed')
                return
            end
            if not tour.vehBlip then
                tour.vehBlip = AddBlipForEntity(veh)
                SetBlipSprite(tour.vehBlip, 67)
                SetBlipColour(tour.vehBlip, 5)
                SetBlipScale(tour.vehBlip, 0.8)
                BeginTextCommandSetBlipName('STRING')
                AddTextComponentSubstringPlayerName(tour.member and 'Van de l\'équipe' or 'Mon van de livraison')
                EndTextCommandSetBlipName(tour.vehBlip)
            end
            targetVan(veh)
        elseif tour.vanLastPos and #(pos - tour.vanLastPos) < 200.0 and now - tour.startedAt > 5000 then
            -- Le van devrait être visible d'ici : il a été supprimé
            TriggerServerEvent('bl_gopostal:fail', 'destroyed')
            return
        end

        -- Colis livré par un coéquipier pendant qu'on le portait
        if carry and carry.kind == 'deliver' and tour.parcels[carry.parcelId] and tour.parcels[carry.parcelId].delivered then
            stopCarry()
        end

        if tour.phase == 'loading' then
            -- Palette posée derrière le van une fois qu'il est posé (pour chaque membre de l'équipe)
            if veh and not tour.palletObj and now - tour.startedAt > 300 then placePallet(veh) end
            if veh then sleep = handleLoading(ped, pos, veh) end
        else
            if tour.phase == 'delivering' then sleep = math.min(sleep, handleDelivering(ped, pos, veh)) end
            sleep = math.min(sleep, handleReturn(ped, pos, veh))
        end

        if now - lastHud > 300 then
            lastHud = now
            SendNUIMessage({ action = 'hud', data = hudData(pos, veh) })
        end
        Wait(sleep)
    end
end

-- Passage en livraison : palette retirée, van débloqué, adresses sur la carte
local function startDelivering(deadlines)
    tour.phase = 'delivering'
    if carry and carry.kind == 'load' then stopCarry() end
    CBridge.remove(tour.palletTarget)
    tour.palletTarget = nil
    if tour.palletObj and DoesEntityExist(tour.palletObj) then DeleteEntity(tour.palletObj) end
    tour.palletObj = nil
    local veh = resolveVan()
    if veh then
        FreezeEntityPosition(veh, false)
        SetVehicleDoorsLocked(veh, 1)
        setRearDoors(veh, false)
    end

    local now = GetGameTimer()
    local express = 0
    for _, p in pairs(tour.parcels) do
        local secs = deadlines and (deadlines[p.id] or deadlines[tostring(p.id)])
        if secs then p.deadlineAt = now + secs * 1000; express = express + 1 end
        if not p.delivered then
            local isExpress = p.type == 'express'
            p.blip = makeBlip(p.coords, 478, isExpress and 1 or 5, (isExpress and 'Express · ' or 'Colis · ') .. p.label, 0.75)
        end
    end
    routeNearest()
    return express
end

RegisterNetEvent('bl_gopostal:start', function(data)
    if tour then return end
    local parcels = {}
    local delivered = 0
    for _, p in ipairs(data.parcels) do
        parcels[p.id] = { id = p.id, type = p.type, cod = p.cod, label = (p.label and p.label ~= '') and p.label or streetLabel(p.coords),
                          coords = vector3(p.coords.x, p.coords.y, p.coords.z), delivered = p.delivered == true }
        if p.delivered then delivered = delivered + 1 end
    end
    tour = {
        id = data.id,
        member = data.member == true,
        team = data.team or {},
        label = data.tour.label,
        bonus = data.tour.bonus,
        premium = data.tour.premium == true,
        plate = data.plate,
        phase = 'loading',
        parcels = parcels,
        total = #data.parcels,
        loaded = data.loaded or 0,
        sorted = data.sorted == true,
        delivered = delivered,
        earned = 0,
        tips = 0,
        ratingSum = 0,
        ratingCount = 0,
        netId = data.netId,
        returnPos = vector3(data.returnPoint.x, data.returnPoint.y, groundZ(data.returnPoint.x, data.returnPoint.y, data.returnPoint.z)),
        leftBoxes = {},
        startedAt = GetGameTimer()
    }

    if not tour.member then
        local veh, netId = spawnVan(data)
        if not veh then
            TriggerServerEvent('bl_gopostal:fail', 'spawn')
            return
        end
        tour.vehicle, tour.netId = veh, netId
        -- Van bloqué et fermé tant que le chargement n'est pas fini (personne ne peut partir avec)
        FreezeEntityPosition(veh, true)
        SetVehicleDoorsLocked(veh, 2)
        setRearDoors(veh, true)
    end

    if wantOutfit then applyOutfit(wantOutfit == 'exclusive' and data.exclusiveOutfit and Config.Outfit.exclusive ~= nil) end
    wantOutfit = false

    if data.phase and data.phase ~= 'loading' then
        local deadlines = {}
        for _, p in ipairs(data.parcels) do if p.deadline then deadlines[p.id] = p.deadline end end
        startDelivering(deadlines)
        if data.phase == 'return' then setReturnPhase() end
    end

    if tour.member then
        notify(('Tu rejoins la tournée de %s. Aide à charger le van (%d/%d colis).'):format(data.ownerName, tour.loaded, tour.total), 'info')
    else
        local hint = Config.Sorting.enabled and ' Trie-les d\'abord pour un bonus.' or ''
        notify(('Charge les %d colis de la palette dans le van (%s).%s'):format(tour.total, data.plate, hint), 'info')
    end
    CreateThread(tourLoop)
end)

RegisterNetEvent('bl_gopostal:team', function(names)
    if tour and type(names) == 'table' then tour.team = names end
end)

RegisterNetEvent('bl_gopostal:keys', function(netId, plate, give)
    CreateThread(function()
        local veh
        if netId then
            local t = GetGameTimer()
            while GetGameTimer() - t < 5000 do
                if NetworkDoesNetworkIdExist(netId) then
                    local v = NetToVeh(netId)
                    if v ~= 0 and DoesEntityExist(v) then veh = v; break end
                end
                if not give then break end
                Wait(100)
            end
        end
        CBridge.keys(veh, plate, give)
    end)
end)

RegisterNetEvent('bl_gopostal:loadAck', function(loaded)
    if not tour then return end
    tour.loaded = loaded
    busy = false
end)

RegisterNetEvent('bl_gopostal:loaded', function(deadlines)
    if not tour then return end
    local express = startDelivering(deadlines)
    notify(express > 0 and ('Van chargé ! %d colis express, ne traîne pas.'):format(express) or 'Van chargé ! Suis le GPS jusqu\'aux adresses.', express > 0 and 'warn' or 'info')
end)

-- --- TRI AU DÉPÔT ---
-- Chaque colis porte le code du quartier de son adresse : il faut le ranger dans le bac de ce quartier.
RegisterNetEvent('bl_gopostal:sortOpen', function()
    if not tour or tour.sorted then busy = false; return end
    local items, binSet, bins = {}, {}, {}
    for _, p in pairs(tour.parcels) do
        local code, label = zoneOf(p.coords)
        label = label or code
        items[#items + 1] = { id = p.id, street = streetName(p.coords) or p.label, code = code, bin = label, type = parcelType(p.type).label }
        if not binSet[label] then binSet[label] = true; bins[#bins + 1] = label end
    end
    -- Bacs leurres : d'autres quartiers desservis par le dépôt, pour qu'il y ait de quoi se tromper
    local pool = {}
    for _, a in ipairs(Config.Addresses) do pool[#pool + 1] = a.coords end
    shuffle(pool)
    for _, c in ipairs(pool) do
        if #bins >= 4 then break end
        local code, label = zoneOf(c)
        label = label or code
        if not binSet[label] then binSet[label] = true; bins[#bins + 1] = label end
    end
    sortOpen = true
    busy = false
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'sort', data = {
        items = shuffle(items), bins = shuffle(bins), timeLimit = Config.Sorting.timeLimit,
        cash = Config.Sorting.cashPerParcel, perfect = Config.Sorting.perfectBonus
    } })
end)

local function closeSort()
    sortOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'sortClose' })
end

RegisterNUICallback('sortDone', function(data, cb)
    cb('ok')
    closeSort()
    TriggerServerEvent('bl_gopostal:sortDone', tonumber(data.correct) or 0)
end)

RegisterNUICallback('sortCancel', function(_, cb)
    cb('ok')
    closeSort()
end)

RegisterNetEvent('bl_gopostal:sorted', function(res)
    if not tour then return end
    tour.sorted = true
    if res.by and tour.member then
        notify(('%s a trié les colis : %d / %d bien rangés.'):format(res.by, res.correct, res.total), 'info')
    end
end)

-- --- REMISE DU COLIS ---
-- Client présent : il ouvre et prend le colis (signature / paiement selon le colis)
local function handOver(res)
    local ped = PlayerPedId()
    local model = Config.Customer.models[math.random(#Config.Customer.models)]
    local hash = loadModel(model)
    local customer = nil
    if hash then
        local pos = GetOffsetFromEntityInWorldCoords(ped, 0.0, 1.1, 0.0)
        customer = CreatePed(4, hash, pos.x, pos.y, pos.z - 1.0, GetEntityHeading(ped) + 180.0, false, true)
        SetBlockingOfNonTemporaryEvents(customer, true)
        SetEntityInvincible(customer, true)
        SetModelAsNoLongerNeeded(hash)
        TaskTurnPedToFaceEntity(customer, ped, 1000)
        if loadDict('gestures@m@standing@casual') then
            TaskPlayAnim(customer, 'gestures@m@standing@casual', 'gesture_hello', 8.0, -8.0, 1200, 48, 0, false, false, false)
        end
        Wait(1200)
    end
    -- Signature : le client signe sur la tablette du livreur
    if res and res.signature and customer then
        TaskStartScenarioInPlace(customer, 'WORLD_HUMAN_CLIPBOARD', 0, true)
        Wait(2500)
        ClearPedTasks(customer)
    end
    if loadDict('mp_common') then
        TaskPlayAnim(ped, 'mp_common', 'givetake1_a', 8.0, -8.0, 2000, 48, 0, false, false, false)
        if customer then TaskPlayAnim(customer, 'mp_common', 'givetake1_b', 8.0, -8.0, 2000, 48, 0, false, false, false) end
    end
    Wait(1100)
    stopCarry()
    Wait(1100)
    -- Paiement à la livraison : le client tend l'argent
    if res and res.cod and customer and loadDict('mp_common') then
        TaskPlayAnim(customer, 'mp_common', 'givetake1_a', 8.0, -8.0, 2000, 48, 0, false, false, false)
        TaskPlayAnim(ped, 'mp_common', 'givetake1_b', 8.0, -8.0, 2000, 48, 0, false, false, false)
        Wait(2000)
    end
    if customer then
        CreateThread(function()
            Wait(1500)
            for a = 255, 0, -25 do
                if not DoesEntityExist(customer) then return end
                SetEntityAlpha(customer, a, false)
                Wait(40)
            end
            DeleteEntity(customer)
        end)
    end
end

-- Client absent : colis déposé devant la porte (objet local, visible du seul livreur).
-- Il disparaît en fondu au bout de `lifetime` ms, et jamais plus de 3 restent au sol.
local MAX_LEFT_BOXES = 3
local function dropAtDoor(lifetime)
    local ped = PlayerPedId()
    local typeKey = carry and carry.typeKey or 'standard'
    playOnce('random@domestic', 'pickup_low', 900)
    stopCarry()
    local hash = loadModel(parcelType(typeKey).prop)
    if not hash or not tour then return nil end
    local pos = GetOffsetFromEntityInWorldCoords(ped, 0.0, 0.6, 0.0)
    local obj = CreateObject(hash, pos.x, pos.y, pos.z, false, false, false)
    PlaceObjectOnGroundProperly(obj)
    FreezeEntityPosition(obj, true)
    SetModelAsNoLongerNeeded(hash)

    -- Ménage : on oublie les colis déjà supprimés, puis on retire les plus anciens au-delà de la limite
    local alive = {}
    for _, o in ipairs(tour.leftBoxes) do
        if DoesEntityExist(o) then alive[#alive + 1] = o end
    end
    while #alive >= MAX_LEFT_BOXES do deleteObject(table.remove(alive, 1)) end
    alive[#alive + 1] = obj
    tour.leftBoxes = alive

    fadeAndDelete(obj, lifetime or 15000)
    return obj
end

-- Un coéquipier a posé ce colis devant la porte : il attend sa photo
RegisterNetEvent('bl_gopostal:parcelDropped', function(id)
    local p = tour and tour.parcels[id]
    if not p then return end
    p.dropped = true
    if carry and carry.parcelId == id then stopCarry() end
    routeNearest()
end)

local function markDelivered(p)
    p.delivered = true
    p.dropped = nil
    removeBlip(p.blip)
    p.blip = nil
    CBridge.remove(p.zone)
    p.zone = nil
    tour.delivered = tour.delivered + 1
end

RegisterNetEvent('bl_gopostal:deliverResult', function(res)
    if not tour then return end
    if not res.ok then
        if res.drop then
            -- Client absent : on pose le colis et on a quelques secondes pour la photo
            local q = tour.parcels[res.id]
            local box = dropAtDoor(((res.window or 20) + 5) * 1000)
            if q then q.box = box end
            busy = false
            if q then
                q.dropped = true
                q.photoUntil = GetGameTimer() + (res.window or 20) * 1000
                tour.photo = q.id
                targetDoor(q)
            end
            notify(('Personne ne répond. Prends le colis en photo devant la porte (%d s), sinon le client te retirera une étoile.'):format(res.window or 20), 'warn')
            routeNearest()
            return
        end
        busy = false
        if res.absent then
            local q = tour.parcels[res.id]
            if q then q.retryAt = GetGameTimer() + (res.retryIn or 0) * 1000 end
            local what = q and parcelType(q.type).cod and 'doit payer en main propre' or 'doit signer en main propre'
            notify(('Personne ne répond, le client %s. Livre une autre adresse et repasse dans %d s.'):format(what, res.retryIn or 0), 'warn')
        end
        return
    end
    local p = tour.parcels[res.id]
    if not p then busy = false; return end

    local wasDropped = p.dropped
    markDelivered(p)
    if tour.photo == p.id then tour.photo = nil end
    tour.earned = tour.earned + res.pay
    tour.tips = tour.tips + res.tip
    tour.ratingSum = tour.ratingSum + res.stars
    tour.ratingCount = tour.ratingCount + 1
    if Config.Night.clock == 'real' then serverNight = res.night == true end

    -- Livré par un coéquipier : pas d'animation de notre côté
    if not res.by then
        if res.present then handOver(res) elseif not wasDropped then dropAtDoor() end
        busy = false
        if res.cod then tour.codCash = (tour.codCash or 0) + res.cod end
    elseif carry and carry.parcelId == p.id then
        stopCarry()
    end

    SendNUIMessage({ action = 'delivered', data = {
        label = p.label, pay = res.pay, tip = res.tip, stars = res.stars, notes = res.notes,
        present = res.present, xp = res.xp, remaining = res.remaining, by = res.by,
        signature = res.signature, cod = res.cod, helped = res.helped, capped = res.capped,
        night = res.night, premium = res.premium, weather = res.weather, team = res.team,
        streak = res.streak, photo = res.photo, rush = res.rush
    } })
    if res.levelUp then
        PlaySoundFrontend(-1, 'RANK_UP', 'HUD_AWARDS', true)
        SendNUIMessage({ action = 'levelUp', data = res.levelUp })
    else
        PlaySoundFrontend(-1, 'PICK_UP', 'HUD_FRONTEND_DEFAULT_SOUNDSET', true)
    end

    if res.remaining == 0 then
        setReturnPhase()
        notify('Tournée terminée ! Ramène le van au dépôt pour toucher la prime et ta caution.', 'info')
    else
        routeNearest()
    end
end)

local payslipUntil = 0   -- fiche de fin de tournée affichée jusqu'à (GetGameTimer)

RegisterNetEvent('bl_gopostal:ended', function(summary)
    cleanupTour()
    restoreOutfit()
    summary.closeKey = Config.Logbook.key or 'F7'
    payslipUntil = GetGameTimer() + 12000
    SendNUIMessage({ action = 'end', data = summary })
end)

RegisterNetEvent('bl_gopostal:notify', function(msg, kind)
    notify(msg, kind)
end)

RegisterNetEvent('bl_gopostal:mission', function(data)
    PlaySoundFrontend(-1, 'CHALLENGE_UNLOCKED', 'HUD_AWARDS', true)
    SendNUIMessage({ action = 'mission', data = data })
end)

-- --- ÉVÉNEMENTS (RUSH) ---
RegisterNetEvent('bl_gopostal:rush', function(data)
    if type(data) ~= 'table' then return end
    if data.ended then
        rush = nil
        notify(('L\'événement %s « %s » est terminé.'):format(Config.Brand.name, data.label or ''), 'info')
        SendNUIMessage({ action = 'rush', data = nil })
        return
    end
    rush = { label = data.label, pay = data.pay, xp = data.xp, parcels = data.parcels, endsAt = GetGameTimer() + (data.endsIn or 0) * 1000 }
    local parts = {}
    if data.pay ~= 1 then parts[#parts + 1] = ('paie x%s'):format(data.pay) end
    if data.xp ~= 1 then parts[#parts + 1] = ('XP x%s'):format(data.xp) end
    if data.parcels ~= 1 then parts[#parts + 1] = ('colis x%s'):format(data.parcels) end
    PlaySoundFrontend(-1, 'CHALLENGE_UNLOCKED', 'HUD_AWARDS', true)
    notify(('Événement %s : %s ! %s pendant %d min.'):format(Config.Brand.name, data.label, table.concat(parts, ', '), math.ceil((data.endsIn or 0) / 60)), 'success')
    SendNUIMessage({ action = 'rush', data = data })
end)

-- --- CARNET DE TOURNÉE ---
-- La même touche ferme la fiche de fin de tournée quand elle est affichée
RegisterCommand('postalcarnet', function()
    if not tour and GetGameTimer() < payslipUntil then
        payslipUntil = 0
        SendNUIMessage({ action = 'closePayslip' })
        return
    end
    if not tour or tour.phase ~= 'delivering' then return end
    logbookOpen = not logbookOpen
    PlaySoundFrontend(-1, 'NAV_UP_DOWN', 'HUD_FRONTEND_DEFAULT_SOUNDSET', true)
end, false)
RegisterKeyMapping('postalcarnet', ('Livreur %s : carnet de tournée / fermer la fiche de fin'):format(Config.Brand.name), 'keyboard', Config.Logbook.key or 'F7')

-- --- MENU ADMIN ---
RegisterNetEvent('bl_gopostal:admin:open', function()
    if adminOpen then return end
    adminOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'adminOpen' })
    CreateThread(function()
        while adminOpen do
            Wait(3000)
            if adminOpen then TriggerServerEvent('bl_gopostal:admin:refresh') end
        end
    end)
end)

RegisterNetEvent('bl_gopostal:admin:data', function(data)
    SendNUIMessage({ action = 'adminData', data = data })
end)

RegisterNetEvent('bl_gopostal:admin:tp', function(c)
    local ped = PlayerPedId()
    local z = groundZ(c.x, c.y, c.z)
    SetEntityCoords(ped, c.x, c.y, z + 1.0, false, false, false, false)
end)

RegisterNUICallback('adminClose', function(_, cb)
    adminOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'adminClose' })
    cb('ok')
end)

RegisterNUICallback('adminAction', function(data, cb)
    TriggerServerEvent('bl_gopostal:admin:action', data.name, data.payload or {})
    cb('ok')
end)

-- --- OUTIL ADMIN ---
RegisterNetEvent('bl_gopostal:printPos', function()
    local ped = PlayerPedId()
    local c, h = GetEntityCoords(ped), GetEntityHeading(ped)
    local line = ('vector4(%.1f, %.1f, %.1f, %.1f)'):format(c.x, c.y, c.z, h)
    print('[bl_gopostal] position : ' .. line)
    notify('Position copiée dans la console F8 : ' .. line, 'info')
end)

-- --- NETTOYAGE ---
AddEventHandler('onResourceStop', function(name)
    if name ~= GetCurrentResourceName() then return end
    removeNpc()
    if tour and not tour.member and tour.vehicle and DoesEntityExist(tour.vehicle) then DeleteEntity(tour.vehicle) end
    cleanupTour()
    restoreOutfit()
    removeBlip(npcBlip)
    if menuOpen or adminOpen or sortOpen then SetNuiFocus(false, false) end
end)
