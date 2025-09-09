/*  
===============================================================================
 Title   : Payments vs. Billed Totals by Lot (WC% Water Services)
 Author  : Teo Espero, IT Administrator - Marina Coast Water District
 Date    : 09/04/2025

 Purpose :  
   Consolidates payment and billed totals for WC% (FLAT) at the lot level,
   shows remaining balance, and adds a STATUS flag.

 Output Columns:  
   lot_no, service_code,
   total_amount (payment), total_amount (billed),
   difference (billed - payment), STATUS,
   street_number, street_directional, street_name, addr_2, city, state, zip,
   connect_date, final_date

 Assumptions / Limitations:  
   1) dbo.Lot has a single address record per lot_no.
   2) ub_master is authoritative for connect_date/final_date.
   3) If any service in a lot has NULL final_date, lot final_date is NULL.
   4) Payment reversals are excluded via ub_history filter.
   5) STATUS uses a small epsilon (0.01) to handle rounding.
===============================================================================
*/

DECLARE @StartDate date = '2005-07-01';
DECLARE @EndDate date = '2013-09-30';
DECLARE @Epsilon  decimal(12,4) = 0.01;  -- rounding tolerance

/* 1) Billed accounts: WC% + FLAT since @StartDate */
WITH BILLED_ACCTS AS (
    SELECT
        BD.cust_no,
        BD.cust_sequence,
        BD.service_code,
        SUM(BD.amount) AS total_billed
    FROM dbo.ub_bill_detail AS BD
    WHERE
        BD.tran_date BETWEEN @StartDate AND @EndDate
        AND (BD.tran_type = 'BILLING' OR BD.tran_type = 'CONVERT')
        AND BD.service_code LIKE 'WC%'
        AND BD.code = 'FLAT'
    GROUP BY BD.cust_no, BD.cust_sequence, BD.service_code
),

/* 2) Payments for those same billed accounts (exclude reversals; handle CONVERT%) */
PAYMENTS AS (
    SELECT
        M.cust_no,
        M.cust_sequence,
        M.service_code,
        SUM(CASE WHEN M.tran_type LIKE 'CONVERT%' THEN -M.amount ELSE M.amount END) AS total_payment
    FROM dbo.ub_bill_detail AS M
    INNER JOIN dbo.ub_history AS H
        ON H.transaction_id = M.transaction_id
       AND (
            H.tran_type LIKE '%PAYMENT' OR H.tran_type LIKE 'PAYMENT%' OR H.tran_type = 'PAYMENT'
            OR H.[description] = 'PAYMENT' OR H.[description] LIKE 'PAYMENT%' OR H.[description] LIKE '%PAYMENT'
       )
       AND H.tran_date BETWEEN @StartDate AND @EndDate
       AND H.[description] NOT LIKE 'REVERSE'
    INNER JOIN BILLED_ACCTS AS BA
        ON BA.cust_no = M.cust_no
       AND BA.cust_sequence = M.cust_sequence
       AND BA.service_code = M.service_code
    WHERE
        M.service_code LIKE 'WC%'
    GROUP BY M.cust_no, M.cust_sequence, M.service_code
),

/* 3) Map account -> lot */
ACCT_LOTS AS (
    SELECT DISTINCT
        UM.cust_no,
        UM.cust_sequence,
        UM.lot_no
    FROM dbo.ub_master AS UM
),

/* 4) Lot-level connect/final dates (NULL final if any service is open) */
LotDates AS (
    SELECT
        UM.lot_no,
        MIN(UM.connect_date) AS connect_date,
        CASE WHEN SUM(CASE WHEN UM.final_date IS NULL THEN 1 ELSE 0 END) > 0
             THEN CAST(NULL AS date)
             ELSE MAX(UM.final_date)
        END AS final_date
    FROM dbo.ub_master AS UM
    GROUP BY UM.lot_no
)

/* 5) Final output + STATUS flag */
SELECT
    LZ.lot_no,
    BA.service_code,
    SUM(ISNULL(P.total_payment, 0.0)) AS [total_amount (payment)],
    --SUM(BA.total_billed)              AS [total_amount (billed)],
    --SUM(BA.total_billed) - SUM(ISNULL(P.total_payment, 0.0)) AS [difference (billed - payment)],
    --CASE
    --    WHEN ABS(SUM(BA.total_billed) - SUM(ISNULL(P.total_payment, 0.0))) <= @Epsilon
    --        THEN 'PAID'
    --    WHEN (SUM(BA.total_billed) - SUM(ISNULL(P.total_payment, 0.0))) > @Epsilon
    --        THEN 'PARTIAL/UNPAID'
    --    ELSE 'OVERPAID'
    --END AS STATUS,
    LT.street_number,
    LT.street_directional,
    LT.street_name,
    LT.addr_2,
    LT.city,
    LT.state,
    LT.zip,
    D.connect_date,
    D.final_date
FROM BILLED_ACCTS AS BA
JOIN ACCT_LOTS AS LZ
  ON LZ.cust_no = BA.cust_no
 AND LZ.cust_sequence = BA.cust_sequence
LEFT JOIN PAYMENTS AS P
  ON P.cust_no = BA.cust_no
 AND P.cust_sequence = BA.cust_sequence
 AND P.service_code = BA.service_code
JOIN LotDates AS D
  ON D.lot_no = LZ.lot_no
JOIN dbo.Lot AS LT
  ON LT.lot_no = LZ.lot_no
GROUP BY
    LZ.lot_no,
    BA.service_code,
    LT.street_number,
    LT.street_directional,
    LT.street_name,
    LT.addr_2,
    LT.city,
    LT.state,
    LT.zip,
    D.connect_date,
    D.final_date
ORDER BY
    LZ.lot_no,
    BA.service_code;
