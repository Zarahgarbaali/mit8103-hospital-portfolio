-- MIVA Teaching Hospital - monthly department revenue (materialised view)
--
-- The board pack shows revenue per department per month for the last two
-- years. Computing that live means joining ~170k invoices to their
-- consultation line, appointment, doctor and department on every page load.
-- The view stores the answer (a few hundred rows) and is refreshed nightly.
--
-- Revenue rule (same as Q3): an invoice's full total is attributed to the
-- department of the doctor on its consultation line. reference_id on a
-- consultation line is the appointment_id. uq_invoice_item_consultation
-- (indexes.sql) guarantees one consultation line per invoice, so no invoice
-- can be counted twice.
--
-- Month boundaries follow the server time zone (Africa/Lagos, see
-- docker/docker-compose.yml).

DROP MATERIALIZED VIEW IF EXISTS mv_monthly_department_revenue;

CREATE MATERIALIZED VIEW mv_monthly_department_revenue AS
SELECT d.department_id,
       d.name                           AS department,
       date_trunc('month', i.issued_at) AS month,
       count(*)                         AS invoices,
       sum(i.total_amount)              AS revenue
FROM invoice i
JOIN invoice_item ii ON ii.invoice_id = i.invoice_id AND ii.item_type = 'consultation'
JOIN appointment  a  ON a.appointment_id = ii.reference_id
JOIN staff        s  ON s.staff_id = a.doctor_id
JOIN department   d  ON d.department_id = s.department_id
WHERE i.status <> 'cancelled'
GROUP BY d.department_id, d.name, date_trunc('month', i.issued_at);

-- Required for REFRESH ... CONCURRENTLY, and serves lookups by department and month.
CREATE UNIQUE INDEX uq_mv_monthly_department_revenue
    ON mv_monthly_department_revenue(department_id, month);

-- Refresh strategy
--
-- Nightly at 02:00, the quietest hour for billing:
--   REFRESH MATERIALIZED VIEW CONCURRENTLY mv_monthly_department_revenue;
--
-- CONCURRENTLY builds the new contents next to the old ones and swaps them
-- in, so dashboards can keep reading the view during the refresh. It needs
-- the unique index above.
--
-- Scheduling options:
--   * pg_cron (inside the database, not bundled in the postgres:16 image):
--       SELECT cron.schedule('mv-revenue', '0 2 * * *',
--         'REFRESH MATERIALIZED VIEW CONCURRENTLY mv_monthly_department_revenue');
--   * host crontab (works with this Docker setup today):
--       0 2 * * * docker exec hospital_pg psql -U hospital_admin -d hospital_db -c "REFRESH MATERIALIZED VIEW CONCURRENTLY mv_monthly_department_revenue"
--
-- Trade-off: figures for the current month are up to 24 hours stale. Q3
-- (live, index-assisted) stays available for anyone who needs today's number.
