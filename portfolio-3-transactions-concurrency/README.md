# Portfolio 3: Transactions and Concurrency

**Course:** MIT 8103 Advanced Database Systems
**Student:** Adejoke Ogunyinka (30150302)
**DBMS:** PostgreSQL 17, Cartify database

---

## 1. Objective

Show, with real output, that Cartify's "place order" operation is atomic (COMMIT and ROLLBACK), that partial failures can be handled with SAVEPOINT, that isolation levels change what a transaction sees, and that two customers buying the last unit of a product at the same moment is a genuine race condition that must be fixed by a concurrency control mechanism. Two fixes are demonstrated: explicit row locking (`SELECT ... FOR UPDATE`) and the SERIALIZABLE isolation level.

## 2. Files

| File | Purpose |
|---|---|
| `sql/01_place_order_commit_rollback.sql` | Single-session demo: successful order (COMMIT), failed order (ROLLBACK), partial failure (SAVEPOINT) |
| `sql/session_a_isolation.sql`, `session_b_isolation.sql` | Two-session demo: READ COMMITTED vs REPEATABLE READ |
| `sql/session_a_oversell.sql`, `session_b_oversell.sql` | Two-session demo: oversold stock, unsafe and with `FOR UPDATE` |
| `sql/session_a_oversell_serializable.sql`, `session_b_oversell_serializable.sql` | Same race under SERIALIZABLE |
| `sql/session_a_lost_update.sql`, `session_b_lost_update.sql` | Two-session demo: lost update on price, unsafe and with `FOR UPDATE` |
| `run_concurrency_demos.sh` | Runs every two-session demo with deterministic timing and saves output |
| `results/*.txt` | Captured output of every demo |
| `screenshots/` | Two-terminal screenshots of the oversell race, taken by hand |

## 3. How to reproduce

```
psql -d cartify -f sql/01_place_order_commit_rollback.sql
bash run_concurrency_demos.sh
```

The two-session demos start Session A and Session B as two separate `psql` processes at the same instant. `pg_sleep()` calls inside the scripts fix the interleaving (A reads at t=0, B acts at t=1, A acts at t=2) so every run produces the same result.

## 4. ACID in Cartify terms

| Property | Meaning for Cartify | Where it is demonstrated |
|---|---|---|
| **Atomicity** | An order is created with its items and stock reduction, or not at all. | Part B of `01_...sql`: a failed stock update rolls back the order and item inserts. |
| **Consistency** | Stock never goes negative, totals never negative, statuses always valid. | The CHECK constraints from Portfolio 1 are what fire in Part B. |
| **Isolation** | A customer never sees another customer's half-finished order. | Isolation level demo (section 6). |
| **Durability** | A committed order survives a crash. | PostgreSQL's write-ahead log guarantees this; not demonstrated here. |

## 5. Transaction demo: COMMIT, ROLLBACK, SAVEPOINT

Output: `results/place_order_commit_rollback.txt`

**Part A, successful order.** Inside one `BEGIN ... COMMIT`: insert the order, insert two items, reduce stock for both products, set the total from the items. Stock went from 10 to 9 and 2 to 0. The order total (280,000.00) was computed inside the transaction, so it cannot disagree with the items.

**Part B, failed order rolled back.** Product 2 now has 0 stock. A second order inserts its header and item, then tries `stock_quantity - 1`. The CHECK constraint raises an error. PostgreSQL marks the transaction as aborted; `ROLLBACK` discards the order and item rows. The order count is unchanged and the failed order id does not exist. The customer is told the item is out of stock; nothing half-done is left behind.

**Part C, SAVEPOINT.** A customer's basket has one in-stock item and one out-of-stock item. `SAVEPOINT before_item_2` is set after the first item. The second item fails. `ROLLBACK TO SAVEPOINT` undoes only the second item; the order commits with the first. This is how a real checkout removes an unavailable item without losing the whole basket.

## 6. Isolation levels: READ COMMITTED vs REPEATABLE READ

Output: `results/isolation_read_committed.txt`, `results/isolation_repeatable_read.txt`

Session A is a report that reads the price of product 1 twice inside one transaction. Between the two reads, Session B changes the price and commits.

| Isolation level | A's first read | A's second read | Phenomenon |
|---|---|---|---|
| READ COMMITTED (PostgreSQL default) | 250,000.00 | 199,999.00 | **Non-repeatable read**: A saw B's committed change mid-transaction. |
| REPEATABLE READ | 250,000.00 | 250,000.00 | A works from a snapshot taken at its first statement; B's change is invisible until A ends. |

READ COMMITTED is right for most storefront operations (always show the latest price). REPEATABLE READ is right for a financial report that must add up: every number comes from the same moment in time.

## 7. Concurrency problem: oversold stock

Output: `results/oversell_unsafe.txt`

Product 3 has 1 unit. Customer A and Customer B both try to buy it. Each follows the pattern most application code uses: read the stock, check it is above zero, write the new value.

```
t=0  A: SELECT stock  -> 1
t=1  B: SELECT stock  -> 1
t=1  B: UPDATE stock = 1 - 1 ; INSERT order ; COMMIT
t=2  A: UPDATE stock = 1 - 1 ; INSERT order ; COMMIT
```

