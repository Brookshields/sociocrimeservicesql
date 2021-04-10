-- Reorganize census table and add a column to categorize communities based on income data. 
create table calgarycensusbackup select * from calgarycensus;
alter table calgarycensus add column inc_class varchar(10);
update calgarycensus set inc_class=(case  when household_median_income>0 and household_median_income<84705 then 'low' 
when household_median_income>84705 and household_median_income<112016 then 'medium'
when household_median_income>112016  then 'high' 
end);
create table calgary_inc_ed select id,Community,Household_cnt,Household_Mean_Income,Household_Median_Income,Res_Cnt_over15yrs,inc_class,Non_edu_pct,Post_sec_pct,Uni_pct from calgarycensus;

-- Make a new table 'ccspop' to include community population and crime rate into crimestatistics table.        
create table ccspop 
SELECT 
    calgarycrimestatisticscopy.*, popu.population
FROM
    calgarycrimestatisticscopy
        JOIN
    (SELECT 
        name, census_year, population
    FROM
        historiccensus
    WHERE
        YEAR(census_year) = 2016) popu ON calgarycrimestatisticscopy.communityname = popu.name;
alter table ccspop add column crime_rate float;    
update ccspop set crime_rate= if(population=0,null,crimecount*100000/population);
-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

-- Income vs. Crime

-- Is crime rate higher in low-income or high-income communities?
select crime.communityname, round(crime.crimerate, 2) crimerate, inc_class
from 
	(select sum(crime_rate) crimerate,communityname 
	from ccspop group by communityname) crime 
join calgarycensus 
on crime.communityname=calgarycensus.community 
order by crimerate desc;
-- Comment: In top 10 crime rate communities, 8 are low-income.

-- What is the most typical crime category in low-income communities? 
select community Community, inc_class `Income Class`, category `Crime Category` 
from calgarycensus cs
INNER JOIN (SELECT tb1.communityname, tb1.category, tb1.rate
			FROM 
			(SELECT communityname, category, SUM(crime_rate) rate
					 FROM ccspop
					 WHERE groupcategory='crime'
					GROUP BY communityname , category) tb1
			INNER JOIN 
				(SELECT tb2.communityname, Max(tb2.rate) maxRate
				FROM 
					(SELECT communityname, category, SUM(crime_rate) rate
					 FROM ccspop
					 WHERE groupcategory='crime'
					GROUP BY communityname , category) tb2
				Group BY tb2.communityname) tb3
			ON tb1.communityname = tb3.communityname and tb1.rate = tb3.maxRate) tab 
on cs.community=tab.communityname
where cs.inc_class='low'
Order by `Crime Category`;

-- What is the most typical crime category in high-income communities? 
select community Community, inc_class `Income Class`, category `Crime Category`, round(rate,2) Top_Crime_Category_rate, ccr.CrimeRate Total_Crime_Rate_In_Community
from calgarycensus cs
INNER JOIN (SELECT tb1.communityname, tb1.category, tb1.rate
			FROM 
			(SELECT communityname, category, SUM(crime_rate) rate
					 FROM ccspop
					 WHERE groupcategory='crime'
					GROUP BY communityname , category) tb1
			INNER JOIN 
				(SELECT tb2.communityname, Max(tb2.rate) maxRate
				FROM 
					(SELECT communityname, category, SUM(crime_rate) rate
					 FROM ccspop
					 WHERE groupcategory='crime'
					GROUP BY communityname , category) tb2
				Group BY tb2.communityname) tb3
			ON tb1.communityname = tb3.communityname and tb1.rate = tb3.maxRate) tab 
on cs.community=tab.communityname
Inner join calgarycrimerate ccr
ON cs.community=ccr.CommunityName
where cs.inc_class='high'
and ccr.CRYear = 2016
order by category;
-- Comment: Other than 'Theft from Vehicle',in low-income communities, dominant crime
-- category is 'Assault (Non-domestic)', while it's 'Residential Break&Enter' in high-income
-- communities.

