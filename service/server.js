const express = require('express');
const morgan = require('morgan');
const cors = require('cors');

const app = express();

// Config
const PORT = Number(process.env.PORT) || 5183;

// CORS configuration
// Allow localhost (any port) and Elastic Beanstalk environment hostnames that match
// asgardeo-webapp-demo-env.[any].us-east-1.elasticbeanstalk.com
const allowedOriginRegexes = [
  /^http:\/\/localhost(?::\d+)?$/,
  /^https?:\/\/asgardeo-webapp-demo-env\.[^/.]+\.us-east-1\.elasticbeanstalk\.com$/
];

app.use(morgan('dev'));
app.use(cors({
  origin: (origin, callback) => {
    // Allow same-origin or non-browser requests (no origin header)
    if (!origin) return callback(null, true);
    const ok = allowedOriginRegexes.some(rgx => rgx.test(origin));
    if (ok) return callback(null, true);
    return callback(new Error('Not allowed by CORS'));
  }
}));

// Health endpoints
// Elastic Beanstalk default expects root path to be healthy
app.get('/', (req, res) => {
  res.type('text/plain').status(200).send('OK');
});

// Current date/time endpoint
app.get('/api/time', (req, res) => {
  try {
    const now = new Date().toISOString();
    res.status(200).json({ now });
  } catch (e) {
    res.status(500).json({ error: 'Internal Server Error' });
  }
});

app.listen(PORT, () => {
  console.log(`[service] Listening on port ${PORT}`);
});
