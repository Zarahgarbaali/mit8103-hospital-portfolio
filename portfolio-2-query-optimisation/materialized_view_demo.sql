-- Compare the live revenue aggregate with the materialised view.
--   docker exec -i hospital_pg psql -U hospital_admin -d hospital_db \
--     -f /workspace/portfolio-2-query-optimisation/materialized_view_demo.sql

\timing on

\echo '--- 1. Live aggregate: revenue per department per month, last 12 months'
EXPLAIN (ANALYZE, BUFFERS)
SELECT d.department_id, d.name, date_trunc('month', i.issued_at) AS month, sum(i.total_amount) AS revenue
FROM invoice i
JOIN invoice_item ii ON ii.invoice_id = i.invoice_id AND ii.item_type = 'consultation'
JOIN appointment  a  ON a.appointment_id = ii.reference_id
JOIN staff        s  ON s.staff_id = a.doctor_id
JOIN department   d  ON d.department_id = s.department_id
WHERE i.status <> 'cancelled'
  AND i.issued_at >= date_trunc('month', now()) - interval '11 months'
GROUP BY d.department_id, d.name, date_trunc('month', i.issued_at);

\echo '--- 2. Same answer from the materialised view'
EXPLAIN (ANALYZE, BUFFERS)
SELECT department_id, department, month, revenue
FROM mv_monthly_department_revenue
WHERE month >= date_trunc('month', now()) - interval '11 months';

\echo '--- 3. Last 3 months from the view'
SELECT department, to_char(month, 'YYYY-MM') AS month, invoices, revenue
FROM mv_monthly_department_revenue
WHERE month >= date_trunc('month', now()) - interval '2 months'
ORDER BY month, department;

\echo '--- 4. Cross-check: the view and the live query agree for last month'
SELECT
    (SELECT sum(revenue) FROM mv_monthly_department_revenue
      WHERE month = date_trunc('month', now()) - interval '1 month') AS view_total,
    (SELECT sum(i.total_amount)
       FROM invoice i
       JOIN invoice_item ii ON ii.invoice_id = i.invoice_id AND ii.item_type = 'consultation'
      WHERE i.status <> 'cancelled'
        AND i.issued_at >= date_trunc('month', now()) - interval '1 month'
        AND i.issued_at <  date_trunc('month', now())) AS live_total;

\echo '--- 5. Nightly refresh (readers are not blocked)'
REFRESH MATERIALIZED VIEW CONCURRENTLY mv_monthly_department_revenue;