-- What is the correlation between crime rate and median income?
   -- Step 1. Add population and calculated crime rate.
	select cs.cryear, cs.CommunityName, cs.CrimeCount, hc.population, round((cs.CrimeCount/hc.population) * 100000) Crime_Rate
	from 
			(select CommunityName, crimeYear crYear, Sum(CrimeCount) CrimeCount from 
			calgarycrimestatistics
			group by CommunityName, crimeYear) cs
				inner join 
			(select name, Year(census_year) cYear, population from 
			historiccensus
			where Year(census_year) in (2012, 2013, 2014, 2015, 2016)) hc
			on hc.cYear = cs.crYear and hc.name = cs.CommunityName
	order by cryear, CommunityName;

    -- Step2. Join CrimeRate Table to Calgary Census Table based on Community Name for Year 2016.
	SELECT community as Community , inc_class as IncomeClass, Household_cnt as HouseholdCount, Household_Mean_Income as AverageIncome, Household_Median_Income as MedianIncome ,CrimeRate, Population
	from calgarycensus cs
	INNER JOIN (SELECT CommunityName, Population, CrimeRate
				FROM calgarycrimerate where CRYear=2016) ccr
			ON  ccr.communityname = cs.community;
        
    -- Step3. Simple linear regression between variables crime rate and average income
       /*A regression line is expressed as follows, where a and b are the intercept and slope of the
        line:
        Y = bX + a
        Letting AverageIncome be X and CrimeRate be Y, */
		SELECT
		 @n := COUNT(CrimeRate) AS N,
		 @meanX := AVG(MedianIncome) AS "X mean",
		 @sumX := SUM(MedianIncome) AS "X sum",
		 @sumXX := SUM(MedianIncome*MedianIncome) "X sum of squares",
		 @meanY := AVG(CrimeRate) AS "Y mean",
		 @sumY := SUM(CrimeRate) AS "Y sum",
		 @sumYY := SUM(CrimeRate*CrimeRate) "Y sum of square",
		 @sumXY := SUM(MedianIncome*CrimeRate) AS "X*Y sum"
		FROM (SELECT community as Community , inc_class as IncomeClass, Household_cnt as HouseholdCount, Household_Mean_Income as AverageIncome, Household_Median_Income as MedianIncome ,CrimeRate, Population
				FROM calgarycensus cs
				INNER JOIN (SELECT CommunityName, Population, CrimeRate
							FROM calgarycrimerate where CRYear=2016) ccr
						ON  ccr.communityname = cs.community) cc;
		 -- Calculate Slope
			SELECT
			 @b := (@n*@sumXY - @sumX*@sumY) / (@n*@sumXX - @sumX*@sumX)
			 AS slope;
		 -- Calculate Intercept
			SELECT @a :=
			  (@meanY - @b*@meanX)
			 AS intercept;
		 -- Calulate regression coefficient
			SELECT CONCAT('Y = ',@b,'X + ',@a) AS 'least-squares regression';
	 
     -- Step 4. To compute the correlation coefficient, many of the same terms are used:
		SELECT
		 round((@n*@sumXY - @sumX*@sumY)
		 / SQRT((@n*@sumXX - @sumX*@sumX) * (@n*@sumYY - @sumY*@sumY)),2)
		 AS correlation;
-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

-- Education vs.Crime

-- Are communities with higher education level less prone to become target area for crime?
select crime.communityname, round(crime.crimerate, 2) crimerate, uni_pct 
from 
	(select sum(crime_rate) crimerate,communityname 
	from ccspop group by communityname) crime 
join calgarycensus 
on crime.communityname=calgarycensus.community 
order by crimerate desc;
-- Comment:No obvious relation is found.

-- What is the most typical crime category in communities with more than 60% of residents achieved 
-- equal or above university education?  
select community, uni_pct, round(rate,2) Crimerate, category 
from calgarycensus 
INNER JOIN 
	(SELECT tb1.communityname, tb1.category, tb1.rate
	FROM 
	(SELECT communityname, category, SUM(crime_rate) rate
			 FROM ccspop
			 WHERE groupcategory='crime'
			GROUP BY communityname , category) tb1
	INNER JOIN 
		(SELECT tb2.communityname, Max(tb2.rate) maxRate
		FROM 
			(SELECT communityname, category, SUM(crime_rate) rate
			 FROM ccspop
			 WHERE groupcategory='crime'
			GROUP BY communityname , category) tb2
		Group BY tb2.communityname) tb3
	ON tb1.communityname = tb3.communityname and tb1.rate = tb3.maxRate) tab 
on calgarycensus.community=tab.communityname
where uni_pct>60;
-- Comment: No obvious relation is observed.
-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

-- Business vs.Crime

