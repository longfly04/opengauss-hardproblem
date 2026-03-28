SELECT s.s_name,
       c.c_name,
       sum(l.l_extendedprice * (1 - l.l_discount)) AS revenue
FROM supplier s
JOIN partsupp ps ON ps.ps_suppkey = s.s_suppkey
JOIN lineitem l ON l.l_partkey = ps.ps_partkey AND l.l_suppkey = ps.ps_suppkey
JOIN orders o ON o.o_orderkey = l.l_orderkey
JOIN customer c ON c.c_custkey = o.o_custkey
WHERE o.o_orderdate >= DATE '1996-01-01'
  AND o.o_orderdate < DATE '1998-01-01'
GROUP BY s.s_name, c.c_name
ORDER BY revenue DESC, s.s_name, c.c_name
LIMIT 10000;
