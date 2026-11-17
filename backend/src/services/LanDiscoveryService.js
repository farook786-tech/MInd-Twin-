const dgram = require('dgram');
const os = require('os');

/**
 * LAN discovery responder.
 *
 * Phones on the same Wi-Fi cannot know the laptop's (DHCP-assigned) IP.
 * The app broadcasts DISCOVERY_REQUEST on UDP DISCOVERY_PORT; this service
 * replies directly to the sender with the HTTP port the API is listening on.
 * The phone then uses the reply's source address, so no IP is hardcoded and
 * nothing scans the subnet.
 *
 * Disable with LAN_DISCOVERY_ENABLED=false (e.g. on cloud deployments).
 */
const DISCOVERY_REQUEST = 'MINDTWIN_DISCOVER_V1';
const DEFAULT_DISCOVERY_PORT = 47777;

function lanAddresses() {
  const result = [];
  for (const [name, addrs] of Object.entries(os.networkInterfaces())) {
    for (const addr of addrs || []) {
      if (addr.family === 'IPv4' && !addr.internal) {
        result.push({ name, address: addr.address });
      }
    }
  }
  return result;
}

function startLanDiscovery(getHttpPort) {
  if (String(process.env.LAN_DISCOVERY_ENABLED).toLowerCase() === 'false') {
    return null;
  }

  const discoveryPort = Number(process.env.LAN_DISCOVERY_PORT || DEFAULT_DISCOVERY_PORT);
  const socket = dgram.createSocket({ type: 'udp4', reuseAddr: true });

  socket.on('message', (msg, rinfo) => {
    if (msg.toString('utf8').trim() !== DISCOVERY_REQUEST) return;
    const httpPort = getHttpPort();
    if (!httpPort) return;
    const reply = Buffer.from(
      JSON.stringify({ service: 'mindtwin-backend', port: httpPort })
    );
    socket.send(reply, rinfo.port, rinfo.address);
  });

  socket.on('error', (err) => {
    console.warn(`[LAN] Discovery disabled (UDP ${discoveryPort}): ${err.message}`);
    try { socket.close(); } catch (_) {}
  });

  socket.bind(discoveryPort, () => {
    console.log(`📡 LAN discovery listening on UDP ${discoveryPort}`);
  });

  return socket;
}

module.exports = { startLanDiscovery, lanAddresses, DISCOVERY_REQUEST, DEFAULT_DISCOVERY_PORT };
