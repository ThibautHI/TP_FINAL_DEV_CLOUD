require('dotenv').config();
const express = require('express');
const cors = require('cors');

const app = express();
const port = process.env.PORT || 3003;

app.use(cors());
app.use(express.json());

const DELIVERY_SERVICE_URL = process.env.DELIVERY_SERVICE_URL || 'http://localhost:3000';
const GPS_INGEST_SERVICE_URL = process.env.GPS_INGEST_SERVICE_URL || 'http://localhost:3001';

// Stockage des simulations actives en mémoire
const activeSimulations = {};

app.get('/healthz', (req, res) => {
  res.status(200).json({ status: 'UP' });
});

app.post('/simulate', async (req, res) => {
  const { parcel_id } = req.body;

  if (!parcel_id) {
    return res.status(400).json({ error: 'Champs requis manquants : parcel_id' });
  }

  if (activeSimulations[parcel_id]) {
    return res.status(409).json({ error: 'Une simulation est déjà en cours pour ce colis' });
  }

  try {
    // 1. Récupérer les détails du colis depuis le delivery-service
    console.log(`[Simulator] Récupération des infos pour le colis ${parcel_id} via ${DELIVERY_SERVICE_URL}...`);
    const response = await fetch(`${DELIVERY_SERVICE_URL}/parcels/${parcel_id}`);
    
    if (!response.ok) {
      if (response.status === 404) {
        return res.status(404).json({ error: `Colis ${parcel_id} introuvable dans le delivery-service` });
      }
      throw new Error(`Erreur delivery-service: ${response.statusText}`);
    }

    const parcel = await response.json();

    if (parcel.status === 'delivered') {
      return res.status(400).json({ error: 'Le colis est déjà livré' });
    }

    // 2. Lancer la simulation de manière asynchrone
    startGpsRouteSimulation(parcel);

    res.status(200).json({ message: `Simulation lancée avec succès pour le colis ${parcel_id}` });

  } catch (err) {
    console.error('[Simulator] Erreur lors du lancement de la simulation:', err.message);
    res.status(500).json({ error: `Erreur serveur : ${err.message}` });
  }
});

// Arrêter une simulation
app.post('/simulate/stop', (req, res) => {
  const { parcel_id } = req.body;
  if (activeSimulations[parcel_id]) {
    clearInterval(activeSimulations[parcel_id]);
    delete activeSimulations[parcel_id];
    console.log(`[Simulator] Simulation arrêtée manuellement pour le colis ${parcel_id}`);
    return res.status(200).json({ message: 'Simulation arrêtée' });
  }
  res.status(404).json({ error: 'Aucune simulation en cours pour ce colis' });
});

// Simulation de trajet pas-à-pas
function startGpsRouteSimulation(parcel) {
  const { id: parcel_id, dest_lat, dest_lng } = parcel;

  // Point de départ : décalé d'environ 1.5 km au sud-ouest de la destination
  const start_lat = dest_lat - 0.012;
  const start_lng = dest_lng - 0.015;

  const totalSteps = 15;
  let currentStep = 0;

  console.log(`[Simulator] Début trajet colis ${parcel_id}. Départ: (${start_lat}, ${start_lng}) -> Arrivée: (${dest_lat}, ${dest_lng})`);

  // Envoyer la première position immédiatement
  sendGpsPoint(parcel_id, start_lat, start_lng);

  const intervalId = setInterval(async () => {
    currentStep += 1;
    
    // Interpolation linéaire entre le départ et l'arrivée
    const ratio = currentStep / totalSteps;
    const lat = start_lat + (dest_lat - start_lat) * ratio;
    const lng = start_lng + (dest_lng - start_lng) * ratio;

    console.log(`[Simulator] Colis ${parcel_id} : Étape ${currentStep}/${totalSteps} - (${lat.toFixed(5)}, ${lng.toFixed(5)})`);

    await sendGpsPoint(parcel_id, lat, lng);

    // Si on est arrivé à destination
    if (currentStep >= totalSteps) {
      clearInterval(intervalId);
      delete activeSimulations[parcel_id];
      console.log(`[Simulator] Colis ${parcel_id} arrivé à destination !`);
      
      // Mettre à jour le statut du colis en 'delivered' dans le delivery-service
      try {
        await fetch(`${DELIVERY_SERVICE_URL}/parcels/${parcel_id}/status`, {
          method: 'PATCH',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ status: 'delivered' })
        });
        console.log(`[Simulator] Statut mis à jour en 'delivered' pour le colis ${parcel_id}`);
      } catch (err) {
        console.error(`[Simulator] Impossible de mettre à jour le statut en 'delivered' :`, err.message);
      }
    }
  }, 5000); // Toutes les 5 secondes

  // Stocker l'ID de l'intervalle pour pouvoir l'arrêter au besoin
  activeSimulations[parcel_id] = intervalId;
}

// Envoyer une position GPS au gps-ingest-service
async function sendGpsPoint(parcel_id, latitude, longitude) {
  try {
    const res = await fetch(`${GPS_INGEST_SERVICE_URL}/gps-points`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        parcel_id,
        latitude,
        longitude,
        timestamp: new Date().toISOString()
      })
    });
    
    if (!res.ok) {
      console.warn(`[Simulator] Échec envoi position. Statut: ${res.status} - ${res.statusText}`);
    }
  } catch (err) {
    console.error('[Simulator] Erreur envoi HTTP vers ingest-service:', err.message);
  }
}

app.listen(port, () => {
  console.log(`gps-simulator démarré sur le port ${port}`);
});
