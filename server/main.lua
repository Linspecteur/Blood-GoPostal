GoPostal = GoPostal or {}
local tours = {}       -- [source du chef de tournée] = tournée en cours
local memberOf = {}    -- [source] = source du chef de tournée (le chef compris)
local invites = {}     -- [source invitée] = { owner, expires }
local cooldowns = {}   -- [identifier] = timestamp de fin
local nextId = 0
GoPostal.tours = tours

function GoPostal.resetCooldowns()
    for k in pairs(cooldowns) do cooldowns[k] = nil end
end

local function debug(...)
    if Config.Debug then print('[bl_gopostal]', ...) end
end

local function notify(src, msg, kind)
    TriggerClientEvent('bl_gopostal:notify', src, msg, kind or 'info')
end

local getIdentifier = Bridge.identifier
local playerName = Bridge.playerName

local function isBlockedJob(src)
    return Bridge.inJobs(src, Config.BlockedJobs)
end

local function countActive()
    local n = 0
    for _ in pairs(tours) do n = n + 1 end
    return n
end

local function findTour(id)
    for _, t in ipairs(Config.Tours) do
        if t.id == id then return t end
    end
end

local function depotPos()
    local c = Config.Npc.coords
    return vector3(c.x, c.y, c.z)
end

local function getVan(m)
    if not m.netId then return nil end
    local ent = NetworkGetEntityFromNetworkId(m.netId)
    if ent and ent ~= 0 and DoesEntityExist(ent) then return ent end
    return nil
end

-- --- ÉQUIPE ---
-- Tournée et fiche de membre d'un joueur (chef ou coéquipier)
local function tourOf(src)
    local owner = memberOf[src]
    local m = owner and tours[owner]
    if not m then return nil end
    return m, m.mem[src]
end
GoPostal.tourOf = tourOf

local function newMember(src, identifier, name, owner)
    return {
        src = src, identifier = identifier, name = name, owner = owner == true,
        earned = 0, tips = 0, xp = 0, bonus = 0, sortCash = 0,
        cod = 0, codCommission = 0, codRemitted = 0,
        delivered = 0, lastAction = 0, joinedAt = os.time()
    }
end