Result: **stock = 0, orders sold = 2**. One unit, two paying customers. No statement broke a constraint; stock never went below zero. The interleaving is the bug. This is called a **lost update**: B's write was overwritten by A's write based on stale data.

Note why the CHECK constraint from Portfolio 1 did not save us: both sessions wrote the absolute value 0, not `stock_quantity - 1`. In real applications the value is computed in application code, so the constraint never sees a negative number.

## 8. Fix 1: pessimistic locking with SELECT ... FOR UPDATE

Output: `results/oversell_safe_for_update.txt`

The only change: `SELECT stock_quantity ... FOR UPDATE`. This locks the product row until the transaction ends.

```
t=0  A: SELECT stock FOR UPDATE -> 1  (row locked by A)
t=1  B: SELECT stock FOR UPDATE      (blocks, waiting for A)
t=2  A: UPDATE stock = 0 ; INSERT order ; COMMIT   (lock released)
t=2  B: ... unblocks, now reads stock = 0, refuses the sale, ROLLBACK
```

Result: **stock = 0, orders sold = 1**. B waited about one second and then saw the truth. This is *pessimistic* concurrency control: assume a conflict will happen and lock up front. It is the right choice for stock, balances and seat bookings, where conflicts on a hot row are common and a short wait is acceptable.

## 9. Fix 2: SERIALIZABLE isolation

Output: `results/oversell_safe_serializable.txt`

Same unsafe read-then-write code, no explicit lock, but both sessions run under `BEGIN ISOLATION LEVEL SERIALIZABLE`. B commits first. When A tries its UPDATE, PostgreSQL detects that A's read is now stale and aborts A:

```
ERROR:  could not serialize access due to concurrent update
```

Result: **stock = 0, orders sold = 1**. This is *optimistic* concurrency control: let everyone proceed, detect conflicts at write time, and make the loser retry. The application must catch the error and retry the transaction. It is the right choice when conflicts are rare and you do not want readers blocking each other.

## 10. Second race: lost update on price

Output: `results/lost_update_unsafe.txt`, `results/lost_update_safe_for_update.txt`

Two staff members edit product 4 (price 100,000) at once. A applies a 10% discount; B adds a 5,000 surcharge. Correct final price: 95,000.

| Mode | A reads | B reads | Final price | Outcome |
|---|---|---|---|---|
| Unsafe | 100,000 | 100,000 | **90,000** | B's surcharge was lost; A overwrote it with a value computed from stale data. |
| `FOR UPDATE` | 100,000 | waits, then 90,000 | **95,000** | B read A's result and applied its change on top. Both edits survive. |

## 11. Comparison of mechanisms

| Mechanism | Type | How it prevents the race | Cost | Use in Cartify for |
|---|---|---|---|---|
| `SELECT ... FOR UPDATE` | Pessimistic (lock) | Second transaction waits for the first | Waiting; risk of deadlock if locks are taken in different orders | Stock reduction at checkout, payment status changes |
| SERIALIZABLE | Optimistic (detect and abort) | Second writer gets a serialization error and retries | Retry logic in application; wasted work on abort | Low-conflict operations such as review submission, address edits |
| CHECK constraint `stock >= 0` | Last line of defence | Rejects a negative result | None | Always on; catches `stock - 1` style updates but not absolute writes |
| Atomic UPDATE `SET stock = stock - 1 WHERE stock > 0` | Row-level atomicity | The read and write happen in one statement under the row lock PostgreSQL takes automatically | None | The simplest fix when no application-side decision is needed |

The last row is worth knowing: if the application does not need to *see* the stock before deciding, a single conditional UPDATE is both safe and lock-free from the application's point of view. The two-session demos use the read-then-write pattern because that is where real bugs come from.

## 12. Screenshots: the oversell race in two terminals

The automated runner proves the behaviour; the screenshots show it happening live. Steps used:

1. Terminal 1 and Terminal 2 both run `psql -d cartify`.
2. Reset: `UPDATE products SET stock_quantity = 1 WHERE id = 3;`
3. Terminal 1: `BEGIN; SELECT stock_quantity FROM products WHERE id = 3 FOR UPDATE;` (returns 1, row now locked)
4. Terminal 2: `BEGIN; SELECT stock_quantity FROM products WHERE id = 3 FOR UPDATE;` (hangs: waiting for Terminal 1's lock)
5. Terminal 1: `UPDATE products SET stock_quantity = 0 WHERE id = 3; COMMIT;`
6. Terminal 2 unblocks and shows stock_quantity = 0. `ROLLBACK;`

`screenshots/01-terminal2-blocked.png` shows step 4 (Terminal 2 waiting), `screenshots/02-terminal2-unblocked-sees-zero.png` shows step 6.

## 13. Reflection notes

- The most important realisation: a race condition produces no error. Every statement succeeded, every constraint held, and the data was still wrong. You cannot find this bug by looking at one session's log.
- `FOR UPDATE` is two words that change everything. The read itself becomes a claim on the row.
- SERIALIZABLE felt safer until I saw that the application has to handle the abort. Safety moved from the database to the code.
- Writing the interleaving with `pg_sleep` made the problem reproducible, which is the only way to be sure the fix works.