-- Are communities with high number of liquor and cannabis stores more vulnerable to crime?
select communityname, round(crime_rate,2) crimerate, coalesce(NumberofBusiness , 0) NumberofBusiness
from 
	(select sum(crime_rate) crime_rate, communityname
	from ccspop 
	group by communityname) crime 
LEFT JOIN 
	(SELECT 
		commname, COUNT(*) NumberofBusiness
	FROM
		calgary_business_licenses
	WHERE
        (License_type like '%LIQUOR%' or License_type like '%ALCOHOL%' or License_type like '%CANNABIS%')
			AND Status_year = 2016
	GROUP BY commname) busi 
on crime.communityname=busi.commname
order by crime_rate desc;
-- Comment: Beltline and downtown commercial area having 18 and 15 alchohol business in the meantime have
-- high crime_rate.


-- What is the rate of change in number of business licenses for each community between years 2015 and 2016?
-- Here we are calculating the increase or decrease percentage of crime rate of all communities and 
-- storing it in a table for further exploration

Create table Rate_Of_Change_In_BusinessLicenses
	Select 2016_CBL.CommName, 
		2015_CBL.ActiveLicenses 2015_Licenses_Count, 
		2016_CBL.ActiveLicenses 2016_Licenses_Count,
		((2016_CBL.ActiveLicenses - 2015_CBL.ActiveLicenses)/2015_CBL.ActiveLicenses) * 100 BL_Rate_Of_Change
		FROM
		(Select CommName, Count(ID) ActiveLicenses
			from Calgary_Business_Licenses
			where Status_year = 2016 
			GROUP BY CommName) 2016_CBL
		LEFT JOIN 
		(Select CommName, Count(ID) ActiveLicenses
			from Calgary_Business_Licenses
			where Status_year = 2015 
			GROUP BY CommName) 2015_CBL
		ON 2016_CBL.CommName = 2015_CBL.CommName
        UNION
		Select 2015_CBL.CommName, 
		2015_CBL.ActiveLicenses 2015_Licenses_Count, 
		2016_CBL.ActiveLicenses 2016_Licenses_Count,
		((2016_CBL.ActiveLicenses - 2015_CBL.ActiveLicenses)/2015_CBL.ActiveLicenses) * 100 BL_Rate_Of_Change
		FROM
		(Select CommName, Count(ID) ActiveLicenses
			from Calgary_Business_Licenses
			where Status_year = 2016 
			GROUP BY CommName) 2016_CBL
		RIGHT JOIN 
		(Select CommName, Count(ID) ActiveLicenses
			from Calgary_Business_Licenses
			where Status_year = 2015 
			GROUP BY CommName) 2015_CBL
		ON 2015_CBL.CommName = 2016_CBL.CommName;
        
        
-- What is the rate of change in crime rate for each community between years 2015 and 2016?
-- Here we are calculating the increase or decrease percentage of crime rate of all communities and 
-- storing it in a table for further exploration

Create table Rate_Of_Change_In_CrimeRate
Select * from (		Select 2016_CR.CommunityName, 
		2015_CR.CrimeRate 2015_CrimeRate, 
		2016_CR.CrimeRate 2016_CrimeRate,
		((2016_CR.CrimeRate - 2015_CR.CrimeRate)/2015_CR.CrimeRate) * 100 CR_Rate_Of_Change
		FROM
		(Select CommunityName, CrimeRate
			from CalgaryCrimeRate
			where CRYear = 2016 ) 2016_CR
		LEFT JOIN 
		(Select CommunityName, CrimeRate
			from CalgaryCrimeRate
			where CRYear = 2015 
		) 2015_CR
		ON 2016_CR.CommunityName = 2015_CR.CommunityName
        UNION
		Select 2015_CR.CommunityName, 
		2015_CR.CrimeRate 2015_CrimeRate, 
		2016_CR.CrimeRate 2016_CrimeRate,
		((2016_CR.CrimeRate - 2015_CR.CrimeRate)/2015_CR.CrimeRate) * 100 CR_Rate_Of_Change
		FROM
		(Select CommunityName, CrimeRate
			from CalgaryCrimeRate
			where CRYear = 2016 ) 2016_CR
		RIGHT JOIN 
		(Select CommunityName, CrimeRate
			from CalgaryCrimeRate
			where CRYear = 2015 
		) 2015_CR
		ON 2015_CR.CommunityName = 2016_CR.CommunityName) CRL_Change_Rate
        Order by CRL_Change_Rate.CR_Rate_Of_Change
        ;     
        
