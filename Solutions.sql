-- // Week 8 SQL Challenge - https://8weeksqlchallenge.com/case-study-4/

select *
from regions ;

select *
from customer_nodes ;

select *
from customer_transactions ;

-- // A. Customer Nodes Exploration

-- // 1) How many unique nodes are there on the Data Bank system?

select
    count(distinct node_id)
from customer_nodes ;

-- // 2) What is the number of nodes per region?

select
    region_name ,
    count(node_id) as nodes 
from customer_nodes as c
inner join regions as r
    on c.region_id = r.region_id
group by region_name ;

-- // 3) How many customers are allocated to each region?

select
    region_name ,
    count(distinct customer_id) as unique_customers
from customer_nodes as c
inner join regions as r
    on c.region_id = r.region_id
group by region_name ;

-- // 4) How many days on average are customers reallocated to a different node?

with days_in_node as (
    select
        customer_id ,
        node_id ,
        sum(datediff('days', start_date, end_date)) as days_in_node
    from customer_nodes
    WHERE end_date <> '9999-12-31'
    group by customer_id, node_id
)
select
    round(avg(days_in_node), 0) as avg_days_in_node
from days_in_node ;

-- // 5) What is the median, 80th and 95th percentile for this same reallocation days metric for each region?

WITH DAYS_IN_NODE AS (
    SELECT 
    region_name,
    customer_id,
    node_id,
    SUM(DATEDIFF('days',start_date,end_date)) as days_in_node
    FROM customer_nodes as C
    INNER JOIN regions as R on R.REGION_ID = C.region_id
    WHERE end_date <> '9999-12-31'
    GROUP BY region_name,
    customer_id,
    node_id
)
,ORDERED AS ( //this will give row id per region
SELECT 
region_name,
days_in_node,
ROW_NUMBER() OVER(PARTITION BY region_name ORDER BY days_in_node) as rn
FROM DAYS_IN_NODE
)
,MAX_ROWS as ( //this will give the max row id for each region / count of rows
SELECT 
region_name,
MAX(rn) as max_rn
FROM ORDERED
GROUP BY region_name
)
SELECT O.region_name
,CASE 
WHEN rn = ROUND(M.max_rn /2,0) THEN 'Median'
WHEN rn = ROUND(M.max_rn * 0.8,0) THEN '80th Percentile'
WHEN rn = ROUND(M.max_rn * 0.95,0) THEN '95th Percentile'
END as metric,
days_in_node as value
FROM ORDERED as O
INNER JOIN MAX_ROWS as M on M.region_name = O.region_name
WHERE rn IN (
    ROUND(M.max_rn /2,0),
    ROUND(M.max_rn * 0.8,0),
     ROUND(M.max_rn * 0.95,0)
) ;

-- // B. Customer Transactions

-- // 1) What is the unique count and total amount for each transaction type?

select
    txn_type ,
    sum(txn_amount) as total_amount ,
    count ( txn_type) as transaction_count
from customer_transactions
group by txn_type ;

-- // 2) What is the average total historical deposit counts and amounts for all customers?

with cte as (
    select
        customer_id ,
        count (*) as transaction_count ,
        avg (txn_amount) as transaction_amount
    from customer_transactions
    where txn_type = 'deposit'
    group by customer_id
)
select
    round(avg(transaction_count), 0) as average_total_deposit_count ,
    round(avg(transaction_amount), 0) as average_total_deposit_amount
from cte ;

-- // 3) For each month - how many Data Bank customers make more than 1 deposit and either 1 purchase or 1 withdrawal in a single month?

with cte as (
    select
       monthname (date_trunc(month, txn_date)) as month ,
       customer_id ,
       sum(iff(txn_type = 'deposit', 1,0)) as deposit ,
       sum(iff(txn_type <> 'deposit',1,0)) as purchase_or_withdrawal
    from customer_transactions
    group by month, customer_id
    having deposit > 1 and purchase_or_withdrawal = 1
)
select
    count(distinct customer_id) as customers_count
from cte
group by month;

-- // 4) What is the closing balance for each customer at the end of the month?

with cte as (
    select
        date_trunc('month', txn_date) as txn_month ,
        txn_date ,
        customer_id ,
        sum( (case when txn_type = 'deposit' then txn_amount else 0 end) - (case when txn_type <> 'deposit' then txn_amount else 0 end) ) as balance 
    from customer_transactions
    group by txn_month, txn_date, customer_id
) , balances as (
    select
       * ,
       sum(balance) over (partition by customer_id order by txn_date) as running_sum ,
       row_number() over (partition by customer_id, txn_month order by txn_date desc) as rn 
    from cte
    order by txn_date
)
select
    customer_id ,
    dateadd('day',-1,dateadd('month', 1, txn_date)) as end_of_month ,
    running_sum as closing_balance 
from balances
where rn = 1 ;

-- 5) What is the percentage of customers who increase their closing balance by more than 5%?

with cte as (
    select
        date_trunc('month',txn_date) as txn_month ,
        txn_date ,
        customer_id ,
        sum ((case when txn_type = 'deposit' then txn_amount else 0 end) - (case when txn_type <> 'deposit' then txn_amount else 0 end)) as balance 
    from customer_transactions
    group by
        date_trunc('month',txn_date) ,
        txn_date ,
        customer_id
), balances as (
    select
        * ,
        sum(balance) over (partition by customer_id order by txn_date) as running_sum ,
        row_number () over (partition by customer_id, txn_month order by txn_date desc) as rn
    from cte
    order by txn_date
), closing_balances as (
    select
        customer_id ,
        dateadd('day',-1,dateadd('month',1,txn_month)) as end_of_month,
        dateadd('day',-1,txn_month) as previous_end_of_month,
        running_sum as closing_balance 
    from balances
    where rn = 1
    order by end_of_month
), percentage_increase as (
    select
        cb1.customer_id ,
        cb1.end_of_month ,
        cb1.closing_balance ,
        cb2.closing_balance as next_month_closing_balance ,
        (cb2.closing_balance / cb1.closing_balance) - 1 as percentage_increase ,
        (case when (cb2.closing_balance < cb1.closing_balance and (cb2.closing_balance / cb1.closing_balance) -1 > 0.05) then 1 else 0 end) as percentage_increase_flag
    from closing_balances as cb1
    inner join closing_balances as cb2
    on cb1.end_of_month = cb2.previous_end_of_month
    and cb1.customer_id = cb2.customer_id
    where cb1.closing_balance <> 0
)
select
    sum(percentage_increase_flag) / count (percentage_increase_flag) as percentage_of_customers_increasing_balance
from percentage_increase;

-- End
