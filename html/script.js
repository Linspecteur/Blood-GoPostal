const $ = (id) => document.getElementById(id);
const resource = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'bl_gopostal';
const post = (name, data = {}) => fetch(`https://${resource}/${name}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json; charset=UTF-8' },
    body: JSON.stringify(data)
}).catch(() => {});

const money = (n) => Math.round(n || 0).toLocaleString('fr-FR').replace(/ | /g, ' ') + ' $';
const fmtTime = (s) => {
    const neg = s < 0;
    s = Math.abs(Math.ceil(s));
    return `${neg ? '-' : ''}${String(Math.floor(s / 60)).padStart(2, '0')}:${String(s % 60).padStart(2, '0')}`;
};
const fmtDist = (m) => m >= 1000 ? (m / 1000).toFixed(1).replace('.', ',') + ' km' : Math.round(m) + ' m';
const fmtNum = (n, d = 2) => Number(n).toFixed(d).replace('.', ',');
const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const stars = (n) => '★'.repeat(n) + `<span class="off">${'★'.repeat(5 - n)}</span>`;

// --- Marque (nom, logo, couleur) ---
let brand = { name: 'GoPostal', logo: 'GP', logoColor: '#1b2f7a', pole: 'Pôle intérimaire', color: '#ffcc00' };
function applyBrand(b) {
    if (!b) return;
    brand = { ...brand, ...b };
    const hex = /^#?([0-9a-f]{6})$/i.exec(brand.color || '');
    if (hex) {
        const n = parseInt(hex[1], 16);
        const rgb = `${(n >> 16) & 255}, ${(n >> 8) & 255}, ${n & 255}`;
        const root = document.documentElement.style;
        root.setProperty('--accent', '#' + hex[1]);
        root.setProperty('--accent-soft', `rgba(${rgb}, 0.14)`);
        root.setProperty('--accent-line', `rgba(${rgb}, 0.38)`);
    }
    $('m-brand').textContent = brand.name;
    $('m-pole').textContent = brand.pole;
    const logo = document.querySelector('.brand-logo');
    logo.textContent = brand.logo || brand.name.charAt(0);
    logo.classList.toggle('long', logo.textContent.length > 1);
    logo.style.color = brand.logoColor || '';
    document.querySelector('.adm-logo').textContent = (brand.logo || brand.name).slice(0, 3).toUpperCase();
    $('hud-kicker').textContent = `${brand.name} · Intérim`;
    document.querySelector('.adm-brand strong').textContent = brand.name;
}

// --- Notifications ---
const icon = (name, cls = '') => `<svg class="ic ${cls}"><use href="#i-${name}"/></svg>`;
const toastIcons = { info: 'info', success: 'check', warn: 'alert', error: 'alert' };

function toast(text, kind = 'info', ms = 5000) {
    const el = document.createElement('div');
    el.className = `toast ${kind}`;
    el.innerHTML = `<span class="toast-ic">${icon(toastIcons[kind] || 'info')}</span><span class="toast-text"></span>`;
    el.lastElementChild.textContent = text;
    $('toasts').appendChild(el);
    setTimeout(() => { el.classList.add('out'); setTimeout(() => el.remove(), 300); }, ms);
}

// --- Menu du dépôt ---
let menu = null;
let selected = null;
let tab = 'tours';

function showTab(t) {
    tab = t;
    document.querySelectorAll('.tab').forEach((b) => b.classList.toggle('active', b.dataset.tab === t));
    document.querySelectorAll('.pane').forEach((p) => { p.hidden = p.dataset.tab !== t; });
}
document.querySelectorAll('.tab').forEach((b) => b.addEventListener('click', () => showTab(b.dataset.tab)));

function warning(d) {
    if (d.active) return '';
    if (!d.enabled) return 'Le dépôt ne recrute pas pour le moment.';
    if (d.blocked) return 'Ton métier actuel ne te permet pas de faire de l\'intérim.';
    if (d.full) return 'Tous les vans sont sortis. Reviens dans quelques minutes.';
    if (d.cooldown > 0) return `Repose-toi un peu : prochaine tournée dans ${d.cooldown >= 60 ? Math.ceil(d.cooldown / 60) + ' min' : d.cooldown + ' s'}.`;
    return '';
}

const fmtMult = (n) => 'x' + fmtNum(n, n % 1 === 0 ? 0 : 2);
const fmtLeft = (s) => s >= 3600 ? `${Math.floor(s / 3600)} h ${String(Math.floor(s % 3600 / 60)).padStart(2, '0')}` : `${Math.max(1, Math.ceil(s / 60))} min`;

function rushText(r) {
    const parts = [];
    if (r.pay !== 1) parts.push(`paie ${fmtMult(r.pay)}`);
    if (r.xp !== 1) parts.push(`XP ${fmtMult(r.xp)}`);
    if (r.parcels !== 1) parts.push(`colis ${fmtMult(r.parcels)}`);
    return parts.join(' · ');
}

function renderRush(r) {
    $('rush-banner').hidden = !r;
    if (!r) return;
    $('rb-label').textContent = `Événement en cours · ${r.label}`;
    $('rb-text').textContent = rushText(r);
    $('rb-left').textContent = `encore ${fmtLeft(r.endsIn)}`;
}

function renderTeam(d) {
    // Invitation reçue (pas de tournée en cours)
    $('invite-box').hidden = !d.invite;
    if (d.invite) {
        $('ib-title').textContent = `${d.invite.from} t'invite dans son équipe`;
        $('ib-text').textContent = `${d.invite.tour} · paie des colis partagée${d.coop ? ` avec +${Math.round(d.coop.bonus * 100)} %` : ''}. La caution reste à sa charge.`;
    }
    const t = d.team;
    $('team-box').hidden = !t;
    if (!t) return;
    $('team-note').textContent = `${t.members.length} / ${t.max}`;
    $('team-members').innerHTML = t.members.map((n, i) => `<span class="member ${i === 0 ? 'lead' : ''}">${icon(i === 0 ? 'award' : 'users')}${esc(n)}${i === 0 ? '<i>chef</i>' : ''}</span>`).join('');
    if (t.canInvite) {
        const c = t.candidates || [];
        $('team-cands').innerHTML = c.length
            ? c.map((p) => `<div class="cand"><span>${esc(p.name)}</span><button class="btn ghost sm" data-invite="${p.id}" type="button">${icon('user-plus')}Inviter</button></div>`).join('')
            : '<div class="empty small">Aucun collègue à côté de toi. Il doit se tenir près de toi pour être invité.</div>';
    } else {
        $('team-cands').innerHTML = '';
    }
}