-- Now lets identify if the increase in decrease of crime rate in Calgary communities does have any impact in the rate of change in Business.

-- Step 1. simple linear regression between rate of change for crime rate change and business license count.
	/*A regression line is expressed as follows, where a and b are the intercept and slope of the
	line:
	Y = bX + a
	Letting rate of change for crime rate be X and rate of change for business license count be Y, */
        
	SELECT
		 @n := COUNT(CR_Rate_of_Change) AS N,
		 @meanX := AVG(CR_Rate_of_Change) AS "X mean",
		 @sumX := SUM(CR_Rate_of_Change) AS "X sum",
		 @sumXX := SUM(CR_Rate_of_Change*CR_Rate_of_Change) "X sum of squares",
		 @meanY := AVG(BL_Rate_Of_Change) AS "Y mean",
		 @sumY := SUM(BL_Rate_Of_Change) AS "Y sum",
		 @sumYY := SUM(BL_Rate_Of_Change*BL_Rate_Of_Change) "Y sum of square",
		 @sumXY := SUM(CR_Rate_of_Change*BL_Rate_Of_Change) AS "X*Y sum"
	FROM (Select RCCR.CommunityName, RCCR.CR_Rate_of_Change, RCBL.BL_Rate_Of_Change
			From rate_of_change_in_crimerate RCCR
			INNER JOIN rate_of_change_in_businesslicenses RCBL
			on RCCR.CommunityName = RCBL.CommName
			WHERE RCCR.CR_Rate_of_Change is not null 
			and  RCBL.BL_Rate_Of_Change is not null) cc;

-- Calculate Slope
	SELECT	 @b := (@n*@sumXY - @sumX*@sumY) / (@n*@sumXX - @sumX*@sumX)
	 AS slope;
     
-- Calculate Intercept
	SELECT @a := (@meanY - @b*@meanX)
	 AS intercept;
     
-- calulate regression coefficient
	SELECT CONCAT('Y = ',@b,'X + ',@a) AS 'least-squares regression';
		 
-- Step 2. To compute the correlation coefficient, many of the same terms are used:
-- Now lets calculate the correlation coefficient to identify how does crime impact bussiness?

SELECT
 round((@n*@sumXY - @sumX*@sumY)
 / SQRT((@n*@sumXX - @sumX*@sumX) * (@n*@sumYY - @sumY*@sumY)),3)
 AS correlation;
 
-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

-- Business vs. Income

-- What are the top businesses in Calgary’s high-income communities?
Select tb3.license_type, Sum(tb3.NumoFBusiness) TotalNumofBusiness
FROM 
	(
	SELECT 
		ccs.community, ccs.inc_class, tb1.license_type, tb1.counts NumoFBusiness
	FROM
	calgarycensus ccs
	INNER JOIN 
		(SELECT 
				tb.commname, license_type, counts
			FROM
				(SELECT 
					commname, license_type, COUNT(*) counts
					FROM
						calgary_business_licenses
					WHERE
						Status_year = 2016
					GROUP BY commname , license_type) tb
			INNER JOIN 
				(SELECT 
						MAX(counts) top, commname
					FROM
						(SELECT 
							commname, license_type, COUNT(*) counts
							FROM
								calgary_business_licenses
							WHERE
								Status_year = 2016
							GROUP BY commname , license_type) tb1
					GROUP BY commname) tb2 
			ON tb.commname = tb2.commname
			AND tb2.top = tb.counts) tb1
	ON ccs.community = tb1.commname
	WHERE ccs.inc_class='high') tb3
Group by tb3.license_type
Order by TotalNumofBusiness desc;

