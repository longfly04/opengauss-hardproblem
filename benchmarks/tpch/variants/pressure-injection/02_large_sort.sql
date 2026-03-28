SELECT l.l_orderkey,
       sum(l.l_extendedprice * (1 - l.l_discount)) AS revenue
FROM lineitem l
WHERE l.l_shipdate >= DATE '1995-01-01'
  AND l.l_shipdate < DATE '1998-01-01'
GROUP BY l.l_orderkey
ORDER BY revenue DESC, l.l_orderkey
LIMIT 20000;
