// Configuration Globale
const API_URL = ''; // Relatif au serveur qui sert le site
const SIMULATOR_URL = 'http://localhost:3003'; // URL du gps-simulator en local
let map;
let activeParcelId = null;
let destinationMarker = null;
let driverMarker = null;
let routeLine = null;
let pollInterval = null;

// Initialisation de la carte Leaflet
function initMap() {
  // Centré sur Montpellier
  map = L.map('map', {
    zoomControl: true,
    attributionControl: false
  }).setView([43.6107, 3.8767], 13);

  // Layer OpenStreetMap standard (sera stylisé en sombre par le CSS)
  L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
    maxZoom: 19,
  }).addTo(map);
}

// Icônes personnalisées
const destinationIcon = L.divIcon({
  className: 'custom-pin-dest',
  html: `<div style="background-color: #ef4444; width: 14px; height: 14px; border-radius: 50%; border: 3px solid white; box-shadow: 0 0 10px rgba(239, 68, 68, 0.5);"></div>`,
  iconSize: [14, 14],
  iconAnchor: [7, 7]
});

const driverIcon = L.divIcon({
  className: 'custom-pin-driver',
  html: `<div class="driver-marker-pulse" style="background-color: #10b981; width: 16px; height: 16px; border-radius: 50%; border: 3px solid white; box-shadow: 0 0 15px #10b981;"></div>`,
  iconSize: [16, 16],
  iconAnchor: [8, 8]
});

// Charger la liste des colis
async function fetchParcels() {
  try {
    const res = await fetch(`${API_URL}/parcels`);
    const parcels = await res.json();
    
    const listElement = document.getElementById('parcel-list');
    listElement.innerHTML = '';

    if (parcels.length === 0) {
      listElement.innerHTML = '<li class="loading">Aucun colis enregistré</li>';
      return;
    }

    parcels.forEach(parcel => {
      const li = document.createElement('li');
      li.className = parcel.id === activeParcelId ? 'active' : '';
      li.dataset.id = parcel.id;
      
      let statusLabel = 'Créé';
      if (parcel.status === 'assigned') statusLabel = 'Assigné';
      if (parcel.status === 'in_transit') statusLabel = 'En transit';
      if (parcel.status === 'delivered') statusLabel = 'Livré';

      li.innerHTML = `
        <div class="item-header">
          <span class="item-id">#${parcel.id}</span>
          <span class="badge ${parcel.status}">${statusLabel}</span>
        </div>
        <div class="item-name">${parcel.name}</div>
      `;

      li.addEventListener('click', () => selectParcel(parcel.id));
      listElement.appendChild(li);
    });
  } catch (err) {
    console.error('Erreur chargement colis:', err);
    document.getElementById('parcel-list').innerHTML = '<li class="loading" style="color: #ef4444;">Erreur de connexion API</li>';
  }
}

// Sélectionner un colis pour affichage
async function selectParcel(parcelId) {
  activeParcelId = parcelId;
  
  // Mettre à jour la classe active dans la liste
  document.querySelectorAll('#parcel-list li').forEach(li => {
    if (li.dataset.id === parcelId) {
      li.classList.add('active');
    } else {
      li.classList.remove('active');
    }
  });

  // Annuler le polling précédent et relancer pour ce colis
  if (pollInterval) clearInterval(pollInterval);
  
  await updateParcelDetails();
  pollInterval = setInterval(updateParcelDetails, 3000);
}

