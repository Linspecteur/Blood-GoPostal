Config = {}

-- Affiche des infos de debug dans la console F8 / serveur
Config.Debug = false

-- Framework du serveur : 'auto' (détection), 'esx', 'qb' (qb-core), 'qbx' (qbx_core) ou 'ox' (ox_core)
Config.Framework = 'auto'

-- --- PÔLE INTÉRIMAIRE ---
-- Job accessible à tous, sans job ESX requis : le joueur garde son métier.
-- Marque entièrement réglable. Exemple Amazon : name = 'Amazon', logo = 'a', color = '#ff9f1c', logoColor = '#1a1208', plate = 'AMZ'
Config.Brand = {
    name = 'GoPostal',        -- nom affiché partout dans l'UI
    logo = 'GP',              -- texte du logo carré (1 à 3 caractères)
    color = '#ffcc00',        -- couleur d'accent de l'UI joueur
    logoColor = '#1b2f7a',    -- couleur du texte du logo (bleu GoPostal)
    pole = 'Pôle intérimaire',
    plate = 'GOP'             -- préfixe des plaques des vans (3 lettres max)
}

-- Métiers qui ne peuvent pas prendre de mission intérim (ex : { 'police', 'ambulance' })
Config.BlockedJobs = {}

-- Compte crédité (paie, pourboires, bonus) et débité (caution) : 'bank' ou 'cash'
Config.Account = 'bank'

-- --- INTÉGRATIONS ---
-- Notifications : 'nui' (celles du job), 'ox_lib', 'esx', 'qb', 'okok' ou 'custom' (Config.CustomNotify)
Config.Notify = 'nui'
-- Utilisé avec Config.Notify = 'custom' (côté client). kind : 'info', 'success', 'warn' ou 'error'
Config.CustomNotify = function(msg, kind)
    -- exports['mon_hud']:Notify(msg, kind)
end

-- Ciblage (« third-eye ») : 'auto' (ox_target, sinon qb-target), 'ox_target', 'qb-target' ou false (touche E)
-- Le PNJ, la palette, l'arrière du van et les portes passent par le ciblage. Le retour du van reste sur E.
Config.Target = 'auto'

-- Clés du van : 'auto' (toutes les ressources reconnues qui sont lancées), false (aucune)
-- ou une liste, ex. { 'qb-vehiclekeys' }. Reconnues : bl_key, qb-vehiclekeys, qbx_vehiclekeys, qs-vehiclekeys,
-- Renewed-Vehiclekeys, wasabi_carlock, MrNewbVehicleKeys, cd_garage
Config.Keys = 'auto'

-- Ressources de carburant : le plein est fait au départ avec celles qui sont lancées
Config.Fuel = { 'LegacyFuel', 'ox_fuel', 'cdn-fuel', 'ps-fuel', 'lc_fuel', 'qs-fuelstations', 'okokGasStation', 'Renewed-Fuel' }

-- --- LE RESPONSABLE DU DÉPÔT (PNJ) ---
-- Les coordonnées sont recalées au sol automatiquement.
-- Toutes les positions se règlent en jeu depuis /postaladmin > Positions.
Config.Npc = {
    model = 's_m_m_postal_01',
    coords = vector4(68.9, 126.5, 79.2, 160.0), -- dépôt GoPostal, Downtown Vinewood
    name = 'Responsable du dépôt',
    scenario = 'WORLD_HUMAN_CLIPBOARD',
    interactDistance = 2.0,
    blip = { enabled = true, sprite = 478, color = 5, scale = 0.75, label = 'Intérim · Livreur ' .. Config.Brand.name }
}

-- Places de parking où apparaissent les vans (une par livreur simultané, doivent être dégagées).
-- Le van prend la première place libre. Ajoute des places en jeu depuis /postaladmin > Positions.
Config.VanSpawns = {
    vector4(60.1, 121.6, 79.2, 162.2)
}

-- Palette de colis à charger : elle apparaît derrière le van, au niveau de ses roues.
-- offset : x = décalage sur le côté, y = recul depuis l'arrière du van (m)
Config.Pallet = {
    model = 'prop_boxpile_07d',
    offset = vector2(1.2, 3.0)
}

