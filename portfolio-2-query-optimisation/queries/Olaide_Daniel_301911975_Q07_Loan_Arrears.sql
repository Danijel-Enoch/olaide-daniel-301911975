-- Q7  Credit control: active loans already past their due date.
--     Only ~2,700 loans exist, of which a minority are ACTIVE.
--     Optimisation target: partial index WHERE status = 'ACTIVE'.
SELECT l.loan_ref, c.first_name || ' ' || c.last_name AS customer, c.phone,
       l.principal, l.interest_rate_pa, l.due_on,
       (CURRENT_DATE - l.due_on) AS days_overdue, s.full_name AS approved_by
FROM loan l
JOIN customer c ON c.customer_id = l.customer_id
LEFT JOIN staff s ON s.staff_id = l.approved_by
WHERE l.status = 'ACTIVE'
  AND l.due_on < CURRENT_DATE
ORDER BY days_overdue DESC, l.principal DESC
LIMIT 50;