function renderTours(d) {
    renderRush(d.rush);
    renderTeam(d);
    $('tours-active').hidden = !d.active;
    if (d.active) {
        const member = d.active.owner === false;
        $('ta-kicker').textContent = member ? `Équipe de ${d.active.ownerName}` : 'Tournée en cours';
        $('ta-label').textContent = d.active.label;
        $('ta-progress').textContent = d.active.phase === 'loading'
            ? 'Chargement du van en cours'
            : `${d.active.delivered} / ${d.active.total} colis livrés`;
        $('ta-text').textContent = member
            ? 'Aide ton équipe à livrer les colis. Quitter l\'équipe est sans pénalité, les colis livrés restent payés.'
            : 'Termine ta tournée puis ramène le van dans la zone de retour du dépôt. Abandonner fait perdre la caution.';
    }
    $('tour-list').hidden = !!d.active;
    $('tour-list').innerHTML = d.tours.map((t) => {
        const facts = [
            `<span class="tag">${t.parcels.min === t.parcels.max ? t.parcels.min : t.parcels.min + '–' + t.parcels.max} colis</span>`,
            `<span class="tag">${esc(t.vehicleLabel || t.vehicle)}</span>`
        ];
        if (t.express >= 1) facts.push('<span class="tag express">100 % express</span>');
        else if (t.express > 0) facts.push('<span class="tag express">Express possibles</span>');
        if (t.heavy) facts.push('<span class="tag heavy">Colis lourds</span>');
        if (t.premium) facts.push(`<span class="tag">${icon('star')}Premium</span>`);
        if (t.locked && !t.levelOk) facts.push(`<span class="tag lock">${icon('lock')}Niveau ${t.level} · ${esc(t.levelTitle)}</span>`);
        else if (t.locked && t.premium) facts.push(`<span class="tag lock">${icon('lock')}Satisfaction ${fmtNum(d.premium.minRating, 1)} ★</span>`);
        const ic = t.express >= 1 ? 'zap' : t.heavy ? 'truck' : 'box';
        return `
            <button class="tour ${t.locked ? 'locked' : ''} ${selected === t.id ? 'selected' : ''}" data-id="${esc(t.id)}" type="button">
                <span class="tour-check">${icon('check')}</span>
                <div class="tour-top">
                    <span class="tour-ic ${t.express >= 1 ? 'express' : ''}">${icon(t.locked ? 'lock' : ic)}</span>
                    <div><strong>${esc(t.label)}</strong><span class="tour-zone">${icon('pin')}${esc(t.zone)}</span></div>
                </div>
                <p>${esc(t.desc)}</p>
                <div class="tour-facts">${facts.join('')}</div>
                <div class="tour-pay"><span>Gain estimé</span><b>${money(t.estimate.min)} <i>–</i> ${money(t.estimate.max)}</b></div>
            </button>`;
    }).join('');
}

