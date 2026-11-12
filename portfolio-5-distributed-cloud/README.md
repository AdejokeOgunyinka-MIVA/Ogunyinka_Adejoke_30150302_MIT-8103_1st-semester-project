# Portfolio 5: Distributed and Cloud Database Exercise

**Course:** MIT 8103 Advanced Database Systems
**Student:** Adejoke Ogunyinka (30150302)
**Setup:** PostgreSQL 17 streaming replication (primary + hot-standby replica) in Docker; declarative partitioning as sharding in miniature

---

## 1. Objective

Make Cartify's database survive the failure of a server and scale beyond one machine. Practically: run a primary and a replica, prove that writes on the primary appear on the replica, prove the replica is read-only, measure replication lag, perform a failover by promoting the replica, and demonstrate sharding by region with partition pruning. Then discuss the consistency and availability trade-offs and how the same design maps to a cloud deployment.

## 2. Files

| File | Purpose |
|---|---|
| `docker/docker-compose.yml` | Primary (port 5433) and replica (port 5434) containers |
| `docker/init-primary.sh` | Creates the replication role and allows replication connections |
| `run_replication_demo.sh` | Loads Cartify into the primary and runs the nine-step demonstration |
| `results/replication_demo.txt` | Full output of the demonstration |
| `sql/partitioning_demo.sql` | Orders partitioned by region; partition pruning evidence |
| `results/partitioning_demo.txt` | Output of the partitioning demonstration |
| `screenshots/` | Docker Desktop and terminal evidence |

## 3. How to reproduce

```
docker compose -f docker/docker-compose.yml up -d        # primary clones itself into the replica
bash run_replication_demo.sh                              # nine-step demo, ~30 seconds
psql -d cartify -f sql/partitioning_demo.sql              # on the local database
docker compose -f docker/docker-compose.yml down -v       # reset
```

## 4. Streaming replication: how it is set up

PostgreSQL writes every change to a **write-ahead log (WAL)** before applying it to the data files. Streaming replication sends that log, record by record, to a standby server that replays it. The standby therefore holds an identical copy that trails the primary by milliseconds.

**Primary** (`docker-compose.yml`, `init-primary.sh`):
- `wal_level=replica`: log enough detail for a standby to replay.
- `max_wal_senders=5`: allow up to five standbys to connect.
- `wal_keep_size=256MB`: retain recent WAL so a briefly disconnected replica can catch up.
- A `replicator` role with the `REPLICATION` privilege, and a `pg_hba.conf` line permitting it to connect from other containers.

**Replica**:
- On first start, `pg_basebackup -R` copies the primary's entire data directory and writes `standby.signal` plus the connection string to the primary. That is what makes the clone start as a standby instead of an independent server.
- `hot_standby=on` lets the standby serve read-only queries while replaying WAL.

The replica's log confirms it: `entering standby mode`, `database system is ready to accept read-only connections`, `started streaming WAL from primary`.

## 5. Replication demonstration (results/replication_demo.txt)

| Step | What was done | Evidence |
|---|---|---|
| 1 | Local Cartify database (50,000 orders) loaded into the primary with `pg_dump` | 50,004 orders, 500 products on primary |
| 2 | `pg_stat_replication` on the primary | one client, `state = streaming`, `sync_state = async`, `sent_lsn = replay_lsn` |
| 3 | `pg_is_in_recovery()` on each node | primary `false`, replica `true` |
| 4 | Count rows on the replica | identical 50,004 orders, 500 products: the bulk load replicated |
| 5 | Insert a product on the primary, read it on the replica one second later | product 501 visible on the replica with identical values |
| 6 | Replication lag | `replay_lag_bytes = 0`, `replay_lag = 0.6 ms` |
| 7 | Attempt an UPDATE on the replica | `ERROR: cannot execute UPDATE in a read-only transaction` |
| 8 | Burst of 1,000 order inserts on the primary | both nodes report 51,004 one second later |
| 9 | `pg_ctl promote` on the replica | replica reports `in_recovery = false`, accepts the UPDATE that was refused in step 7; primary's standby count drops to 0 |

Step 9 is a **manual failover**. In production a tool such as Patroni or a cloud provider's managed service detects the primary's failure and runs the promotion automatically, then repoints the application's connection string.

## 6. What replication gives Cartify

- **High availability.** If the primary's disk dies during a sales event, the replica is promoted and Cartify keeps taking orders. Recovery time is seconds, not the hours a restore from backup would take.
- **Read scaling.** The storefront is read-heavy (Portfolio 2). Catalogue browsing, order history and reports can be sent to one or more replicas, leaving the primary's capacity for checkout writes. The `hot_standby` setting is what makes this possible.
- **Safe reporting.** The materialised view refresh and heavy finance queries from Portfolio 2 can run on the replica without slowing checkout.

## 7. Consistency trade-off: asynchronous versus synchronous

