#!/usr/bin/env bash

# script will be executed at "rc.local-like" level during first boot. rc.local-like means "very late in the boot sequence" 

set -euo pipefail

TEMPDIR="$(mktemp -d)"

cd "$TEMPDIR"

cat <<EOF > papatcher.go.md5
f6d1aed1ee406024fa3a7cb7d14f805e  papatcher.go
EOF

PAPATCHER_FILE="$TEMPDIR/papatcher.go"

curl -s -L -o "$PAPATCHER_FILE" https://bitbucket.org/papatcher/papatcher/raw/a7b8b4febb491d6fc6c45155b238fd42ee34fcc8/papatcher.go

md5sum -c papatcher.go.md5

perl -0777 -i.original -pe 's/\s+cacerts := x509.NewCertPool\(\)\n\s+worked := cacerts.AppendCertsFromPEM\(\[\]byte\(cacerts_pem\)\)\n\s+if !worked \{\n\s+panic\("could not parse CA certs"\)\n\s+\}\s+tr := &http.Transport\{\n\s+TLSClientConfig: &tls.Config\{ RootCAs: cacerts \},\s+\}/	tr := &http.Transport{}/igs' papatcher.go
perl -0777 -i.original -pe 's/import "crypto\/tls"//igs' papatcher.go
perl -0777 -i.original -pe 's/import "crypto\/x509"//igs' papatcher.go
perl -0777 -i.original -pe 's/urlroot = "http:\/\/uberent.com"/urlroot = "https:\/\/uberent.com"/igs' papatcher.go

mkdir -p /opt/local/bin
mkdir -p /opt/local/pa
GOCACHE="$(mktemp -d)" GOBIN=/opt/local/bin /snap/bin/go install "$PAPATCHER_FILE"

cat <<EOF > "$TEMPDIR/expect-script"
#!/usr/bin/env expect
set timeout 480
spawn /opt/local/bin/papatcher --dir=/opt/local/pa --stream=stable --update-only

expect "Ubername: "
send "imperatorpat\n"
expect "Password: "
send "UBER_ENTERTAINMENT_PASSWORD\n"
expect "Finished"
EOF

chmod +x "$TEMPDIR/expect-script"

"$TEMPDIR/expect-script"

mkdir -p /var/log/pa
chown -R paserver:paserver /var/log/pa
chown -R paserver:paserver /opt/local/pa

# Now with the server installed, set it up and run it via systemd:
# see https://planetaryannihilation.com/guides/hosting-a-local-server/
# and regarding the systemd location https://unix.stackexchange.com/a/367237

PA_UNIT_FILE="/etc/systemd/system/pa.service"
cat <<EOF > "$PA_UNIT_FILE"
[Unit]

Description=PA
After=network.target

[Service]
User=paserver

Environment=MINIDUMP_DIRECTORY=/var/log/pa/output

ExecStart=/opt/local/pa/stable/server \
--port 20545 \
--headless \
--allow-lan \
--mt-enabled \
--max-players 32 \
--max-spectators 5 \
--spectators 5 \
--empty-timeout 5 \
--replay-filename "UTCTIMESTAMP" \
--replay-timeout 180 \
--gameover-timeout 360 \
--server-name "patrickc server" \
--server-password "password" \
--game-mode "PAExpansion1:config" \
--output-dir /var/log/pa/output

StandardOutput=null
StandardError=null

Restart=always
RestartSec=5

NoNewPrivileges=yes
PrivateTmp=yes
PrivateDevices=yes

ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectControlGroups=yes
ProtectSystem=strict
ProtectHome=read-only
SystemCallFilter=~@mount
ReadOnlyPaths=/opt/local/pa
ReadWritePaths=/var/log/pa

[Install]
WantedBy=multi-user.target
EOF

systemctl enable pa
systemctl start pa
