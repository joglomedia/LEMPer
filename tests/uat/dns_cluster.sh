#!/usr/bin/env bash
# Run the DNS acceptance test in three disposable Podman/systemd containers.
set -euo pipefail
image=${1:?Usage: bash tests/uat/dns_cluster.sh SYSTEMD_IMAGE}
cd "$(dirname "${BASH_SOURCE[0]}")/../.."
nodes=()
addresses=()
network=$(podman network create)
cleanup() {
    if ((${#nodes[@]})); then podman rm -f --time 1 "${nodes[@]}" >/dev/null; fi
    podman network rm "$network" >/dev/null
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

for role in primary secondary1 secondary2; do
    node=$(podman create --network "$network" --hostname "$role.dns-uat.test" \
        --systemd=always --cgroupns=private --tmpfs /run --tmpfs /tmp "$image")
    nodes+=("$node")
    podman start "$node" >/dev/null
    address=$(podman inspect --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$node")
    [[ "$address" =~ ^[0-9]+(\.[0-9]+){3}$ ]]
    addresses+=("$address")
    podman cp tests/uat/helpers.bash "$node:/root/helpers.bash"
    podman cp tests/uat/dns_prepare.sh "$node:/root/dns_prepare.sh"
done

primary=${nodes[0]}
release=/opt/lemper/local-dnsuat
podman exec "$primary" mkdir -p "$release"
COPYFILE_DISABLE=1 tar -cf - .env.dist bin lib scripts etc/knot | \
    podman exec -i "$primary" tar -xf - --no-same-owner -C "$release"
podman exec "$primary" bash /root/dns_prepare.sh primary "${addresses[@]}"
for index in 1 2; do
    peer=${addresses[index]}
    # Deliver the generated key on stdin, directly between the two fixtures.
    podman exec "$primary" cat "/etc/lemper/dns-keys/$peer.key" | \
        podman exec -i "${nodes[index]}" bash /root/dns_prepare.sh secondary "${addresses[0]}" "$peer"
done

podman cp tests/uat/dns_acceptance.sh "$primary:/root/dns_acceptance.sh"
podman exec "$primary" bash /root/dns_acceptance.sh --disposable "${addresses[@]}"