`sync_state = async` in step 2 means the primary commits without waiting for the replica. The measured lag was under a millisecond on one machine, but across a network it could be tens of milliseconds, and during a burst (step 8) it grows. Two consequences:

1. **Read-your-writes anomaly.** A customer places an order (written to primary), the "My Orders" page reads from the replica, and the order is not there yet. Fix: route reads that must reflect a user's own recent writes to the primary, or to a replica only after checking its replay position has passed the write's LSN.
2. **Data loss on failover.** If the primary dies with un-replayed WAL, those last transactions are lost when the replica is promoted.

**Synchronous replication** (`synchronous_commit = on` with `synchronous_standby_names` set) makes the primary wait for the replica to confirm every commit. Nothing is lost on failover, at the cost of higher write latency and the risk that a slow or dead replica stalls all writes. For Cartify: payments and stock changes justify synchronous replication to at least one standby; catalogue edits and reviews do not.

This is the **CAP theorem** in practice. During a network partition between primary and replica, asynchronous replication keeps the system available but the replica may serve stale data (AP). Synchronous replication keeps the data consistent but a write cannot complete until the partition heals (CP). PostgreSQL lets this be chosen per transaction via `SET synchronous_commit`, so Cartify can be CP for checkout and AP for browsing.

## 8. Sharding: splitting the data, not copying it

Replication copies the whole database to every node; every node must still hold everything. **Sharding** splits one logical table across nodes by a **shard key**, so each node holds a fraction. It is how a system grows beyond one machine's disk and write capacity.

`sql/partitioning_demo.sql` demonstrates the mechanics using PostgreSQL's declarative partitioning, which is sharding within one server and the first step towards distributing partitions across servers (via `postgres_fdw` or the Citus extension). The shard key is the delivery region, derived from the address state:

| Partition (shard) | Orders | Share |
|---|---|---|
| South West | 28,847 | 58% |
| North | 9,877 | 20% |
| South South | 6,472 | 13% |
| South East | 4,808 | 10% |

**Partition pruning.** A query filtered on the shard key (`WHERE region = 'South East'`) is executed against that one partition only; the plan shows a single `Seq Scan on orders_south_east`. A query without the shard key (`WHERE status = 'delivered'`) shows an `Append` over all four partitions: a **scatter-gather** that would, in a real sharded cluster, contact every node. Execution times: 0.7 ms versus 6.1 ms.

**Choosing the shard key.** The region split above is uneven: Lagos alone puts 58% of orders in one shard, a **hot shard**. A better key for Cartify would be a hash of `customer_id`: it spreads load evenly, and a customer's orders stay together so "My Orders" hits one shard. The cost is that reports by state become scatter-gather queries. There is no key that makes every query local; the key is chosen for the most frequent, latency-sensitive query.

**Sharding and transactions.** Portfolio 3's place-order transaction touched `orders`, `order_items` and `products`. If products were sharded by category and orders by customer, one checkout would span shards and need a distributed (two-phase) commit, which is slow and fragile. This is the main reason Cartify would shard orders by customer and keep the product catalogue replicated to every node rather than sharded. MongoDB (Portfolio 4) shards natively by a chosen key with the same trade-offs.

## 9. Cloud deployment

The Docker setup maps directly onto managed cloud services, which run the same PostgreSQL with the operational work done by the provider:

| Concern | This portfolio | Managed cloud equivalent |
|---|---|---|
| Primary + replica | two containers, `pg_basebackup` | AWS RDS Multi-AZ, Google Cloud SQL HA, Azure Database for PostgreSQL zone-redundant HA, Neon |
| Failover | manual `pg_ctl promote` | automatic, typically 30 to 60 seconds, with DNS repointed |
| Read replicas | `hot_standby=on` | add replicas in the console; cross-region replicas for Nigerian customers served from a European region |
| Backups | none | automated daily snapshots plus continuous WAL archiving for point-in-time recovery |
| Sharding | declarative partitioning | Citus on Azure (Cosmos DB for PostgreSQL), or application-level sharding |
| MongoDB (Portfolio 4) | one container | MongoDB Atlas replica set with three nodes across zones, sharded cluster when needed |

For Cartify specifically: a managed PostgreSQL instance with one synchronous standby in a second availability zone for checkout and payments, two asynchronous read replicas for the storefront, and MongoDB Atlas for the catalogue. Data residency matters: Nigerian data protection rules (NDPR) favour hosting in-country or in a region with adequate safeguards, which affects provider and region choice.

## 10. Reflection notes

- The replica refusing writes (step 7) and then accepting them after promotion (step 9) made the primary/standby roles concrete in a way reading about them did not.
- Replication lag of 0.6 ms on one laptop is misleading; the design has to assume the lag across a real network and plan the read-your-writes case.
- The uneven shard sizes were a useful accident. Picking the shard key by what is convenient to query (region) produced a hot shard; the key has to be chosen for load distribution first.
- The permissions error on the replica's data directory (fixed with `chmod 0700`) was a reminder that PostgreSQL enforces security on the file system, not only in SQL.