-- Zone de retour du van en fin de tournée
Config.Return = {
    coords = vector3(73.4, 120.6, 79.2),
    radius = 5.0
}

-- --- APPARENCE DES VANS ---
-- Pour un van moddé (add-on), mets son nom de spawn dans "vehicle" de chaque tournée ci-dessous.
-- livery : index de la livrée GoPostal si le modèle en propose plusieurs (nil = ne rien changer)
-- extras : { [id] = true/false } pour activer / retirer des extras du modèle
-- color  : { primaire, secondaire } couleurs GTA (nil = ne rien changer)
-- Une tournée peut avoir son propre style (champ `style` dans Config.Tours), qui passe avant celui-ci.
Config.VanStyle = {
    livery = nil,
    extras = {},
    color = nil
}

-- --- CAUTION DU VAN ---
-- Prélevée au départ, rendue au retour au prorata de l'état du van.
-- Perdue si le van est détruit, abandonné ou si le joueur se déconnecte.
Config.Deposit = 500

-- --- TOURNÉES ---
-- parcels : nombre de colis tiré entre min et max
-- level   : niveau intérim requis
-- express : part de colis express (0 à 1)
-- heavy   : multiplie la probabilité de colis lourds
-- bonus   : prime de fin de tournée si tous les colis sont livrés (avant multiplicateurs)
Config.Tours = {
    {
        id = 'quartier', label = 'Tournée de quartier', zone = 'ville',
        desc = 'Quelques colis dans les collines de Vinewood. Idéal pour découvrir le métier.',
        parcels = { min = 4, max = 5 }, level = 1, vehicle = 'boxville2', express = 0.0, heavy = 1.0, bonus = 250
    },
    {
        id = 'standard', label = 'Tournée standard', zone = 'ville',
        desc = 'Une tournée classique à travers Los Santos, quelques express à prévoir.',
        parcels = { min = 6, max = 8 }, level = 1, vehicle = 'boxville2', express = 0.15, heavy = 1.0, bonus = 500
    },
    {
        id = 'express', label = 'Livraisons express', zone = 'ville',
        desc = 'Tous les colis sont attendus dans les temps. Bien payé si tu tiens le rythme.',
        parcels = { min = 5, max = 6 }, level = 2, vehicle = 'boxville2', express = 1.0, heavy = 0.0, bonus = 800
    },
    {
        -- style : remplace Config.VanStyle pour cette tournée (ici un camion Benson marron)
        id = 'volume', label = 'Gros volume', zone = 'ville',
        desc = 'Beaucoup de colis, dont des lourds. Un camion porteur et de bons bras.',
        parcels = { min = 9, max = 12 }, level = 3, vehicle = 'benson', express = 0.1, heavy = 3.0, bonus = 1200,
        style = { color = { 96, 96 } }   -- 96 = marron chocolat (métallisé), 108 = marron utilitaire (mat)
    },
    {
        id = 'nord', label = 'Tournée Blaine County', zone = 'nord',
        desc = 'Sandy Shores, Grapeseed, Paleto Bay. Longue route, grosse prime.',
        parcels = { min = 6, max = 8 }, level = 4, vehicle = 'boxville2', express = 0.0, heavy = 1.5, bonus = 1600
    },
    {
        -- premium = true : réservée aux livreurs bien notés (Config.Premium)
        id = 'premium', label = 'Clients premium', zone = 'ville', premium = true,
        desc = 'Une clientèle exigeante, très bien payée et généreuse en pourboires. La moindre erreur coûte une étoile de plus.',
        parcels = { min = 5, max = 7 }, level = 2, vehicle = 'boxville2', express = 0.2, heavy = 0.5, bonus = 1500
    }
}

Config.Zones = {
    ville = 'Los Santos',
    nord = 'Blaine County'
}

