# 查询内存使用情况

可以使用 `gs_total_memory_detail` 视图来查看数据库实例的整体内存使用情况。执行以下SQL语句：

```sql
SELECT * FROM gs_total_memory_detail;
```

## 📊 关键指标解读

查询结果中，以下几个字段是关键信息：

| 内存类型 (memorytype)         | 描述                                          |
| :------------------------ | :------------------------------------------ |
| **max\_dynamic\_memory**  | 动态内存池允许使用的最大大小。                             |
| **dynamic\_used\_memory** | 动态内存池当前已使用的大小。                              |
| **max\_shared\_memory**   | 共享内存池允许使用的最大大小（通常为 `shared_buffers` + 元数据）。 |
| **shared\_used\_memory**  | 共享内存池当前已使用的大小。                              |

## 📊 场景一：已开启线程池 (`enable_thread_pool = on`)

当线程池开启时，推荐使用 `GS_SESSION_MEMORY_DETAIL` 视图。这个视图可以统计所有会话和线程的内存使用情况。

你可以执行以下 SQL 来查看每个会话的总内存使用量，并按从大到小排序：

```sql
-- 查询每个会话的总内存使用大小，并按降序排列
SELECT sessid, pg_size_pretty(sum(totalsize)) AS total_memory_size FROM gs_session_memory_detail GROUP BY sessid ORDER BY sum(totalsize) DESC;
```

## 🧵 场景二：未开启线程池 (`enable_thread_pool = off`)

当线程池关闭时，`GS_THREAD_MEMORY_DETAIL` 视图和 `GS_SESSION_MEMORY_DETAIL` 视图是等价的，都可以用来查询线程的内存使用情况。

你可以使用以下 SQL 查询每个线程的内存使用情况：

```sql
-- 查询每个线程的总内存使用大小，并按降序排列
SELECT 
    threadid, 
    pg_size_pretty(sum(totalsize)) AS total_memory_size
FROM 
    gs_thread_memory_detail
GROUP BY 
    threadid
ORDER BY 
    sum(totalsize) DESC;
```

## 🔍 深入分析：定位高内存占用的具体SQL

如果你发现某个会话或线程的内存占用异常高，可以将其与活跃会话视图 `pg_stat_activity` 关联查询，从而找到正在执行的具体 SQL 语句。

以下是一个在开启线程池模式下，查找内存占用最高的前10个会话及其对应SQL的示例：

```sql
-- 关联查询，找出高内存占用会话对应的SQL语句
SELECT 
    b.state, 
    a.sessid, 
    substr(b.query, 1, 80) AS query_snippet, 
    pg_size_pretty(sum(a.totalsize)) AS total_memory_size
FROM 
    gs_session_memory_detail a, 
    pg_stat_activity b 
WHERE 
    split_part(a.sessid, '.', 2) = b.pid 
GROUP BY 
    b.state, a.sessid, b.query 
ORDER BY 
    sum(a.totalsize) DESC 
LIMIT 10;
```

## 查询每个会话的内存占用 (Top N)

```sql
SELECT ROUND(SUM(a.totalsize) / 1024.0 / 1024.0, 2) AS memory_mb,b.usename AS db_user, b.client_addr AS client_ip, b.application_name AS app_name, SUBSTR(b.query, 1, 60) AS sql_snippet, b.state AS status FROM  gs_session_memory_detail a JOIN pg_stat_activity b ON split_part(a.sessid, '.', 2)::text = b.pid::text WHERE  b.state != 'idle' GROUP BY a.sessid, b.usename, b.client_addr, b.application_name, b.query, b.state
ORDER BY SUM(a.totalsize) DESC LIMIT 20;

```

要实现对**每个SQL的工作内存进行细粒度查询**这个目标，我们需要结合 **`EXPLAIN`** **执行计划分析**（针对单次查询）和 **系统统计视图**（针对聚合数据）。

以下是具体的实现方案：

### 1. 查询单次 SQL 的工作内存与缓存详情

