require('dotenv').config();
const express = require('express');
const cors = require('cors');
const { Pool } = require('pg');
const { Kafka } = require('kafkajs');
const client = require('prom-client');

const app = express();
const port = process.env.PORT || 3000;

// Configuration Express
app.use(cors());
app.use(express.json());
app.use(express.static('public'));

// --- PROMETHEUS METRICS ---
const collectDefaultMetrics = client.collectDefaultMetrics;
collectDefaultMetrics({ register: client.register });

const httpRequestsTotal = new client.Counter({
  name: 'delivery_service_http_requests_total',
  help: 'Total number of HTTP requests received by delivery-service',
  labelNames: ['method', 'route', 'status']
});

const httpRequestDuration = new client.Histogram({
  name: 'delivery_service_http_request_duration_seconds',
  help: 'Duration of HTTP requests in seconds',
  labelNames: ['method', 'route', 'status'],
  buckets: [0.01, 0.05, 0.1, 0.5, 1, 2, 5]
});

const dbConnectionStatus = new client.Gauge({
  name: 'delivery_service_db_connected',
  help: 'Database connection status (1 = connected, 0 = disconnected)'
});

const kafkaConsumerStatus = new client.Gauge({
  name: 'delivery_service_kafka_consumer_connected',
  help: 'Kafka consumer connection status (1 = connected, 0 = disconnected)'
});

// Middleware pour collecter les métriques
app.use((req, res, next) => {
  const start = Date.now();
  res.on('finish', () => {
    const duration = (Date.now() - start) / 1000;
    const route = req.route ? req.route.path : req.path;
    httpRequestsTotal.inc({ method: req.method, route, status: res.statusCode });
    httpRequestDuration.observe({ method: req.method, route, status: res.statusCode }, duration);
  });
  next();
});

// --- BASE DE DONNÉES ---
const pool = new Pool({
  host: process.env.DB_HOST || 'localhost',
  user: process.env.DB_USER || 'postgres',
  password: process.env.DB_PASSWORD || 'postgres',
  database: process.env.DB_NAME || 'greenlogistics',
  port: parseInt(process.env.DB_PORT || '5432'),
  // Gérer la connexion initiale
  connectionTimeoutMillis: 5000,
});

// Initialisation de la BDD
async function initDb() {
  let retries = 5;
  while (retries > 0) {
    try {
      const client = await pool.connect();
      dbConnectionStatus.set(1);
      console.log('Connecté à PostgreSQL avec succès');
      
      // Table parcels
      await client.query(`
        CREATE TABLE IF NOT EXISTS parcels (
          id VARCHAR(50) PRIMARY KEY,
          name VARCHAR(255) NOT NULL,
          recipient_email VARCHAR(255) NOT NULL,
          dest_lat DOUBLE PRECISION NOT NULL,
          dest_lng DOUBLE PRECISION NOT NULL,
          status VARCHAR(50) DEFAULT 'created',
          notified_at TIMESTAMP DEFAULT NULL,
          created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        );
      `);

      // Table tracking_points
      await client.query(`
        CREATE TABLE IF NOT EXISTS tracking_points (
          id SERIAL PRIMARY KEY,
          parcel_id VARCHAR(50) REFERENCES parcels(id) ON DELETE CASCADE,
          latitude DOUBLE PRECISION NOT NULL,
          longitude DOUBLE PRECISION NOT NULL,
          timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        );
      `);

      client.release();
      console.log('Schéma de base de données validé');
      break;
    } catch (err) {
      dbConnectionStatus.set(0);
      console.error(`Erreur connexion BDD. Tentatives restantes: ${retries - 1}`, err.message);
      retries -= 1;
      await new Promise(res => setTimeout(res, 5000));
    }
  }
}

// --- KAFKA CONSUMER ---
const kafkaBroker = process.env.KAFKA_BROKER || 'localhost:9092';
const kafka = new Kafka({
  clientId: 'delivery-service',
  brokers: [kafkaBroker],
  retry: {
    initialRetryTime: 300,
    retries: 10
  }
});

const consumer = kafka.consumer({ groupId: 'delivery-service-group' });