-- --- TYPES DE COLIS ---
-- pay : paie de base, xp : expérience, chance : poids du tirage
-- fragile : abîmé si le van prend des chocs, heavy : impossible de courir en le portant
Config.Parcels = {
    standard = { label = 'Colis standard', pay = 170, xp = 10, chance = 55, prop = 'prop_cs_cardbox_01' },
    small    = { label = 'Petit paquet',   pay = 120, xp = 8,  chance = 22, prop = 'prop_cs_package_01' },
    fragile  = { label = 'Fragile',        pay = 250, xp = 14, chance = 13, prop = 'prop_cs_cardbox_01', fragile = true },
    heavy    = { label = 'Colis lourd',    pay = 310, xp = 16, chance = 10, prop = 'hei_prop_heist_box', heavy = true },
    express  = { label = 'Express',        pay = 260, xp = 15, chance = 0,  prop = 'prop_cs_package_01', express = true },
    -- Colis spéciaux
    signature = { label = 'Contre signature', pay = 280, xp = 16, chance = 8, prop = 'prop_cs_package_01', signature = true },
    cod       = { label = 'Paiement à la livraison', pay = 230, xp = 15, chance = 7, prop = 'prop_cs_cardbox_01', cod = true },
    bulky     = { label = 'Volumineux', pay = 380, xp = 20, chance = 5, prop = 'prop_boxpile_06b', heavy = true, bulky = true }
}

-- Contre signature : le client doit signer en main propre. Absent = repasser plus tard (il sera là).
Config.Signature = { retryDelay = 90 }   -- secondes avant de pouvoir repasser

-- Paiement à la livraison : le client paie en liquide, l'argent appartient au dépôt.
-- Il est remis au retour du van et le livreur touche une commission dessus.
-- Abandon, van détruit ou abandonné : la somme est retenue sur son compte (dans la limite de son solde).
Config.Cod = { amount = { min = 300, max = 1200 }, commission = 0.10 }

-- Volumineux : se porte mieux à deux. Un autre joueur à côté de toi à la porte = aide.
-- Seul : livré quand même, mais une étoile en moins (colis cogné).
Config.Bulky = { helperRadius = 4.0, helperPay = 0.30 }  -- l'aide touche 30 % de la paie du colis
-- (en tournée à deux, le coéquipier compte comme aide, sans paie en plus)

-- --- TOURNÉE EN ÉQUIPE ---
-- Pendant le chargement, le chef de tournée invite un collègue depuis le menu du responsable.
-- L'invité accepte depuis son propre menu. Un seul van, les colis sont partagés :
-- la paie de chaque colis (+ bonus) est répartie à parts égales, le pourboire va à celui qui a sonné,
-- et chacun gagne l'XP complète. La caution reste payée et rendue au chef de tournée.
Config.Coop = {
    enabled = true,
    maxMembers = 2,        -- livreurs par van, chef compris
    inviteRadius = 8.0,    -- distance max pour inviter un collègue (m)
    inviteTimeout = 60,    -- secondes pour accepter
    bonus = 0.15           -- +15 % sur la paie des colis livrés en équipe
}

-- --- PREUVE DE DÉPÔT ---
-- Client absent : le colis est posé devant la porte et le livreur a `window` secondes pour le prendre en photo.
-- Sans photo, le client retire `penalty` étoile(s).
Config.Photo = { enabled = true, window = 20, penalty = 1 }

-- --- TRI AU DÉPÔT ---
-- Mini-jeu facultatif avant de charger le premier colis : ranger chaque colis dans le bac de son quartier.
-- Gains par colis bien trié, et prime de fin de tournée augmentée si le tri est parfait.
Config.Sorting = {
    enabled = true,
    key = 47,              -- touche du jeu pour lancer le tri sans ciblage (47 = G)
    timeLimit = 40,        -- secondes
    cashPerParcel = 30,
    xpPerParcel = 2,
    perfectBonus = 0.10    -- +10 % sur la prime de fin de tournée
}

-- --- MÉTÉO ---
-- Par mauvais temps : paie des colis augmentée (pay) et colis fragiles plus sensibles aux chocs (fragile).
-- Météo lue sur le client (celle de ta synchro météo).
Config.Weather = {
    enabled = true,
    types = {
        CLEARING = { label = 'Averses', pay = 0.10, fragile = 1.25 },
        RAIN     = { label = 'Pluie',   pay = 0.15, fragile = 1.5 },
        THUNDER  = { label = 'Orage',   pay = 0.30, fragile = 2.0 },
        SNOWLIGHT = { label = 'Neige',  pay = 0.20, fragile = 1.5 },
        SNOW     = { label = 'Neige',   pay = 0.25, fragile = 1.5 },
        BLIZZARD = { label = 'Blizzard', pay = 0.35, fragile = 2.0 },
        XMAS     = { label = 'Neige',   pay = 0.25, fragile = 1.5 }
    }
}