function renderCareer(d) {
    const p = d.profile;
    $('m-lvl').textContent = `Niv. ${p.level} · ${p.title}`;
    $('c-level').textContent = p.level;
    $('c-title').textContent = p.title;
    $('c-mult').textContent = `Paie x${fmtNum(p.mult)}`;
    if (p.xpNext) {
        const pct = (p.xp - p.xpFrom) / (p.xpNext - p.xpFrom) * 100;
        $('c-xpbar').style.width = Math.max(0, Math.min(100, pct)) + '%';
        $('c-xp').textContent = `${p.xp} / ${p.xpNext} XP`;
        $('c-next').textContent = `${p.xpNext - p.xp} XP`;
    } else {
        $('c-xpbar').style.width = '100%';
        $('c-xp').textContent = `${p.xp} XP · niveau maximum`;
        $('c-next').textContent = 'Max';
    }
    $('c-delivered').textContent = p.delivered;
    $('c-tours').textContent = p.tours;
    $('c-earned').textContent = money(p.earned);
    $('c-rating').textContent = p.satisfaction ? fmtNum(p.satisfaction, 1) + ' ★' : '—';
    $('c-sat-label').textContent = p.premium ? 'Satisfaction · premium ✓' : 'Satisfaction';
    $('c-week').textContent = p.weekDelivered;
    $('c-week-earned').textContent = money(p.weekEarned);
    $('c-tips').textContent = money(p.tips);

    $('c-ladder').innerHTML = d.levels.map((l, i) => {
        const n = i + 1;
        const cls = n === p.level ? 'current' : n < p.level ? 'done' : '';
        const rewards = [];
        if (l.cash) rewards.push(`<span class="tag">Prime ${money(l.cash)}</span>`);
        if (l.van) rewards.push('<span class="tag">Van amélioré</span>');
        if (l.outfit && !(d.levels[i - 1] || {}).outfit) rewards.push('<span class="tag">Tenue exclusive</span>');
        if (l.plate && !(d.levels[i - 1] || {}).plate) rewards.push('<span class="tag">Plaque perso</span>');
        return `<div class="rung ${cls}"><span class="n">${n}</span><span>${esc(l.title)}${rewards.length ? `<span class="rung-rewards">${rewards.join('')}</span>` : ''}</span><span class="x">${l.xp} XP</span><span class="m">x${fmtNum(l.mult)}</span></div>`;
    }).join('');

    const perks = p.perks || {};
    $('c-plate-box').hidden = !perks.plate;
    if (perks.plate && document.activeElement !== $('c-plate')) $('c-plate').value = p.plate || '';

    // Série de jours
    const s = p.streak;
    $('c-streak').hidden = !(d.streak && s);
    if (d.streak && s) {
        $('cs-title').textContent = s.days > 0 ? `Série de ${s.days} jour${s.days > 1 ? 's' : ''}` : 'Pas de série en cours';
        $('cs-text').textContent = s.validated
            ? `Journée validée. Reviens demain pour la prolonger.${s.best > 1 ? ` Record : ${s.best} jours.` : ''}`
            : `${Math.min(s.today, d.streak.minParcels)} / ${d.streak.minParcels} colis aujourd'hui pour valider la journée.${s.best > 1 ? ` Record : ${s.best} jours.` : ''}`;
        $('cs-bonus').textContent = `+${Math.round(s.bonus * 100)} %`;
    }

    // Succès
    const ach = d.achievements || [];
    $('c-ach-count').textContent = `${ach.filter((a) => a.done).length} / ${ach.length}`;
    $('c-badges').innerHTML = ach.map((a) => {
        const pct = Math.min(100, a.progress / a.goal * 100);
        const reward = [a.cash ? money(a.cash) : '', a.xp ? `+${a.xp} XP` : ''].filter(Boolean).join(' · ');
        return `
            <div class="badge-card ${a.done ? 'done' : ''}">
                <span class="badge-ic">${icon(a.done ? 'award' : 'lock')}</span>
                <div>
                    <b>${esc(a.label)}</b>
                    <span>${esc(a.desc || '')}</span>
                    ${a.done ? `<span class="badge-reward">Débloqué · ${reward}</span>`
                        : `<div class="xpbar"><i style="width:${pct}%"></i></div><span class="badge-reward mono">${a.goal >= 1000 ? money(a.progress) + ' / ' + money(a.goal) : a.progress + ' / ' + a.goal} · ${reward}</span>`}
                </div>
            </div>`;
    }).join('');
}

function renderMissions(d) {
    const row = (m) => {
        const pct = Math.min(100, m.progress / m.goal * 100);
        const amount = m.goal >= 1000 ? `${money(m.progress)} / ${money(m.goal)}` : `${m.progress} / ${m.goal}`;
        return `
            <div class="mission ${m.done ? 'done' : ''}">
                <div class="mission-top"><b>${esc(m.label)}</b><span class="mono">${m.done ? 'Terminée ✓' : amount}</span></div>
                <div class="xpbar"><i style="width:${pct}%"></i></div>
                <span class="mission-reward">${money(m.cash)} · +${m.xp} XP</span>
            </div>`;
    };
    const mi = d.missions || { daily: [], weekly: [] };
    $('mi-daily').innerHTML = mi.daily.map(row).join('') || '<div class="empty">Aucune mission aujourd\'hui.</div>';
    $('mi-weekly').innerHTML = mi.weekly.map(row).join('') || '<div class="empty">Aucune mission cette semaine.</div>';
}

function renderRanking(d) {
    const rewards = (d.weeklyRewards || []).slice(0, 3);
    $('rank-rewards').hidden = !rewards.some((r) => r > 0);
    $('rank-rewards').innerHTML = rewards.map((r, i) => r > 0
        ? `<div class="podium-step p${i + 1}"><span>${i + 1}${i ? 'e' : 'er'}</span><b>${money(r)}</b></div>` : '').join('');
    const rows = d.leaderboard || [];
    $('rank-list').innerHTML = rows.length ? rows.map((r, i) => `
        <div class="rank-row ${r.me ? 'me' : ''}">
            <span class="pos">${i + 1}</span>
            <span>${esc(r.name)}${r.me ? ' <span class="tag">toi</span>' : ''}</span>
            <span class="num">${r.delivered} colis</span>
            <span class="num money">${money(r.earned)}</span>
        </div>`).join('') : '<div class="empty">Personne n\'a encore livré cette semaine. La première place est à prendre.</div>';
}

