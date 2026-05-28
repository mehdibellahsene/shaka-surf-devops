// Frontend mock Shaka Surf — vanilla JS, sans framework ni CDN (tout offline).
// Toutes les requêtes passent par /api/ : nginx les proxifie vers le backend.

const $ = (selecteur) => document.querySelector(selecteur);

/* ------------------------------------------------------------------ */
/* 1. Badge "Servi par app-X" (identité de l'instance backend)        */
/* ------------------------------------------------------------------ */

async function chargerInstance() {
  const badge = $('#badge-instance');
  try {
    const reponse = await fetch('/api/whoami', { cache: 'no-store' });
    const donnees = await reponse.json();
    badge.textContent = `Servi par ${donnees.instance}`;
  } catch {
    badge.textContent = 'Backend injoignable';
  }
}

/* ------------------------------------------------------------------ */
/* 2. Santé de la chaîne Frontend -> Backend -> PostgreSQL            */
/* ------------------------------------------------------------------ */

function setPastille(element, etat) {
  // etat : 'verte' | 'rouge' | 'grise'
  element.className = `pastille ${etat}`;
}

async function chargerSante() {
  const pastilleBack = $('#pastille-back');
  const pastilleDb = $('#pastille-db');
  const bandeau = $('#bandeau-degrade');
  try {
    const reponse = await fetch('/api/health', { cache: 'no-store' });
    const donnees = await reponse.json();
    setPastille(pastilleBack, 'verte');
    const dbUp = donnees.db === 'up';
    setPastille(pastilleDb, dbUp ? 'verte' : 'rouge');
    bandeau.classList.toggle('cache', dbUp);
  } catch {
    // Backend injoignable : tout est rouge derrière le frontend.
    setPastille(pastilleBack, 'rouge');
    setPastille(pastilleDb, 'rouge');
    bandeau.classList.remove('cache');
  }
}

/* ------------------------------------------------------------------ */
/* 3. Visualiseur de load balancing (10 requêtes séquentielles)       */
/* ------------------------------------------------------------------ */

async function envoyerDixRequetes() {
  const bouton = $('#btn-dix-requetes');
  const conteneur = $('#barres-lb');
  bouton.disabled = true;
  const compteur = {}; // { nomInstance: nombre de réponses }
  for (let i = 0; i < 10; i++) {
    try {
      const reponse = await fetch('/api/whoami', { cache: 'no-store' });
      const donnees = await reponse.json();
      compteur[donnees.instance] = (compteur[donnees.instance] || 0) + 1;
    } catch {
      compteur['(erreur)'] = (compteur['(erreur)'] || 0) + 1;
    }
    dessinerBarres(conteneur, compteur); // mise à jour en direct, requête après requête
  }
  bouton.disabled = false;
}

function dessinerBarres(conteneur, compteur) {
  conteneur.innerHTML = '';
  for (const [instance, nb] of Object.entries(compteur).sort()) {
    const ligne = document.createElement('div');
    ligne.className = 'ligne-barre';

    const label = document.createElement('span');
    label.className = 'label-barre';
    label.textContent = instance;

    const piste = document.createElement('div');
    piste.className = 'piste-barre';
    const barre = document.createElement('div');
    barre.className = 'barre';
    barre.style.width = `${(nb / 10) * 100}%`;
    barre.textContent = nb;
    piste.appendChild(barre);

    ligne.append(label, piste);
    conteneur.appendChild(ligne);
  }
}

/* ------------------------------------------------------------------ */
/* 4. Spots de surf (cartes + alimentation du select du formulaire)   */
/* ------------------------------------------------------------------ */

