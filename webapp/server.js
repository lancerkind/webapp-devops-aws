const express = require('express');
const app = express();
// Webapp should run on 5173 by default, overridable via PORT env var
const PORT = process.env.PORT || 5173;

// Config endpoint to share service URL with the client
const SERVICE_URL = process.env.SERVICE_URL || 'http://localhost:5183';

// Serve static files from the directory where this file resides
app.use(express.static(__dirname));

// Expose minimal runtime config to the frontend
app.get('/config', (req, res) => {
    res.json({ serviceUrl: SERVICE_URL });
});

// Basic health endpoint for monitoring
app.get('/healthz', (req, res) => {
    res.status(200).send('OK');
});

app.listen(PORT, () => {
    console.log(`Server running on port ${PORT}`);
});