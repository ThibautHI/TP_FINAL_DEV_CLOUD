require('dotenv').config();
const express = require('express');
const { Pool } = require('pg');
const { Kafka } = require('kafkajs');
const nodemailer = require('nodemailer');
const client = require('prom-client');

const app = express();
const port = process.env.PORT || 3002;

// --- PROMETHEUS METRICS ---
const collectDefaultMetrics = client.collectDefaultMetrics;
collectDefaultMetrics({ register: client.register });

const notificationsSentTotal = new client.Counter({
  name: 'notifications_sent_total',
  help: 'Total number of email notifications sent via MailHog'
});

const notificationFailuresTotal = new client.Counter({
  name: 'notification_failures_total',
  help: 'Total number of failed notification attempts'
});

const distanceCalculationsTotal = new client.Counter({
  name: 'distance_calculations_total',
  help: 'Total number of distance calculations executed'
});

const dbConnectionStatus = new client.Gauge({
  name: 'notification_service_db_connected',
  help: 'Database connection status (1 = connected, 0 = disconnected)'
});

const kafkaConsumerStatus = new client.Gauge({
  name: 'notification_service_kafka_consumer_connected',
  help: 'Kafka consumer connection status (1 = connected, 0 = disconnected)'
});

// --- BASE DE DONNÉES ---
const pool = new Pool({
  host: process.env.DB_HOST || 'localhost',
  user: process.env.DB_USER || 'postgres',
  password: process.env.DB_PASSWORD || 'postgres',
  database: process.env.DB_NAME || 'greenlogistics',
  port: parseInt(process.env.DB_PORT || '5432'),
  connectionTimeoutMillis: 5000,
});

// Vérifier la connexion BDD
async function checkDbConnection() {
  try {
    const client = await pool.connect();
    dbConnectionStatus.set(1);
    client.release();
    console.log('[Notification] Connecté à PostgreSQL');
  } catch (err) {
    dbConnectionStatus.set(0);
    console.error('[Notification] Erreur connexion PostgreSQL:', err.message);
  }
}

// --- CONFIGURATION SMTP (MAILHOG) ---
const transporter = nodemailer.createTransport({
  host: process.env.SMTP_HOST || 'localhost',
  port: parseInt(process.env.SMTP_PORT || '1025'),
  secure: false,
  tls: {
    rejectUnauthorized: false
  }
});

// --- FORMULE DE HAVERSINE ---
function calculateDistance(lat1, lon1, lat2, lon2) {
  const R = 6371; // Rayon de la Terre en km
  const dLat = (lat2 - lat1) * Math.PI / 180;
  const dLon = (lon2 - lon1) * Math.PI / 180;
  const a = 
    Math.sin(dLat/2) * Math.sin(dLat/2) +
    Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) * 
    Math.sin(dLon/2) * Math.sin(dLon/2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1-a));
  return R * c; // Distance en km
}

// --- KAFKA CONSUMER ---
const kafkaBroker = process.env.KAFKA_BROKER || 'localhost:9092';
const kafka = new Kafka({
  clientId: 'notification-service',
  brokers: [kafkaBroker],
  retry: {
    initialRetryTime: 300,
    retries: 10
  }
});

const consumer = kafka.consumer({ groupId: 'notification-service-group' });

