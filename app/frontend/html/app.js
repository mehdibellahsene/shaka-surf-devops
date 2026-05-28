// Frontend Shaka Surf — vanilla JS, sans framework ni CDN (tout offline).
// Toutes les requetes passent par /api/ : nginx les proxifie vers le backend.

const $ = (selecteur) => document.querySelector(selecteur);

/* ------------------------------------------------------------------ */
/* 1. Badge "Servi par app-X" (identite de l'instance backend)        */
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
/* 2. Tableau de bord (metriques calculees depuis PostgreSQL)         */
/* ------------------------------------------------------------------ */

async function chargerDashboard() {
  const revenu = $('#metrique-revenu');
  const eleves = $('#metrique-eleves');
  const remplissage = $('#metrique-remplissage');
  try {
    const reponse = await fetch('/api/dashboard', { cache: 'no-store' });
    if (!reponse.ok) throw new Error(`HTTP ${reponse.status}`);
    const d = await reponse.json();
    revenu.textContent = `${d.revenue_eur.toLocaleString('fr-FR')} €`;
    eleves.textContent = d.students;
    remplissage.textContent = `${d.fill_rate} %`;
  } catch {
    revenu.textContent = eleves.textContent = remplissage.textContent = '—';
  }
}

/* ------------------------------------------------------------------ */
/* 3. Sante de la chaine Frontend -> Backend -> PostgreSQL            */
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
    // Backend injoignable : tout est rouge derriere le frontend.
    setPastille(pastilleBack, 'rouge');
    setPastille(pastilleDb, 'rouge');
    bandeau.classList.remove('cache');
  }
}

/* ------------------------------------------------------------------ */
/* 4. Visualiseur de load balancing (10 requetes sequentielles)       */
/* ------------------------------------------------------------------ */

async function envoyerDixRequetes() {
  const bouton = $('#btn-dix-requetes');
  const conteneur = $('#barres-lb');
  bouton.disabled = true;
  const compteur = {}; // { nomInstance: nombre de reponses }
  for (let i = 0; i < 10; i++) {
    try {
      const reponse = await fetch('/api/whoami', { cache: 'no-store' });
      const donnees = await reponse.json();
      compteur[donnees.instance] = (compteur[donnees.instance] || 0) + 1;
    } catch {
      compteur['(erreur)'] = (compteur['(erreur)'] || 0) + 1;
    }
    dessinerBarres(conteneur, compteur); // mise a jour en direct, requete apres requete
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
/* 5. Planning des cours (cartes + alimentation du select)            */
/* ------------------------------------------------------------------ */

async function chargerCours() {
  const conteneur = $('#liste-cours');
  const select = $('#insc-cours');
  try {
    const reponse = await fetch('/api/lessons');
    if (!reponse.ok) throw new Error(`HTTP ${reponse.status}`);
    const cours = await reponse.json();

    conteneur.innerHTML = '';
    select.length = 1; // on garde uniquement l'option "— choisis un cours —"

    for (const c of cours) {
      // Carte du cours (construction DOM : pas d'injection HTML).
      const carte = document.createElement('article');
      carte.className = 'carte-cours';

      const titre = document.createElement('h3');
      titre.textContent = c.title;

      const moniteur = document.createElement('p');
      moniteur.className = 'moniteur';
      moniteur.textContent = `Moniteur : ${c.instructor}`;

      const infos = document.createElement('div');
      infos.className = 'infos';

      const niveau = document.createElement('span');
      niveau.className = 'etiquette';
      niveau.textContent = c.level;

      const prix = document.createElement('span');
      prix.className = 'etiquette prix';
      prix.textContent = `${c.price_eur} €`;

      const places = document.createElement('span');
      places.className = 'etiquette places';
      places.textContent = `${c.capacity} places`;

      infos.append(niveau, prix, places);
      carte.append(titre, moniteur, infos);
      conteneur.appendChild(carte);

      // Option correspondante dans le formulaire d'inscription.
      const option = document.createElement('option');
      option.value = c.id;
      option.textContent = `${c.title} — ${c.price_eur} €`;
      select.appendChild(option);
    }
  } catch {
    conteneur.innerHTML =
      '<p class="note erreur">Planning indisponible (base de donnees injoignable).</p>';
  }
}

/* ------------------------------------------------------------------ */
/* 6. Inscriptions (liste + formulaire)                               */
/* ------------------------------------------------------------------ */

function formaterDateFr(aaaaMmJj) {
  // 'AAAA-MM-JJ' -> 'JJ/MM/AAAA' sans passer par Date (pas de souci de fuseau).
  if (!aaaaMmJj) return 'date libre';
  const [annee, mois, jour] = aaaaMmJj.split('-');
  return `${jour}/${mois}/${annee}`;
}

async function chargerInscriptions() {
  const liste = $('#liste-inscriptions');
  try {
    const reponse = await fetch('/api/enrollments');
    if (!reponse.ok) throw new Error(`HTTP ${reponse.status}`);
    const inscriptions = await reponse.json();

    liste.innerHTML = '';
    if (inscriptions.length === 0) {
      const vide = document.createElement('li');
      vide.className = 'note';
      vide.textContent = "Aucune inscription pour l'instant.";
      liste.appendChild(vide);
      return;
    }
    for (const insc of inscriptions) {
      const li = document.createElement('li');
      li.textContent = `${insc.student} — ${insc.lesson_title || 'cours inconnu'} — ${formaterDateFr(
        insc.scheduled_for
      )}`;
      liste.appendChild(li);
    }
  } catch {
    liste.innerHTML =
      '<li class="note erreur">Inscriptions indisponibles (base de donnees injoignable).</li>';
  }
}

function afficherMessage(texte, type) {
  // type : 'ok' | 'erreur'
  const message = $('#message-inscription');
  message.textContent = texte;
  message.className = `message ${type}`;
}

async function soumettreInscription(evenement) {
  evenement.preventDefault();
  const corps = {
    student: $('#insc-eleve').value.trim(),
    lesson_id: parseInt($('#insc-cours').value, 10),
    scheduled_for: $('#insc-date').value,
  };
  try {
    const reponse = await fetch('/api/enrollments', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(corps),
    });
    if (reponse.status === 201) {
      afficherMessage('Inscription enregistree.', 'ok');
      evenement.target.reset();
      chargerInscriptions();
      chargerDashboard(); // le chiffre d'affaires et les eleves evoluent
    } else if (reponse.status === 503) {
      afficherMessage('Base de donnees injoignable : reessaie un peu plus tard.', 'erreur');
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
  chargerDashboard();
  chargerSante();
  chargerCours();
  chargerInscriptions();

  $('#btn-recharger-sante').addEventListener('click', chargerSante);
  $('#btn-dix-requetes').addEventListener('click', envoyerDixRequetes);
  $('#form-inscription').addEventListener('submit', soumettreInscription);

  // Auto-refresh de la sante toutes les 10 secondes.
  setInterval(chargerSante, 10000);
});
