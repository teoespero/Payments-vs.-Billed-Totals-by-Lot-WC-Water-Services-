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