-- --- SÉRIE DE JOURS ---
-- Un jour compte quand au moins minParcels colis y sont livrés.
-- Bonus de paie = perDay x jours consécutifs, plafonné à max. Un jour sauté remet la série à zéro.
Config.Streak = { enabled = true, minParcels = 5, perDay = 0.03, max = 0.15 }

-- --- PAIE ---
-- paie d'un colis = (base + km depuis le dépôt x perKm) x niveau x multiplicateur x note client
-- note client : 5 étoiles = 100 %, chaque étoile en moins retire 8 %
Config.Pay = {
    perKm = 55,
    multiplier = 1.0,
    xpMultiplier = 1.0
}

-- --- EXPRESS ---
-- délai = base + distance / vitesse x marge + perStop par colis express précédent (secondes)
Config.Express = { base = 90, avgSpeed = 22.0, margin = 1.4, perStop = 60, bonus = 0.40 }

-- --- FRAGILE ---
-- dégâts de carrosserie du van (depuis le chargement) qui ruinent un colis fragile
Config.Fragile = { maxDamage = 300.0 }

-- --- CLIENTS ---
Config.Customer = {
    presentChance = 0.65,           -- le client ouvre la porte (sinon colis déposé devant)
    tipChance = 0.35,               -- pourboire si client présent et note >= 4
    tip = { min = 40, max = 150 },
    models = { 'a_f_y_hipster_02', 'a_m_y_hipster_01', 'a_f_m_bevhills_01', 'a_m_m_bevhills_02', 'a_f_y_business_02', 'a_m_y_business_03', 'a_m_m_farmer_01', 'a_f_m_fatwhite_01' }
}

-- --- LIVRAISONS DE NUIT ---
-- De startHour à endHour, les colis sont mieux payés mais les clients ouvrent moins souvent.
-- clock : 'game' (heure du jeu, celle de ta synchro météo / heure) ou 'real' (heure du serveur)
Config.Night = {
    enabled = true,
    clock = 'game',
    startHour = 22,
    endHour = 6,
    payBonus = 0.25,       -- +25 % sur la paie des colis
    xpBonus = 0.15,        -- +15 % d'expérience
    presentFactor = 0.6    -- chance que le client ouvre multipliée par 0,6
}

-- --- SATISFACTION ET CLIENTS PREMIUM ---
-- Satisfaction = moyenne des notes sur les `window` dernières livraisons (elle peut donc baisser).
-- Les tournées premium demandent minRating de satisfaction, sur au moins minRatings notes.
-- Clients premium : paie x payMult, pourboires plus fréquents (tipChance) et plus gros (tipMult),
-- mais exigeants : chaque défaut (retard, colis abîmé...) coûte une étoile de plus.
Config.Premium = {
    window = 50,
    minRating = 4.5,
    minRatings = 20,
    payMult = 1.35,
    tipChance = 0.6,
    tipMult = 2.0
}

-- --- PROGRESSION ---
-- mult   : multiplicateur de paie du niveau
-- cash   : prime versée une fois en atteignant le niveau
-- van    : améliorations du van (engine / brakes / transmission de 0 à 3, turbo)
-- outfit : débloque la tenue exclusive (Config.Outfit.exclusive)
-- plate  : plaque personnalisée sur le van
Config.Levels = {
    { xp = 0,    title = 'Intérimaire',       mult = 1.00 },
    { xp = 250,  title = 'Livreur',           mult = 1.10, cash = 1000,  van = { engine = 1, brakes = 1 } },
    { xp = 700,  title = 'Livreur confirmé',  mult = 1.20, cash = 2500,  van = { engine = 2, brakes = 2, transmission = 1 } },
    { xp = 1500, title = 'Chef d\'équipe',    mult = 1.35, cash = 5000,  van = { engine = 2, brakes = 2, transmission = 2 }, outfit = true },
    { xp = 3000, title = 'Expert logistique', mult = 1.50, cash = 10000, van = { engine = 3, brakes = 2, transmission = 2, turbo = true }, outfit = true, plate = true }
}