async function initKafka() {
  let retries = 5;
  while (retries > 0) {
    try {
      await consumer.connect();
      kafkaConsumerStatus.set(1);
      console.log('Connecté à Redpanda/Kafka avec succès');
      await consumer.subscribe({ topic: 'gps-location-events', fromBeginning: true });
      console.log('Souscrit au topic gps-location-events');

      await consumer.run({
        eachMessage: async ({ topic, partition, message }) => {
          try {
            const data = JSON.parse(message.value.toString());
            const { parcel_id, latitude, longitude, timestamp } = data;
            
            if (!parcel_id || !latitude || !longitude) {
              console.warn('Message GPS invalide reçu:', data);
              return;
            }

            // Insérer la position dans la table tracking_points
            await pool.query(
              'INSERT INTO tracking_points (parcel_id, latitude, longitude, timestamp) VALUES ($1, $2, $3, $4)',
              [parcel_id, latitude, longitude, timestamp ? new Date(timestamp) : new Date()]
            );

            // Mettre à jour le statut du colis s'il passe en transit
            await pool.query(
              "UPDATE parcels SET status = 'in_transit' WHERE id = $1 AND status = 'created'",
              [parcel_id]
            );

            console.log(`Position GPS enregistrée pour le colis ${parcel_id}: (${latitude}, ${longitude})`);
          } catch (err) {
            console.error('Erreur traitement message GPS:', err.message);
          }
        },
      });
      break;
    } catch (err) {
      kafkaConsumerStatus.set(0);
      console.error(`Erreur connexion Redpanda/Kafka. Tentatives restantes: ${retries - 1}`, err.message);
      retries -= 1;
      await new Promise(res => setTimeout(res, 5000));
    }
  }
}

// --- ENDPOINTS API ---

// Exposer les métriques Prometheus
app.get('/metrics', async (req, res) => {
  try {
    res.set('Content-Type', client.register.contentType);
    res.end(await client.register.metrics());
  } catch (err) {
    res.status(500).end(err);
  }
});

// Créer un colis
app.post('/parcels', async (req, res) => {
  const { id, name, recipient_email, dest_lat, dest_lng } = req.body;
  if (!id || !name || !recipient_email || dest_lat === undefined || dest_lng === undefined) {
    return res.status(400).json({ error: 'Champs manquants' });
  }

  try {
    const result = await pool.query(
      'INSERT INTO parcels (id, name, recipient_email, dest_lat, dest_lng) VALUES ($1, $2, $3, $4, $5) RETURNING *',
      [id, name, recipient_email, dest_lat, dest_lng]
    );
    res.status(201).json(result.rows[0]);
  } catch (err) {
    console.error('Erreur création colis:', err.message);
    if (err.code === '23505') {
      res.status(409).json({ error: 'Un colis avec cet ID existe déjà' });
    } else {
      res.status(500).json({ error: 'Erreur serveur' });
    }
  }
});

// Liste de tous les colis
app.get('/parcels', async (req, res) => {
  try {
    const result = await pool.query('SELECT * FROM parcels ORDER BY created_at DESC');
    res.json(result.rows);
  } catch (err) {
    console.error('Erreur liste colis:', err.message);
    res.status(500).json({ error: 'Erreur serveur' });
  }
});

// Détails d'un colis (avec sa dernière position)
app.get('/parcels/:id', async (req, res) => {
  try {
    const parcelResult = await pool.query('SELECT * FROM parcels WHERE id = $1', [req.params.id]);
    if (parcelResult.rows.length === 0) {
      return res.status(404).json({ error: 'Colis non trouvé' });
    }

    const lastGpsResult = await pool.query(
      'SELECT latitude, longitude, timestamp FROM tracking_points WHERE parcel_id = $1 ORDER BY timestamp DESC LIMIT 1',
      [req.params.id]
    );

    const parcel = parcelResult.rows[0];
    parcel.last_position = lastGpsResult.rows.length > 0 ? lastGpsResult.rows[0] : null;
    
    res.json(parcel);
  } catch (err) {
    console.error('Erreur détails colis:', err.message);
    res.status(500).json({ error: 'Erreur serveur' });
  }
});

// Historique de route d'un colis
app.get('/parcels/:id/route', async (req, res) => {
  try {
    const routeResult = await pool.query(
      'SELECT latitude, longitude, timestamp FROM tracking_points WHERE parcel_id = $1 ORDER BY timestamp ASC',
      [req.params.id]
    );
    res.json(routeResult.rows);
  } catch (err) {
    console.error('Erreur route colis:', err.message);
    res.status(500).json({ error: 'Erreur serveur' });
  }
});

// Mettre à jour le statut du colis
app.patch('/parcels/:id/status', async (req, res) => {
  const { status } = req.body;
  if (!status) {
    return res.status(400).json({ error: 'Statut manquant' });
  }

  try {
    const result = await pool.query(
      'UPDATE parcels SET status = $1 WHERE id = $2 RETURNING *',
      [status, req.params.id]
    );
    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Colis non trouvé' });
    }
    res.json(result.rows[0]);
  } catch (err) {
    console.error('Erreur mise à jour statut:', err.message);
    res.status(500).json({ error: 'Erreur serveur' });
  }
});

// --- DEMARRAGE SERVEUR ---
app.listen(port, async () => {
  console.log(`delivery-service démarré sur le port ${port}`);
  await initDb();
  await initKafka();
});
