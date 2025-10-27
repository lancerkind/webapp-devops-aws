const express = require('express');
const app = express();
const PORT = process.env.PORT || 8080;

// Serve static files from the directory where this file resides
app.use(express.static(__dirname));

// Basic health endpoint for monitoring
app.get('/healthz', (req, res) => {
    res.status(200).send('OK');
});

app.listen(PORT, () => {
    console.log(`Server running on port ${PORT}`);
});