require('dotenv').config();
const express = require('express');
const cors = require('cors');
const { Kafka } = require('kafkajs');
const client = require('prom-client');

const app = express();
const port = process.env.PORT || 3001;

// Configuration Express
app.use(cors());
app.use(express.json());

// --- PROMETHEUS METRICS ---
const collectDefaultMetrics = client.collectDefaultMetrics;
collectDefaultMetrics({ register: client.register });

const gpsRequestsTotal = new client.Counter({
  name: 'gps_ingest_requests_total',
  help: 'Total number of GPS coordinates ingestion requests received',
  labelNames: ['status']
});

const gpsIngestedTotal = new client.Counter({
  name: 'gps_points_ingested_total',
  help: 'Total number of GPS points successfully pushed to Redpanda/Kafka'
});

const kafkaProducerStatus = new client.Gauge({
  name: 'gps_ingest_kafka_producer_connected',
  help: 'Kafka producer connection status (1 = connected, 0 = disconnected)'
});

// --- KAFKA PRODUCER ---
const kafkaBroker = process.env.KAFKA_BROKER || 'localhost:9092';
const kafka = new Kafka({
  clientId: 'gps-ingest-service',
  brokers: [kafkaBroker],
  retry: {
    initialRetryTime: 300,
    retries: 10
  }
});

const producer = kafka.producer();

async function initKafka() {
  let retries = 5;
  while (retries > 0) {
    try {
      await producer.connect();
      kafkaProducerStatus.set(1);
      console.log('Connecté à Redpanda/Kafka avec succès en tant que producteur');
      break;
    } catch (err) {
      kafkaProducerStatus.set(0);
      console.error(`Erreur connexion Redpanda/Kafka. Tentatives restantes: ${retries - 1}`, err.message);
      retries -= 1;
      await new Promise(res => setTimeout(res, 5000));
    }
  }
}

// --- ENDPOINTS API ---

// Endpoint Liveness/Readiness probe pour Kubernetes
app.get('/healthz', (req, res) => {
  res.status(200).json({ status: 'UP' });
});

// Métriques Prometheus
app.get('/metrics', async (req, res) => {
  try {
    res.set('Content-Type', client.register.contentType);
    res.end(await client.register.metrics());
  } catch (err) {
    res.status(500).end(err);
  }
});

// Ingestion des positions GPS
app.post('/gps-points', async (req, res) => {
  const { parcel_id, latitude, longitude, timestamp } = req.body;
  
  if (!parcel_id || latitude === undefined || longitude === undefined) {
    gpsRequestsTotal.inc({ status: '400' });
    return res.status(400).json({ error: 'Champs requis manquants : parcel_id, latitude, longitude' });
  }

  // Validation basique des coordonnées
  if (latitude < -90 || latitude > 90 || longitude < -180 || longitude > 180) {
    gpsRequestsTotal.inc({ status: '422' });
    return res.status(422).json({ error: 'Coordonnées GPS invalides' });
  }

  const gpsEvent = {
    parcel_id,
    latitude: parseFloat(latitude),
    longitude: parseFloat(longitude),
    timestamp: timestamp || new Date().toISOString()
  };

  try {
    // Publier sur Redpanda dans le topic gps-location-events
    await producer.send({
      topic: 'gps-location-events',
      messages: [
        { 
          key: parcel_id, 
          value: JSON.stringify(gpsEvent) 
        }
      ],
    });

    gpsRequestsTotal.inc({ status: '200' });
    gpsIngestedTotal.inc();
    
    console.log(`[Ingest] Position GPS publiée pour le colis ${parcel_id}: (${latitude}, ${longitude})`);
    res.status(200).json({ message: 'Position GPS ingérée avec succès', data: gpsEvent });
  } catch (err) {
    console.error('[Ingest] Erreur lors de la publication sur Redpanda:', err.message);
    gpsRequestsTotal.inc({ status: '500' });
    res.status(500).json({ error: 'Erreur d\'écriture sur le bus d\'événements' });
  }
});

// --- DEMARRAGE SERVEUR ---
app.listen(port, async () => {
  console.log(`gps-ingest-service démarré sur le port ${port}`);
  await initKafka();
});
