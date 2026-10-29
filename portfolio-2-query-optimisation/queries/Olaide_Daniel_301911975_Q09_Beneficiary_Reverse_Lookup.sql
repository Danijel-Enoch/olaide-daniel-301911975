-- Q9  Fraud investigation: which customers have saved this external account
--     as a beneficiary? Searches a non-leading column of a composite unique
--     constraint, so that constraint's index cannot help.
--     Optimisation target: dedicated index on beneficiary(account_number).
SELECT c.customer_id, c.first_name || ' ' || c.last_name AS customer, c.phone,
       bn.bank_code, bn.alias, bn.created_at::date AS saved_on
FROM beneficiary bn
JOIN customer c ON c.customer_id = bn.customer_id
WHERE bn.account_number = '0000118785'
ORDER BY bn.created_at;
