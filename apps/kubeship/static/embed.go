package static

import "embed"

// Files contains the browser console assets baked into the binary.
//
//go:embed index.html app.css app.js
var Files embed.FS
