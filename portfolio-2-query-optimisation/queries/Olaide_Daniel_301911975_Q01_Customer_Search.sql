-- Q1  Operations searches for a customer by surname, case-insensitively.
--     Typed into the support console dozens of times an hour.
--     Optimisation target: expression index on lower(last_name).
SELECT c.customer_id, c.first_name, c.last_name, c.phone, c.kyc_tier, b.branch_code
FROM customer c
JOIN branch b ON b.branch_id = c.home_branch_id
WHERE lower(c.last_name) LIKE 'okonkwo%'
ORDER BY c.last_name, c.first_name
LIMIT 50;