function renderInfos(d) {
    $('i-express').textContent = `+${Math.round(d.express.bonus * 100)} %`;
    if (d.cod) $('i-cod').textContent = `${Math.round(d.cod.commission * 100)} %`;
    if (d.bulky) $('i-bulky').textContent = `${Math.round(d.bulky.helperPay * 100)} %`;
    $('i-night').hidden = !d.night;
    if (d.night) {
        $('i-night').innerHTML = `<b>Nuit</b> (${d.night.from} h – ${d.night.to} h) : colis payés +${Math.round(d.night.payBonus * 100)} % et plus d'XP, mais les clients ouvrent moins souvent.`;
    }
    const rule = (id, html) => { $(id).hidden = !html; if (html) $(id).innerHTML = html; };
    rule('i-photo', d.photo && `<b>Client absent</b> : pose le colis devant la porte puis prends-le en photo dans les ${d.photo.window} s. Sans photo, le client retire ${d.photo.penalty} étoile${d.photo.penalty > 1 ? 's' : ''}.`);
    rule('i-coop', d.coop && `<b>En équipe</b> : pendant le chargement, invite un collègue depuis ce menu (${d.coop.max} livreurs par van). La paie des colis est partagée avec +${Math.round(d.coop.bonus * 100)} %, chacun gagne l'XP complète.`);
    rule('i-sort', d.sorting && `<b>Tri au dépôt</b> : avant de charger, trie les colis à la palette. ${money(d.sorting.cash)} par colis bien rangé, et un tri parfait augmente la prime de fin de tournée de ${Math.round(d.sorting.perfect * 100)} %.`);
    rule('i-weather', d.weather && `<b>Mauvais temps</b> : ${d.weather.map((w) => `${esc(w.label.toLowerCase())} +${Math.round(w.pay * 100)} %`).join(', ')} sur les colis. Les fragiles craignent davantage les chocs.`);
    rule('i-streak', d.streak && `<b>Série</b> : livre au moins ${d.streak.minParcels} colis par jour, plusieurs jours d'affilée. +${Math.round(d.streak.perDay * 100)} % de paie par jour de série (max +${Math.round(d.streak.max * 100)} %). Un jour sauté remet la série à zéro.`);
    $('i-premium').innerHTML =`<b>Clients premium</b> : réservés aux livreurs à ${fmtNum(d.premium.minRating, 1)} ★ de satisfaction ou plus (sur tes ${d.premium.window} dernières notes, ${d.premium.minRatings} minimum). Paie x${fmtNum(d.premium.payMult)} et gros pourboires, mais chaque défaut coûte une étoile de plus.`;
    $('i-cap').hidden = !(d.cap && d.cap.perHour > 0);
    if (d.cap && d.cap.perHour > 0) {
        $('i-cap').textContent = `Au-delà de ${money(d.cap.perHour)} gagnés en une heure, la paie des colis passe à ${Math.round(d.cap.overRate * 100)} %.`;
    }
    $('parcel-table').innerHTML = d.parcels.map((p) => {
        const tag = p.express ? '<span class="tag express">délai</span>'
            : p.bulky ? '<span class="tag heavy">à deux</span>'
            : p.heavy ? '<span class="tag heavy">pas de course</span>'
            : p.signature ? '<span class="tag special">client présent</span>'
            : p.cod ? '<span class="tag special">liquide à rapporter</span>'
            : p.fragile ? '<span class="tag fragile">attention aux chocs</span>' : '';
        return `<div><span class="left">${esc(p.label)} ${tag}</span><span class="mono">dès ${money(p.pay)}</span></div>`;
    }).join('');
}

function updateFooter() {
    const d = menu;
    const warn = warning(d);
    const t = d.tours.find((x) => x.id === selected);
    $('menu-warn').hidden = !warn;
    $('menu-warn').textContent = warn;
    $('outfit-row').hidden = !d.outfit || !!d.active;
    const member = d.active && d.active.owner === false;
    $('btn-cancel').dataset.label = member ? 'Quitter l\'équipe' : 'Abandonner la tournée';
    $('btn-cancel').dataset.confirm = member ? 'Confirmer' : 'Confirmer (caution perdue)';
    if (!$('btn-cancel').dataset.armed) $('btn-cancel').textContent = $('btn-cancel').dataset.label;
    const excl = !!(d.exclusiveOutfit && d.profile.perks && d.profile.perks.outfit);
    $('opt-outfit-excl').hidden = !excl;
    $('opt-outfit-excl').disabled = !excl;
    if (excl) $('opt-outfit-excl').textContent = d.exclusiveOutfit;
    if (!excl && $('opt-outfit').value === 'exclusive') $('opt-outfit').value = 'standard';
    $('m-deposit').hidden = !!d.active;
    $('m-deposit').textContent = d.deposit > 0 ? `Caution du van : ${money(d.deposit)}` : 'Pas de caution';
    $('m-night').hidden = !(d.night && d.night.active) || !!d.active;
    if (d.night) $('m-night').textContent = `Nuit en cours : colis +${Math.round(d.night.payBonus * 100)} %`;
    $('btn-cancel').hidden = !d.active;
    $('btn-start').hidden = !!d.active;
    $('btn-start').disabled = !!warn || !t || t.locked;
    $('btn-start').textContent = t ? 'Commencer la tournée' : 'Choisis une tournée';
}

function openMenu(d) {
    menu = d;
    applyBrand(d.brand);
    $('npc-name').textContent = d.npcName || 'Responsable du dépôt';
    if (!d.tours.some((t) => t.id === selected && !t.locked)) {
        const first = d.tours.find((t) => !t.locked);
        selected = first ? first.id : null;
    }
    renderTours(d);
    renderMissions(d);
    renderCareer(d);
    renderRanking(d);
    renderInfos(d);
    updateFooter();
    showTab(d.active ? 'tours' : tab);
    $('menu').hidden = false;
}
function closeMenu() { $('menu').hidden = true; }

