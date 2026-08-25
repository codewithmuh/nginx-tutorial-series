// Deliberately dependency-free: a backend for Nginx to proxy to.
const http = require('http');

http.createServer((req, res) => {
  const headers = {
    'Content-Type': 'application/json',
    // Echo the trace id Nginx generated, so you can follow one request
    // across both logs (chapter 11).
    'X-Request-ID': req.headers['x-request-id'] || 'none',
  };

  if (req.url === '/api/hello') {
    res.writeHead(200, headers);
    res.end(JSON.stringify({
      message: 'Hello from the API container',
      served_by: 'node:' + process.version,
      // These only look right because Nginx forwards them (chapter 04).
      client_ip: req.headers['x-real-ip'] || 'not forwarded',
      forwarded_proto: req.headers['x-forwarded-proto'] || 'not forwarded',
      request_id: req.headers['x-request-id'] || 'not forwarded',
    }, null, 2) + '\n');
    return;
  }

  if (req.url === '/health') {
    res.writeHead(200, { 'Content-Type': 'text/plain' });
    res.end('ok\n');
    return;
  }

  res.writeHead(404, headers);
  res.end(JSON.stringify({ error: 'not found', path: req.url }) + '\n');
}).listen(3000, () => console.log('api listening on :3000'));