-- What are the top businesses in Calgary’s low-income communities?
Select tb3.license_type, Sum(tb3.NumoFBusiness) TotalNumofBusiness
FROM 
	(
	SELECT 
		ccs.community, ccs.inc_class, tb1.license_type, tb1.counts NumoFBusiness
	FROM
	calgarycensus ccs
	INNER JOIN 
		(SELECT 
				tb.commname, license_type, counts
			FROM
				(SELECT 
					commname, license_type, COUNT(*) counts
					FROM
						calgary_business_licenses
					WHERE
						Status_year = 2016
					GROUP BY commname , license_type) tb
			INNER JOIN 
				(SELECT 
						MAX(counts) top, commname
					FROM
						(SELECT 
							commname, license_type, COUNT(*) counts
							FROM
								calgary_business_licenses
							WHERE
								Status_year = 2016
							GROUP BY commname , license_type) tb1
					GROUP BY commname) tb2 
			ON tb.commname = tb2.commname
			AND tb2.top = tb.counts) tb1
	ON ccs.community = tb1.commname
	WHERE ccs.inc_class='low') tb3
Group by tb3.license_type
Order by TotalNumofBusiness desc;

-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

-- Service vs. Crime

-- Which agency received the highest number of requests from communities with high crime rate?
Select ccr.CommunityName, ccr.CrimeRate, ccsr.agency_responsible, ccsr.Requestcounts
from 
calgarycrimerate ccr
INNER JOIN 
	(
	Select csrCountstbl.comm_name, csrCountstbl.agency_responsible, csrCountstbl.Requestcounts
	from 
		(select comm_name, agency_responsible, count(*) Requestcounts
		 from calgary_service_requests 
         where year
         group by comm_name, agency_responsible
		) csrCountstbl
	Inner join 
	(
	select max(counts) maxReqCnts, comm_name 
	from 
		(select count(*) counts, comm_name, agency_responsible
		 from calgary_service_requests group by comm_name, agency_responsible
		) tb 
	group by comm_name) ccsr
	ON csrCountstbl.comm_name=ccsr.comm_name AND csrCountstbl.Requestcounts = ccsr.maxReqCnts
	) ccsr
ON ccr.CommunityName = ccsr.comm_name
WHERE ccr.CRYear = 2016
ORDER BY ccr.CrimeRate desc;

-- What is the most frequent service requested from communities with higher crime count?
Select tb1.CommunityName, tb1.CrimeCount, ccsrs.Service_Name ServiceName, SNAgncy.Agency_Responsible, ccsrs.Requestcounts
From 
	(Select CrimeYear, CommunityName, Sum(CrimeCount) CrimeCount
	FROM `l02-7`.calgarycrimestatistics 
	where CrimeYear = 2016
	group by CrimeYear, CommunityName) tb1
INNER JOIN 
	(
	Select csrCountstbl.comm_name, csrCountstbl.service_name, csrCountstbl.Requestcounts
	from 
		(select comm_name, service_name, count(*) Requestcounts
		 from calgary_service_requests group by comm_name, service_name
		) csrCountstbl
	Inner join 
	(
	select comm_name, max(counts) maxReqCnts
	from 
		(select comm_name, service_name, count(*) counts
		 from calgary_service_requests group by comm_name, service_name
		) tb 
	group by comm_name) ccsr
	ON csrCountstbl.comm_name=ccsr.comm_name AND csrCountstbl.Requestcounts = ccsr.maxReqCnts
	) ccsrs
ON tb1.CommunityName = ccsrs.comm_name
INNER JOIN 
	(SELECT service_name, Agency_Responsible FROM calgary_service_requests
	group by service_name, Agency_Responsible) SNAgncy
ON ccsrs.service_name = SNAgncy.service_name
ORDER BY tb1.CrimeCount desc;


-- Does these data set support 'Broken Window Theory'? What is the correlation between service request and crime?

-- Step 1.Simple linear regression between crime count and service request count.
	/*A regression line is expressed as follows, where a and b are the intercept and slope of the
	line:
	Y = bX + a
	Letting service request count be X and crime count be Y, */
    
SELECT
	 @n := COUNT(NumberOfSRs) AS N,
	 @meanX := AVG(NumberOfSRs) AS "X mean",
	 @sumX := SUM(NumberOfSRs) AS "X sum",
	 @sumXX := SUM(NumberOfSRs*NumberOfSRs) "X sum of squares",
	 @meanY := AVG(crimecount) AS "Y mean",
	 @sumY := SUM(crimecount) AS "Y sum",
	 @sumYY := SUM(crimecount*crimecount) "Y sum of square",
	 @sumXY := SUM(NumberOfSRs*crimecount) AS "X*Y sum"