$('tour-list').addEventListener('click', (e) => {
    const b = e.target.closest('.tour');
    if (!b || b.classList.contains('locked')) return;
    selected = b.dataset.id;
    document.querySelectorAll('.tour').forEach((x) => x.classList.toggle('selected', x === b));
    updateFooter();
});
$('btn-close').addEventListener('click', () => post('close'));
$('btn-start').addEventListener('click', () => {
    if ($('btn-start').disabled || !selected) return;
    post('start', { tourId: selected, outfit: $('opt-outfit').value });
});
$('c-plate').addEventListener('input', (e) => {
    e.target.value = e.target.value.toUpperCase().replace(/[^A-Z0-9 ]/g, '').slice(0, 8);
});
$('c-plate-save').addEventListener('click', () => {
    post('setPlate', { plate: $('c-plate').value.trim() });
    if (menu) menu.profile.plate = $('c-plate').value.trim();
});
$('btn-cancel').addEventListener('click', () => {
    const b = $('btn-cancel');
    if (b.dataset.armed) { post('cancelTour'); return; }
    b.dataset.armed = '1';
    b.classList.add('confirm');
    b.textContent = b.dataset.confirm || 'Confirmer (caution perdue)';
    setTimeout(() => { delete b.dataset.armed; b.classList.remove('confirm'); b.textContent = b.dataset.label || 'Abandonner la tournée'; }, 3000);
});
$('team-cands').addEventListener('click', (e) => {
    const b = e.target.closest('[data-invite]');
    if (!b || b.disabled) return;
    post('invite', { id: Number(b.dataset.invite) });
    b.disabled = true;
    b.textContent = 'Invité';
});
$('ib-accept').addEventListener('click', () => post('inviteAnswer', { accept: true, outfit: $('opt-outfit').value }));
$('ib-decline').addEventListener('click', () => post('inviteAnswer', { accept: false }));
window.addEventListener('keydown', (e) => {
    if (e.key === 'Escape' && !$('menu').hidden) post('close');
});

// --- HUD ---
const phases = { loading: 'Chargement', delivering: 'Livraisons', return: 'Retour' };
const shortType = { express: 'express', fragile: 'fragile', heavy: 'lourd', bulky: 'à deux', signature: 'signature', cod: 'paiement', small: 'petit' };

// Une ligne du carnet (même style qu'avant) : délai express, attente avant de repasser ou distance.
// Déplié, le type du colis est ajouté devant.
function stopRow(s, open) {
    const timed = s.remaining !== null && s.remaining !== undefined;
    let right = fmtDist(s.distance);
    if (s.delivered) right = 'livré';
    else if (s.photo !== null && s.photo !== undefined) right = `photo ${fmtTime(s.photo)}`;
    else if (s.waiting) right = 'photo en cours';
    else if (s.retry) right = `repasser ${fmtTime(s.retry)}`;
    else if (timed) right = fmtTime(s.remaining);
    if (open && !s.delivered && shortType[s.type]) right = `${shortType[s.type]} · ${right}`;
    return `<li class="${s.delivered ? 'done' : ''} ${s.current && !s.delivered ? 'current' : ''} ${s.type === 'express' ? 'express' : ''}">
                <i></i><span>${esc(s.label)}</span><span class="mono">${right}</span>
            </li>`;
}

