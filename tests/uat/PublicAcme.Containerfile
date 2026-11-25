FROM docker.io/library/ubuntu:24.04
ENV container=podman DEBIAN_FRONTEND=noninteractive TERM=xterm
RUN apt-get update -qq && apt-get install -q -y systemd systemd-sysv dbus nginx cron python3-venv python-is-python3 curl ca-certificates sudo iproute2 jq libxml2-utils dnsutils procps && rm -f /usr/sbin/policy-rc.d
STOPSIGNAL SIGRTMIN+3
CMD ["/sbin/init"]
