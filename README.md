# Livreur GoPostal (bl_gopostal)

![FiveM](https://img.shields.io/badge/FiveM-Script-orange?style=flat-square)
![Framework](https://img.shields.io/badge/Framework-ESX%20%7C%20QBCore%20%7C%20Qbox%20%7C%20ox__core-blue?style=flat-square)
![Licence](https://img.shields.io/badge/Licence-voir%20LICENSE-lightgrey?style=flat-square)

Job de livraison intérimaire pour FiveM, ouvert à tous sans changer de métier : on charge le van au dépôt, on livre les colis porte à porte, seul ou en équipe, et on progresse sur 5 niveaux. Menu admin complet avec statistiques et événements « rush ».

## Fonctionnalités

- **Tournées** : 6 tournées (quartier, standard, express, gros volume, Blaine County, clients premium), débloquées par niveau. Caution du van prélevée au départ, rendue selon l'état du véhicule, prime si tout est livré.
- **Livraison réaliste** : chargement des colis un par un depuis la palette, colis porté à la main jusqu'à la porte, client présent ou absent, note de 1 à 5 étoiles et pourboires.
- **Types de colis** : standard, petit, fragile (abîmé par les chocs), lourd (pas de course), express (délai, +40 %), contre signature, paiement à la livraison (liquide à rapporter, commission), volumineux (à porter à deux).
- **Tournée en équipe** : le chef de tournée invite un collègue pendant le chargement. Un seul van, paie des colis partagée avec +15 %, XP complète pour chacun.
- **Preuve de dépôt** : client absent, il faut prendre le colis en photo devant la porte, sinon une étoile en moins.
- **Tri au dépôt** : mini-jeu facultatif avant le départ, chaque colis va dans le bac de son quartier. Bonus en cash et XP, tri parfait = prime de fin augmentée.
- **Nuit et météo** : de 22 h à 6 h et par mauvais temps (pluie, orage, neige), colis mieux payés. La nuit les clients ouvrent moins, sous la pluie les fragiles craignent plus les chocs.
- **Progression** : 5 niveaux avec multiplicateur de paie, prime de promotion, van amélioré, tenue exclusive et plaque personnalisée.
- **Missions** du jour et de la semaine, **succès** permanents (badges), **série** de jours consécutifs (+3 % par jour, max +15 %).
- **Satisfaction et clients premium** : moyenne des 50 dernières notes. À 4,5 ★, la tournée premium se débloque (paie x1,35, gros pourboires, clients exigeants).
- **Classement hebdomadaire** : top 3 récompensé automatiquement chaque lundi (versé à la connexion si le joueur est hors ligne).
- **HUD de tournée** : prochain arrêt, délais express, carnet de tournée dépliable (F7), argent encaissé, équipe, météo et événement en cours. Fiche de paie détaillée en fin de tournée.
- **Anti-abus** : vérifications côté serveur (distances, délais, van à proximité), plafond de gains par heure, van abandonné ou déplacé pendant le chargement = tournée échouée, alertes staff sur Discord.
- **Marque modifiable** : nom, logo, couleur et plaques (GoPostal par défaut, Amazon, DHL…). Véhicule et couleur réglables par tournée.

## Prérequis

Un framework parmi :

- [es_extended](https://github.com/esx-framework/esx-legacy) (ESX)
- [qb-core](https://github.com/qbcore-framework/qb-core) (QBCore)
- [qbx_core](https://github.com/Qbox-project/qbx_core) (Qbox)
- [ox_core](https://github.com/overextended/ox_core), avec [ox_inventory](https://github.com/overextended/ox_inventory) si `Config.Account = 'cash'`

Le framework est détecté automatiquement (ou forcé avec `Config.Framework`).

Intégrations optionnelles, utilisées si la ressource est lancée :

| Réglage | Ressources reconnues |
|---|---|
| `Config.Target` | ox_target, qb-target (sinon touche E) |
| `Config.Notify` | notifications du job, ox_lib, ESX, QBCore, okokNotify, ou fonction perso |
| `Config.Keys` | bl_key, qb-vehiclekeys, qbx_vehiclekeys, qs-vehiclekeys, Renewed-Vehiclekeys, wasabi_carlock, MrNewbVehicleKeys, cd_garage |
| `Config.Fuel` | LegacyFuel, ox_fuel, cdn-fuel, ps-fuel, lc_fuel, qs-fuelstations, okokGasStation, Renewed-Fuel |

## Installation

1. Placer le dossier `bl_gopostal` dans `resources/` (par exemple dans `resources/[JOB INTERIME]/`).
2. Ajouter dans `server.cfg` :
   ```cfg
   ensure bl_gopostal
   add_ace group.admin bl_gopostal.admin allow
   ```
3. Régler `config.lua` (marque, compte crédité, caution, tournées, paie, intégrations).
4. En jeu, avec `/postaladmin` > **Positions** : recaler le PNJ, les places de van (une par livreur simultané) et la zone de retour. Vérifier quelques adresses, les coordonnées par défaut sont approximatives.

### Accès au menu admin

Un joueur a accès à `/postaladmin` si une de ces sources le permet (`Config.Admin`) :

- la permission ace `bl_gopostal.admin` ;
- son groupe ESX (`owner`, `superadmin`, `admin` par défaut) ;
- une permission QBCore (`god`, `admin` par défaut) ;
- la permission `bl.gopostal` de `bl_admin` (ressource propre au serveur BloodLeak, non fournie).

## Commandes et touches

| Touche | Commande | Rôle |
|---|---|---|
| `E` | | Interagir (PNJ, palette, van, porte, photo, retour du van) |
| `G` | | Lancer le tri au dépôt, à la palette |
| `F7` | `/postalcarnet` | Déplier le carnet de tournée, fermer la fiche de fin de tournée |
| | `/postalannuler` | Abandonner sa tournée (caution perdue), ou quitter l'équipe |
| | `/postaladmin` | Menu admin |
| | `/postalpos` | (admin) Afficher sa position dans la console F8 |

F7 se change dans `config.lua` (`Config.Logbook.key`) ou dans les paramètres de touches FiveM du joueur. Les commandes se renomment en bas de `config.lua`.

## Menu admin

| Onglet | Contenu |
|---|---|
| **En cours** | Tournées actives, équipe, progression, gains. Aller voir ou annuler (caution rendue). |
| **Réglages** | Caution, paie, XP, chances de présence et de pourboire, délai entre deux tournées, plafond horaire, récompenses du classement, prime de nuit, seuil premium. Ouverture / fermeture du recrutement. |
| **Positions** | PNJ, places de van, zone de retour et adresses de livraison, placés à sa position en jeu. |
| **Livreurs** | Profils, réglage manuel du niveau, remise à zéro. |
| **Statistiques** | Sur 7, 14 ou 30 jours : argent distribué par jour, taux de réussite et d'échec, colis, livreurs actifs, durée moyenne, tournées les plus jouées, causes d'échec. |
| **Événement** | Rush (« Double paie », « Black Friday »…) : multiplicateurs de paie, d'XP et de colis pendant une durée donnée, annoncé à tous les joueurs. |
| **Historique** | Les dernières tournées et leur résultat. |

## Alertes Discord

`Config.Webhook` reçoit les fins de tournée et le classement de la semaine. `Config.Alerts` (webhook séparé possible, avec ping de rôle) prévient le staff en cas de :

- gains au-delà de `hourlyEarn` sur l'heure glissante ;
- liquide de paiement à la livraison non rendu (abandon, van détruit, déconnexion) ;
- déplacement trop rapide entre deux livraisons (téléportation probable) ;
- actions refusées à répétition par le serveur (events déclenchés à la main) ;
- van sorti du dépôt avant la fin du chargement.

Une alerte du même type pour un même joueur au plus toutes les 10 minutes (`throttle`).

## Personnalisation

### Changer de marque

```lua
Config.Brand = { name = 'Amazon', logo = 'a', color = '#ff9f1c', logoColor = '#1a1208', pole = 'Pôle intérimaire', plate = 'AMZ' }
```

Toute l'interface et les plaques suivent.

### Véhicules

- Chaque tournée a son véhicule (`vehicle` dans `Config.Tours`) et peut avoir son propre `style` (couleur, livrée, extras). Par défaut, la tournée Gros volume utilise un Benson marron, les autres le van GoPostal (`boxville2`).
- **Véhicule add-on** : mettre son nom de spawn dans `vehicle`.
- **Remplacement du `speedo`** : streamer les `.yft` / `.ytd` dans une ressource à part, puis mettre `speedo` dans `vehicle`. Cela remplace tous les Speedo du serveur.
- Style commun à tous les vans : `Config.VanStyle`.

## Données

Réglages, profils, historique, statistiques et événement en cours sont stockés dans `data/*.json`. Les profils sont rangés par identifiant de personnage (ESX : identifier, QBCore / Qbox : citizenid, ox_core : charId) : changer de framework repart de profils vierges.

## Licence

Utilisation gratuite sur ton serveur, modifications autorisées pour ton usage. Revente, réupload et retrait des crédits interdits. Détails dans [LICENSE](LICENSE).

Développé par **BloodLeak**.