local function addMember(m, mem)
    m.members[#m.members + 1] = mem
    m.mem[mem.src] = mem
    memberOf[mem.src] = m.owner
end

local function teamNames(m)
    local list = {}
    for i, x in ipairs(m.members) do list[i] = x.name end
    return list
end

local function broadcast(m, event, data)
    for _, x in ipairs(m.members) do TriggerClientEvent(event, x.src, data) end
end

local function notifyTeam(m, msg, kind, except)
    for _, x in ipairs(m.members) do
        if x.src ~= except then notify(x.src, msg, kind) end
    end
end

-- Places de parking pas encore prises par le van d'un autre livreur (dans l'ordre de la config)
local function freeSpawns(except)
    local list = {}
    for i, s in ipairs(Config.VanSpawns) do
        local pos, taken = vector3(s.x, s.y, s.z), false
        for src, m in pairs(tours) do
            if src ~= except then
                local ent = getVan(m)
                if ent then
                    taken = #(GetEntityCoords(ent) - pos) < 4.0
                else
                    taken = m.spot == i -- van en cours d'apparition
                end
                if taken then break end
            end
        end
        if not taken then list[#list + 1] = { index = i, coords = s } end
    end
    return list
end

local function vanHealth(ent)
    return math.max(0.0, math.min(1.0, (math.max(0.0, GetVehicleBodyHealth(ent)) + math.max(0.0, GetVehicleEngineHealth(ent))) / 2000.0))
end

local function addMoney(src, amount)
    Bridge.addMoney(src, Config.Account, amount)
end

-- --- CLÉS DU VAN ---
-- Systèmes côté serveur ici, côté client via l'event bl_gopostal:keys
local function keysOn(res)
    local K = Config.Keys
    if not K or GetResourceState(res) ~= 'started' then return false end
    if K == 'auto' then return true end
    if type(K) == 'table' then
        for _, r in ipairs(K) do if r == res then return true end end
    end
    return false
end

local function giveKeys(src, m)
    local ent = getVan(m)
    if keysOn('bl_key') then pcall(function() exports.bl_key:GiveKey(src, m.plate) end) end
    if keysOn('Renewed-Vehiclekeys') then pcall(function() exports['Renewed-Vehiclekeys']:addKey(src, m.plate) end) end
    if ent and keysOn('qbx_vehiclekeys') then pcall(function() exports.qbx_vehiclekeys:GiveKeys(src, ent) end) end
    TriggerClientEvent('bl_gopostal:keys', src, m.netId, m.plate, true)
end

local function removeKeys(src, m, ent)
    if keysOn('bl_key') then pcall(function() exports.bl_key:RemoveKey(src, m.plate) end) end
    if keysOn('Renewed-Vehiclekeys') then pcall(function() exports['Renewed-Vehiclekeys']:removeKey(src, m.plate) end) end
    if ent and keysOn('qbx_vehiclekeys') then pcall(function() exports.qbx_vehiclekeys:RemoveKeys(src, ent) end) end
    TriggerClientEvent('bl_gopostal:keys', src, m.netId, m.plate, false)
end

local function postEmbed(url, embed, content)
    if not url or url == '' then return end
    embed.footer = embed.footer or { text = ('%s · %s'):format(Config.Brand.name, os.date('%d/%m/%Y %H:%M')) }
    embed.timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ')
    PerformHttpRequest(url, function() end, 'POST', json.encode({
        username = 'Intérim · ' .. Config.Brand.name,
        content = content,
        embeds = { embed }
    }), { ['Content-Type'] = 'application/json' })
end

-- lines : texte de l'embed, fields : { { name, value, inline } }
local function webhook(title, lines, color, fields)
    postEmbed(Config.Webhook, { title = title, description = lines and table.concat(lines, '\n') or nil, color = color or 16750592, fields = fields })
end

-- Fiche du joueur pour les embeds
local function who(src, m)
    local mem = m and m.mem and m.mem[src]
    local name = mem and mem.name or playerName(src)
    local id = mem and mem.identifier or getIdentifier(src)
    return ('%s (ID %d)\n`%s`'):format(name, src, id)
end

-- --- ALERTES STAFF ---
-- Une seule alerte par type et par joueur toutes les Config.Alerts.throttle secondes
local lastAlert = {}
local function alert(kind, src, m, title, lines, fields)
    local A = Config.Alerts
    if not A or not A.enabled then return end
    local url = (A.webhook and A.webhook ~= '') and A.webhook or Config.Webhook
    if not url or url == '' then return end
    local mem = m and m.mem and m.mem[src]
    local key = kind .. ':' .. (mem and mem.identifier or getIdentifier(src))
    local now = os.time()
    if lastAlert[key] and now - lastAlert[key] < (A.throttle or 600) then return end
    lastAlert[key] = now

    local f = { { name = 'Livreur', value = who(src, m), inline = true } }
    if m then f[#f + 1] = { name = 'Tournée', value = ('%s · %s'):format(m.tour.label, m.plate), inline = true } end
    for _, x in ipairs(fields or {}) do f[#f + 1] = x end
    postEmbed(url, { title = '⚠ ' .. title, description = table.concat(lines or {}, '\n'), color = 15026239, fields = f },
        (A.mention and A.mention ~= '') and A.mention or nil)
    print(('[bl_gopostal] ALERTE %s : %s (ID %d)'):format(kind, mem and mem.name or playerName(src), src))
end

GoPostal.addMoney = addMoney
GoPostal.getIdentifier = getIdentifier
GoPostal.webhook = webhook
GoPostal.alert = alert
GoPostal.notify = notify

-- Retire jusqu'à `amount` (dans la limite du solde) et renvoie ce qui a été pris
local function removeMoney(src, amount)
    if amount <= 0 or not Bridge.ready() then return 0 end
    local take = math.min(amount, math.max(0, Bridge.getMoney(src, Config.Account)))
    if take > 0 and not Bridge.removeMoney(src, Config.Account, take) then return 0 end
    return take
end

-- Action refusée par le serveur : au-delà de Config.Alerts.refusals dans une tournée, on prévient le staff
local function refused(src, m, why)
    if not m then return end
    m.refusals = (m.refusals or 0) + 1
    local limit = Config.Alerts and Config.Alerts.refusals or 0
    if limit > 0 and m.refusals == limit then
        alert('refusals', src, m, 'Actions refusées à répétition', {
            ('%d actions refusées par le serveur sur cette tournée.'):format(m.refusals),
            'Possible déclenchement d\'events à la main (exécuteur) ou grosse désynchro.'
        }, { { name = 'Dernier refus', value = why, inline = false } })
    end
end

-- --- NUIT ---
-- clientHour : heure du jeu envoyée par le client (mode 'game')
local function isNight(clientHour)
    local N = Config.Night
    if not N or not N.enabled then return false end
    local h = N.clock == 'real' and tonumber(os.date('%H')) or tonumber(clientHour)
    if not h or h < 0 or h > 23 then return false end
    h = math.floor(h)
    if N.startHour > N.endHour then return h >= N.startHour or h < N.endHour end
    return h >= N.startHour and h < N.endHour
end
GoPostal.isNight = isNight

-- --- MÉTÉO ---
-- weather : nom du type de météo envoyé par le client (RAIN, THUNDER...)
local function weatherDef(weather)
    local W = Config.Weather
    if not W or not W.enabled or type(weather) ~= 'string' then return nil end
    return W.types[weather]
end

-- --- TIRAGE D'UNE TOURNÉE ---
local function pickType(tour)
    local pool, total = {}, 0
    for key, p in pairs(Config.Parcels) do
        local w = p.chance or 0
        if p.heavy then w = w * (tour.heavy or 1.0) end
        if w > 0 and not p.express then
            pool[#pool + 1] = { key = key, w = w }
            total = total + w
        end
    end
    table.sort(pool, function(a, b) return a.key < b.key end)
    local r = math.random() * total
    for _, e in ipairs(pool) do
        r = r - e.w
        if r <= 0 then return e.key end
    end
    return 'standard'
end

local function buildParcels(tour)
    local candidates = {}
    for i, a in ipairs(Config.Addresses) do
        if a.zone == tour.zone then candidates[#candidates + 1] = i end
    end
    if #candidates == 0 then return nil end

    -- mélange
    for i = #candidates, 2, -1 do
        local j = math.random(i)
        candidates[i], candidates[j] = candidates[j], candidates[i]
    end

    -- Événement en cours : plus de colis par tournée
    local rush = GoPostal.rushActive()
    local count = math.random(tour.parcels.min, tour.parcels.max)
    if rush and (rush.parcels or 1) ~= 1 then count = math.floor(count * rush.parcels + 0.5) end
    count = math.max(1, math.min(count, #candidates))
    local depot = depotPos()
    local list = {}
    for i = 1, count do
        local a = Config.Addresses[candidates[i]]
        local kind = (tour.express or 0) > 0 and math.random() < tour.express and 'express' or pickType(tour)
        local cod = nil
        if Config.Parcels[kind] and Config.Parcels[kind].cod then
            cod = math.random(Config.Cod.amount.min, Config.Cod.amount.max)
        end
        list[i] = {
            id = i,
            type = kind,
            cod = cod,
            label = a.label or '',
            coords = a.coords,
            km = #(a.coords - depot) / 1000.0,
            delivered = false
        }
    end
    return list
end

-- Estimation affichée dans le menu (fourchette de paie d'une tournée)
local function estimateTour(tour, mult)
    local depot = depotPos()
    local kmSum, n = 0, 0
    for _, a in ipairs(Config.Addresses) do
        if a.zone == tour.zone then kmSum = kmSum + #(a.coords - depot) / 1000.0; n = n + 1 end
    end
    if n == 0 then return { min = 0, max = 0 } end
    local avgKm = kmSum / n

    local wSum, payW = 0, 0
    for _, p in pairs(Config.Parcels) do
        local w = p.chance or 0
        if p.heavy then w = w * (tour.heavy or 1.0) end
        if not p.express and w > 0 then wSum = wSum + w; payW = payW + w * p.pay end
    end
    local avgPay = wSum > 0 and payW / wSum or Config.Parcels.standard.pay
    local ex = tour.express or 0
    avgPay = avgPay * (1 - ex) + Config.Parcels.express.pay * (1 + Config.Express.bonus) * ex

    local rush = GoPostal.rushActive()
    local rushPay = rush and rush.pay or 1.0
    local rushCount = rush and rush.parcels or 1.0
    local per = (avgPay + avgKm * Config.Pay.perKm) * mult * Config.Pay.multiplier * rushPay * (tour.premium and Config.Premium.payMult or 1.0)
    local bonus = tour.bonus * mult * Config.Pay.multiplier * rushPay
    local minCount = math.min(math.floor(tour.parcels.min * rushCount + 0.5), n)
    local maxCount = math.min(math.floor(tour.parcels.max * rushCount + 0.5), n)
    return {
        min = math.floor(per * 0.85 * minCount + bonus),
        max = math.floor(per * maxCount + bonus)
    }
end

-- --- FIN DE TOURNÉE ---
local labels = { success = 'Complète', partial = 'Écourtée', cancel = 'Abandon', fail = 'Échec' }
-- Pas de retenue sur le liquide encaissé : ce n'est pas la faute du livreur
local codExempt = { admin = true, spawn = true, left = true, ownerLeft = true }

-- Clôture la tournée d'un membre (chef ou coéquipier) : profil, liquide non rendu, délai, fiche de paie.
-- Renvoie le montant total versé à ce membre sur la tournée.
local function finishMember(m, mem, result, reason, extra)
    local src = mem.src
    local profile = GoPostal.players[mem.identifier]
    if profile and (result == 'success' or result == 'partial') then
        profile.tours = profile.tours + 1
        GoPostal.playersDirty = true
    end
    if profile and result == 'success' and reason ~= 'left' then
        GoPostal.missionProgress(src, profile, { tour = 1 })
        GoPostal.checkLevelRewards(src, profile)
    end

    -- Paiement à la livraison : le liquide encaissé n'a pas été remis au dépôt
    local codLost = 0
    if mem.cod > 0 and result ~= 'success' and result ~= 'partial' and not codExempt[reason] then
        codLost = removeMoney(src, mem.cod)
    end
    local A = Config.Alerts
    if A and mem.cod >= (A.codLost or 1) and result ~= 'success' and result ~= 'partial' and reason ~= 'admin' and reason ~= 'ownerLeft' then
        local missing = mem.cod - codLost
        alert('cod', src, m, 'Liquide non rendu au dépôt', {
            ('%d $ encaissés en paiement à la livraison, tournée terminée sans rendre le van (%s).'):format(mem.cod, reason or result),
            missing > 0 and ('**%d $ n\'ont pas pu être repris** sur son compte.'):format(missing) or 'La somme a été reprise sur son compte.'
        }, {
            { name = 'Encaissé', value = ('%d $'):format(mem.cod), inline = true },
            { name = 'Repris', value = ('%d $'):format(codLost), inline = true },
            { name = 'Manquant', value = ('%d $'):format(missing), inline = true }
        })
    end

    -- Le délai ne s'applique qu'aux tournées réellement effectuées
    if m.deliveredCount > 0 or result == 'success' then
        cooldowns[mem.identifier] = os.time() + Config.Cooldown
    end

    local refund = mem.owner and (extra.refund or 0) or 0
    local paid = mem.earned + mem.tips + mem.bonus + mem.codCommission + mem.sortCash - codLost

    if reason ~= 'left' then
        removeKeys(src, m, getVan(m))
        TriggerClientEvent('bl_gopostal:ended', src, {
            result = result,
            reason = reason,
            tour = m.tour.label,
            delivered = m.deliveredCount,
            total = #m.parcels,
            mine = mem.delivered,
            team = #m.members > 1 and teamNames(m) or nil,
            earned = mem.earned,
            tips = mem.tips,
            bonus = mem.bonus,
            sortCash = mem.sortCash,
            refund = refund,
            codCommission = mem.codCommission,
            codRemitted = mem.codRemitted,
            codLost = codLost,
            capped = mem.capped == true,
            deposit = mem.owner and m.deposit or 0,
            xp = mem.xp,
            duration = os.time() - mem.joinedAt,
            profile = profile and GoPostal.profileView(profile) or nil
        })
    end
    return paid
end

-- result : 'success' (tout livré + van rendu), 'partial' (van rendu avant la fin), 'cancel', 'fail'
-- src : le chef de tournée
function GoPostal.endTour(src, result, reason, extra)
    local m = tours[src]
    if not m then return end
    tours[src] = nil
    extra = extra or {}
    for _, x in ipairs(m.members) do memberOf[x.src] = nil end
    for target, inv in pairs(invites) do
        if inv.owner == src then invites[target] = nil end
    end

    local paidTotal = m.paidGone or 0
    local names = {}
    for _, x in ipairs(m.members) do
        -- Le chef s'est déconnecté : ses coéquipiers ne sont pas pénalisés
        local r = (not x.owner and reason == 'left') and 'ownerLeft' or reason
        paidTotal = paidTotal + finishMember(m, x, result, r, extra)
        names[#names + 1] = x.name
    end

    local ent = getVan(m)
    if ent then DeleteEntity(ent) end

    local duration = os.time() - m.createdAt
    GoPostal.addHistory({
        t = os.time(),
        name = table.concat(names, ' + '),
        identifier = m.identifier,
        tour = m.tour.label,
        result = result,
        reason = reason,
        delivered = m.deliveredCount,
        total = #m.parcels,
        paid = paidTotal,
        refund = extra.refund or 0,
        duration = duration,
        team = #m.members
    })

    local ids = {}
    for _, x in ipairs(m.members) do ids[#ids + 1] = x.identifier end
    for _, id in ipairs(m.leftIds or {}) do ids[#ids + 1] = id end
    GoPostal.recordStats({
        tourId = m.tour.id, result = result, reason = reason, delivered = m.deliveredCount,
        paid = paidTotal, duration = duration, identifiers = ids, team = #m.members + #(m.leftIds or {})
    })

    local refund = extra.refund or 0
    webhook(('Tournée terminée · %s'):format(m.tour.label), nil,
        result == 'success' and 4115580 or (result == 'partial' and 16750592 or 15026239), {
            { name = #m.members > 1 and 'Équipe' or 'Livreur', value = who(src, m) .. (#m.members > 1 and ('\n+ ' .. table.concat(names, ', ', 2)) or ''), inline = true },
            { name = 'Résultat', value = (labels[result] or result) .. (reason and (' (' .. reason .. ')') or ''), inline = true },
            { name = 'Colis', value = ('%d / %d'):format(m.deliveredCount, #m.parcels), inline = true },
            { name = 'Versé', value = ('%d $'):format(paidTotal + refund), inline = true },
            { name = 'Détail', value = ('paie %d · pourboires %d · caution %d'):format(m.earned, m.tips, refund), inline = false },
            { name = 'Durée', value = ('%d min'):format(math.floor(duration / 60)), inline = true },
            { name = 'Note', value = m.ratingCount > 0 and ('%.1f ★'):format(m.ratingSum / m.ratingCount) or '—', inline = true },
            { name = 'Refus serveur', value = tostring(m.refusals or 0), inline = true }
        })

    debug(('tournée %d terminée : %s (%s) %d/%d'):format(m.id, result, reason or '-', m.deliveredCount, #m.parcels))
end

-- Un coéquipier quitte l'équipe (commande, déconnexion). La tournée continue pour les autres.
local function leaveTeam(src, reason)
    local m, mem = tourOf(src)
    if not m or not mem or mem.owner then return end
    for i, x in ipairs(m.members) do
        if x.src == src then table.remove(m.members, i); break end
    end
    m.mem[src] = nil
    memberOf[src] = nil
    m.leftIds = m.leftIds or {}
    m.leftIds[#m.leftIds + 1] = mem.identifier
    m.paidGone = (m.paidGone or 0) + finishMember(m, mem, 'cancel', reason, {})
    notifyTeam(m, ('%s a quitté l\'équipe.'):format(mem.name), 'warn')
    broadcast(m, 'bl_gopostal:team', teamNames(m))
end

-- --- MENU DU DÉPÔT ---
local function nearbyCandidates(src)
    local list = {}
    local pos = GetEntityCoords(GetPlayerPed(src))
    for _, s in ipairs(GetPlayers()) do
        local other = tonumber(s)
        if other ~= src and not memberOf[other] then
            local ped = GetPlayerPed(other)
            if ped ~= 0 and #(GetEntityCoords(ped) - pos) <= Config.Coop.inviteRadius then
                list[#list + 1] = { id = other, name = playerName(other) }
            end
        end
    end
    return list
end

RegisterNetEvent('bl_gopostal:requestMenu', function(clientHour)
    local src = source
    if not Bridge.ready() then return end
    local identifier = getIdentifier(src)
    local profile = GoPostal.getProfile(identifier, playerName(src))
    GoPostal.payPending(src, identifier)
    local view = GoPostal.profileView(profile)
    local m, mem = tourOf(src)

    local list = {}
    for _, t in ipairs(Config.Tours) do
        list[#list + 1] = {
            id = t.id,
            label = t.label,
            desc = t.desc,
            zone = Config.Zones[t.zone] or t.zone,
            parcels = t.parcels,
            level = t.level,
            levelTitle = Config.Levels[t.level] and Config.Levels[t.level].title or ('Niveau ' .. t.level),
            locked = view.level < t.level or (t.premium == true and not view.premium),
            premium = t.premium == true,
            levelOk = view.level >= t.level,
            vehicle = t.vehicle,
            express = t.express or 0,
            heavy = (t.heavy or 1) > 1,
            estimate = estimateTour(t, view.mult)
        }
    end

    local levels = {}
    for i, l in ipairs(Config.Levels) do
        levels[i] = { title = l.title, xp = l.xp, mult = l.mult, cash = l.cash, van = l.van ~= nil, outfit = l.outfit, plate = l.plate }
    end

    local parcels = {}
    for key, p in pairs(Config.Parcels) do
        parcels[#parcels + 1] = { key = key, label = p.label, pay = p.pay, fragile = p.fragile, heavy = p.heavy, express = p.express,
                                  signature = p.signature, cod = p.cod, bulky = p.bulky }
    end
    table.sort(parcels, function(a, b) return a.pay < b.pay end)

    local active, team = nil, nil
    if m then
        active = { label = m.tour.label, delivered = m.deliveredCount, total = #m.parcels, phase = m.phase,
                   owner = mem.owner, ownerName = m.name }
        local C = Config.Coop
        team = {
            members = teamNames(m),
            max = C.maxMembers,
            canInvite = C.enabled and mem.owner and m.phase == 'loading' and m.netId ~= nil and #m.members < C.maxMembers,
        }
        if team.canInvite then team.candidates = nearbyCandidates(src) end
    end

    local invite = nil
    local inv = invites[src]
    if inv and inv.expires > os.time() and tours[inv.owner] and not m then
        local om = tours[inv.owner]
        invite = { from = om.name, tour = om.tour.label, expiresIn = inv.expires - os.time() }
    end

    local weather = {}
    if Config.Weather.enabled then
        local seen = {}
        for _, w in pairs(Config.Weather.types) do
            if not seen[w.label] then
                seen[w.label] = true
                weather[#weather + 1] = { label = w.label, pay = w.pay, fragile = w.fragile }
            end
        end
        table.sort(weather, function(a, b) return a.pay < b.pay end)
    end

    TriggerClientEvent('bl_gopostal:openMenu', src, {
        brand = Config.Brand,
        enabled = GoPostal.enabled,
        blocked = isBlockedJob(src),
        full = countActive() >= Config.MaxActive,
        cooldown = math.max(0, (cooldowns[identifier] or 0) - os.time()),
        deposit = Config.Deposit,
        account = Config.Account,
        active = active,
        team = team,
        invite = invite,
        tours = list,
        profile = view,
        levels = levels,
        parcels = parcels,
        leaderboard = GoPostal.leaderboard(10, identifier),
        express = { bonus = Config.Express.bonus },
        outfit = Config.Outfit.enabled,
        exclusiveOutfit = Config.Outfit.exclusive and Config.Outfit.exclusive.label or nil,
        missions = GoPostal.missionsView(profile),
        achievements = GoPostal.achievementsView(profile),
        weeklyRewards = Config.WeeklyRewards,
        cap = Config.Cap,
        cod = { commission = Config.Cod.commission },
        bulky = { helperPay = Config.Bulky.helperPay },
        coop = Config.Coop.enabled and { bonus = Config.Coop.bonus, max = Config.Coop.maxMembers } or nil,
        photo = Config.Photo.enabled and { window = Config.Photo.window, penalty = Config.Photo.penalty } or nil,
        sorting = Config.Sorting.enabled and { cash = Config.Sorting.cashPerParcel, perfect = Config.Sorting.perfectBonus } or nil,
        weather = #weather > 0 and weather or nil,
        streak = Config.Streak.enabled and { minParcels = Config.Streak.minParcels, perDay = Config.Streak.perDay, max = Config.Streak.max } or nil,
        rush = GoPostal.rushView(),
        night = Config.Night.enabled and {
            active = isNight(clientHour), from = Config.Night.startHour, to = Config.Night.endHour, clock = Config.Night.clock,
            payBonus = Config.Night.payBonus, presentFactor = Config.Night.presentFactor
        } or nil,
        premium = { minRating = Config.Premium.minRating, minRatings = Config.Premium.minRatings,
                    window = Config.Premium.window, payMult = Config.Premium.payMult }
    })
end)

-- Plaque personnalisée (avantage de niveau) : 8 caractères max, lettres / chiffres / espaces
local function cleanPlate(s)
    s = tostring(s or ''):upper():gsub('[^A-Z0-9 ]', ''):gsub('^%s+', ''):gsub('%s+$', '')
    return s:sub(1, 8)
end

RegisterNetEvent('bl_gopostal:setPlate', function(text)
    local src = source
    if not Bridge.ready() then return end
    local profile = GoPostal.getProfile(getIdentifier(src), playerName(src))
    local perks = GoPostal.perksFor(GoPostal.levelFor(profile.xp))
    if not perks.plate then return notify(src, 'La plaque personnalisée n\'est pas encore débloquée.', 'error') end
    local plate = cleanPlate(text)
    profile.plate = plate ~= '' and plate or nil
    GoPostal.playersDirty = true
    notify(src, profile.plate and ('Plaque enregistrée : %s'):format(profile.plate) or 'Plaque personnalisée retirée.', 'success')
end)

-- Données envoyées au client au départ (ou à l'arrivée d'un coéquipier en cours de tournée)
local function startPayload(m, mem, perks, spawns)
    local now = os.time()
    local parcels = {}
    for i, p in ipairs(m.parcels) do
        parcels[i] = { id = p.id, type = p.type, label = p.label, coords = p.coords, cod = p.cod,
                       delivered = p.delivered, deadline = p.deadline and (p.deadline - now) or nil }
    end
    return {
        id = m.id,
        member = not mem.owner,
        ownerName = m.name,
        team = teamNames(m),
        tour = { id = m.tour.id, label = m.tour.label, bonus = m.tour.bonus, premium = m.tour.premium == true },
        model = m.tour.vehicle,
        plate = m.plate,
        spawns = spawns,
        netId = m.netId,
        phase = m.phase,
        loaded = m.loaded,
        sorted = m.sorted == true,
        returnPoint = Config.Return.coords,
        parcels = parcels,
        deposit = mem.owner and m.deposit or 0,
        vanMods = perks.van,
        exclusiveOutfit = perks.outfit
    }
end

RegisterNetEvent('bl_gopostal:startTour', function(tourId)
    local src = source
    if not Bridge.ready() then return end
    if not GoPostal.enabled then return notify(src, 'Le dépôt ne recrute pas pour le moment.', 'error') end
    if memberOf[src] then return notify(src, 'Tu as déjà une tournée en cours.', 'error') end
    if isBlockedJob(src) then return notify(src, 'Ton métier ne te permet pas de faire de l\'intérim.', 'error') end

    local tour = findTour(tourId)
    if not tour then return end

    local npc = depotPos()
    if #(GetEntityCoords(GetPlayerPed(src)) - npc) > 15.0 then return end

    local spawns = freeSpawns(src)
    if #spawns == 0 then
        return notify(src, 'Toutes les places de van sont prises, attends qu\'un livreur parte.', 'error')
    end

    local identifier = getIdentifier(src)
    local name = playerName(src)
    local profile = GoPostal.getProfile(identifier, name)
    local level = GoPostal.levelFor(profile.xp)
    if level < tour.level then
        return notify(src, ('Cette tournée demande le niveau %d.'):format(tour.level), 'error')
    end
    if tour.premium and not GoPostal.premiumOk(profile) then
        local P = Config.Premium
        return notify(src, ('Les clients premium demandent %.1f ★ de satisfaction sur au moins %d livraisons.'):format(P.minRating, P.minRatings), 'error')
    end

    local now = os.time()
    if (cooldowns[identifier] or 0) > now then
        return notify(src, ('Repose-toi un peu, prochaine tournée dans %d s.'):format(cooldowns[identifier] - now), 'error')
    end
    if countActive() >= Config.MaxActive then
        return notify(src, 'Tous les vans sont sortis. Reviens dans quelques minutes.', 'error')
    end

    local parcels = buildParcels(tour)
    if not parcels or #parcels == 0 then
        return notify(src, 'Aucune adresse configurée pour cette tournée. Préviens un admin.', 'error')
    end

    if not Bridge.hasPlayer(src) then return end
    if Config.Deposit > 0 and not Bridge.removeMoney(src, Config.Account, Config.Deposit, 'Caution du van ' .. Config.Brand.name) then
        return notify(src, ('Il te faut %d $ %s pour la caution du van.'):format(Config.Deposit, Config.Account == 'bank' and 'en banque' or 'sur toi'), 'error')
    end
    invites[src] = nil

    local perks = GoPostal.perksFor(level)
    local plate = ('%s%05d'):format(Config.Brand.plate:sub(1, 3), math.random(0, 99999))
    if perks.plate and profile.plate and profile.plate ~= '' then plate = profile.plate end

    nextId = nextId + 1
    local m = {
        id = nextId,
        owner = src,
        tour = tour,
        phase = 'loading',
        identifier = identifier,
        name = name,
        members = {},
        mem = {},
        parcels = parcels,
        loaded = 0,
        deliveredCount = 0,
        plate = plate,
        deposit = Config.Deposit,
        earned = 0,
        tips = 0,
        far = 0,
        ratingSum = 0,
        ratingCount = 0,
        refusals = 0,
        createdAt = now,
        lastLoad = 0,
        spot = spawns[1].index
    }
    tours[src] = m
    local mem = newMember(src, identifier, name, true)
    addMember(m, mem)

    TriggerClientEvent('bl_gopostal:start', src, startPayload(m, mem, perks, spawns))
    notify(src, m.deposit > 0 and ('Caution de %d $ prélevée pour le van.'):format(m.deposit) or 'Van prêt sur le parking.', 'info')
    debug(('tournée %d lancée par %d : %s, %d colis'):format(m.id, src, tour.id, #parcels))
end)

RegisterNetEvent('bl_gopostal:vehicleSpawned', function(netId, spot)
    local src = source
    local m = tours[src]
    if not m or m.netId or type(netId) ~= 'number' then return end
    m.netId = netId
    if Config.VanSpawns[tonumber(spot) or 0] then m.spot = tonumber(spot) end
    local s = Config.VanSpawns[m.spot]
    if s then m.spotPos = vector3(s.x, s.y, s.z) end
    giveKeys(src, m)
end)

-- --- ÉQUIPE : INVITATIONS ---
RegisterNetEvent('bl_gopostal:invite', function(target)
    local src = source
    local C = Config.Coop
    if not C or not C.enabled then return end
    local m = tours[src]
    if not m then return notify(src, 'Lance d\'abord une tournée.', 'error') end
    if m.phase ~= 'loading' or not m.netId then return notify(src, 'On ne peut inviter un collègue que pendant le chargement du van.', 'error') end
    if #m.members >= C.maxMembers then return notify(src, 'Ton équipe est complète.', 'error') end
    target = tonumber(target)
    if not target or target == src or not GetPlayerName(target) then return end
    if memberOf[target] then return notify(src, 'Ce joueur a déjà une tournée en cours.', 'error') end
    local dist = #(GetEntityCoords(GetPlayerPed(target)) - GetEntityCoords(GetPlayerPed(src)))
    if dist > C.inviteRadius + 4.0 then return notify(src, 'Ce joueur est trop loin.', 'error') end
    if isBlockedJob(target) then return notify(src, 'Le métier de ce joueur ne lui permet pas de faire de l\'intérim.', 'error') end

    invites[target] = { owner = src, expires = os.time() + C.inviteTimeout }
    notify(src, ('Invitation envoyée à %s.'):format(playerName(target)), 'success')
    notify(target, ('%s t\'invite dans sa tournée « %s ». Parle au %s pour répondre (%d s).')
        :format(m.name, m.tour.label, Config.Npc.name:lower(), C.inviteTimeout), 'info')
end)

RegisterNetEvent('bl_gopostal:inviteAnswer', function(accept)
    local src = source
    local inv = invites[src]
    invites[src] = nil
    if not inv then return end
    local m = tours[inv.owner]
    if not m then return notify(src, 'Cette tournée est déjà terminée.', 'error') end
    local name = playerName(src)
    if not accept then
        return notify(inv.owner, ('%s a refusé ton invitation.'):format(name), 'warn')
    end
    if inv.expires < os.time() then return notify(src, 'L\'invitation a expiré.', 'error') end
    if not Bridge.ready() or not Bridge.hasPlayer(src) then return end
    if memberOf[src] then return notify(src, 'Tu as déjà une tournée en cours.', 'error') end
    if m.phase ~= 'loading' then return notify(src, 'Le van est déjà parti.', 'error') end
    if #m.members >= Config.Coop.maxMembers then return notify(src, 'L\'équipe est déjà complète.', 'error') end
    if isBlockedJob(src) then return notify(src, 'Ton métier ne te permet pas de faire de l\'intérim.', 'error') end
    if #(GetEntityCoords(GetPlayerPed(src)) - depotPos()) > 40.0 then return notify(src, 'Rejoins le dépôt pour monter dans l\'équipe.', 'error') end

    local identifier = getIdentifier(src)
    if (cooldowns[identifier] or 0) > os.time() then
        return notify(src, ('Repose-toi un peu, prochaine tournée dans %d s.'):format(cooldowns[identifier] - os.time()), 'error')
    end

    local profile = GoPostal.getProfile(identifier, name)
    local mem = newMember(src, identifier, name, false)
    addMember(m, mem)
    giveKeys(src, m)
    TriggerClientEvent('bl_gopostal:start', src, startPayload(m, mem, GoPostal.perksFor(GoPostal.levelFor(profile.xp)), nil))
    notifyTeam(m, ('%s rejoint l\'équipe !'):format(name), 'success', src)
    broadcast(m, 'bl_gopostal:team', teamNames(m))
end)

-- --- CHARGEMENT ---
RegisterNetEvent('bl_gopostal:load', function()
    local src = source
    local m, mem = tourOf(src)
    if not m or m.phase ~= 'loading' or m.loaded >= #m.parcels then return end

    local now = GetGameTimer()
    if now - mem.lastAction < Config.Security.loadGap then return end
    local van = getVan(m)
    local ref = van and GetEntityCoords(van) or depotPos()
    if #(GetEntityCoords(GetPlayerPed(src)) - ref) > Config.Security.loadRadius then
        refused(src, m, 'chargement loin du van')
        return notify(src, 'Tu es trop loin du van.', 'error')
    end
    mem.lastAction = now
    m.loaded = m.loaded + 1
    broadcast(m, 'bl_gopostal:loadAck', m.loaded)

    if m.loaded < #m.parcels then return end

    -- Tout est chargé : départ de la tournée
    m.phase = 'delivering'
    m.startedAt = os.time()
    local ent = getVan(m)
    m.bodyStart = ent and GetVehicleBodyHealth(ent) or 1000.0
    for _, x in ipairs(m.members) do
        x.lastStopPos, x.lastStopAt = GetEntityCoords(GetPlayerPed(x.src)), GetGameTimer()
    end
    for target, inv in pairs(invites) do
        if inv.owner == m.owner then invites[target] = nil end
    end

    -- Délais express : les plus proches d'abord, chaque arrêt précédent ajoute du temps
    local express = {}
    for _, p in ipairs(m.parcels) do if p.type == 'express' then express[#express + 1] = p end end
    table.sort(express, function(a, b) return a.km < b.km end)
    local deadlines = {}
    local e = Config.Express
    for rank, p in ipairs(express) do
        local secs = math.floor(e.base + (p.km * 1000.0) / e.avgSpeed * e.margin + (rank - 1) * e.perStop)
        p.deadline = m.startedAt + secs
        deadlines[p.id] = secs
    end
    broadcast(m, 'bl_gopostal:loaded', deadlines)
end)

-- --- TRI AU DÉPÔT ---
RegisterNetEvent('bl_gopostal:sortStart', function()
    local src = source
    local m = tourOf(src)
    if not m or not Config.Sorting.enabled or m.phase ~= 'loading' or m.loaded > 0 or m.sorted then return end
    m.sortStart = { by = src, at = GetGameTimer() }
    TriggerClientEvent('bl_gopostal:sortOpen', src)
end)

RegisterNetEvent('bl_gopostal:sortDone', function(correct)
    local src = source
    local m, mem = tourOf(src)
    if not m or m.sorted or not m.sortStart or m.sortStart.by ~= src then return end
    local S = Config.Sorting
    local n = #m.parcels
    local elapsed = (GetGameTimer() - m.sortStart.at) / 1000
    m.sorted = true
    m.sortStart = nil
    correct = math.max(0, math.min(n, math.floor(tonumber(correct) or 0)))
    -- Trop rapide pour être joué à la main
    if correct > 0 and elapsed < n * 0.3 then
        refused(src, m, ('tri de %d colis en %.1f s'):format(n, elapsed))
        correct = 0
    end
    if elapsed > S.timeLimit + 10 then correct = 0 end

    local perfect = correct == n
    m.sortPerfect = perfect
    local cash, xp = correct * S.cashPerParcel, correct * S.xpPerParcel
    if cash > 0 then
        local paid, capped = GoPostal.capEarn(mem.identifier, cash)
        cash = paid
        if capped then mem.capped = true end
        addMoney(src, cash)
    end
    mem.sortCash = mem.sortCash + cash
    mem.xp = mem.xp + xp
    local profile = GoPostal.getProfile(mem.identifier, mem.name)
    profile.xp = profile.xp + xp
    profile.earned = profile.earned + cash
    GoPostal.playersDirty = true
    if perfect then GoPostal.missionProgress(src, profile, { sortPerfect = 1 }) end
    GoPostal.checkLevelRewards(src, profile)

    broadcast(m, 'bl_gopostal:sorted', { correct = correct, total = n, perfect = perfect, by = mem.name })
    notify(src, perfect
        and ('Tri parfait ! +%d $ · +%d XP · prime de fin de tournée +%d %%'):format(cash, xp, math.floor(S.perfectBonus * 100 + 0.5))
        or ('Tri terminé : %d / %d colis bien rangés. +%d $ · +%d XP'):format(correct, n, cash, xp), perfect and 'success' or 'info')
end)

-- --- LIVRAISON ---
local function deliverFail(src, msg)
    TriggerClientEvent('bl_gopostal:deliverResult', src, { ok = false })
    if msg then notify(src, msg, 'error') end
end

-- Un autre joueur juste à côté, vivant, hors de l'équipe (aide pour les colis volumineux)
local function findHelper(src, pos, m)
    for _, s in ipairs(GetPlayers()) do
        local other = tonumber(s)
        if other ~= src and not m.mem[other] then
            local ped = GetPlayerPed(other)
            if ped ~= 0 and GetEntityHealth(ped) > 0 and #(GetEntityCoords(ped) - pos) <= Config.Bulky.helperRadius then
                return other
            end
        end
    end
end

local function teammateNear(m, src, pos)
    for _, x in ipairs(m.members) do
        if x.src ~= src then
            local ped = GetPlayerPed(x.src)
            if ped ~= 0 and GetEntityHealth(ped) > 0 and #(GetEntityCoords(ped) - pos) <= Config.Bulky.helperRadius then return true end
        end
    end
    return false
end

-- Livraison validée : note, paie partagée entre les membres, profils, missions.
-- ctx : { pos, hour, weather, body, present, t }   photo : nil (sans objet), true ou false
local function finalize(src, m, mem, p, ctx, photo)
    local t = Config.Parcels[p.type] or Config.Parcels.standard
    local ent = getVan(m)
    local pos = ctx.pos
    local present = ctx.present
    local night = isNight(ctx.hour)
    local premium = m.tour.premium == true
    local wx = weatherDef(ctx.weather)
    local rush = GoPostal.rushActive()
    local now = GetGameTimer()

    -- Note du client
    local stars, notes = 5, {}
    local condition = 1.0
    if t.fragile then
        local body = ent and GetVehicleBodyHealth(ent) or tonumber(ctx.body) or 1000.0
        local maxDamage = Config.Fragile.maxDamage / (wx and wx.fragile or 1.0)
        condition = math.max(0.0, math.min(1.0, 1.0 - (m.bodyStart - body) / maxDamage))
        if condition < 0.35 then stars = stars - 3; notes[#notes + 1] = 'colis cassé'
        elseif condition < 0.6 then stars = stars - 2; notes[#notes + 1] = 'colis abîmé'
        elseif condition < 0.85 then stars = stars - 1; notes[#notes + 1] = 'carton enfoncé' end
    end
    local onTime = true
    if p.deadline then
        onTime = ctx.t <= p.deadline
        if not onTime then stars = stars - 2; notes[#notes + 1] = 'en retard' end
    end
    -- Volumineux : un coéquipier ou un autre joueur doit aider à le porter jusqu'à la porte
    local helper, teamHelp = nil, false
    if t.bulky then
        teamHelp = teammateNear(m, src, pos)
        if not teamHelp then helper = findHelper(src, pos, m) end
        if not helper and not teamHelp then stars = stars - 1; notes[#notes + 1] = 'porté seul, carton cogné' end
    end
    if photo == false then
        stars = stars - (Config.Photo.penalty or 1)
        notes[#notes + 1] = 'pas de photo du dépôt'
    end
    -- Client premium : chaque défaut coûte une étoile de plus
    if premium and stars < 5 then stars = stars - 1; notes[#notes + 1] = 'client exigeant' end
    stars = math.max(1, math.min(5, stars))

    -- Paie de base, partagée à parts égales en équipe (avec le bonus d'équipe)
    local n = #m.members
    local team = n > 1
    local base = t.pay + p.km * Config.Pay.perKm
    if p.type == 'express' and onTime then base = base * (1.0 + Config.Express.bonus) end
    if night then base = base * (1.0 + Config.Night.payBonus) end
    if premium then base = base * Config.Premium.payMult end
    if wx then base = base * (1.0 + wx.pay) end
    if rush then base = base * rush.pay end
    if team then base = base * (1.0 + Config.Coop.bonus) / n end
    local starFactor = 0.6 + 0.08 * stars

    -- Pourboire : pour celui qui a sonné
    local tip = 0
    if present and stars >= 4 and math.random() < (premium and Config.Premium.tipChance or Config.Customer.tipChance) then
        tip = math.floor(math.random(Config.Customer.tip.min, Config.Customer.tip.max) * (premium and Config.Premium.tipMult or 1.0))
    end

    local xp = math.floor(t.xp * Config.Pay.xpMultiplier * (stars >= 4 and 1.0 or 0.6)
        * (night and (1.0 + Config.Night.xpBonus) or 1.0) * (rush and rush.xp or 1.0) + 0.5)

    p.delivered = true
    p.dropped = nil
    m.deliveredCount = m.deliveredCount + 1
    mem.delivered = mem.delivered + 1
    m.ratingSum, m.ratingCount = m.ratingSum + stars, m.ratingCount + 1
    if p.cod then mem.cod = mem.cod + p.cod end

    -- Beaucoup de distance en très peu de temps depuis l'arrêt précédent : téléportation probable
    local A = Config.Alerts
    if A and (A.maxSpeed or 0) > 0 and mem.lastStopPos then
        local dist = #(pos - mem.lastStopPos)
        local secs = math.max(1, (now - mem.lastStopAt) / 1000)
        if dist > 300.0 and dist / secs > A.maxSpeed then
            alert('speed', src, m, 'Déplacement anormalement rapide', {
                ('%.0f m parcourus en %d s depuis l\'arrêt précédent (%.0f km/h à vol d\'oiseau).'):format(dist, math.floor(secs), dist / secs * 3.6),
                'Téléportation ou véhicule modifié probable.'
            })
        end
    end
    mem.lastStopPos, mem.lastStopAt = pos, now

    local results = {}
    for _, x in ipairs(m.members) do
        local profile = GoPostal.getProfile(x.identifier, x.name)
        local lvlIdx, lvl = GoPostal.levelFor(profile.xp)
        local streak = GoPostal.streakBonus(profile)
        local pay = math.floor(base * lvl.mult * Config.Pay.multiplier * starFactor * (1.0 + streak))
        local myTip = x.src == src and tip or 0

        -- Plafond horaire : au-delà, la paie est réduite
        local gross = pay + myTip
        local paid, capped = GoPostal.capEarn(x.identifier, gross)
        if capped and gross > 0 then
            pay = math.floor(pay * paid / gross)
            myTip = paid - pay
            if not x.capped then
                x.capped = true
                notify(x.src, ('Plafond de %d $ / heure atteint : la paie des colis est réduite à %d %%.'):format(Config.Cap.perHour, math.floor(Config.Cap.overRate * 100)), 'warn')
            end
        end

        addMoney(x.src, pay + myTip)
        x.earned, x.tips, x.xp = x.earned + pay, x.tips + myTip, x.xp + xp
        m.earned, m.tips = m.earned + pay, m.tips + myTip

        profile.xp = profile.xp + xp
        profile.delivered = profile.delivered + 1
        profile.earned = profile.earned + pay + myTip
        profile.tips = profile.tips + myTip
        profile.ratingSum = profile.ratingSum + stars
        profile.ratingCount = profile.ratingCount + 1
        GoPostal.addRecentRating(profile, stars)
        profile.weekDelivered = profile.weekDelivered + 1
        profile.weekEarned = profile.weekEarned + pay + myTip
        GoPostal.playersDirty = true
        GoPostal.streakDeliver(x.src, profile)

        local stats = { deliver = 1, earn = pay + myTip }
        if night then stats.night = 1 end
        if premium then stats.premium = 1 end
        if team then stats.team = 1 end
        if wx then stats.weather = 1 end
        if photo == true and x.src == src then stats.photo = 1 end
        if t.fragile then
            if condition >= 0.85 then
                stats.fragile = 1
                profile.fragileRun = (profile.fragileRun or 0) + 1
                GoPostal.setRecord(profile, 'fragileStreak', profile.fragileRun)
            else
                profile.fragileRun = 0
            end
        end
        if p.type == 'express' and onTime then stats.express = 1 end
        if stars == 5 then stats.stars5 = 1 end
        if t.signature or t.cod or t.bulky then stats.special = 1 end
        if t.heavy then stats.heavy = 1 end
        GoPostal.missionProgress(x.src, profile, stats)
        GoPostal.checkLevelRewards(x.src, profile)

        -- Gains élevés sur l'heure glissante
        if A and (A.hourlyEarn or 0) > 0 then
            local hour = GoPostal.earnedLastHour(x.identifier)
            if hour >= A.hourlyEarn then
                alert('earn', x.src, m, 'Gains élevés sur une heure', {
                    ('%d $ gagnés en livraisons sur la dernière heure (seuil %d $).'):format(hour, A.hourlyEarn)
                }, { { name = 'Note de la tournée', value = ('%.1f ★ sur %d colis'):format(m.ratingSum / m.ratingCount, m.ratingCount), inline = true } })
            end
        end

        local newIdx, newLvl = GoPostal.levelFor(profile.xp)
        results[x.src] = {
            pay = pay, tip = myTip, xp = xp, capped = capped, streak = streak,
            levelUp = newIdx > lvlIdx and { level = newIdx, title = newLvl.title, mult = newLvl.mult } or nil
        }
    end

    if helper then
        local share = math.floor(results[src].pay * Config.Bulky.helperPay)
        addMoney(helper, share)
        notify(helper, ('Merci pour le coup de main ! +%d $'):format(share), 'success')
    end

    local remaining = #m.parcels - m.deliveredCount
    if remaining == 0 then m.phase = 'return' end

    for _, x in ipairs(m.members) do
        local r = results[x.src]
        TriggerClientEvent('bl_gopostal:deliverResult', x.src, {
            ok = true,
            id = p.id,
            by = x.src ~= src and mem.name or nil,
            pay = r.pay,
            tip = r.tip,
            stars = stars,
            notes = notes,
            present = present,
            xp = r.xp,
            remaining = remaining,
            signature = t.signature == true,
            cod = p.cod,
            helped = helper ~= nil or teamHelp,
            capped = r.capped,
            night = night,
            premium = premium,
            weather = wx and wx.label or nil,
            team = team,
            streak = r.streak,
            photo = photo,
            rush = rush and rush.label or nil,
            levelUp = r.levelUp
        })
    end
end

RegisterNetEvent('bl_gopostal:deliver', function(parcelId, clientBody, clientHour, weather)
    local src = source
    local m, mem = tourOf(src)
    if not m or m.phase ~= 'delivering' then return deliverFail(src) end

    local p = m.parcels[tonumber(parcelId) or 0]
    if not p or p.delivered or p.dropped then
        refused(src, m, ('colis invalide ou déjà livré (%s)'):format(tostring(parcelId)))
        return deliverFail(src)
    end

    local now = GetGameTimer()
    if now - mem.lastAction < Config.Security.deliverGap then
        debug(('livraison trop rapide (%d)'):format(src))
        refused(src, m, 'livraisons trop rapprochées')
        return deliverFail(src, 'Doucement, le client n\'a pas encore ouvert.')
    end

    local ped = GetPlayerPed(src)
    local pos = GetEntityCoords(ped)
    local gap = #(pos - p.coords)
    if gap > Config.Security.deliverRadius then
        debug(('livraison refusée (%d) : %.0f m de l\'adresse'):format(src, gap))
        refused(src, m, ('livraison à %.0f m de l\'adresse'):format(gap))
        return deliverFail(src, 'Tu n\'es pas à la bonne adresse.')
    end

    local ent = getVan(m)
    if ent and #(GetEntityCoords(ent) - pos) > Config.Security.vanRange then
        refused(src, m, 'van trop loin de l\'adresse')
        return deliverFail(src, 'Ton van est trop loin, rapproche-le de l\'adresse.')
    end
    local t = Config.Parcels[p.type] or Config.Parcels.standard
    local night = isNight(clientHour)

    -- Signature et paiement à la livraison : le client doit être là.
    -- Absent au premier passage, il est là quand on repasse après le délai.
    -- La nuit, les clients ouvrent moins souvent.
    local present = math.random() < Config.Customer.presentChance * (night and Config.Night.presentFactor or 1.0)
    if t.signature or t.cod then
        if p.retryAt then present = os.time() >= p.retryAt end
        if not present then
            p.retryAt = p.retryAt or (os.time() + Config.Signature.retryDelay)
            mem.lastAction = now
            TriggerClientEvent('bl_gopostal:deliverResult', src, { ok = false, absent = true, id = p.id, retryIn = math.max(0, p.retryAt - os.time()) })
            return
        end
    end
    mem.lastAction = now

    local ctx = { pos = pos, hour = clientHour, weather = weather, body = clientBody, present = present, t = os.time() }

    -- Client absent : colis posé devant la porte, le livreur doit le prendre en photo
    if not present and Config.Photo.enabled then
        p.dropped = { by = src, at = os.time(), ctx = ctx }
        TriggerClientEvent('bl_gopostal:deliverResult', src, { ok = false, drop = true, id = p.id, window = Config.Photo.window })
        for _, x in ipairs(m.members) do
            if x.src ~= src then TriggerClientEvent('bl_gopostal:parcelDropped', x.src, p.id) end
        end
        return
    end

    finalize(src, m, mem, p, ctx, nil)
end)

-- Photo du colis déposé devant la porte
RegisterNetEvent('bl_gopostal:photo', function(parcelId)
    local src = source
    local m, mem = tourOf(src)
    if not m then return end
    local p = m.parcels[tonumber(parcelId) or 0]
    if not p or p.delivered or not p.dropped or p.dropped.by ~= src then return end
    if os.time() - p.dropped.at > Config.Photo.window + 3 then return end
    if #(GetEntityCoords(GetPlayerPed(src)) - p.coords) > Config.Security.deliverRadius + 5.0 then
        return notify(src, 'Tu es trop loin du colis pour la photo.', 'error')
    end
    finalize(src, m, mem, p, p.dropped.ctx, true)
end)

-- Photos jamais prises : la livraison est validée sans photo à la fin du délai
CreateThread(function()
    while true do
        Wait(2000)
        local now = os.time()
        for _, m in pairs(tours) do
            for _, p in ipairs(m.parcels) do
                if p.dropped and now - p.dropped.at > Config.Photo.window + 2 then
                    local by = p.dropped.by
                    local mem = m.mem[by] or m.members[1]
                    finalize(mem.src, m, mem, p, p.dropped.ctx, false)
                end
            end
        end
    end
end)

-- --- RETOUR DU VAN ---
RegisterNetEvent('bl_gopostal:returnVan', function()
    local src = source
    local m = tourOf(src)
    if not m or (m.phase ~= 'delivering' and m.phase ~= 'return') then return end
    for _, p in ipairs(m.parcels) do
        if p.dropped then return notify(src, 'Attends la fin de la photo de dépôt en cours.', 'error') end
    end

    local ped = GetPlayerPed(src)
    local ret = Config.Return.coords
    if #(GetEntityCoords(ped) - ret) > Config.Return.radius + 10.0 then
        return notify(src, 'Gare le van dans la zone de retour du dépôt.', 'error')
    end

    local ent = getVan(m)
    local health = 1.0
    if ent then
        if #(GetEntityCoords(ent) - ret) > Config.Return.radius + 10.0 then
            return notify(src, 'Le van doit être dans la zone de retour.', 'error')
        end
        if GetVehiclePedIsIn(ped, false) ~= ent then
            return notify(src, 'Tu dois être au volant de ton van.', 'error')
        end
        health = vanHealth(ent)
    end

    local refund = math.floor(m.deposit * health)
    local allDone = m.phase == 'return'
    local n = #m.members
    local rush = GoPostal.rushActive()
    for _, x in ipairs(m.members) do
        local bonus = 0
        if allDone then
            local profile = GoPostal.getProfile(x.identifier, x.name)
            local _, lvl = GoPostal.levelFor(profile.xp)
            bonus = m.tour.bonus * lvl.mult * Config.Pay.multiplier * (rush and rush.pay or 1.0)
            if m.sortPerfect then bonus = bonus * (1.0 + Config.Sorting.perfectBonus) end
            if n > 1 then bonus = bonus * (1.0 + Config.Coop.bonus) / n end
            local capped
            bonus, capped = GoPostal.capEarn(x.identifier, math.floor(bonus))
            if capped then x.capped = true end
            profile.earned = profile.earned + bonus
            profile.weekEarned = profile.weekEarned + bonus
            GoPostal.playersDirty = true
        end
        -- Liquide des paiements à la livraison remis au dépôt : commission pour celui qui l'a encaissé
        x.bonus = bonus
        x.codRemitted = x.cod
        x.codCommission = math.floor(x.cod * Config.Cod.commission)
        addMoney(x.src, bonus + x.codCommission + (x.owner and refund or 0))
    end
    GoPostal.endTour(m.owner, allDone and 'success' or 'partial', nil, { refund = refund })
end)

local allowedFails = { destroyed = true, spawn = true }
RegisterNetEvent('bl_gopostal:fail', function(reason)
    local src = source
    local m, mem = tourOf(src)
    if not m or not allowedFails[reason] then return end
    if reason == 'spawn' then
        if not mem.owner then return end
        -- Le van n'a jamais pu apparaître : on rend la caution
        if not m.netId then addMoney(src, m.deposit) end
        return GoPostal.endTour(src, 'fail', reason, { refund = not m.netId and m.deposit or 0 })
    end
    GoPostal.endTour(m.owner, 'fail', reason)
end)

local function cancel(src)
    local m, mem = tourOf(src)
    if not m then return end
    if mem.owner then
        GoPostal.endTour(src, 'cancel', 'cancel')
        return
    end
    leaveTeam(src, 'leftTeam')
end

RegisterNetEvent('bl_gopostal:cancel', function()
    cancel(source)
end)

-- --- COMMANDES ---
RegisterCommand(Config.CancelCommand, function(src)
    if src == 0 then return end
    cancel(src)
end, false)

-- Réservée aux admins (ace command.postalpos)
RegisterCommand(Config.PosCommand, function(src)
    if src == 0 then return end
    TriggerClientEvent('bl_gopostal:printPos', src)
end, true)

-- --- VAN ABANDONNÉ ---
-- Toute l'équipe trop loin du van trop longtemps : tournée échouée, caution perdue
CreateThread(function()
    local step = 15
    while true do
        Wait(step * 1000)
        local A = Config.Abandon
        if A and (A.minutes or 0) > 0 then
            local limit = A.minutes * 60
            for src, m in pairs(tours) do
                local van = getVan(m)
                local near = false
                if van then
                    local vpos = GetEntityCoords(van)
                    for _, x in ipairs(m.members) do
                        local ped = GetPlayerPed(x.src)
                        if ped ~= 0 and #(GetEntityCoords(ped) - vpos) <= A.distance then near = true; break end
                    end
                end
                if van and not near then
                    m.far = (m.far or 0) + step
                    if m.far >= limit then
                        GoPostal.endTour(src, 'fail', 'abandoned')
                    elseif m.far >= limit / 2 and not m.farWarned then
                        m.farWarned = true
                        notifyTeam(m, ('Tu t\'éloignes de ton van ! Reviens-y avant %d min ou la tournée est annulée (caution perdue).'):format(math.ceil((limit - m.far) / 60)), 'warn')
                    end
                else
                    m.far, m.farWarned = 0, nil
                end
            end
        end
    end
end)

-- --- VAN DÉPLACÉ PENDANT LE CHARGEMENT ---
-- Le van est bloqué côté client tant que tout n'est pas chargé. S'il bouge quand même
-- (menu de triche, poussé, remorqué), la tournée échoue et la caution est perdue.
CreateThread(function()
    while true do
        Wait(2000)
        local limit = Config.Security.loadMove or 15.0
        for src, m in pairs(tours) do
            if m.phase == 'loading' and m.spotPos then
                local van = getVan(m)
                if van and #(GetEntityCoords(van) - m.spotPos) > limit then
                    alert('moved', src, m, 'Van sorti pendant le chargement', {
                        ('Le van a quitté sa place (%.0f m) avant que les colis soient chargés.'):format(#(GetEntityCoords(van) - m.spotPos))
                    })
                    notifyTeam(m, 'Le van a quitté le dépôt sans être chargé : tournée annulée, caution perdue.', 'error')
                    GoPostal.endTour(src, 'fail', 'moved')
                end
            end
        end
    end
end)

-- --- NETTOYAGE ---
AddEventHandler('playerDropped', function()
    local src = source
    invites[src] = nil
    if tours[src] then
        GoPostal.endTour(src, 'fail', 'left')
    elseif memberOf[src] then
        leaveTeam(src, 'left')
    end
end)

AddEventHandler('onResourceStop', function(name)
    if name ~= GetCurrentResourceName() then return end
    for src, m in pairs(tours) do
        local ent = getVan(m)
        if ent then DeleteEntity(ent) end
        -- Arrêt de la ressource : la caution n'est pas de la faute du joueur
        if m.deposit > 0 and Bridge.ready() then addMoney(src, m.deposit) end
    end
end)
