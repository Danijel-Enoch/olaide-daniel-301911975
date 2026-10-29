-- Q3  Daily operations dashboard: failure rate by channel over 90 days.
--     Optimisation target: index on txn(created_at) to cut the scan to the
--     recent window instead of reading all 274,795 rows.
SELECT ch.channel_code, ch.channel_name,
       count(*)                                           AS attempted,
       count(*) FILTER (WHERE t.status = 'SUCCESS')        AS succeeded,
       count(*) FILTER (WHERE t.status = 'FAILED')         AS failed,
       round(100.0 * count(*) FILTER (WHERE t.status = 'FAILED') / count(*), 2) AS failure_pct,
       to_char(sum(t.amount) FILTER (WHERE t.status = 'SUCCESS'), 'FM999,999,999,990.00') AS value_moved
FROM txn t
JOIN channel ch ON ch.channel_code = t.channel_code
WHERE t.created_at >= now() - INTERVAL '90 days'
GROUP BY ch.channel_code, ch.channel_name
ORDER BY failure_pct DESC;
