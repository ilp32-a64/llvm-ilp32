-- Deterministic SQLite workload: the output of a GCC-built and a clang-built
-- sqlite3 shell must be identical.
.headers on
.mode list
CREATE TABLE seq(n INTEGER PRIMARY KEY, r INTEGER, s TEXT, x REAL);
WITH RECURSIVE g(n, r) AS (
  SELECT 1, 12345
  UNION ALL
  SELECT n + 1, (r * 1103515245 + 12345) % 2147483648 FROM g WHERE n < 20000
)
INSERT INTO seq SELECT n, r, printf('k%08x-%s', r, substr('abcdefghijklmnopqrstuvwxyz', r % 26 + 1, 5)),
  (r % 100000) / 7.0 FROM g;
CREATE INDEX seq_r ON seq(r);
CREATE INDEX seq_s ON seq(s);
SELECT count(*), sum(r), min(r), max(r), total(x), avg(n) FROM seq;
SELECT r % 17 AS bucket, count(*), sum(r % 1000), group_concat(n % 10, '') FROM seq
  GROUP BY bucket ORDER BY bucket;
SELECT n, r, s FROM seq ORDER BY r DESC, n LIMIT 15;
SELECT n, s FROM seq WHERE s LIKE 'k0%' ORDER BY s LIMIT 10;
SELECT count(*) FROM seq a JOIN seq b ON a.r % 1000 = b.r % 1000 WHERE a.n < 2000 AND b.n < 2000;
SELECT upper(s), length(s), instr(s, '-'), replace(s, 'a', '@'), hex(substr(s, 2, 4))
  FROM seq WHERE n % 2500 = 0;
SELECT printf('%.6f|%e|%10.3g|%d|%x', x, x * 1e10, x / 3, r, r) FROM seq WHERE n % 3000 = 1;
SELECT json_object('n', n, 'r', r, 'tags', json_array(r % 3, r % 5, s)) FROM seq WHERE n % 4000 = 7;
SELECT n, r, sum(r % 100) OVER (ORDER BY n ROWS BETWEEN 3 PRECEDING AND CURRENT ROW),
  rank() OVER (PARTITION BY r % 3 ORDER BY r) FROM seq WHERE n <= 12;
CREATE TABLE t2 AS SELECT s, count(*) AS c FROM seq GROUP BY substr(s, 11);
SELECT * FROM t2 ORDER BY c DESC, s LIMIT 10;
DELETE FROM seq WHERE r % 3 = 0;
UPDATE seq SET s = s || '!' WHERE n % 5 = 0;
SELECT count(*), sum(length(s)), sum(r) FROM seq;
PRAGMA integrity_check;
