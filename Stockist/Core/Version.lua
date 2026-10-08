local ADDON_NAME, Stockist = ...

Stockist.VERSION = "0.1.0"
-- Bump when the wire format or signing scheme changes. Clients on a different
-- protocol version ignore each other's readings.
Stockist.PROTOCOL_VERSION = 1