// Mettre à jour les détails et la carte pour le colis actif
async function updateParcelDetails() {
  if (!activeParcelId) return;

  try {
    // 1. Charger les détails du colis
    const res = await fetch(`${API_URL}/parcels/${activeParcelId}`);
    if (res.status === 404) {
      clearInterval(pollInterval);
      document.getElementById('info-panel').classList.add('hidden');
      return;
    }
    const parcel = await res.json();

    // 2. Charger l'historique de sa route
    const routeRes = await fetch(`${API_URL}/parcels/${activeParcelId}/route`);
    const routeHistory = await routeRes.json();

    // Mettre à jour les éléments de l'UI
    document.getElementById('info-panel').classList.remove('hidden');
    document.getElementById('parcel-title').innerText = `Colis #${parcel.id}`;
    
    let statusLabel = 'Créé';
    if (parcel.status === 'assigned') statusLabel = 'Assigné';
    if (parcel.status === 'in_transit') statusLabel = 'En transit';
    if (parcel.status === 'delivered') statusLabel = 'Livré';
    
    const statusBadge = document.getElementById('parcel-status-badge');
    statusBadge.className = `badge ${parcel.status}`;
    statusBadge.innerText = statusLabel;

    document.getElementById('parcel-desc').innerText = parcel.name;
    document.getElementById('parcel-email').innerText = parcel.recipient_email;
    document.getElementById('parcel-dest-coords').innerText = `${parcel.dest_lat.toFixed(4)}, ${parcel.dest_lng.toFixed(4)}`;
    
    const notifiedBadge = document.getElementById('parcel-notified');
    if (parcel.notified_at) {
      notifiedBadge.className = 'badge-notified yes';
      notifiedBadge.innerText = 'Envoyée (MailHog)';
    } else {
      notifiedBadge.className = 'badge-notified no';
      notifiedBadge.innerText = 'Non envoyée';
    }

    // Gestion du bouton de simulation
    const simBtn = document.getElementById('start-sim-btn');
    if (parcel.status === 'delivered') {
      simBtn.disabled = true;
      simBtn.innerText = 'Colis déjà livré';
    } else if (parcel.status === 'in_transit') {
      simBtn.disabled = true;
      simBtn.innerText = 'Livraison en cours...';
    } else {
      simBtn.disabled = false;
      simBtn.innerText = 'Lancer la simulation';
    }

    // Mise à jour de la carte
    const destLatLng = [parcel.dest_lat, parcel.dest_lng];

    // Positionner le marqueur de destination
    if (destinationMarker) {
      destinationMarker.setLatLng(destLatLng);
    } else {
      destinationMarker = L.marker(destLatLng, { icon: destinationIcon }).addTo(map)
        .bindPopup('<b>Destination du colis</b>').openPopup();
    }

    // Positionner le marqueur du livreur et tracer la ligne
    if (routeHistory.length > 0) {
      const pathCoordinates = routeHistory.map(pt => [pt.latitude, pt.longitude]);
      const lastPoint = pathCoordinates[pathCoordinates.length - 1];

      document.getElementById('parcel-last-coords').innerText = `${lastPoint[0].toFixed(4)}, ${lastPoint[1].toFixed(4)}`;

      // Mettre à jour/Créer le traceur de route
      if (routeLine) {
        routeLine.setLatLngs(pathCoordinates);
      } else {
        routeLine = L.polyline(pathCoordinates, { color: '#3b82f6', weight: 4, opacity: 0.8 }).addTo(map);
      }

      // Mettre à jour/Créer le livreur
      if (driverMarker) {
        driverMarker.setLatLng(lastPoint);
      } else {
        driverMarker = L.marker(lastPoint, { icon: driverIcon }).addTo(map)
          .bindPopup('<b>Livreur en mouvement</b>');
      }

      // Adapter la vue de la carte pour englober la destination et la position du livreur
      const bounds = L.latLngBounds([destLatLng, ...pathCoordinates]);
      map.fitBounds(bounds, { padding: [50, 50] });
    } else {
      document.getElementById('parcel-last-coords').innerText = 'En attente de signal GPS';
      if (driverMarker) {
        map.removeLayer(driverMarker);
        driverMarker = null;
      }
      if (routeLine) {
        map.removeLayer(routeLine);
        routeLine = null;
      }
      map.setView(destLatLng, 14);
    }

  } catch (err) {
    console.error('Erreur mise à jour détails colis:', err);
  }
}

// Lancer la simulation de trajet
async function startSimulation() {
  if (!activeParcelId) return;
  const simBtn = document.getElementById('start-sim-btn');
  simBtn.disabled = true;
  simBtn.innerText = 'Initialisation...';

  try {
    const res = await fetch(`${SIMULATOR_URL}/simulate`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ parcel_id: activeParcelId })
    });
    
    if (res.ok) {
      simBtn.innerText = 'Simulation lancée';
      // Forcer une mise à jour immédiate
      await updateParcelDetails();
    } else {
      const data = await res.json();
      alert(`Erreur simulateur: ${data.error || 'inconnue'}`);
      simBtn.disabled = false;
      simBtn.innerText = 'Lancer la simulation';
    }
  } catch (err) {
    console.error('Erreur appel simulateur:', err);
    alert('Impossible de contacter le service gps-simulator. Est-il démarré ?');
    simBtn.disabled = false;
    simBtn.innerText = 'Lancer la simulation';
  }
}

// Initialisation globale
document.addEventListener('DOMContentLoaded', () => {
  initMap();
  fetchParcels();
  
  // Rafraîchir la liste toutes les 8 secondes
  setInterval(fetchParcels, 8000);

  // Bouton de fermeture de panneau
  document.getElementById('close-panel-btn').addEventListener('click', () => {
    document.getElementById('info-panel').classList.add('hidden');
    activeParcelId = null;
    if (pollInterval) clearInterval(pollInterval);
    if (destinationMarker) { map.removeLayer(destinationMarker); destinationMarker = null; }
    if (driverMarker) { map.removeLayer(driverMarker); driverMarker = null; }
    if (routeLine) { map.removeLayer(routeLine); routeLine = null; }
    document.querySelectorAll('#parcel-list li').forEach(li => li.classList.remove('active'));
    map.setView([43.6107, 3.8767], 13);
  });

  // Bouton de simulation
  document.getElementById('start-sim-btn').addEventListener('click', startSimulation);

  // Recherche simple de colis
  document.getElementById('search-input').addEventListener('input', (e) => {
    const filter = e.target.value.toLowerCase();
    document.querySelectorAll('#parcel-list li').forEach(li => {
      const text = li.innerText.toLowerCase();
      if (text.includes(filter)) {
        li.style.display = 'flex';
      } else {
        li.style.display = 'none';
      }
    });
  });
});
