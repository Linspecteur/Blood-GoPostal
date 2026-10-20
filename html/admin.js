// Menu admin du job (réutilise $, post, money, toast, fmtTime, esc de script.js)
(() => {
    const adm = $('adm');
    let data = null;
    let tab = 'live';
    let zoneFilter = 'all';
    let settingsDirty = false;
    let zonesFilled = false;
    let statsDays = 7;
    let presetsFilled = false;
    const levelPick = {};   // niveau choisi dans la liste des livreurs (conservé entre deux rafraîchissements)

    const coord = (c) => c ? `${c.x.toFixed(1)}, ${c.y.toFixed(1)}, ${c.z.toFixed(1)}${c.w !== undefined && c.w !== null ? ', ' + c.w.toFixed(1) : ''}` : '—';
    const action = (name, payload = {}) => post('adminAction', { name, payload });
    const phaseLabel = { loading: 'Chargement', delivering: 'Livraisons', return: 'Retour' };
    const resultLabel = { success: 'Complète', partial: 'Écourtée', cancel: 'Abandon', fail: 'Échec' };
    const reasons = { destroyed: 'Van détruit', left: 'Déconnexion', spawn: 'Erreur van', admin: 'Annulée (admin)', cancel: 'Abandon', abandoned: 'Van abandonné', moved: 'Parti sans charger', leftTeam: 'Équipe quittée', ownerLeft: 'Chef déconnecté' };
    const pct = (a, b) => b ? Math.round(a / b * 100) + ' %' : '—';
    const dayLabel = (key) => { const [, m, d] = key.split('-'); return `${d}/${m}`; };
    const fmtDate = (t) => {
        const d = new Date(t * 1000);
        return `${String(d.getDate()).padStart(2, '0')}/${String(d.getMonth() + 1).padStart(2, '0')} ${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`;
    };
    const gotoBtn = (c) => `<button class="adm-btn ghost sm" data-goto='${JSON.stringify(c)}' type="button">Y aller</button>`;

    // Boutons à double clic de confirmation (actions destructrices)
    function confirmClick(btn, fn) {
        if (btn.dataset.armed) { fn(); return; }
        const label = btn.textContent;
        btn.dataset.armed = '1';
        btn.classList.add('confirm');
        btn.textContent = 'Confirmer ?';
        setTimeout(() => { delete btn.dataset.armed; btn.classList.remove('confirm'); btn.textContent = label; }, 2500);
    }

    // --- Onglets ---
    function showTab(t) {
        tab = t;
        document.querySelectorAll('.adm-nav').forEach((b) => b.classList.toggle('active', b.dataset.tab === t));
        document.querySelectorAll('.adm-tab').forEach((s) => { s.hidden = s.dataset.tab !== t; });
    }
    document.querySelectorAll('.adm-nav').forEach((b) => b.addEventListener('click', () => showTab(b.dataset.tab)));

    // --- Rendu ---
    function render() {
        if (!data) return;
        const live = data.tours || [];
        const s = data.stats || {};

        $('st-live').textContent = live.length;
        $('st-parcels').textContent = s.parcels || 0;
        $('st-rate').textContent = s.total ? Math.round(s.success / s.total * 100) + ' %' : '—';
        $('st-paid').textContent = money(s.paid || 0);
        $('nav-live-count').textContent = live.length;
        $('nav-live-count').classList.toggle('on', live.length > 0);

        const on = data.settings.enabled;
        $('adm-toggle').classList.toggle('on', on);
        $('adm-toggle-label').textContent = on ? 'Recrutement ouvert' : 'Recrutement fermé';

        // En cours
        $('live-list').innerHTML = live.length ? live.map((m) => {
            const done = m.phase === 'loading' ? m.loaded : m.delivered;
            return `
            <div class="item live">
                <div class="who"><strong>${esc(m.name)}</strong><span class="sub">ID ${m.src} · ${esc(m.plate)}${m.team ? ` · avec ${m.team.map(esc).join(', ')}` : ''}</span></div>
                <div>${esc(m.tour)}<div class="sub">depuis ${fmtTime(m.since)}</div></div>
                <div><span class="mono">${done} / ${m.total}</span><div class="mini-bar"><i style="width:${m.total ? done / m.total * 100 : 0}%"></i></div></div>
                <div><span class="badge ${m.phase}">${phaseLabel[m.phase] || m.phase}</span><div class="sub mono">${money(m.earned)}</div></div>
                <div class="acts">
                    <button class="adm-btn ghost sm" data-tp="${m.src}" type="button">Aller voir</button>
                    <button class="adm-btn danger sm" data-cancel="${m.src}" type="button">Annuler</button>
                </div>
            </div>`;
        }).join('') : '<div class="empty">Aucune tournée en cours.</div>';

        // Réglages (on n'écrase pas une saisie en cours)
        if (!settingsDirty) {
            const f = $('settings-form');
            for (const [k, v] of Object.entries(data.settings)) {
                if (f.elements[k]) f.elements[k].value = v;
            }
        }

        // Positions
        const p = data.positions;
        $('pos-npc').innerHTML = `<span class="lbl">Responsable (PNJ)</span><span class="mono">${coord(p.npc)}</span>
            <span class="acts">${gotoBtn(p.npc)}<button class="adm-btn primary sm" data-action="setNpc" type="button">Placer ici</button></span>`;
        $('pos-vans').innerHTML = p.vanSpawns.map((s, i) => `
            <div class="pos-row"><span class="lbl">Place de van ${i + 1}</span><span class="mono">${coord(s)}</span>
                <span class="acts">
                    ${gotoBtn(s)}
                    <button class="adm-btn ghost sm" data-move-van="${i + 1}" type="button">Recaler ici</button>
                    ${p.vanSpawns.length > 1 ? `<button class="adm-btn danger sm" data-rm-van="${i + 1}" type="button">Supprimer</button>` : ''}
                </span></div>`).join('') + `
            <div class="pos-row"><span class="lbl sub">Une place par livreur simultané</span>
                <span class="acts"><button class="adm-btn primary sm" data-action="addVanSpawn" type="button">Ajouter une place ici</button></span></div>`;
        $('pos-return').innerHTML = `<span class="lbl">Zone de retour</span><span class="mono">${coord(p.returnPoint)}</span>
            <span class="acts">${gotoBtn(p.returnPoint)}<button class="adm-btn primary sm" data-action="setReturn" type="button">Placer ici</button></span>`;

        const zones = data.zones || {};
        if (!zonesFilled) {
            $('addr-zone').innerHTML = Object.entries(zones).map(([k, v]) => `<option value="${esc(k)}">${esc(v)}</option>`).join('');
            zonesFilled = true;
        }
        const counts = {};
        p.addresses.forEach((a) => { counts[a.zone] = (counts[a.zone] || 0) + 1; });
        $('addr-filter').innerHTML = [['all', 'Toutes', p.addresses.length], ...Object.entries(zones).map(([k, v]) => [k, v, counts[k] || 0])]
            .map(([k, v, n]) => `<button class="${zoneFilter === k ? 'active' : ''}" data-zone="${esc(k)}" type="button">${esc(v)}<b>${n}</b></button>`).join('');
        $('pos-addresses').innerHTML = p.addresses.map((a, i) => (zoneFilter !== 'all' && a.zone !== zoneFilter) ? '' : `
            <div class="pos-row"><span class="lbl">${a.label ? esc(a.label) : `Adresse ${i + 1} <span class="sub">(rue auto)</span>`}</span><span class="zone">${esc(zones[a.zone] || a.zone)}</span><span class="mono">${coord(a.coords)}</span>
                <span class="acts">
                    ${gotoBtn(a.coords)}
                    <button class="adm-btn ghost sm" data-move-address="${i + 1}" type="button">Recaler ici</button>
                    <button class="adm-btn danger sm" data-rm-address="${i + 1}" type="button">Supprimer</button>
                </span></div>`).join('');

        // Livreurs
        // On ne redessine pas la liste pendant qu'un menu de niveau est ouvert
        const pl = data.players || [];
        const levels = data.levels || [];
        const editing = (document.activeElement && document.activeElement.matches('#players-list select'))
            || document.querySelector('#players-list [data-armed]');
        if (!editing) {
            $('players-list').innerHTML = pl.length ? pl.map((e) => {
                const pick = levelPick[e.identifier] || e.level;
                return `
                <div class="item players">
                    <div class="who"><strong>${esc(e.name)}</strong><span class="sub mono">${esc(e.identifier)}</span></div>
                    <div>Niv. ${e.level} · ${esc(e.title)}<div class="sub mono">${e.xp} XP</div></div>
                    <div class="mono">${e.delivered}<div class="sub">colis</div></div>
                    <div class="mono">${e.tours}<div class="sub">tournées</div></div>
                    <div class="mono">${money(e.earned)}</div>
                    <div class="mono">${e.rating ? e.rating.toFixed(1).replace('.', ',') + ' ★' : '—'}</div>
                    <div class="acts">
                        <select class="lvl-select" data-level-for="${esc(e.identifier)}">
                            ${levels.map((l, i) => `<option value="${i + 1}" ${i + 1 === pick ? 'selected' : ''}>${i + 1} · ${esc(l.title)}</option>`).join('')}
                        </select>
                        <button class="adm-btn ghost sm" data-set-level="${esc(e.identifier)}" type="button">Régler</button>
                        <button class="adm-btn danger sm" data-reset="${esc(e.identifier)}" type="button">Remettre à zéro</button>
                    </div>
                </div>`;
            }).join('') : '<div class="empty">Aucun livreur enregistré.</div>';
        }

        renderStats();
        renderRushTab();

        // Historique
        const h = data.history || [];
        $('history-list').innerHTML = h.length ? h.map((e) => `
            <div class="item hist">
                <span class="sub mono">${fmtDate(e.t)}</span>
                <span><strong>${esc(e.name)}</strong></span>
                <span>${esc(e.tour)}</span>
                <span class="mono">${e.delivered} / ${e.total}</span>
                <span><span class="badge ${e.result}">${e.result === 'fail' || e.result === 'cancel' ? esc(reasons[e.reason] || resultLabel[e.result]) : resultLabel[e.result]}</span></span>
                <span class="mono">${money(e.paid)}</span>
            </div>`).join('') : '<div class="empty">Aucune tournée enregistrée.</div>';
    }

    // --- Statistiques ---
    function renderStats() {
        const all = data.daily || [];
        const days = all.slice(-statsDays);
        const sum = (k) => days.reduce((a, d) => a + (d[k] || 0), 0);
        const tours = sum('tours');
        const paid = sum('paid');
        const fails = sum('fail') + sum('cancel');
        const couriers = days.reduce((a, d) => a + d.couriers, 0);
        const kpi = (label, value, sub) => `<div class="kpi"><span>${label}</span><b>${value}</b>${sub ? `<i>${sub}</i>` : ''}</div>`;
        $('stats-kpis').innerHTML = [
            kpi('Argent distribué', money(paid), tours ? `${money(paid / tours)} par tournée` : ''),
            kpi('Tournées', tours, `${sum('team')} en équipe`),
            kpi('Taux de réussite', pct(sum('success'), tours), `${sum('partial')} écourtées`),
            kpi('Taux d\'échec', pct(fails, tours), `${fails} abandons ou échecs`),
            kpi('Colis livrés', sum('parcels'), tours ? `${fmtNum(sum('parcels') / tours, 1)} par tournée` : ''),
            kpi('Livreurs actifs', couriers, 'cumul par jour'),
            kpi('Durée moyenne', tours ? fmtTime(sum('duration') / tours) : '—', 'par tournée')
        ].join('');

        // Barres : argent distribué par jour (une seule série, pas de légende)
        const max = Math.max(1, ...days.map((d) => d.paid));
        const best = days.reduce((a, d) => (d.paid > (a ? a.paid : -1) ? d : a), null);
        $('stats-peak').textContent = best && best.paid > 0 ? `Meilleur jour : ${dayLabel(best.day)} · ${money(best.paid)}` : '';
        const step = days.length > 14 ? 3 : days.length > 7 ? 2 : 1;
        $('stats-chart').innerHTML = `
            <div class="chart-grid"><span>${money(max)}</span><span>${money(max / 2)}</span><span>0 $</span></div>
            <div class="chart-bars">${days.map((d, i) => `
                <div class="cbar" tabindex="0">
                    <i style="height:${d.paid / max * 100}%"></i>
                    <span class="cx">${(days.length - 1 - i) % step === 0 ? dayLabel(d.day) : ''}</span>
                    <div class="tip"><b>${dayLabel(d.day)}</b><span>${money(d.paid)} distribués</span><span>${d.tours} tournée${d.tours > 1 ? 's' : ''} · ${d.parcels} colis</span><span>${pct(d.success, d.tours)} réussies · ${d.couriers} livreur${d.couriers > 1 ? 's' : ''}</span></div>
                </div>`).join('')}</div>`;

        // Tournées les plus jouées
        const byTour = {};
        days.forEach((d) => Object.entries(d.byTour || {}).forEach(([id, t]) => {
            const x = byTour[id] || (byTour[id] = { n: 0, success: 0, paid: 0, parcels: 0 });
            x.n += t.n; x.success += t.success; x.paid += t.paid; x.parcels += t.parcels;
        }));
        const tl = Object.entries(byTour).sort((a, b) => b[1].n - a[1].n);
        const tMax = Math.max(1, ...tl.map(([, t]) => t.n));
        $('stats-tours').innerHTML = tl.length ? `
            <div class="rank-table"><div class="rt-head"><span>Tournée</span><span>Jouées</span><span>Réussite</span><span>Moy. versée</span></div>
            ${tl.map(([id, t]) => `
                <div class="rt-row"><span>${esc((data.tourLabels || {})[id] || id)}<i class="mini-bar"><i style="width:${t.n / tMax * 100}%"></i></i></span>
                <span class="mono">${t.n}</span><span class="mono">${pct(t.success, t.n)}</span><span class="mono">${money(t.paid / t.n)}</span></div>`).join('')}
            </div>` : '<div class="empty">Aucune tournée sur la période.</div>';

        // Causes d'échec
        const rs = {};
        days.forEach((d) => Object.entries(d.reasons || {}).forEach(([k, n]) => { rs[k] = (rs[k] || 0) + n; }));
        const rl = Object.entries(rs).sort((a, b) => b[1] - a[1]);
        const rMax = Math.max(1, ...rl.map(([, n]) => n));
        $('stats-reasons').innerHTML = rl.length ? `
            <div class="rank-table"><div class="rt-head two"><span>Cause</span><span>Tournées</span></div>
            ${rl.map(([k, n]) => `
                <div class="rt-row two"><span>${esc(reasons[k] || k)}<i class="mini-bar err"><i style="width:${n / rMax * 100}%"></i></i></span><span class="mono">${n} · ${pct(n, fails)}</span></div>`).join('')}
            </div>` : '<div class="empty">Aucun échec sur la période.</div>';
    }

    $('stats-range').addEventListener('click', (e) => {
        const b = e.target.closest('[data-days]');
        if (!b) return;
        statsDays = Number(b.dataset.days);
        [...$('stats-range').children].forEach((x) => x.classList.toggle('active', x === b));
        if (data) renderStats();
    });

    // --- Événement (rush) ---
    function fillRush(p) {
        const f = $('rush-form');
        f.elements.label.value = p.label;
        f.elements.minutes.value = p.minutes || 30;
        f.elements.pay.value = p.pay;
        f.elements.xp.value = p.xp;
        f.elements.parcels.value = p.parcels || 1;
    }

    function renderRushTab() {
        const r = data.rush;
        $('nav-rush').hidden = !r;
        $('nav-rush').classList.toggle('on', !!r);
        $('rush-live').hidden = !r;
        if (r) {
            $('rl-label').textContent = r.label;
            const parts = [`paie x${fmtNum(r.pay)}`, `XP x${fmtNum(r.xp)}`, `colis x${fmtNum(r.parcels)}`];
            $('rl-text').textContent = parts.join(' · ') + (r.by ? ` · lancé par ${r.by}` : '');
            $('rl-left').textContent = `reste ${fmtTime(r.endsIn)}`;
        }
        if (!$('rush-start').dataset.armed) $('rush-start').textContent = r ? 'Remplacer l\'événement en cours' : 'Lancer l\'événement';
        if (!presetsFilled) {
            const ps = data.rushPresets || [];
            $('rush-presets').innerHTML = ps.map((p, i) => `<button type="button" data-preset="${i}">${esc(p.label)}<b>${p.minutes} min</b></button>`).join('');
            if (ps[0]) fillRush(ps[0]);
            presetsFilled = true;
        }
    }

    $('rush-presets').addEventListener('click', (e) => {
        const b = e.target.closest('[data-preset]');
        if (!b) return;
        fillRush(data.rushPresets[Number(b.dataset.preset)]);
        [...$('rush-presets').children].forEach((x) => x.classList.toggle('active', x === b));
    });

    $('rush-start').addEventListener('click', () => {
        const f = $('rush-form');
        const payload = {
            label: f.elements.label.value.trim(),
            minutes: Number(f.elements.minutes.value),
            pay: Number(f.elements.pay.value),
            xp: Number(f.elements.xp.value),
            parcels: Number(f.elements.parcels.value)
        };
        if (!payload.label) { toast('Donne un nom à l\'événement.', 'error'); return; }
        confirmClick($('rush-start'), () => action('rushStart', payload));
    });

    // --- Événements ---
    adm.addEventListener('change', (e) => {
        const s = e.target.closest('[data-level-for]');
        if (s) levelPick[s.dataset.levelFor] = Number(s.value);
    });

    adm.addEventListener('click', (e) => {
        const t = e.target.closest('button');
        if (!t) return;
        if (t.dataset.zone) { zoneFilter = t.dataset.zone; render(); }
        else if (t.dataset.days || t.dataset.preset || t.id === 'rush-start') return;
        else if (t.dataset.setLevel) {
            const id = t.dataset.setLevel;
            const sel = document.querySelector(`[data-level-for="${CSS.escape(id)}"]`);
            const level = sel ? Number(sel.value) : levelPick[id];
            confirmClick(t, () => { delete levelPick[id]; action('setLevel', { identifier: id, level }); });
        }
        else if (t.dataset.tp) action('teleport', { src: +t.dataset.tp });
        else if (t.dataset.goto) action('teleport', { coords: JSON.parse(t.dataset.goto) });
        else if (t.dataset.cancel) confirmClick(t, () => action('cancel', { src: +t.dataset.cancel }));
        else if (t.dataset.moveAddress) confirmClick(t, () => action('moveAddress', { index: +t.dataset.moveAddress }));
        else if (t.dataset.moveVan) confirmClick(t, () => action('moveVanSpawn', { index: +t.dataset.moveVan }));
        else if (t.dataset.rmVan) confirmClick(t, () => action('removeVanSpawn', { index: +t.dataset.rmVan }));
        else if (t.dataset.rmAddress) confirmClick(t, () => action('removeAddress', { index: +t.dataset.rmAddress }));
        else if (t.dataset.reset) confirmClick(t, () => action('resetPlayer', { identifier: t.dataset.reset }));
        else if (t.dataset.action === 'clearHistory' || t.dataset.action === 'resetCooldowns') confirmClick(t, () => action(t.dataset.action));
        else if (t.dataset.action) action(t.dataset.action);
    });

    $('settings-form').addEventListener('input', () => { settingsDirty = true; });
    $('settings-save').addEventListener('click', () => {
        const f = $('settings-form');
        const settings = {};
        for (const el of f.elements) if (el.name) settings[el.name] = Number(el.value);
        settingsDirty = false;
        action('saveSettings', { settings });
    });

    $('adm-toggle').addEventListener('click', () => action('toggle'));

    $('add-address').addEventListener('click', () => {
        const label = $('addr-label').value.trim();
        action('addAddress', { label, zone: $('addr-zone').value });
        $('addr-label').value = '';
    });

    const close = () => post('adminClose');
    $('adm-close').addEventListener('click', close);
    window.addEventListener('keydown', (e) => { if (e.key === 'Escape' && !adm.hidden) close(); });

    window.addEventListener('message', (e) => {
        const m = e.data || {};
        if (m.action === 'adminOpen') { adm.hidden = false; settingsDirty = false; presetsFilled = false; showTab(tab); }
        else if (m.action === 'adminClose') adm.hidden = true;
        else if (m.action === 'adminData') {
            data = m.data;
            render();
            if (m.data.toast) toast(m.data.toast, 'info');
        }
    });
})();