function hud(d) {
    $('hud').hidden = false;
    $('hud-phase').textContent = [phases[d.phase] || '', d.premium ? 'Premium' : '', d.night ? 'Nuit' : '', d.weather || ''].filter(Boolean).join(' · ');
    const chips = [];
    if (d.rush) chips.push(`<span class="chip rush">${icon('zap')}${esc(d.rush.label)} · ${fmtTime(d.rush.left)}</span>`);
    if (d.team) chips.push(`<span class="chip">${icon('users')}${d.team.map(esc).join(', ')}</span>`);
    $('hud-chips').hidden = !chips.length;
    $('hud-chips').innerHTML = chips.join('');
    $('hl-sort').hidden = !(d.phase === 'loading' && d.canSort);
    const photo = (d.stops || []).find((s) => s.photo !== null && s.photo !== undefined && !s.delivered);
    $('hud-photo').hidden = !photo;
    if (photo) $('hud-photo').textContent = `Prends le colis en photo devant la porte · ${Math.ceil(photo.photo)} s`;
    const order = ['loading', 'delivering', 'return'];
    const at = order.indexOf(d.phase);
    document.querySelectorAll('#hud-steps i').forEach((el, i) => {
        el.className = i < at ? 'done' : i === at ? 'on' : '';
    });
    $('hud-loading').hidden = d.phase !== 'loading';
    $('hud-delivering').hidden = d.phase !== 'delivering';
    $('hud-return').hidden = d.phase !== 'return';

    if (d.phase === 'loading') {
        $('hl-count').textContent = d.loaded;
        $('hl-total').textContent = `/ ${d.total}`;
        $('hl-bar').style.width = (d.total ? d.loaded / d.total * 100 : 0) + '%';
    } else if (d.phase === 'delivering') {
        const pending = d.stops.filter((s) => !s.delivered).sort((a, b) => (b.current - a.current) || (a.distance - b.distance));
        const done = d.stops.filter((s) => s.delivered);
        const cur = pending[0];
        if (cur) {
            $('hd-addr').textContent = cur.label;
            $('hd-type').textContent = cur.typeLabel;
            $('hd-type').className = 'tag ' + ({ express: 'express', heavy: 'heavy', bulky: 'heavy', fragile: 'fragile', signature: 'special', cod: 'special' }[cur.type] || '');
            $('hd-dist').textContent = fmtDist(cur.distance);
        }
        // délai express le plus urgent
        const urgent = pending.filter((s) => s.remaining !== null && s.remaining !== undefined).sort((a, b) => a.remaining - b.remaining)[0];
        $('hd-express').hidden = !urgent;
        if (urgent) {
            $('hd-timer').textContent = fmtTime(urgent.remaining);
            $('hd-express').className = 'express' + (urgent.remaining < 0 ? ' late' : urgent.remaining <= 45 ? ' low' : '');
            $('hd-express').firstElementChild.textContent = urgent.remaining < 0 ? `En retard · ${urgent.label}` : `Express · ${urgent.label}`;
        }
        // Carnet de tournée : replié = les prochains arrêts, déplié = tout, avec l'état de chaque colis
        const lb = d.logbook || { open: false, compact: 7, key: 'F7' };
        const list = [...pending, ...done];
        const shown = lb.open ? list : list.slice(0, lb.compact);
        $('hud').classList.toggle('logbook', lb.open);
        const key = esc(lb.key);
        const foot = lb.open
            ? `<li class="more">${done.length} livré${done.length > 1 ? 's' : ''} · ${pending.length} à faire · ${key} pour replier</li>`
            : list.length > shown.length ? `<li class="more">+ ${list.length - shown.length} autres arrêts · ${key} carnet complet</li>`
            : `<li class="more">${key} carnet complet</li>`;
        $('hd-stops').innerHTML = shown.map((s) => stopRow(s, lb.open)).join('') + foot;
    } else if (d.phase === 'return') {
        $('hr-dist').textContent = fmtDist(d.returnDistance);
    }

    $('hud-carry').hidden = !d.carrying;
    if (d.carrying) $('hud-carry').textContent = `En main : ${d.carrying.label}${d.carrying.heavy ? ' · impossible de courir' : ''}`;
    $('hud-vanfar').hidden = !d.vanFar;
    $('hud-cod').hidden = !(d.codCash > 0);
    if (d.codCash > 0) $('hud-cod').textContent = `Liquide à remettre au dépôt : ${money(d.codCash)}`;
    $('hf-done').textContent = `${d.delivered}/${d.total}`;
    $('hf-earned').textContent = money(d.earned);
    $('hf-rating').textContent = d.rating ? fmtNum(d.rating, 1) + ' ★' : '—';
}

// --- File des cartes ---
// Colis livré, promotion, mission et succès s'affichent au même endroit : une seule carte à la fois.
// Le colis livré passe en premier (urgent) ; les autres attendent qu'il disparaisse.
const cards = { queue: [], current: null, timer: null };

function cardNext() {
    cards.current = cards.queue.shift() || null;
    if (!cards.current) return;
    const c = cards.current;
    c.show();
    cards.timer = setTimeout(() => { $(c.el).hidden = true; cardNext(); }, c.ms);
}

function card(c, urgent) {
    if (urgent) {
        // Une carte déjà affichée est remise en tête de file et repassera juste après
        if (cards.current) {
            clearTimeout(cards.timer);
            $(cards.current.el).hidden = true;
            cards.queue.unshift(cards.current);
            cards.current = null;
        }
        cards.queue.unshift(c);
    } else {
        cards.queue.push(c);
    }
    if (!cards.current) cardNext();
}

// Le serveur envoie souvent le succès juste avant le colis livré : petit délai pour laisser passer le colis d'abord
const cardLater = (c) => setTimeout(() => card(c), 300);

function cardsDrop(el) {
    cards.queue = cards.queue.filter((c) => c.el !== el);
    if (cards.current && cards.current.el === el) {
        clearTimeout(cards.timer);
        $(el).hidden = true;
        cardNext();
    }
}

// --- Colis livré ---
function delivered(d) {
    card({ el: 'pop', ms: 4500, show: () => showDelivered(d) }, true);
}

function showDelivered(d) {
    $('pop-kicker').textContent = d.by ? `Livré par ${d.by}`
        : d.signature ? 'Remis contre signature'
        : d.cod ? `Payé à la livraison · ${money(d.cod)} encaissés`
        : d.present ? 'Colis remis en main propre'
        : d.photo ? 'Client absent · dépôt photographié' : 'Client absent · déposé devant la porte';
    $('pop-pay').textContent = '+ ' + money(d.pay + d.tip);
    $('pop-stars').innerHTML = stars(d.stars);
    $('pop').classList.toggle('bad', d.stars <= 2);
    const parts = [];
    if (d.tip > 0) parts.push(`dont ${money(d.tip)} de pourboire`);
    if (d.team) parts.push('ta part de l\'équipe');
    if (d.helped) parts.push('porté à deux');
    if (d.premium) parts.push('client premium');
    if (d.night) parts.push('prime de nuit');
    if (d.weather) parts.push(`prime ${d.weather.toLowerCase()}`);
    if (d.rush) parts.push(d.rush);
    if (d.streak > 0) parts.push(`série +${Math.round(d.streak * 100)} %`);
    if (d.capped) parts.push('paie réduite (plafond horaire)');
    if (d.notes && d.notes.length) parts.push(d.notes.join(', '));
    parts.push(`+${d.xp} XP`);
    parts.push(d.remaining > 0 ? `${d.remaining} colis restant${d.remaining > 1 ? 's' : ''}` : 'tournée terminée');
    $('pop-text').textContent = parts.join(' · ');
    $('pop').hidden = false;
}