FROM 
	(Select ccr.CommunityName, csr.NumberOfSRs, ccr.crimecount 
	from `l02-7`.calgarycrimerate ccr
	Inner join 
		(Select Comm_Name, Count(Service_Name) NumberOfSRs 
			from `l02-7`.calgary_service_requests
			Where Service_Name IN ('Bylaw - Disturbance and Behavioural Concerns',
									'Bylaw - Material on Public Property',
									'Bylaw - Noise Concerns',
									'Bylaw - Other Concerns',
									'Bylaw - Property Maintenance Concerns',
									'Bylaw - Vandalism and Property Damage Concerns',
									'Bylaw - Vehicle Concerns',
									'Corporate - Graffiti Concerns',
									'Roads - Streetlight Damage',
									'Roads - Streetlight Maintenance',
									'Roads - Traffic or Pedestrian Light Repair')
			And Requested_Year = 2016
			Group by Comm_Name) CSR
	On CCR.CommunityName = CSR.Comm_Name
	Where ccr.CRYear = 2016) cc;
    
-- Calculate Slope

SELECT @b := (@n*@sumXY - @sumX*@sumY) / (@n*@sumXX - @sumX*@sumX)
AS slope;

-- Calculate Intercept

SELECT @a := (@meanY - @b*@meanX)
 AS intercept;

 -- Calulate regression coefficient
 SELECT CONCAT('Y = ',@b,'X + ',@a) AS 'least-squares regression';
		 
 -- Step 2. To compute the correlation coefficient, many of the same terms are used:
SELECT
 round((@n*@sumXY - @sumX*@sumY)
 / SQRT((@n*@sumXX - @sumX*@sumX) * (@n*@sumYY - @sumY*@sumY)),2)
 AS correlation;
-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

-- Income vs Services received

-- What are the top service requests in Calgary’s high-income communities?
Select  tb1.Service_Name, Sum(tb1.Requestcounts) TotalRequestcounts
from
(
	SELECT 
		ccs.community, ccs.inc_class, ccsr.service_name, ccsr.Requestcounts 
	FROM
	calgarycensus ccs
	INNER JOIN 
		(
		Select csrCountstbl.comm_name, csrCountstbl.service_name, csrCountstbl.Requestcounts
		from 
			(select comm_name, service_name, count(*) Requestcounts
			 from calgary_service_requests group by comm_name, service_name
			) csrCountstbl
		Inner join 
		(
		select comm_name, max(counts) maxReqCnts
		from 
			(select comm_name, service_name, count(*) counts
			 from calgary_service_requests group by comm_name, service_name
			) tb 
		group by comm_name) ccsr
		ON csrCountstbl.comm_name=ccsr.comm_name AND csrCountstbl.Requestcounts = ccsr.maxReqCnts
		) ccsr
	ON ccs.community = ccsr.comm_name
	WHERE ccs.inc_class='high') tb1
Group by tb1.Service_Name
Order by TotalRequestcounts desc;

-- What are the top service requests in Calgary’s low-income communities?
Select  tb1.Service_Name, Sum(tb1.Requestcounts) TotalRequestcounts
from
(
	SELECT 
		ccs.community, ccs.inc_class, ccsr.service_name, ccsr.Requestcounts 
	FROM
	calgarycensus ccs
	INNER JOIN 
		(
		Select csrCountstbl.comm_name, csrCountstbl.service_name, csrCountstbl.Requestcounts
		from 
			(select comm_name, service_name, count(*) Requestcounts
			 from calgary_service_requests group by comm_name, service_name
			) csrCountstbl
		Inner join 
		(
		select comm_name, max(counts) maxReqCnts
		from 
			(select comm_name, service_name, count(*) counts
			 from calgary_service_requests group by comm_name, service_name
			) tb 
		group by comm_name) ccsr
		ON csrCountstbl.comm_name=ccsr.comm_name AND csrCountstbl.Requestcounts = ccsr.maxReqCnts
		) ccsr
	ON ccs.community = ccsr.comm_name
	WHERE ccs.inc_class='low') tb1
Group by tb1.Service_Name
Order by TotalRequestcounts desc;

-- How does total number of requests change with community income? 
SELECT 
	ccs.community, ccs.inc_class, csr.Requestcounts 
FROM
calgarycensus ccs
INNER JOIN 
	(select comm_name, count(CS_ID) Requestcounts
	 from calgary_service_requests group by comm_name
	) csr
ON ccs.community = csr.comm_name
ORDER BY csr.Requestcounts desc;
