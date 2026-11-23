# Home server

One front door for every app on the Mac mini. The Mac has one IP address, so a single
**Caddy** container owns ports 80 and 443 and sends each request to the right app by the
name in the address. Every app gets **https** with a certificate from Caddy's own private
certificate authority, the **Home Server CA**:

```
https://kids-dashboard.local  ─┐
https://recipes.local         ─┼─> Mac mini :443 ─> Caddy ─┬─> kids-dashboard:8787
https://<mac-ip>              ─┘   (Home Server CA)        └─> recipes-web:3000
http://...  -> redirects to https (except /home-ca.crt, the CA download)
```

- Each app runs in its own Docker container, in its own folder, with its own
  `docker-compose.yml`. Apps don't publish ports 80/443; they join the shared Docker
  network `home-proxy`, and Caddy reaches them there by container name.
- Each app gets a `name.local` address. A small LaunchAgent announces every name with
  macOS's built-in Bonjour (`dns-sd`), so iPhone, iPad, Mac, Windows and recent Android
  find them on the home Wi-Fi with no router changes.
- Certificates: public CAs (Let's Encrypt) can't issue for `.local` names, so Caddy runs
  its own CA (`local_certs`). It lives only in `./caddy-data` on this Mac. Each device
  trusts it once; after that every current and future app shows the padlock. App
  certificates renew by themselves; the CA lasts 10 years.
- Home network only. Nothing is exposed to the internet.

## Set up (once per Mac)

Docker Desktop must be installed and running. Caddy runs inside Docker; nothing else to install.

```bash
cd ~/VsCode/home-server
bash bin/setup.sh
```

It saves this Mac's IP in `.env`, creates the `home-proxy` network, starts Caddy on ports
80 and 443, creates the CA (public part copied to `certs/home-ca.crt`), and installs the
name announcer (starts at login). Safe to run again: after `git pull`, or if the Mac's IP
changed. It also upgrades app files from the older http-only version.

**Back up `caddy-data/`** privately (it holds the CA's private key). Never commit it.

## Trust the certificate (once per device)

Download link (plain http on purpose): `http://<mac-ip>/home-ca.crt` or
`http://<any-app>.local/home-ca.crt`.

| Device | Steps |
|---|---|
| This Mac | `bash bin/trust-this-mac.sh` |
| Other Mac | download, then `bash bin/trust-this-mac.sh ~/Downloads/home-ca.crt`, or Keychain Access > System > the cert > Trust > Always Trust |
| iPhone / iPad | open the link in **Safari** > Allow; Settings > General > VPN & Device Management > install the profile; Settings > General > About > **Certificate Trust Settings** > turn it on |
| Android | download in Chrome; Settings > Security & privacy > More security & privacy > Encryption & credentials > Install a certificate > CA certificate |

The certificate is named "Home Server - 2026 ECC Root".

## Add an app

1. In the app's `docker-compose.yml`, give the web container a fixed name and put it on
   the shared network. Don't publish ports 80/443:

   ```yaml
   services:
     web:
       container_name: recipes-web
       # ports: ["8790:3000"]     # optional direct backup port
       networks: [default, home-proxy]

   networks:
     home-proxy:
       external: true
   ```

2. Start it (`docker compose up -d` in the app's folder), then give it a name:

   ```bash
   bash bin/add-app.sh recipes recipes-web:3000
   ```

   `https://recipes.local` works a few seconds later, with its own certificate. The port
   is the one the app listens on **inside** its container.

Options:

- `--default` also sends the Mac's plain IP address (`https://192.168.1.250`) to this app.
  Only one app can be the default; the kids dashboard is.
- `--alias some.other.name` adds another hostname, for devices whose DNS knows it.

## Other commands

| What | Command |
|---|---|
| List names and where they go | `bash bin/list-apps.sh` |
| Remove a name | `bash bin/remove-app.sh recipes` |
| Caddy log | `docker logs -f home-proxy` |
| Name announcer log | `tail -50 ~/Library/Logs/home-server-mdns.log` |
| Restart Caddy | `docker compose restart` |
| Stop everything here | `bash bin/setup.sh --remove` |
| Stop trusting the CA on this Mac | `bash bin/trust-this-mac.sh --remove` |

## Files

| File | What it is | In git? |
|---|---|---|
| `docker-compose.yml` | the Caddy container (ports 80, 443) | yes |
| `Caddyfile` | global settings (private CA, redirects, CA download); loads every `sites/*.caddy` | yes |
| `sites/<name>.caddy` | one per app, written by `add-app.sh` | yes |
| `sites/_default.caddy` | what the plain IP address shows | yes |
| `bin/mdns-advertise.sh` | announces every `sites/<name>.caddy` as `<name>.local`, re-checks every 30 s | yes |
| `caddy-data/` | the CA (private key) and certificates | **never** |
| `certs/home-ca.crt` | the CA's public certificate | no |
| `.env` | `HOME_IP`, this Mac's IP | no |
| `~/Library/LaunchAgents/home.server.mdns.plist` | starts the announcer at login | no |

## If something goes wrong

- **Certificate warning.** That device doesn't trust the CA yet. On iPhone, check
  Certificate Trust Settings is on. A different Mac (say, a test laptop) has a different CA.
- **A name doesn't open.** `bash bin/list-apps.sh` shows it? `docker logs home-proxy`
  shows a "dial" error? Then the app container isn't on `home-proxy` or isn't running:
  `docker network inspect home-proxy` lists who's on it.
- **`.local` doesn't resolve but the IP works.** `tail ~/Library/Logs/home-server-mdns.log`.
- **`https://<ip>` warns but names work.** The IP changed: `bash bin/setup.sh`.
- **Port 80 or 443 busy.** Something else has it: `lsof -nP -iTCP:443 -sTCP:LISTEN`.
