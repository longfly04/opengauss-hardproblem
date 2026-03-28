SELECT c.c_name,
       o.o_orderdate,
       sum(l.l_extendedprice * (1 - l.l_discount)) AS revenue
FROM customer c
JOIN orders o ON o.o_custkey = c.c_custkey
JOIN lineitem l ON l.l_orderkey = o.o_orderkey
WHERE o.o_orderdate >= DATE '1996-01-01'
  AND o.o_orderdate < DATE '1998-01-01'
GROUP BY c.c_name, o.o_orderdate
ORDER BY revenue DESC, c.c_name
LIMIT 5000;
