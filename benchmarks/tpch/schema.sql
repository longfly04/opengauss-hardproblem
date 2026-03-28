CREATE TABLE IF NOT EXISTS region (
  r_regionkey integer PRIMARY KEY,
  r_name char(25) NOT NULL,
  r_comment varchar(152)
);

CREATE TABLE IF NOT EXISTS nation (
  n_nationkey integer PRIMARY KEY,
  n_name char(25) NOT NULL,
  n_regionkey integer NOT NULL REFERENCES region (r_regionkey),
  n_comment varchar(152)
);

CREATE TABLE IF NOT EXISTS supplier (
  s_suppkey integer PRIMARY KEY,
  s_name char(25) NOT NULL,
  s_address varchar(40) NOT NULL,
  s_nationkey integer NOT NULL REFERENCES nation (n_nationkey),
  s_phone char(15) NOT NULL,
  s_acctbal numeric(15,2) NOT NULL,
  s_comment varchar(101) NOT NULL
);

CREATE TABLE IF NOT EXISTS customer (
  c_custkey integer PRIMARY KEY,
  c_name varchar(25) NOT NULL,
  c_address varchar(40) NOT NULL,
  c_nationkey integer NOT NULL REFERENCES nation (n_nationkey),
  c_phone char(15) NOT NULL,
  c_acctbal numeric(15,2) NOT NULL,
  c_mktsegment char(10) NOT NULL,
  c_comment varchar(117) NOT NULL
);

CREATE TABLE IF NOT EXISTS part (
  p_partkey integer PRIMARY KEY,
  p_name varchar(55) NOT NULL,
  p_mfgr char(25) NOT NULL,
  p_brand char(10) NOT NULL,
  p_type varchar(25) NOT NULL,
  p_size integer NOT NULL,
  p_container char(10) NOT NULL,
  p_retailprice numeric(15,2) NOT NULL,
  p_comment varchar(23) NOT NULL
);

CREATE TABLE IF NOT EXISTS partsupp (
  ps_partkey integer NOT NULL REFERENCES part (p_partkey),
  ps_suppkey integer NOT NULL REFERENCES supplier (s_suppkey),
  ps_availqty integer NOT NULL,
  ps_supplycost numeric(15,2) NOT NULL,
  ps_comment varchar(199) NOT NULL,
  PRIMARY KEY (ps_partkey, ps_suppkey)
);

CREATE TABLE IF NOT EXISTS orders (
  o_orderkey bigint PRIMARY KEY,
  o_custkey integer NOT NULL REFERENCES customer (c_custkey),
  o_orderstatus char(1) NOT NULL,
  o_totalprice numeric(15,2) NOT NULL,
  o_orderdate date NOT NULL,
  o_orderpriority char(15) NOT NULL,
  o_clerk char(15) NOT NULL,
  o_shippriority integer NOT NULL,
  o_comment varchar(79) NOT NULL
);

CREATE TABLE IF NOT EXISTS lineitem (
  l_orderkey bigint NOT NULL REFERENCES orders (o_orderkey),
  l_partkey integer NOT NULL REFERENCES part (p_partkey),
  l_suppkey integer NOT NULL REFERENCES supplier (s_suppkey),
  l_linenumber integer NOT NULL,
  l_quantity numeric(15,2) NOT NULL,
  l_extendedprice numeric(15,2) NOT NULL,
  l_discount numeric(15,2) NOT NULL,
  l_tax numeric(15,2) NOT NULL,
  l_returnflag char(1) NOT NULL,
  l_linestatus char(1) NOT NULL,
  l_shipdate date NOT NULL,
  l_commitdate date NOT NULL,
  l_receiptdate date NOT NULL,
  l_shipinstruct char(25) NOT NULL,
  l_shipmode char(10) NOT NULL,
  l_comment varchar(44) NOT NULL,
  PRIMARY KEY (l_orderkey, l_linenumber)
);

CREATE INDEX IF NOT EXISTS idx_orders_custkey ON orders (o_custkey);
CREATE INDEX IF NOT EXISTS idx_lineitem_part_supp ON lineitem (l_partkey, l_suppkey);
CREATE INDEX IF NOT EXISTS idx_lineitem_shipdate ON lineitem (l_shipdate);
CREATE INDEX IF NOT EXISTS idx_partsupp_suppkey ON partsupp (ps_suppkey);
CREATE INDEX IF NOT EXISTS idx_customer_nationkey ON customer (c_nationkey);
CREATE INDEX IF NOT EXISTS idx_supplier_nationkey ON supplier (s_nationkey);