这是最细粒度的分析方式。通过在 SQL 前加上 `EXPLAIN (ANALYZE, BUFFERS)`，数据库会在执行结束后直接告诉你：这条 SQL 到底用了多少内存（是否落盘），以及它从缓存中读取了多少数据。

**命令格式：**

```sql
EXPLAIN (ANALYZE, BUFFERS) <你的SQL语句>;
```

**结果解读示例：**
假设你执行了一条查询，结果如下：

```text
Sort  (cost=10.00..10.05 rows=20 width=100) (actual time=0.050..0.055 rows=20 loops=1)
  Sort Key: id
  Sort Method: quicksort  Memory: 25kB  <-- 【工作内存】这里显示该算子实际使用的内存
  Buffers: shared hit=150 read=0  <-- 【缓存命中】shared hit 表示命中缓存的块数
  ->  Seq Scan on my_table  (cost=0.00..1.20 rows=20 width=100) (actual time=0.010..0.015 rows=20 loops=1)
        Buffers: shared hit=150 read=0
```

- **工作内存 (`Memory: 25kB`)**：
  - 如果显示 `Memory`，说明排序或哈希操作完全在内存中完成，性能极佳。
  - 如果显示 `Disk: xxx`（例如 `Sort Method: external merge Disk: 1024kB`），说明 `work_mem` 设置过小，内存不够用，SQL 被迫使用了临时文件（落盘），性能会大幅下降。
- **缓存命中 (`Buffers`)**：
  - `shared hit=150`：表示读取了 150 个数据块（通常 1 块=8kB），且**全部命中了共享缓冲区（Buffer Cache）**。
  - `read=0`：表示没有发生物理磁盘 I/O。如果这个数字很大，说明缓存命中率低，或者数据不在内存中。

***

### 2. 查询当前活跃 SQL 的累计缓存统计

如果你想查看**当前正在运行**或**最近运行过**的 SQL 累计占用了多少缓存和内存，可以查询 `pg_stat_statements`（需先开启该插件）或 `pg_stat_activity`。

**推荐查询** **`pg_stat_statements`（最准确的聚合统计）：**
这个视图记录了所有执行过的 SQL 的累计统计信息。

```sql
SELECT 
    queryid, 
    SUBSTR(query, 1, 50) AS sql_text, 
    calls, -- 执行次数
    shared_blks_hit, -- 共享内存命中块数
    shared_blks_read, -- 物理读取块数
    temp_blks_read, -- 临时文件读取（说明内存不足）
    temp_blks_written -- 临时文件写入
FROM 
    pg_stat_statements 
ORDER BY 
    shared_blks_hit DESC -- 按缓存命中数排序，找出最“热”的 SQL
LIMIT 10;
```

- **`shared_blks_hit`**：数值越大，说明这条 SQL 越频繁地访问内存中的数据，是系统的“热点”SQL。
- **`temp_blks_written`**：如果此值很大，说明该 SQL 经常因为工作内存不足而写临时文件。

***

### 3. 查询当前会话的实时工作内存 (Work Memory)

如果你想知道当前某个会话（Session）到底占用了多少**动态工作内存**（即 `work_mem` 所在的区域），可以使用 `gs_session_memory_detail` 视图，并筛选特定的上下文。

**查询特定会话的内存上下文详情：**

```sql
SELECT 
    sessid, 
    contextname, 
    ROUND(totalsize / 1024.0 / 1024.0, 2) AS size_mb, 
    ROUND(freesize / 1024.0 / 1024.0, 2) AS free_mb, 
    (totalsize - freesize) / 1024.0 / 1024.0 AS used_mb 
FROM 
    gs_session_memory_detail
WHERE 
    contextname LIKE '%QueryContext%' 
    OR contextname LIKE '%Executor%'
ORDER BY 
    used_mb DESC;
```

- **`QueryContext`** **/** **`Executor`**：这些上下文通常对应 SQL 执行期间分配的内存。
- **`used_mb`**：这里显示的数值就是该 SQL 执行过程中实际占用的工作内存大小。




