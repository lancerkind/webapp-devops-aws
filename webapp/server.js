const express = require('express');
const app = express();
// Webapp should run on 5173 by default, overridable via PORT env var
const PORT = process.env.PORT || 5173;

// Config for backend service (private/internal EB ALB)
const SERVICE_URL = process.env.SERVICE_URL || 'http://localhost:5183';

// Serve static files from the directory where this file resides
app.use(express.static(__dirname));

// Expose minimal runtime config to the frontend (kept for visibility)
app.get('/config', (req, res) => {
  res.json({ serviceUrl: SERVICE_URL });
});

// Server-side proxy to the service so the browser never calls the service directly.
// This allows the service ALB to remain internal and avoids CORS issues.
app.get('/api/time', async (req, res) => {
  try {
    const base = SERVICE_URL.replace(/\/$/, '');
    const r = await fetch(`${base}/api/time`, { headers: { 'Accept': 'application/json' } });
    if (!r.ok) {
      return res.status(r.status).send(await r.text());
    }
    const data = await r.json();
    res.status(200).json(data);
  } catch (err) {
    res.status(502).json({ error: 'Bad Gateway', detail: err.message });
  }
});

// Basic health endpoint for monitoring
app.get('/healthz', (req, res) => {
  res.status(200).send('OK');
});

// For any other request, send the index.html (SPA support)
const path = require('path');
app.get('*', (req, res) => {
    res.sendFile(path.join(__dirname, 'index.html'));
});

app.listen(PORT, () => {
  console.log(`Server running on port ${PORT}`);
});