async function chargerSpots() {
  const conteneur = $('#liste-spots');
  const select = $('#resa-spot');
  try {
    const reponse = await fetch('/api/spots');
    if (!reponse.ok) throw new Error(`HTTP ${reponse.status}`);
    const spots = await reponse.json();

    conteneur.innerHTML = '';
    select.length = 1; // on garde uniquement l'option "— choisis un spot —"

    for (const spot of spots) {
      // Carte du spot (construction DOM : pas d'injection HTML).
      const carte = document.createElement('article');
      carte.className = 'carte-spot';

      const emoji = document.createElement('span');
      emoji.className = 'emoji-spot';
      emoji.textContent = spot.emoji || '🏄';

      const titre = document.createElement('h3');
      titre.textContent = spot.name;

      const infos = document.createElement('div');
      infos.className = 'infos';

      const niveau = document.createElement('span');
      niveau.className = 'etiquette';
      niveau.textContent = `Niveau : ${spot.level}`;

      const vagues = document.createElement('span');
      vagues.className = 'etiquette vague-haut';
      vagues.textContent = `Vagues : ${spot.wave_height}`;

      infos.append(niveau, vagues);
      carte.append(emoji, titre, infos);
      conteneur.appendChild(carte);

      // Option correspondante dans le formulaire de réservation.
      const option = document.createElement('option');
      option.value = spot.id;
      option.textContent = `${spot.emoji || ''} ${spot.name}`.trim();
      select.appendChild(option);
    }
  } catch {
    conteneur.innerHTML =
      '<p class="note erreur">Spots indisponibles (base de données injoignable).</p>';
  }
}

/* ------------------------------------------------------------------ */
/* 5. Réservations (liste + formulaire)                               */
/* ------------------------------------------------------------------ */

function formaterDateFr(aaaaMmJj) {
  // 'AAAA-MM-JJ' -> 'JJ/MM/AAAA' sans passer par Date (pas de souci de fuseau).
  if (!aaaaMmJj) return 'date libre';
  const [annee, mois, jour] = aaaaMmJj.split('-');
  return `${jour}/${mois}/${annee}`;
}

async function chargerReservations() {
  const liste = $('#liste-resa');
  try {
    const reponse = await fetch('/api/bookings');
    if (!reponse.ok) throw new Error(`HTTP ${reponse.status}`);
    const reservations = await reponse.json();

    liste.innerHTML = '';
    if (reservations.length === 0) {
      const vide = document.createElement('li');
      vide.className = 'note';
      vide.textContent = "Aucune réservation pour l'instant — à toi la première vague !";
      liste.appendChild(vide);
      return;
    }
    for (const resa of reservations) {
      const li = document.createElement('li');
      li.textContent = `${resa.spot_emoji || '🏄'} ${resa.name} — ${
        resa.spot_name || 'spot inconnu'
      } — ${formaterDateFr(resa.booked_for)}`;
      liste.appendChild(li);
    }
  } catch {
    liste.innerHTML =
      '<li class="note erreur">Réservations indisponibles (base de données injoignable).</li>';
  }
}

function afficherMessage(texte, type) {
  // type : 'ok' | 'erreur'
  const message = $('#message-resa');
  message.textContent = texte;
  message.className = `message ${type}`;
}

async function soumettreReservation(evenement) {
  evenement.preventDefault();
  const corps = {
    name: $('#resa-nom').value.trim(),
    spot_id: parseInt($('#resa-spot').value, 10),
    booked_for: $('#resa-date').value,
  };
  try {
    const reponse = await fetch('/api/bookings', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(corps),
    });
    if (reponse.status === 201) {
      afficherMessage('🤙 Réservation enregistrée, bonne session !', 'ok');
      evenement.target.reset();
      chargerReservations();
    } else if (reponse.status === 503) {
      afficherMessage('⚠️ Base de données injoignable : réessaie un peu plus tard.', 'erreur');
    } else {
      const donnees = await reponse.json().catch(() => ({}));
      afficherMessage(`Erreur : ${donnees.error || `HTTP ${reponse.status}`}`, 'erreur');
    }
  } catch {
    afficherMessage('Backend injoignable.', 'erreur');
  }
}

/* ------------------------------------------------------------------ */
/* Initialisation                                                     */
/* ------------------------------------------------------------------ */

document.addEventListener('DOMContentLoaded', () => {
  chargerInstance();
  chargerSante();
  chargerSpots();
  chargerReservations();

  $('#btn-recharger-sante').addEventListener('click', chargerSante);
  $('#btn-dix-requetes').addEventListener('click', envoyerDixRequetes);
  $('#form-resa').addEventListener('submit', soumettreReservation);

  // Auto-refresh de la santé toutes les 10 secondes.
  setInterval(chargerSante, 10000);
});
