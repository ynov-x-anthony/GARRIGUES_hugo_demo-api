'use strict';

/*
 * demo-notifier - second service metier du fil rouge.
 * Responsabilite unique : recevoir une notification de l'API et la logger
 * (simulateur d'email / Slack). Il ne connait ni la base, ni le code de api.
 *
 * Variables d'environnement :
 *   PORT   port d'ecoute   (def: 4000)
 */

const express = require('express');

const PORT = Number(process.env.PORT || 4000);

const app = express();
app.use(express.json());

// Liveness : sert aussi au HEALTHCHECK du Dockerfile.
app.get('/health', (_req, res) => res.json({ status: 'UP' }));

// Appele par api apres un POST /products reussi. Best-effort cote api :
// une erreur ici ne doit jamais faire echouer la creation du produit.
app.post('/notify', (req, res) => {
  console.log(`[notifier] nouveau produit : ${JSON.stringify(req.body)}`);
  res.status(202).json({ received: true });
});

const server = app.listen(PORT, () => {
  console.log(JSON.stringify({ level: 'info', msg: 'notifier started', port: PORT }));
});

// PID 1 dans le conteneur : arret propre sur docker stop.
function shutdown(sig) {
  console.log(JSON.stringify({ level: 'info', msg: 'shutting down', sig }));
  server.close(() => process.exit(0));
  setTimeout(() => process.exit(1), 8000).unref();
}
process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));
