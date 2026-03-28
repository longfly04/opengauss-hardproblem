SELECT o.o_orderpriority,
       count(*) AS order_count,
       sum(l.l_extendedprice * (1 - l.l_discount)) AS revenue
FROM orders o
JOIN lineitem l ON l.l_orderkey = o.o_orderkey
WHERE l.l_shipdate >= DATE '1995-01-01'
  AND l.l_shipdate < DATE '1998-01-01'
GROUP BY o.o_orderpriority
ORDER BY revenue DESC, order_count DESC;
