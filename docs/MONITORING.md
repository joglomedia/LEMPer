# Managed monitoring

Monit is the optional health/alerting backend. `INSTALL_MONITORING=false` is the
default and minimal installation profiles skip it. It runs under a separate
`lemper-monit.service`, preserving the distribution's Monit configuration.

```bash
sudo lemperctl stack install monit --yes
sudo lemperctl monitor check
sudo lemperctl monitor status
sudo lemperctl monitor reload
sudo lemperctl monitor logs
sudo lemperctl stack update monit
```

The generated configuration checks system load, memory and root-filesystem space.
A loopback HTTP web-health check is added when Nginx is active during configuration.
Monit collects current health data and maintains state across restarts. The status
interface binds only to `127.0.0.1:${MONITOR_HTTP_PORT}` (default `2813`) and requires
an automatically generated credential. The credential and configuration stay
root-only under `/etc/lemper/monitoring/`; commands read the protected configuration
without placing passwords in arguments. Use a protected SSH tunnel for browser
access, with the private credential; the firewall does not expose this port.

## Alerts and updates

Set `MONITOR_ALERT_EMAIL` to an explicit recipient and `MONITOR_SMTP_HOST` to the
SMTP endpoint in the installed profile, then rerun installation to apply it.
The default endpoint is localhost, allowing the hosted mail system to handle
outgoing transport. Empty recipient settings disable outbound alerts. Configure
and verify the selected SMTP server's delivery/transport policy before relying on
notifications; external SMTP delivery was not exercised by local UAT.

Configuration replacement retains the prior file, runs `monit -t` before activation,
and restores the previous configuration on activation failure. User-owned Monit
configuration is not overwritten; managed ownership is explicit. `--dry-run`
validates configuration without creating credentials or changing services.

```bash
sudo lemperctl stack remove monit --yes
```

Removal stops the owned unit and removes owned packages while retaining health
configuration, credentials and state. `--force` permits explicit removal of an
unowned package. Resource metrics, authentication, loopback binding, configuration
validation and lifecycle were verified with real Monit in a disposable Podman
container. This provides managed health checks and alerts; it does not add a
central fleet metrics/time-series platform.
