# Running the relay server

Online matches go through a small relay server: the host and guest both connect to it, it pairs
them by room code and passes their messages along. It never looks inside game messages and keeps
nothing on disk.

## Locally

```bash
swift run TanksRelay                                  # listens on ws://0.0.0.0:8080/ws
TANKS_RELAY_URL=ws://localhost:8080/ws swift run TanksOfDoom
```

Start the game twice (two terminals) to play against yourself. Other Macs on your network can use
`ws://<your-mac's-IP>:8080/ws`.

Settings (environment variables):

| Variable | Default | Meaning |
|---|---|---|
| `PORT` | `8080` | TCP port to listen on |
| `ROOM_TTL` | `600` | Seconds a host may wait for a guest before the room is closed |

Fixed limits: 500 rooms, 64 KB per frame, 100 frames per second per connection.

## On a server

Any Linux VPS with Docker works (1 vCPU / 512 MB is plenty). Put TLS in front of it so players
connect with `wss://`.

```bash
git clone https://github.com/dpalmqvist/tanks-of-doom.git && cd tanks-of-doom
docker build -t tanks-relay .
docker run -d --restart unless-stopped --name tanks-relay -p 127.0.0.1:8080:8080 tanks-relay
```

Then point a domain at the server and let [Caddy](https://caddyserver.com) handle certificates.
`/etc/caddy/Caddyfile`:

```
relay.example.com {
    reverse_proxy /ws 127.0.0.1:8080
}
```

`sudo systemctl reload caddy`, and the relay is at `wss://relay.example.com/ws`. Put that URL in
`RelayConfig.defaultURL` (`Sources/TanksOfDoom/RelayConnection.swift`) before building a release.

## Updating

Bump `TanksNet.protocolVersion` whenever the message format changes. The relay refuses games with
a different version, so deploy the new relay together with the new game release.
