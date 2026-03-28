SELECT p.p_brand,
       p.p_type,
       l.l_shipmode,
       sum(l.l_quantity) AS total_qty,
       sum(l.l_extendedprice) AS total_ext_price
FROM part p
JOIN lineitem l ON l.l_partkey = p.p_partkey
WHERE l.l_shipdate >= DATE '1995-01-01'
  AND l.l_shipdate < DATE '1998-12-31'
GROUP BY p.p_brand, p.p_type, l.l_shipmode
ORDER BY total_ext_price DESC, total_qty DESC;
