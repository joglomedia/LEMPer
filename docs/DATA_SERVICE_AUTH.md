# MongoDB and cache authentication

New MongoDB installations listen on IPv4 loopback and require authorization. The
installer enrolls the first administrator through a private service network
namespace with Unix sockets disabled. It saves the credentials in the protected
LEMPer profile before exposing the authenticated service on host loopback. A
failed enrollment keeps its pending credential in root-only state and can be
retried with the same install command. The bootstrap refuses to launch MongoDB
if the required network namespace is unavailable. An existing unmanaged MongoDB deployment
keeps its configuration and data. Review its authentication, application accounts,
and recovery procedure before changing its policy.

Removing the MongoDB packages preserves the data, users, and configuration unless
data removal is explicitly selected. Applications should have database-specific
accounts and use an administrator credential only for administration.

A new Redis or Valkey installation requires a password by default. Leave the
example profile's `REDIS_PASSWORD` empty to generate a strong credential. The
configured value is stored in the protected LEMPer profile and rendered into the
daemon configuration with read access for the service group. Configure each
authorized cache client before enabling object caching. A server-wide password
authorizes access to the shared instance, so independent tenants need separate
instances or administrator-managed ACLs that scope commands and keys to each
principal. Keep the shared cache credential within one trust boundary.

Use `REDIS_REQUIRE_PASSWORD=false` only for an intentionally unauthenticated
cache on a single-trust host. The installer preserves an existing server unless
explicitly instructed to reconfigure it. Refresh client credentials together with
the daemon if an existing installation's password changes.
