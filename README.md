<div align="center">
  <img src="https://img.shields.io/badge/FiveM-Script-orange?style=for-the-badge&logo=fivem&logoColor=white" />
  <img src="https://img.shields.io/badge/Framework-ESX%20%7C%20QBCore%20%7C%20Qbox%20%7C%20ox__core-blue?style=for-the-badge" />
  <img src="https://img.shields.io/badge/Author-BloodLeak-purple?style=for-the-badge" />
  <img src="https://img.shields.io/badge/License-BloodLeak-green?style=for-the-badge" />

  <h1>📦 Livreur GoPostal (bl_gopostal)</h1>
  <p><i>Job de livraison intérimaire complet, en solo ou en équipe, pour serveurs FiveM</i></p>
</div>

---

## 📖 À propos

**bl_gopostal** est un job de livraison du **pôle intérimaire** : ouvert à tous, sans changer de métier. Le joueur parle au responsable du dépôt, charge son van colis par colis, livre porte à porte et rend le van pour toucher sa prime.

Tournées en équipe, progression sur 5 niveaux, missions, succès, classement hebdomadaire et menu admin avec statistiques et événements « rush ». Compatible **ESX, QBCore, Qbox et ox_core**, avec détection automatique.

---

## ✨ Fonctionnalités Clés

### 🚚 Tournées & Livraison Réaliste
- **6 tournées** : quartier, standard, express, gros volume (camion Benson), Blaine County et clients premium, débloquées par niveau.
- **Caution du van** prélevée au départ, rendue selon l'état du véhicule. Prime de fin de tournée si tout est livré.
- **Chargement manuel** des colis depuis la palette, colis porté à la main jusqu'à la porte, client présent ou absent.
- **Note client de 1 à 5 étoiles** et pourboires. La paie dépend de la distance, du niveau et de la note.

### 📦 Types de Colis
- **Standard, petit, fragile** (abîmé par les chocs du van), **lourd** (impossible de courir), **express** (délai, +40 %).
- **Contre signature** : le client doit être là, sinon il faut repasser.
- **Paiement à la livraison** : le liquide est rapporté au dépôt, le livreur touche une commission.
- **Volumineux** : à porter à deux, l'aide est payée.

### 👥 Tournée en Équipe
- Pendant le chargement, le chef de tournée **invite un collègue** depuis le menu du responsable.
- Un seul van, colis partagés : paie de chaque colis **répartie à parts égales avec +15 %**, pourboire pour celui qui sonne, **XP complète** pour chacun.
- Un coéquipier quitte l'équipe sans pénalité. Si le chef se déconnecte, personne n'est pénalisé.

### 📸 Preuve de Dépôt & Tri au Dépôt
- **Client absent** : le colis est posé devant la porte et doit être **pris en photo** dans les 20 s, sinon une étoile en moins.
- **Tri au dépôt** : mini-jeu facultatif avant le départ, chaque colis va dans le bac de son quartier d'après le code de l'étiquette. Bonus en cash et XP, **tri parfait = prime de fin +10 %**.

### 🌙 Nuit, Météo & Événements
- **Nuit** (22 h – 6 h) : colis +25 % et XP +15 %, mais les clients ouvrent moins souvent.
- **Mauvais temps** (pluie, orage, neige) : colis mieux payés, fragiles plus sensibles aux chocs.
- **Rush** lancé par un admin (« Double paie », « Black Friday »…) : multiplicateurs de paie, d'XP et de colis, annoncés à tous les joueurs.

### 🏆 Progression & Récompenses
- **5 niveaux** avec multiplicateur de paie, prime de promotion, van amélioré, tenue exclusive et plaque personnalisée.
- **Missions** du jour et de la semaine, **succès** permanents (badges), **série de jours** consécutifs (+3 % par jour, max +15 %).
- **Satisfaction & clients premium** : à 4,5 ★ de moyenne, la tournée premium se débloque (paie x1,35, gros pourboires).
- **Classement hebdomadaire** : top 3 payé automatiquement chaque lundi, versé à la connexion si le joueur est hors ligne.

### 🗺️ HUD de Tournée
- Prochain arrêt, délais express, **carnet de tournée** dépliable (F7), liquide encaissé, équipe, météo et événement en cours.
- **Fiche de paie** détaillée en fin de tournée, fermable avec F7.

### 🛡️ Anti-Abus & Alertes Staff
- **Vérifications côté serveur** : distances, délais entre deux actions, van à proximité de l'adresse.
- **Plafond de gains par heure**. Van abandonné ou sorti du dépôt avant la fin du chargement = tournée échouée.
- **Alertes Discord** : gains anormaux, liquide non rendu, téléportation probable, events déclenchés à la main.