-- --- MISSIONS ---
-- Tirées chaque jour / chaque semaine, les mêmes pour tout le monde. Récompense versée dès qu'elle est remplie.
-- stat : deliver (colis), fragile (fragiles intacts), express (express à l'heure), stars5 (notes 5 étoiles),
--        tour (tournées complètes), earn ($ gagnés), special (signature / paiement / volumineux), heavy (lourds et volumineux),
--        night (colis livrés de nuit), premium (colis livrés en tournée premium), team (colis livrés en équipe),
--        weather (colis livrés par mauvais temps), photo (dépôts photographiés), sortPerfect (tris parfaits)
Config.Missions = {
    dailyCount = 3,
    weeklyCount = 3,
    daily = {
        { id = 'd_deliver', label = 'Livrer 15 colis',                 stat = 'deliver', goal = 15, cash = 1500, xp = 60 },
        { id = 'd_fragile', label = 'Livrer 5 colis fragiles intacts', stat = 'fragile', goal = 5,  cash = 1800, xp = 70 },
        { id = 'd_express', label = 'Livrer 4 express à l\'heure',      stat = 'express', goal = 4,  cash = 1800, xp = 70 },
        { id = 'd_stars',   label = 'Obtenir 10 notes 5 étoiles',      stat = 'stars5',  goal = 10, cash = 1500, xp = 60 },
        { id = 'd_tour',    label = 'Terminer 2 tournées complètes',   stat = 'tour',    goal = 2,  cash = 2000, xp = 80 },
        { id = 'd_special', label = 'Livrer 3 colis spéciaux',         stat = 'special', goal = 3,  cash = 1600, xp = 60 },
        { id = 'd_heavy',   label = 'Livrer 4 colis lourds',           stat = 'heavy',   goal = 4,  cash = 1400, xp = 60 },
        { id = 'd_night',   label = 'Livrer 6 colis de nuit',          stat = 'night',   goal = 6,  cash = 1800, xp = 70 },
        { id = 'd_premium', label = 'Livrer 5 colis à des clients premium', stat = 'premium', goal = 5, cash = 2000, xp = 80 },
        { id = 'd_team',    label = 'Livrer 6 colis en équipe',        stat = 'team',    goal = 6,  cash = 1800, xp = 70 },
        { id = 'd_sort',    label = 'Réussir un tri parfait au dépôt', stat = 'sortPerfect', goal = 1, cash = 1200, xp = 50 }
    },
    weekly = {
        { id = 'w_deliver', label = 'Livrer 120 colis',                 stat = 'deliver', goal = 120,   cash = 12000, xp = 400 },
        { id = 'w_fragile', label = 'Livrer 30 colis fragiles intacts', stat = 'fragile', goal = 30,    cash = 10000, xp = 350 },
        { id = 'w_express', label = 'Livrer 25 express à l\'heure',      stat = 'express', goal = 25,    cash = 10000, xp = 350 },
        { id = 'w_tour',    label = 'Terminer 12 tournées complètes',   stat = 'tour',    goal = 12,    cash = 12000, xp = 400 },
        { id = 'w_earn',    label = 'Gagner 60 000 $ en livraisons',    stat = 'earn',    goal = 60000, cash = 8000,  xp = 300 },
        { id = 'w_special', label = 'Livrer 20 colis spéciaux',         stat = 'special', goal = 20,    cash = 10000, xp = 350 },
        { id = 'w_night',   label = 'Livrer 40 colis de nuit',          stat = 'night',   goal = 40,    cash = 11000, xp = 380 }
    }
}

-- --- RÉCOMPENSES DU CLASSEMENT HEBDO ---
-- Versées automatiquement au top 3 au changement de semaine (lundi).
-- Joueur hors ligne : versé à sa prochaine visite au dépôt ou connexion.
Config.WeeklyRewards = { 15000, 8000, 4000 }

-- --- SUCCÈS ---
-- Badges permanents affichés dans « Ma carrière ». Récompense versée une seule fois.
-- stat : les mêmes que les missions (cumulées depuis le début), plus :
--        fragileStreak (fragiles intacts d'affilée, un colis abîmé remet à zéro), streak (jours de travail d'affilée)
Config.Achievements = {
    { id = 'first',     label = 'Premier colis',       desc = 'Livrer son premier colis',              stat = 'deliver', goal = 1,      cash = 250 },
    { id = 'c100',      label = 'Centurion',           desc = 'Livrer 100 colis',                      stat = 'deliver', goal = 100,    cash = 2500,  xp = 100 },
    { id = 'c1000',     label = 'Légende du bitume',   desc = 'Livrer 1 000 colis',                    stat = 'deliver', goal = 1000,   cash = 20000, xp = 500 },
    { id = 'fragile50', label = 'Mains de velours',    desc = '50 colis fragiles intacts d\'affilée',  stat = 'fragileStreak', goal = 50, cash = 5000, xp = 200 },
    { id = 'express50', label = 'Toujours à l\'heure', desc = '50 colis express livrés à l\'heure',    stat = 'express', goal = 50,     cash = 5000,  xp = 200 },
    { id = 'stars100',  label = 'Client roi',          desc = '100 notes 5 étoiles',                   stat = 'stars5',  goal = 100,    cash = 4000,  xp = 150 },
    { id = 'tour50',    label = 'Pilier du dépôt',     desc = 'Terminer 50 tournées complètes',        stat = 'tour',    goal = 50,     cash = 8000,  xp = 300 },
    { id = 'night100',  label = 'Oiseau de nuit',      desc = 'Livrer 100 colis de nuit',              stat = 'night',   goal = 100,    cash = 4000,  xp = 150 },
    { id = 'storm50',   label = 'Ni pluie ni orage',   desc = 'Livrer 50 colis par mauvais temps',     stat = 'weather', goal = 50,     cash = 4000,  xp = 150 },
    { id = 'team50',    label = 'Esprit d\'équipe',    desc = 'Livrer 50 colis en équipe',             stat = 'team',    goal = 50,     cash = 4000,  xp = 150 },
    { id = 'sort10',    label = 'Trieur hors pair',    desc = 'Réussir 10 tris parfaits',              stat = 'sortPerfect', goal = 10, cash = 3000,  xp = 120 },
    { id = 'streak7',   label = 'Assidu',              desc = 'Travailler 7 jours d\'affilée',         stat = 'streak',  goal = 7,      cash = 7000,  xp = 250 },
    { id = 'rich',      label = 'Gros salaire',        desc = 'Gagner 250 000 $ en livraisons',        stat = 'earn',    goal = 250000, cash = 10000, xp = 300 }
}

-- --- ÉVÉNEMENTS (RUSH) ---
-- Lancés par un admin depuis /postaladmin > Événement, pour une durée donnée. Annoncés à tous les joueurs.
-- pay / xp : multiplicateurs de paie et d'XP des colis, parcels : multiplicateur du nombre de colis par tournée.
-- Le plafond horaire (Config.Cap) suit le multiplicateur de paie.
Config.Rush = {
    announce = true,
    presets = {
        { id = 'double',      label = 'Double paie',          pay = 2.0, xp = 1.0, parcels = 1.0, minutes = 30 },
        { id = 'blackfriday', label = 'Black Friday',         pay = 1.5, xp = 1.5, parcels = 1.5, minutes = 60 },
        { id = 'formation',   label = 'Formation accélérée',  pay = 1.0, xp = 2.0, parcels = 1.0, minutes = 30 }
    }
}

-- --- PLAFOND DE GAINS ---
-- Au-delà de perHour $ gagnés sur l'heure glissante, la paie des colis passe à overRate (25 %).
Config.Cap = { perHour = 30000, overRate = 0.25 }

-- --- VAN ABANDONNÉ ---
-- Livreur à plus de distance m de son van pendant minutes : tournée échouée, caution perdue.
Config.Abandon = { distance = 400.0, minutes = 5 }

-- --- LIMITES ---
Config.Cooldown = 60       -- délai entre deux tournées par joueur (secondes)
Config.MaxActive = 15      -- tournées simultanées max sur le serveur

-- --- SÉCURITÉ (vérifications côté serveur) ---
Config.Security = {
    loadRadius = 35.0,      -- distance max au van pour charger (m)
    loadGap = 1500,         -- délai min entre deux chargements (ms)
    deliverRadius = 15.0,   -- distance max à l'adresse pour livrer (m)
    deliverGap = 8000,      -- délai min entre deux livraisons (ms)
    vanRange = 90.0,        -- le van doit être à moins de X m du joueur pour livrer
    loadMove = 15.0         -- pendant le chargement, le van ne doit pas s'éloigner de plus de X m de sa place
}

-- --- TENUE DE TRAVAIL ---
-- Proposée dans le menu, remise automatiquement en fin de tournée.
-- Composants freemode : [id] = { drawable, texture }. À adapter à vos vêtements.
Config.Outfit = {
    enabled = true,
    male = {
        components = { [3] = { 0, 0 }, [4] = { 10, 0 }, [6] = { 24, 0 }, [8] = { 15, 0 }, [11] = { 56, 0 } },
        props = { [0] = { 10, 6 } }
    },
    female = {
        components = { [3] = { 14, 0 }, [4] = { 37, 0 }, [6] = { 24, 0 }, [8] = { 14, 0 }, [11] = { 49, 0 } },
        props = { [0] = { 10, 6 } }
    },
    -- Tenue exclusive, débloquée par un niveau avec outfit = true
    exclusive = {
        label = 'Tenue chef d\'équipe',
        male = {
            components = { [3] = { 1, 0 }, [4] = { 24, 0 }, [6] = { 10, 0 }, [8] = { 15, 0 }, [11] = { 241, 0 } },
            props = { [0] = { 10, 6 } }
        },
        female = {
            components = { [3] = { 3, 0 }, [4] = { 37, 0 }, [6] = { 29, 0 }, [8] = { 14, 0 }, [11] = { 249, 0 } },
            props = { [0] = { 10, 6 } }
        }
    }
}

-- --- ADRESSES DE LIVRAISON ---
-- coords = devant la porte / la boîte aux lettres. label est optionnel :
-- sans label, le nom de la rue et du quartier est lu directement dans le jeu.
-- Positions reprises de scripts GoPostal publiés (relevées en jeu).
-- Ajoute / recale les adresses en jeu depuis /postaladmin > Positions.
Config.Addresses = {
    -- Los Santos
    { zone = 'ville', coords = vector3(207.2, -85.2, 69.2) },
    { zone = 'ville', coords = vector3(319.9, -121.6, 68.4) },
    { zone = 'ville', coords = vector3(330.2, -202.5, 54.1) },
    { zone = 'ville', coords = vector3(-315.4, -3.9, 48.2) },
    { zone = 'ville', coords = vector3(-482.9, -17.1, 45.1) },
    { zone = 'ville', coords = vector3(121.7, 40.7, 73.5) },
    { zone = 'ville', coords = vector3(401.1, 98.8, 101.5) },
    { zone = 'ville', coords = vector3(172.5, 183.5, 105.7) },
    { zone = 'ville', coords = vector3(-85.2, 38.5, 71.9) },
    { zone = 'ville', coords = vector3(-599.1, -251.0, 36.3) },
    { zone = 'ville', coords = vector3(-722.5, -98.2, 38.2) },
    { zone = 'ville', coords = vector3(825.2, -96.2, 80.6) },
    { zone = 'ville', coords = vector3(-88.9, 214.9, 96.4) },
    { zone = 'ville', coords = vector3(-239.0, 205.8, 83.9) },
    { zone = 'ville', coords = vector3(-1146.7, 546.6, 100.5) },
    { zone = 'ville', coords = vector3(-867.3, 785.5, 191.0) },
    { zone = 'ville', coords = vector3(-134.4, 600.5, 204.2) },
    { zone = 'ville', coords = vector3(-378.9, 351.7, 108.1) },
    { zone = 'ville', coords = vector3(-1007.0, 512.8, 78.6) },
    { zone = 'ville', coords = vector3(-2008.5, 367.6, 93.8) },
    { zone = 'ville', coords = vector3(-1817.6, 343.4, 87.6) },
    { zone = 'ville', coords = vector3(-1109.1, -1060.6, 1.2) },
    { zone = 'ville', coords = vector3(-1086.0, -1503.8, 4.7) },
    { zone = 'ville', coords = vector3(132.5, -71.5, 66.7) },
    { zone = 'ville', coords = vector3(-569.3, 169.7, 65.6) },
    { zone = 'ville', coords = vector3(968.9, -551.7, 58.2) },
    { zone = 'ville', coords = vector3(868.2, -518.7, 56.4) },
    { zone = 'ville', coords = vector3(1371.1, -562.5, 73.4) },
    { zone = 'ville', coords = vector3(328.9, -1845.5, 27.8) },
    { zone = 'ville', coords = vector3(-20.8, -1858.6, 25.4) },
    { zone = 'ville', coords = vector3(1295.4, -1739.4, 53.3) },
    -- Blaine County
    { zone = 'nord', coords = vector3(-34.5, 6625.9, 29.3) },
    { zone = 'nord', coords = vector3(-416.9, 6255.2, 29.5) },
    { zone = 'nord', coords = vector3(31.2, 6596.7, 31.8) },
    { zone = 'nord', coords = vector3(-372.1, 6180.9, 30.5) },
    { zone = 'nord', coords = vector3(-214.5, 6431.5, 30.5) },
    { zone = 'nord', coords = vector3(1691.0, 4683.8, 42.0) },
    { zone = 'nord', coords = vector3(1712.6, 4634.2, 42.3) },
    { zone = 'nord', coords = vector3(2564.3, 4680.4, 33.1) },
    { zone = 'nord', coords = vector3(1835.8, 3776.9, 32.5) },
    { zone = 'nord', coords = vector3(1480.7, 3678.4, 33.3) },
    { zone = 'nord', coords = vector3(1987.1, 3813.8, 31.3) },
    { zone = 'nord', coords = vector3(1654.7, 3820.9, 34.5) },
    { zone = 'nord', coords = vector3(911.1, 3644.5, 32.7) },
}

-- --- CARNET DE TOURNÉE (HUD) ---
-- Touche pour déplier / replier la liste complète des arrêts.
-- Chaque joueur peut la changer dans Paramètres > Raccourcis clavier > FiveM.
Config.Logbook = {
    key = 'F7',
    compactStops = 7   -- arrêts affichés quand le carnet est replié
}

-- --- LOGS DISCORD (optionnel) ---
Config.Webhook = ''   -- URL du webhook (fins de tournée, classement), vide = désactivé

-- --- ALERTES STAFF (Discord) ---
-- Comportements suspects envoyés sur un webhook à part (vide = Config.Webhook).
-- mention : ex. '<@&123456789012345678>' pour notifier un rôle Discord
Config.Alerts = {
    enabled = true,
    webhook = '',
    mention = '',
    hourlyEarn = 25000,   -- gains sur l'heure glissante au-delà desquels on prévient
    maxSpeed = 75.0,      -- vitesse moyenne à vol d'oiseau entre deux livraisons (m/s, ~270 km/h) : téléportation probable
    refusals = 5,         -- actions refusées par le serveur dans une même tournée (mauvaise adresse, trop loin, trop rapide...)
    codLost = 1,          -- liquide de paiement à la livraison non rendu au dépôt, à partir de ce montant
    throttle = 10 * 60    -- délai min entre deux alertes du même type pour un même joueur (secondes)
}

-- --- COMMANDES ---
Config.CancelCommand = 'postalannuler'  -- abandonner sa tournée (caution perdue)
Config.PosCommand = 'postalpos'         -- (admin) affiche la position actuelle dans la console F8

-- --- MENU ADMIN (/postaladmin) ---
-- L'accès est donné si UNE de ces sources le permet. Mets une ligne à nil pour la désactiver.
Config.Admin = {
    command = 'postaladmin',

    -- Permission ace (txAdmin, server.cfg) :  add_ace group.admin bl_gopostal.admin allow
    ace = 'bl_gopostal.admin',

    -- Groupes ESX autorisés
    esxGroups = { 'owner', 'superadmin', 'admin' },

    -- BloodAdmin : permission "bl.gopostal" réglable par grade dans l'onglet Permissions
    bloodAdmin = { resources = { 'bl_admin_v4', 'bl_admin_v3', 'bl_admin' }, permission = 'bl.gopostal' },

    -- QBCore (si qb-core est lancé)
    qbPermissions = { 'god', 'admin' }
}
