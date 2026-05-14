# Stage 7: Three-Node MySQL Host Installation

This directory contains the hand-operated artifacts for Stage 7, where MySQL is
installed directly on `node1`, `node2`, and `node3` instead of running in
containers.

## Files

- `node1-init.sql`: initialize `logtrace_node1` on `node1`
- `node2-init.sql`: initialize `logtrace_node2` on `node2`
- `node3-init.sql`: initialize `logtrace_node3` on `node3`
- `node1-grants.sql`: create the Stage 7 application account on `node1`
- `node2-grants.sql`: create the Stage 7 application account on `node2`
- `node3-grants.sql`: create the Stage 7 application account on `node3`
- `backend-stage7.env.example`: backend datasource environment variables for
  `node1`

## Host-level MySQL Baseline

Run these steps on each Ubuntu VM:

```bash
sudo apt update
sudo apt install -y mysql-server
sudo systemctl enable --now mysql
sudo systemctl status mysql --no-pager
```

Edit `/etc/mysql/mysql.conf.d/mysqld.cnf` so the following settings are present:

```ini
[mysqld]
bind-address = <NODE_IP>
character-set-server = utf8mb4
collation-server = utf8mb4_bin
default-time-zone = '+00:00'
skip-name-resolve = ON
```

Recommended values for `bind-address`:

- `node1`: `127.0.0.1`
- `node2`: `192.168.88.102`
- `node3`: `192.168.88.103`

Then restart and confirm:

```bash
sudo systemctl restart mysql
sudo systemctl status mysql --no-pager
sudo ss -lntp | grep 3306
```

## SQL Import Order

Upload the matching files with `Xftp`, then import them as `root`:

```bash
sudo mysql < node1-init.sql
sudo mysql < node1-grants.sql
```

```bash
sudo mysql < node2-init.sql
sudo mysql < node2-grants.sql
```

```bash
sudo mysql < node3-init.sql
sudo mysql < node3-grants.sql
```

Before running each `*-grants.sql`, replace the placeholder password:

- `CHANGE_ME_NODE1_APP_PASSWORD`
- `CHANGE_ME_NODE2_APP_PASSWORD`
- `CHANGE_ME_NODE3_APP_PASSWORD`

## Firewall Boundary

The expected network boundary for Stage 7 is:

- `node1` MySQL is only for the local backend on `node1`
- `node2:3306` only accepts backend access from `192.168.88.101`
- `node3:3306` only accepts backend access from `192.168.88.101`

If `ufw` is enabled, the minimum rules are:

```bash
sudo ufw allow from 192.168.88.101 to any port 3306 proto tcp
```

Only apply that rule on `node2` and `node3`.

## Stage 7 Acceptance Commands

### 1. Verify version and server variables on each node

```sql
SELECT @@version, @@time_zone, @@character_set_server, @@collation_server;
```

### 2. Verify object boundaries

On `node1`:

```sql
SHOW TABLES FROM logtrace_node1;
SHOW PROCEDURE STATUS WHERE Db = 'logtrace_node1' AND Name LIKE 'sp_tamper_%';
SHOW GRANTS FOR 'logtrace_app'@'localhost';
SHOW GRANTS FOR 'logtrace_app'@'127.0.0.1';
```

On `node2`:

```sql
SHOW TABLES FROM logtrace_node2;
SHOW PROCEDURE STATUS WHERE Db = 'logtrace_node2';
SHOW GRANTS FOR 'logtrace_app'@'192.168.88.101';
```

On `node3`:

```sql
SHOW TABLES FROM logtrace_node3;
SHOW PROCEDURE STATUS WHERE Db = 'logtrace_node3';
SHOW GRANTS FOR 'logtrace_app'@'192.168.88.101';
```

### 3. Verify from `node1`

After preparing the passwords, run from `node1`:

```bash
mysql -ulogtrace_app -p -h127.0.0.1 -Dlogtrace_node1 -e "SELECT 1;"
mysql -ulogtrace_app -p -h192.168.88.102 -Dlogtrace_node2 -e "SELECT 1;"
mysql -ulogtrace_app -p -h192.168.88.103 -Dlogtrace_node3 -e "SELECT 1;"
```

Then verify tables and variables from `node1`:

```bash
mysql -ulogtrace_app -p -h127.0.0.1 -Dlogtrace_node1 -e "SHOW TABLES; SELECT @@time_zone, @@character_set_server, @@collation_server;"
mysql -ulogtrace_app -p -h192.168.88.102 -Dlogtrace_node2 -e "SHOW TABLES; SELECT @@time_zone, @@character_set_server, @@collation_server;"
mysql -ulogtrace_app -p -h192.168.88.103 -Dlogtrace_node3 -e "SHOW TABLES; SELECT @@time_zone, @@character_set_server, @@collation_server;"
```

## Backend Preparation on `node1`

Use `backend-stage7.env.example` as the template for the backend process
environment. Keep `logtrace.ledger.mode=mock` during Stage 7.

The Stage 7 target is only datasource readiness:

- JDBC URLs point to three real MySQL nodes
- usernames/passwords come from the `logtrace_app` accounts
- no OpenAPI, schema, or Fabric Gateway changes are introduced