### 🔌 Intégrations Automatiques
- **Ciblage** : ox_target, qb-target (sinon touche E).
- **Notifications** : celles du job, ox_lib, ESX, QBCore, okokNotify ou fonction personnalisée.
- **Clés** : bl_key, qb-vehiclekeys, qbx_vehiclekeys, qs-vehiclekeys, Renewed-Vehiclekeys, wasabi_carlock, MrNewbVehicleKeys, cd_garage.
- **Carburant** : LegacyFuel, ox_fuel, cdn-fuel, ps-fuel, lc_fuel, qs-fuelstations, okokGasStation, Renewed-Fuel.

---

## 📋 Configuration (`config.lua`)

```lua
-- Marque entièrement modifiable (UI, plaques)
Config.Brand = { name = 'GoPostal', logo = 'GP', color = '#ffcc00', logoColor = '#1b2f7a', pole = 'Pôle intérimaire', plate = 'GOP' }

Config.Account = 'bank'      -- compte crédité et débité : 'bank' ou 'cash'
Config.Deposit = 500         -- caution du van
Config.Cooldown = 60         -- délai entre deux tournées (secondes)

Config.Target = 'auto'       -- 'auto', 'ox_target', 'qb-target' ou false
Config.Notify = 'nui'        -- 'nui', 'ox_lib', 'esx', 'qb', 'okok' ou 'custom'
Config.Keys = 'auto'         -- 'auto', false ou une liste de ressources

-- Chaque tournée a son véhicule et peut avoir son propre style
{
    id = 'volume', label = 'Gros volume', zone = 'ville',
    parcels = { min = 9, max = 12 }, level = 3, vehicle = 'benson', bonus = 1200,
    style = { color = { 96, 96 } }   -- camion marron
}
```

Pour passer en Amazon, DHL ou autre, il suffit de changer `Config.Brand` : toute l'interface et les plaques suivent.

---

## 🚀 Installation

1. Placez le dossier `bl_gopostal` dans votre répertoire de ressources (par exemple `resources/[JOB INTERIME]/`).
2. Ajoutez dans votre `server.cfg` :
   ```cfg
   ensure bl_gopostal
   add_ace group.admin bl_gopostal.admin allow
   ```
3. Réglez [config.lua](config.lua) : marque, compte, caution, tournées, paie et intégrations.
4. En jeu, ouvrez `/postaladmin` > **Positions** et recalez le PNJ, les places de van (une par livreur simultané) et la zone de retour. Vérifiez aussi quelques adresses : les coordonnées par défaut sont approximatives.

Avec ox_core et `Config.Account = 'cash'`, [ox_inventory](https://github.com/overextended/ox_inventory) est requis.

---

## 🎮 Commandes & Touches

| Commande / Touche | Type | Description |
| :--- | :--- | :--- |
| `E` | Touche | Interagir : PNJ, palette, van, porte, photo, retour du van |
| `G` | Touche | Lancer le tri au dépôt, à la palette |
| `F7` / `/postalcarnet` | Touche | Déplier le carnet de tournée, fermer la fiche de fin de tournée |
| `/postalannuler` | Commande | Abandonner sa tournée (caution perdue), ou quitter l'équipe |
| `/postaladmin` | Commande | Ouvrir le menu admin |
| `/postalpos` | Commande | (admin) Afficher sa position dans la console F8 |

---

## 🛠️ Menu Admin (`/postaladmin`)

| Onglet | Description |
| :--- | :--- |
| **En cours** | Tournées actives, équipe, progression et gains. Aller voir ou annuler (caution rendue). |
| **Réglages** | Caution, paie, XP, présence des clients, délais, plafond horaire, récompenses du classement. Ouverture / fermeture du recrutement. |
| **Positions** | PNJ, places de van, zone de retour et adresses, placés à votre position en jeu. |
| **Livreurs** | Profils, réglage manuel du niveau, remise à zéro. |
| **Statistiques** | Sur 7, 14 ou 30 jours : argent distribué, taux de réussite et d'échec, tournées les plus jouées, causes d'échec. |
| **Événement** | Lancer ou arrêter un rush, à partir de modèles ou de multiplicateurs personnalisés. |
| **Historique** | Les dernières tournées et leur résultat. |

Accès accordé par la permission ace `bl_gopostal.admin`, un groupe ESX, une permission QBCore ou `bl_admin` (voir `Config.Admin`).

Données (réglages, profils, historique, statistiques, événement en cours) stockées dans `data/*.json`.

---

## 📜 Licence

Utilisation gratuite sur votre serveur, modifications autorisées pour votre usage. Revente, réupload et retrait des crédits interdits. Détails dans [LICENSE](LICENSE).

---

<div align="center">
  <p><i>Développé avec passion par <b>BloodLeak</b>. Des designs haut de gamme et des performances optimisées pour votre communauté FiveM.</i></p>
</div>
