--1A (1)
SELECT 
	c.customer_name,
	c.city,
	s.origin_city,
	s.destination_city,
	s.shipment_date,
	s.status
FROM customers AS c
LEFT JOIN shipments AS s USING (customer_id)
WHERE 
	(s.status = 'Delayed' OR status = 'Cancelled')
	AND s.shipment_date BETWEEN '2024-07-01' AND '2024-09-30'
order BY s.shipment_date DESC;

SELECT 
	c.customer_name,
	c.city,
	s.origin_city,
	s.destination_city,
	s.shipment_date,
	s.status
FROM shipments AS s
LEFT JOIN customers AS c USING (customer_id)
WHERE 
	(s.status = 'Delayed' OR status = 'Cancelled')
	AND s.shipment_date BETWEEN '2024-07-01' AND '2024-09-30'
order BY s.shipment_date DESC;

--1A (2)
SELECT 
	c.region,
	COUNT(s.shipment_id) AS shipment_count,
	SUM(sc.total_cost) AS total_cost
FROM customers AS c
LEFT JOIN shipments AS s USING (customer_id)
LEFT JOIN shipment_costs AS sc USING  (shipment_id)
WHERE s.shipment_date BETWEEN '2024-01-01' AND '2024-12-31'
GROUP BY c.region
HAVING COUNT(s.shipment_id) > 5
ORDER BY total_cost DESC;

-- 1A (3)
WITH customer_ranks AS (
	SELECT
		c.customer_name,
		c.city,
		SUM(s.weight_kg) AS total_weight_kg,
		DENSE_RANK() OVER (ORDER BY COALESCE(SUM(s.weight_kg), 0) DESC) AS dense_rank_num
	FROM customers AS c
	LEFT JOIN shipments AS s USING (customer_id)
	GROUP BY customer_name, city
)
SELECT 
	customer_name,
	city,
	total_weight_kg
FROM customer_ranks
WHERE dense_rank_num <= 3;

-- 1A (4)
SELECT
	s.shipment_id,
	c.customer_name,
	s.shipment_date,
	s.delivery_date,
	(s.delivery_date - s.shipment_date) - 5 as days_overdue
FROM customers AS c
LEFT JOIN shipments AS s using (customer_id)
WHERE s.delivery_date IS NOT NULL 
	AND (s.delivery_date - s.shipment_date) - 5 > 0;

-- 1A (5)
SELECT 
    EXTRACT (MONTH FROM s.shipment_date) AS month_num,
    TO_CHAR(s.shipment_date, 'Month') AS month_name,
    COUNT(CASE WHEN s.status = 'Delivered' THEN 1 END) AS delivered,
    COUNT(CASE WHEN s.status = 'In Transit' THEN 1 END) AS in_transit,
    COUNT(CASE WHEN s.status = 'Delayed' THEN 1 END) AS delayed,
    COUNT(CASE WHEN s.status = 'Cancelled' THEN 1 END) AS cancelled
FROM shipments AS s
WHERE s.shipment_date BETWEEN '2024-01-01' and '2024-12-31'
GROUP BY
    EXTRACT (MONTH FROM s.shipment_date),
    TO_CHAR(s.shipment_date, 'Month')
ORDER BY month_num ASC;

-- 1B (6)
SELECT 
    d.driver_id,
    d.driver_name,
    COUNT(s.shipment_id) AS total_shipments,
    ROUND(
        (COUNT(CASE WHEN s.status IN ('Delayed', 'Cancelled') THEN 1 END) * 100.0) / COUNT(s.shipment_id), 
        2
    ) AS delay_cancel_pct,
    ROUND(AVG(s.weight_kg), 2) AS avg_shipment_weight
FROM drivers AS d
JOIN shipments AS s USING (shipment_id)
GROUP BY d.driver_id, d.driver_name
HAVING COUNT(s.shipment_id) >= 3
ORDER BY delay_cancel_pct DESC;

-- 1B (7)
WITH monthly AS (
    SELECT c.customer_id,
           c.customer_name,
           EXTRACT(MONTH FROM s.shipment_date)::int AS month_num,
           SUM(sc.total_cost)                       AS month_cost
    FROM customers c
    JOIN shipments s        ON s.customer_id = c.customer_id
    JOIN shipment_costs sc  ON sc.shipment_id = s.shipment_id
    WHERE s.shipment_date >= DATE '2024-01-01'
      AND s.shipment_date <  DATE '2025-01-01'
    GROUP BY 1, 2, 3
),
ranked AS (
    SELECT m.*,
           ROW_NUMBER() OVER (PARTITION BY m.customer_id
                              ORDER BY m.month_cost DESC, m.month_num ASC) AS rn_peak,
           ROW_NUMBER() OVER (PARTITION BY m.customer_id
                              ORDER BY m.month_cost ASC,  m.month_num ASC) AS rn_low
    FROM monthly m
)
SELECT p.customer_name,
       TO_CHAR(make_date(2024, p.month_num, 1), 'FMMonth') AS peak_month,
       p.month_cost                                        AS peak_cost,
       TO_CHAR(make_date(2024, l.month_num, 1), 'FMMonth') AS lowest_month,
       l.month_cost                                        AS lowest_cost
FROM ranked p
JOIN ranked l ON l.customer_id = p.customer_id
             AND l.rn_low = 1
WHERE p.rn_peak = 1
ORDER BY p.customer_name;

-- 1C
WITH monthly AS (
    SELECT m.month_num,
           COALESCE(SUM(sc.total_cost), 0) AS monthly_total
    FROM generate_series(1, 12) AS m(month_num)
    LEFT JOIN shipments s
           ON EXTRACT(MONTH FROM s.shipment_date) = m.month_num
          AND s.shipment_date >= DATE '2024-01-01'
          AND s.shipment_date <  DATE '2025-01-01'
    LEFT JOIN shipment_costs sc ON sc.shipment_id = s.shipment_id
    GROUP BY m.month_num
),
calc AS (
    SELECT mo.month_num,
           mo.monthly_total,
           SUM(mo.monthly_total) OVER (ORDER BY mo.month_num
                                       ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS running_total,
           AVG(mo.monthly_total) OVER ()                                                  AS avg_monthly,
           100.0 * (mo.monthly_total - LAG(mo.monthly_total) OVER (ORDER BY mo.month_num))
                 / NULLIF(LAG(mo.monthly_total) OVER (ORDER BY mo.month_num), 0)          AS mom_raw
    FROM monthly mo
)
SELECT month_num,
       TO_CHAR(make_date(2024, month_num, 1), 'FMMonth') AS month_name,
       monthly_total,
       running_total,
       ROUND(mom_raw, 2)                     AS mom_change_pct,
       ROUND(monthly_total - avg_monthly, 2) AS vs_avg,
       COALESCE(mom_raw > 15, FALSE)         AS is_spike   -- pakai nilai mentah (belum dibulatkan) agar keputusan spike tidak bergantung pembulatan
FROM calc
ORDER BY month_num;

select * from shipments;
select * from shipment_costs;
select * from customers;
select * from drivers;