function showLevelCard(kicker, iconId, title, text) {
    $('levelup').querySelector('.kicker').textContent = kicker;
    $('lu-icon').setAttribute('href', iconId);
    $('lu-title').textContent = title;
    $('lu-text').textContent = text;
    // Relance l'animation d'entrée quand deux cartes se suivent
    const el = $('levelup');
    el.hidden = true;
    void el.offsetWidth;
    el.hidden = false;
}

function levelUp(d) {
    cardLater({ el: 'levelup', ms: 5000, show: () => showLevelCard('Promotion', '#i-award', `Niveau ${d.level} · ${d.title}`,
        `Ta paie passe à x${fmtNum(d.mult)}. De nouvelles tournées peuvent être débloquées.`) });
}

function missionDone(d) {
    const reward = [d.cash ? `+ ${money(d.cash)}` : '', d.xp ? `+${d.xp} XP` : ''].filter(Boolean).join(' · ');
    cardLater({ el: 'levelup', ms: 5000, show: () => showLevelCard(d.achievement ? 'Succès débloqué' : `${d.kind} terminée`,
        d.achievement ? '#i-award' : '#i-target', d.label, reward) });
}

// --- Fiche de fin de tournée ---
const endTitles = {
    success: 'Tournée réussie',
    partial: 'Tournée écourtée',
    cancel: 'Tournée abandonnée'
};
const failReasons = {
    moved: 'Le van a quitté le dépôt sans être chargé. Caution perdue.',
    destroyed: 'Le van est détruit. Caution perdue.',
    spawn: 'Le van n\'a pas pu être sorti. Caution rendue, préviens un admin.',
    cancel: 'Tu as abandonné la tournée. Caution perdue.',
    abandoned: 'Tu as laissé ton van trop longtemps. Tournée annulée, caution perdue.',
    admin: 'Un admin a annulé ta tournée. Caution rendue.',
    leftTeam: 'Tu as quitté l\'équipe. Les colis livrés restent payés.',
    ownerLeft: 'Le chef de tournée s\'est déconnecté. Les colis livrés restent payés.'
};
let psTimer = null;
function showPayslip(s) {
    $('hud').hidden = true;
    cardsDrop('pop');
    const ok = s.result === 'success' || s.result === 'partial';
    const box = $('payslip');
    box.className = `payslip ${s.result === 'success' ? 'success' : ok ? '' : 'fail'}`;
    $('ps-kicker').textContent = `${s.tour} · fiche de fin de tournée`;
    $('ps-title').textContent = s.reason === 'leftTeam' ? 'Équipe quittée' : (endTitles[s.result] || 'Tournée échouée');
    $('ps-sub').textContent = s.result === 'success' ? 'Tous les colis sont livrés et le van est rendu. Beau travail.'
        : s.result === 'partial' ? 'Van rendu avant la fin : pas de prime de tournée.'
        : (failReasons[s.reason] || 'Tournée terminée.');

    const lines = [
        ['Colis livrés', `${s.delivered} / ${s.total}`]
    ];
    if (s.team) lines.push([`En équipe · ${s.team.map(esc).join(', ')}`, `${s.mine} livré${s.mine > 1 ? 's' : ''} par toi`]);
    lines.push([s.team ? 'Ta part de la paie des colis' : 'Paie des colis', '+ ' + money(s.earned)]);
    if (s.tips > 0) lines.push(['Pourboires', '+ ' + money(s.tips)]);
    if (s.sortCash > 0) lines.push(['Tri au dépôt', '+ ' + money(s.sortCash)]);
    if (s.bonus > 0) lines.push(['Prime de fin de tournée', '+ ' + money(s.bonus)]);
    if (s.codRemitted > 0) lines.push([`Commission sur ${money(s.codRemitted)} encaissés`, '+ ' + money(s.codCommission)]);
    if (s.codLost > 0) lines.push(['Liquide non remis au dépôt', '− ' + money(s.codLost), 'neg']);
    if (s.capped) lines.push(['Plafond horaire atteint', 'paie réduite']);
    if (s.deposit > 0) {
        lines.push(['Caution prélevée', '− ' + money(s.deposit), 'neg']);
        lines.push(['Caution rendue', '+ ' + money(s.refund)]);
    }
    lines.push(['Durée', fmtTime(s.duration)]);
    $('ps-lines').innerHTML = lines.map(([k, v, c]) => `<div><dt>${k}</dt><dd class="${c || ''}">${v}</dd></div>`).join('');

    const net = s.earned + s.tips + s.bonus + (s.sortCash || 0) + s.refund + (s.codCommission || 0) - (s.codLost || 0) - s.deposit;
    $('ps-total').textContent = (net < 0 ? '− ' : '') + money(Math.abs(net));
    $('ps-total').style.color = net < 0 ? '#ff6b7f' : '';
    document.querySelector('.ps-total span').textContent = 'Gain net';

    const p = s.profile;
    if (p && s.xp > 0) {
        const pct = p.xpNext ? (p.xp - p.xpFrom) / (p.xpNext - p.xpFrom) * 100 : 100;
        $('ps-xp').innerHTML = `+${s.xp} XP · ${esc(p.title)} (niveau ${p.level})${p.xpNext ? ` · ${p.xpNext - p.xp} XP avant le prochain niveau` : ''}
            <div class="xpbar"><i style="width:${Math.max(0, Math.min(100, pct))}%"></i></div>`;
        $('ps-xp').hidden = false;
    } else {
        $('ps-xp').hidden = true;
    }
    $('ps-key').textContent = s.closeKey || 'F7';
    box.hidden = false;
    clearTimeout(psTimer);
    psTimer = setTimeout(() => { box.hidden = true; }, 12000);
}

