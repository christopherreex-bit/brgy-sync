const express = require('express');
const path = require('path');
const fs = require('fs');
const app = express();
const PORT = process.env.PORT || 3000;

// The Flutter web build lives at ../build/web relative to this script
// On Heroku, the whole project root is deployed, so build/web exists
const STATIC_DIR = path.join(__dirname, 'build', 'web');

// Verify the build directory exists
if (!fs.existsSync(STATIC_DIR)) {
  console.error('ERROR: build/web directory not found.');
  console.error('Run "flutter build web --release" first.');
  process.exit(1);
}

// Serve static files
app.use(express.static(STATIC_DIR));

// SPA routing — all non-file routes go to index.html
app.get('*', (req, res) => {
  res.sendFile(path.join(STATIC_DIR, 'index.html'));
});

app.listen(PORT, () => {
  console.log(`BrgySync running on port ${PORT}`);
});
