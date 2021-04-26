use leadgen;

DECLARE	@minDate DateTime, @maxDate DateTime
	
SET @minDate = dbo.getStartOfDay('3/2/2009')
SET @maxDate = dbo.getEndOfDay('3/8/2009');	

WITH FFBilling AS (
				SELECT
					ch_chargeDateStart
					,cc_id 
				FROM CLIENTS_CHARGES_HISTORY WITH(NOLOCK)
					INNER JOIN CLIENTS_CHARGES ON cc_id = ch_cc_id		
					INNER JOIN PRODUCT_CHARGES ON pc_id = cc_pc_id
					INNER JOIN PRODUCTS ON pr_id = pc_pr_id
					INNER JOIN PRODUCT_TYPES ON pt_id = pr_pt_id
					INNER JOIN PRODUCT_FAMILIES ON pf_id = pt_pf_id
					INNER JOIN CHARGES_TYPES ON cht_id = pc_cht_id
					INNER JOIN CHARGES_TYPES_GROUPS ON ctg_id = cht_ctg_id
				WHERE pt_name LIKE 'Fit Factory'
					AND cc_co_id = 159
					AND ch_succeeded = 1
					AND ctg_recurring = 1			
				),
FFBillingTotal AS (
				SELECT
					ch_chargeDateStart = isNull(ch_chargeDateStart, 0)
					,FirstBill = (isNull(SUM(firstBill), 0))
					,SeqBill = (isNull(SUM(lastbill), 0))
				FROM ( 
					SELECT 	
						ch_chargeDateStart
						,cc_id
						,firstBill = (	SELECT CASE WHEN MIN(WB2.ch_chargeDateStart) = MAX(WB1.ch_chargeDateStart) THEN 1 ELSE 0 END FROM FFBilling WB2 WHERE WB2.cc_id = WB1.cc_id )
						,lastbill = ( SELECT CASE WHEN WB1.ch_chargeDateStart > MIN(WB2.ch_chargeDateStart) THEN 1 ELSE 0 END FROM FFBilling WB2 WHERE WB2.cc_id = WB1.cc_id )
					FROM FFBilling WB1
					WHERE ch_chargeDateStart BETWEEN @minDate AND @maxDate
					GROUP BY ch_chargeDateStart, cc_id 
					) X
				GROUP BY ch_chargeDateStart
				),
chargeRates AS (
				SELECT
					cc_startDate	
					,Sales = SUM( Sales )
					,pt_name = MIN ( pt_name )
					,co_name = MIN ( co_name )
					,cst_sourceID = MIN( cst_sourceID )
					,cst_subID = MIN( cst_subID )
					,Attempted = isNull( SUM( Attempted ), 0 )
					,Accepted = isNull( SUM( Accepted ), 0 )
					,Refunded = isNull( SUM( Refunded ), 0 )
					,Chargedback = isNull( SUM( Chargedback ), 0 )					
					,pctSaleAtt = isNull( 1.0 * SUM( Attempted ) / SUM( Sales ), 0 )
					,pctSaleAcc = isNull( 1.0 * SUM( Accepted ) / SUM( Sales ), 0 )
					,pctSaleRF = isNull( 1.0 *  SUM( Refunded ) / SUM( Sales ), 0 )
					,pctSaleCB = isNull( 1.0 * SUM( Chargedback ) / SUM( Sales ), 0 )					
					,pctAttAcc = isNull( 1.0 * SUM( Accepted ) / SUM( Attempted ), 0 )
					,pctAttRF = isNull( 1.0 *  SUM( Refunded ) / SUM( Attempted ), 0 )
					,pctAttCB = isNull( 1.0 * SUM( Chargedback ) / SUM( Attempted ), 0 )					
					,pctAccRF = isNull( 1.0 *  SUM( Refunded ) / SUM( Accepted ), 0 )
					,pctAccCB = isNull( 1.0 * SUM( Chargedback ) / SUM( Accepted ), 0 )
				FROM (
					SELECT
						cc_startDate	
						,Sales = COUNT(*)
						,pt_name
						,co_name
						,cst_sourceID
						,cst_subID = cst_subID
						,Attempted = nullIf( SUM( Attempted ), 0 )
						,Accepted = nullIf( SUM( Accepted ), 0 )
						,Refunded = nullIf( SUM( Refunded ), 0 )
						,Chargedback = nullIf( SUM( Chargedback ), 0 )		
					FROM (
						SELECT
							cc_startDate		
							,pt_name
							,co_name
							,cst_sourceID = COALESCE( cst_sourceID, '')
							,cst_subID = COALESCE( cst_subID, '')
							,Attempted = CASE
								WHEN EXISTS (SELECT NULL FROM CLIENTS_CHARGES_HISTORY WITH(NOLOCK) WHERE cc_id = ch_cc_id)
									THEN 1
								ELSE 0
							END
							,Accepted = CASE
								WHEN EXISTS (SELECT NULL FROM CLIENTS_CHARGES_HISTORY WITH(NOLOCK) WHERE cc_id = ch_cc_id AND ch_succeeded = 1)
									THEN 1
								ELSE 0
							END
							,Refunded = CASE
								WHEN EXISTS (SELECT NULL FROM CS_EVENTS WITH(NOLOCK) WHERE cc_id = ev_cc_id AND ev_et_id = 3)
									THEN 1
								ELSE 0
							END
							,Chargedback = CASE
								WHEN EXISTS (SELECT NULL FROM CS_EVENTS WITH(NOLOCK) WHERE cc_id = ev_cc_id AND ev_et_id = 4)
									THEN 1
								ELSE 0
							END
							,pc_amt
						FROM CLIENTS_CHARGES WITH(NOLOCK)
							INNER JOIN CLIENTINFO ON ci_id = cc_ci_id
							LEFT JOIN CLIENTS_SOURCE_TRACKING ON ci_id = cst_ci_id
							INNER JOIN PRODUCT_CHARGES ON pc_id = cc_pc_id
							INNER JOIN PRODUCTS ON pr_id = pc_pr_id
							INNER JOIN PRODUCT_TYPES ON pt_id = pr_pt_id
							INNER JOIN CHARGES_TYPES ON cht_id = pc_cht_id
							INNER JOIN CHARGES_TYPES_GROUPS ON ctg_id = cht_ctg_id
							INNER JOIN COMPANYS ON co_id = ci_co_id
							INNER JOIN COMPANY_CHANNELS ON coc_id = co_coc_id
						WHERE cc_startDate BETWEEN @MinDate and @MaxDate
							AND pt_name = 'Fit Factory'
							AND (
								( 
									coc_name IN ( 'InhouseWeb','OutboundCall','AffiliateWeb' )
									AND ctg_name = 'Recurring Subscription'
								)
								OR (
									coc_name IN ( 'UpsellWeb','BumpsellWeb','AffiliateWeb','InhouseWeb','OutboundCall' )
									AND ctg_name = 'Recurring Upsell'
								)
								)
						) x
						WHERE co_name LIKE 'Bottom Two LLC%'
						GROUP BY
							 cc_startDate
							,pt_name
							,co_name
							,cst_sourceID
							,cst_subID
					) y

					GROUP BY cc_startDate
			)		

select *
from chargeRates
left join FFBillingTotal on ch_chargeDateStart = cc_startDate
order by cc_startDate ASC