async function initKafka() {
  let retries = 5;
  while (retries > 0) {
    try {
      await consumer.connect();
      kafkaConsumerStatus.set(1);
      console.log('[Notification] Connecté à Redpanda/Kafka');
      await consumer.subscribe({ topic: 'gps-location-events', fromBeginning: true });

      await consumer.run({
        eachMessage: async ({ topic, partition, message }) => {
          try {
            const data = JSON.parse(message.value.toString());
            const { parcel_id, latitude, longitude } = data;

            if (!parcel_id || latitude === undefined || longitude === undefined) return;

            // Récupérer le colis en BDD
            const res = await pool.query(
              'SELECT name, recipient_email, dest_lat, dest_lng, notified_at, status FROM parcels WHERE id = $1',
              [parcel_id]
            );

            if (res.rows.length === 0) {
              console.log(`[Notification] Colis ${parcel_id} non trouvé en BDD`);
              return;
            }

            const parcel = res.rows[0];

            // Si déjà notifié ou déjà livré, ignorer
            if (parcel.notified_at || parcel.status === 'delivered') return;

            // Calculer la distance
            distanceCalculationsTotal.inc();
            const distance = calculateDistance(latitude, longitude, parcel.dest_lat, parcel.dest_lng);
            
            console.log(`[Notification] Distance pour le colis ${parcel_id} : ${distance.toFixed(3)} km`);

            // Seuil de notification : 0.5 km (environ 5 minutes à vélo/voiture en ville)
            if (distance <= 0.5) {
              await sendEmailNotification(parcel_id, parcel);
            }
          } catch (err) {
            console.error('[Notification] Erreur traitement message:', err.message);
          }
        }
      });
      break;
    } catch (err) {
      kafkaConsumerStatus.set(0);
      console.error(`[Notification] Erreur connexion Kafka. Tentatives restantes: ${retries - 1}`, err.message);
      retries -= 1;
      await new Promise(res => setTimeout(res, 5000));
    }
  }
}

// Envoyer l'email
async function sendEmailNotification(parcelId, parcel) {
  const mailOptions = {
    from: '"GreenLogistics Tracking" <alerts@greenlogistics.local>',
    to: parcel.recipient_email,
    subject: `🟢 Votre colis "${parcel.name}" arrive dans moins de 5 minutes !`,
    html: `
      <div style="font-family: 'Outfit', Arial, sans-serif; max-width: 600px; margin: 0 auto; padding: 20px; border: 1px solid #e5e7eb; border-radius: 12px; background-color: #f9fafb;">
        <h2 style="color: #10b981; margin-bottom: 10px;">Votre livraison est toute proche !</h2>
        <p style="font-size: 16px; color: #374151;">Bonjour,</p>
        <p style="font-size: 16px; color: #374151;">Bonne nouvelle ! Le livreur écologique transportant votre colis <strong>"${parcel.name}"</strong> (ID: #${parcelId}) est à moins de <strong>500 mètres</strong> de votre domicile.</p>
        
        <div style="margin: 20px 0; padding: 15px; background-color: #ecfdf5; border-left: 4px solid #10b981; border-radius: 4px;">
          <h4 style="margin: 0 0 5px 0; color: #065f46;">Temps d'attente estimé</h4>
          <p style="margin: 0; font-size: 15px; color: #047857; font-weight: bold;">Moins de 5 minutes</p>
        </div>

        <p style="font-size: 14px; color: #6b7280; margin-top: 20px;">Vous pouvez suivre la position en direct sur notre plateforme.</p>
        <hr style="border: 0; border-top: 1px solid #e5e7eb; margin: 20px 0;" />
        <p style="font-size: 12px; color: #9ca3af; text-align: center;">GreenLogistics - Livraison Éco-responsable Dernière Mile</p>
      </div>
    `
  };

  try {
    await transporter.sendMail(mailOptions);
    notificationsSentTotal.inc();
    console.log(`[Notification] E-mail envoyé avec succès à ${parcel.recipient_email} pour le colis ${parcelId}`);

    // Mettre à jour notified_at en BDD pour éviter les renvois
    await pool.query(
      'UPDATE parcels SET notified_at = NOW() WHERE id = $1',
      [parcelId]
    );
  } catch (err) {
    notificationFailuresTotal.inc();
    console.error(`[Notification] Échec de l'envoi de l'e-mail pour le colis ${parcelId}:`, err.message);
  }
}

// --- ENDPOINTS EXPRESS (METRICS & HEALTH) ---

app.get('/healthz', (req, res) => {
  res.status(200).json({ status: 'UP' });
});

app.get('/metrics', async (req, res) => {
  try {
    res.set('Content-Type', client.register.contentType);
    res.end(await client.register.metrics());
  } catch (err) {
    res.status(500).end(err);
  }
});

// --- DEMARRAGE ---
app.listen(port, async () => {
  console.log(`notification-service démarré sur le port ${port}`);
  await checkDbConnection();
  await initKafka();
});