function closePayslip() {
    clearTimeout(psTimer);
    $('payslip').hidden = true;
}

// --- Tri au dépôt ---
// Un colis à la fois : son étiquette porte le code du quartier, il faut cliquer le bac correspondant.
const sortGame = { items: [], bins: [], i: 0, correct: 0, endsAt: 0, total: 0, timer: null, locked: false, open: false };

function sortShowItem() {
    const it = sortGame.items[sortGame.i];
    $('so-count').textContent = `Colis ${sortGame.i + 1} / ${sortGame.items.length}`;
    $('so-code').textContent = it.code;
    $('so-street').textContent = it.street;
    $('so-type').textContent = it.type;
    const card = $('so-parcel');
    card.classList.remove('in');
    void card.offsetWidth;
    card.classList.add('in');
}

function sortFinish() {
    if (!sortGame.open) return;
    sortGame.open = false;
    clearInterval(sortGame.timer);
    post('sortDone', { correct: sortGame.correct });
}

function sortChoose(idx) {
    if (!sortGame.open || sortGame.locked || idx < 0 || idx >= sortGame.bins.length) return;
    const it = sortGame.items[sortGame.i];
    const ok = sortGame.bins[idx] === it.bin;
    if (ok) sortGame.correct++;
    const bin = $('so-bins').children[idx];
    bin.classList.add(ok ? 'ok' : 'ko');
    // Mauvais bac : on montre le bon
    if (!ok) {
        const good = sortGame.bins.indexOf(it.bin);
        if (good >= 0) $('so-bins').children[good].classList.add('hint');
    }
    $('so-score').textContent = `${sortGame.correct} bien rangé${sortGame.correct > 1 ? 's' : ''}`;
    sortGame.locked = true;
    setTimeout(() => {
        [...$('so-bins').children].forEach((b) => b.classList.remove('ok', 'ko', 'hint'));
        sortGame.locked = false;
        sortGame.i++;
        if (sortGame.i >= sortGame.items.length) sortFinish();
        else sortShowItem();
    }, ok ? 400 : 750);
}

function openSort(d) {
    Object.assign(sortGame, { items: d.items, bins: d.bins, i: 0, correct: 0, locked: false, open: true,
        total: d.timeLimit, endsAt: Date.now() + d.timeLimit * 1000 });
    $('so-sub').textContent = `Le code du quartier est imprimé sur l'étiquette. ${money(d.cash)} par colis bien rangé, tri parfait : prime de fin +${Math.round(d.perfect * 100)} %.`;
    $('so-bins').innerHTML = d.bins.map((b, i) => `<button class="bin" type="button" data-bin="${i}"><kbd>${i + 1}</kbd><span>${esc(b)}</span></button>`).join('');
    $('so-maxkey').textContent = Math.min(9, d.bins.length);
    $('so-score').textContent = '0 bien rangé';
    sortShowItem();
    $('sort').hidden = false;
    clearInterval(sortGame.timer);
    sortGame.timer = setInterval(() => {
        const left = (sortGame.endsAt - Date.now()) / 1000;
        $('so-timer').textContent = fmtTime(Math.max(0, left));
        $('so-bar').style.width = Math.max(0, left / sortGame.total * 100) + '%';
        $('sort').classList.toggle('low', left <= 8);
        if (left <= 0) sortFinish();
    }, 100);
}

function closeSort() {
    sortGame.open = false;
    clearInterval(sortGame.timer);
    $('sort').hidden = true;
}

$('so-bins').addEventListener('click', (e) => {
    const b = e.target.closest('[data-bin]');
    if (b) sortChoose(Number(b.dataset.bin));
});
$('so-quit').addEventListener('click', () => { if (sortGame.open) { sortGame.open = false; clearInterval(sortGame.timer); post('sortCancel'); } });
window.addEventListener('keydown', (e) => {
    if (!sortGame.open) return;
    if (e.key === 'Escape') { $('so-quit').click(); return; }
    const n = Number(e.key);
    if (n >= 1 && n <= 9) sortChoose(n - 1);
});

// --- Messages du jeu ---
window.addEventListener('message', (e) => {
    const m = e.data || {};
    switch (m.action) {
        case 'brand': applyBrand(m.data); break;
        case 'sort': openSort(m.data); break;
        case 'sortClose': closeSort(); break;
        case 'rush': if (menu) { menu.rush = m.data; renderRush(m.data); } break;
        case 'menu': openMenu(m.data); break;
        case 'closeMenu': closeMenu(); break;
        case 'hud': $('payslip').hidden = true; hud(m.data); break;
        case 'delivered': delivered(m.data); break;
        case 'levelUp': levelUp(m.data); break;
        case 'mission': missionDone(m.data); break;
        case 'end': showPayslip(m.data); break;
        case 'closePayslip': closePayslip(); break;
        case 'toast': toast(m.text, m.kind); break;
    }
});
