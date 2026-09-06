#!/usr/bin/env bash
# Rebuilds the Wazuh + TheHive/Cortex/DVWA/Juice-Shop stack on the new docker01 VM from
# the backup taken during the ARM->x86 migration (docker-lab/configs/, plus the
# unredacted secrets/volume tarballs in ~/migration-export/, which must already be on
# this machine -- see migration/proxmox-migration-plan.md phase C3).
#
# Idempotent-ish: safe to re-run, but assumes ~/migration-export/ is present and the
# target directories (~/wazuh-docker, ~/docker) don't already exist with conflicting
# content. Run as the `wazuh` user (needs docker group membership or sudo for docker).
set -euo pipefail

EXPORT_DIR="$HOME/migration-export"
WAZUH_VERSION="v4.14.7"

if [ ! -d "$EXPORT_DIR" ]; then
    echo "ERROR: $EXPORT_DIR not found. Copy it here first (phase C3 of the migration plan)." >&2
    exit 1
fi

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

# ---------------------------------------------------------------------------
log "Cloning wazuh-docker $WAZUH_VERSION"
if [ ! -d "$HOME/wazuh-docker" ]; then
    git clone https://github.com/wazuh/wazuh-docker.git -b "$WAZUH_VERSION" "$HOME/wazuh-docker"
fi
cd "$HOME/wazuh-docker/single-node"

log "Generating fresh indexer TLS certs (not reusing old ones -- see migration plan Phase D3)"
docker compose -f generate-indexer-certs.yml run --rm generator

log "Restoring the real (unredacted) compose file and indexer users from migration-export"
cp "$EXPORT_DIR/wazuh-docker/docker-compose.yml" ./docker-compose.yml
cp "$EXPORT_DIR/wazuh-docker/internal_users.yml" ./config/wazuh_indexer/internal_users.yml

log "Creating containers + named volumes without starting them (docker compose create)"
docker compose create

log "Restoring named volumes from tarballs"
for tarball in "$EXPORT_DIR"/volumes/single-node_*.tar.gz; do
    volname=$(basename "$tarball" .tar.gz)
    log "  -> $volname"
    docker run --rm \
        -v "${volname}:/data" \
        -v "$EXPORT_DIR/volumes:/backup:ro" \
        alpine sh -c "cd /data && tar xzf /backup/${volname}.tar.gz"
done
# This restores /var/ossec/etc (client.keys, rules, decoders, ossec.conf incl. the
# custom-w2thive <integration> block) and /var/ossec/integrations (custom-w2thive +
# custom-w2thive.py) in one shot, since those were backed up as whole named volumes.

log "Starting the Wazuh stack"
docker compose start

log "Waiting for the manager container to be up"
sleep 20
MANAGER_CID=$(docker compose ps -q wazuh.manager)

log "Reinstalling thehive4py into the manager's Python env (not on a volume, lost on every recreate)"
docker exec "$MANAGER_CID" /var/ossec/framework/python/bin/python3 -m pip install thehive4py==2.0.3

log "Re-applying ownership/permissions on the integration scripts (belt and suspenders after the volume restore)"
docker exec "$MANAGER_CID" chown root:wazuh /var/ossec/integrations/custom-w2thive /var/ossec/integrations/custom-w2thive.py
docker exec "$MANAGER_CID" chmod 750 /var/ossec/integrations/custom-w2thive /var/ossec/integrations/custom-w2thive.py

# Same root cause, different files: the volume restore preserves whatever UID/GID owned these on
# the source (confirmed once as a stray 1000:1000 instead of wazuh:wazuh), which makes analysisd
# silently ignore them ("Could not open file ... Permission denied") -- silent because Wazuh keeps
# running fine on its stock rules either way, so this is easy to miss until a real custom rule
# mysteriously never fires.
docker exec "$MANAGER_CID" chown wazuh:wazuh /var/ossec/etc/rules/local_rules.xml /var/ossec/etc/decoders/local_decoder.xml

# The wazuh_etc volume tarball is not guaranteed to carry the <integration> block --
# confirmed once during the Proxmox migration that the restored ossec.conf had the
# integration scripts but not the config block referencing them (wazuh-integratord
# didn't even start). Check explicitly instead of trusting the volume restore silently.
if ! docker exec "$MANAGER_CID" grep -q "custom-w2thive" /var/ossec/etc/ossec.conf; then
    echo ""
    echo "WARNING: the <integration> block for custom-w2thive is missing from ossec.conf"
    echo "on the restored manager. Append it manually (see"
    echo "docker-lab/configs/wazuh-manager/ossec.conf.integration-block.snippet) with the"
    echo "real API key and docker01's IP, then: docker exec $MANAGER_CID /var/ossec/bin/wazuh-control restart"
    echo ""
fi

# ---------------------------------------------------------------------------
log "Cloning StrangeBee docker repo (TheHive/Cortex, 'testing' profile)"
if [ ! -d "$HOME/docker" ]; then
    git clone https://github.com/StrangeBeeCorp/docker.git "$HOME/docker"
fi
cd "$HOME/docker/testing"

log "Restoring the real .env"
cp "$EXPORT_DIR/thehive-testing/.env" ./.env

log "Restoring Cassandra + Elasticsearch bind-mount data (these are bind mounts, not named volumes)"
mkdir -p ./cassandra/data ./elasticsearch/data
tar xzf "$EXPORT_DIR/volumes/thehive-testing_cassandra-data.tar.gz" -C ./cassandra/data
tar xzf "$EXPORT_DIR/volumes/thehive-testing_elasticsearch-data.tar.gz" -C ./elasticsearch/data

log "Starting TheHive/Cortex/nginx"
docker compose up -d

log "Restoring the TheHive-integration scripts (already restored into the manager via the wazuh_integrations volume above -- this is just the local copy for reference/redeploy)"
mkdir -p "$HOME/thehive-integration"
cp "$EXPORT_DIR/thehive-integration/custom-w2thive" "$EXPORT_DIR/thehive-integration/custom-w2thive.py" "$HOME/thehive-integration/"

cat <<'EOF'

Done. Verify:
  docker compose -f ~/wazuh-docker/single-node/docker-compose.yml ps
  docker compose -f ~/docker/testing/docker-compose.yml ps
  docker exec <manager> /var/ossec/bin/agent_control -l    # once DC01/WS01 agents enroll

IMPORTANT: because the Cassandra volume was restored (not recreated fresh), the TheHive
API key baked into the manager's ossec.conf <integration> block (restored via the
wazuh_etc volume) should still be valid. If TheHive logins/alerts don't work, the
Cassandra restore likely failed silently -- generate a new API key in the TheHive UI and
update the <integration> block per docker-lab/configs/wazuh-manager/ossec.conf.integration-block.snippet
and the migration plan's Phase D4 coupling note.

DVWA/Juice Shop are NOT started by this script -- they're the pentest-profile targets
from docker-lab/03-dvwa-juiceshop.md, bring them up separately with:
  docker compose --profile pentest up -d
EOF
