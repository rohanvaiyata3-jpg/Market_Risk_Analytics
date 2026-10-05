CREATE DATABASE IF NOT EXISTS market_risk_analytics;

USE market_risk_analytics;

DROP TABLE IF EXISTS market_prices;

CREATE TABLE market_prices (
    Date DATE,
    Ticker VARCHAR(10),
    Adj_Close DOUBLE,
    Close DOUBLE,
    High DOUBLE,
    Low DOUBLE,
    Open DOUBLE,
    Volume BIGINT
);



LOAD DATA INFILE
'C:/ProgramData/MySQL/MySQL Server 8.0/Uploads/market_prices_clean.csv'

INTO TABLE market_prices

FIELDS TERMINATED BY ','
ENCLOSED BY '"'

LINES TERMINATED BY '\n'

IGNORE 1 ROWS

(Date, Ticker, Adj_Close, Close, High, Low, Open, Volume);

SELECT COUNT(*) AS total_records
FROM market_prices;

SELECT DISTINCT Ticker
FROM market_prices
ORDER BY Ticker;

SELECT
    MIN(Date) AS first_date,
    MAX(Date) AS last_date
FROM market_prices;


SELECT
    COUNT(*) AS total_rows,
    SUM(Date IS NULL) AS missing_dates,
    SUM(Ticker IS NULL) AS missing_tickers,
    SUM(Adj_Close IS NULL) AS missing_adj_close,
    SUM(Close IS NULL) AS missing_close,
    SUM(High IS NULL) AS missing_high,
    SUM(Low IS NULL) AS missing_low,
    SUM(Open IS NULL) AS missing_open,
    SUM(Volume IS NULL) AS missing_volume
FROM market_prices;

SELECT
    Date,
    Ticker,
    COUNT(*) AS duplicate_count
FROM market_prices
GROUP BY Date, Ticker
HAVING COUNT(*) > 1;

SELECT *
FROM market_prices
WHERE
    Adj_Close <= 0
    OR Close <= 0
    OR High <= 0
    OR Low <= 0
    OR Open <= 0;


SELECT *
FROM market_prices
WHERE
    High < Low
    OR High < Open
    OR High < Close
    OR Low > Open
    OR Low > Close;

SELECT *
FROM market_prices
WHERE Volume < 0;

SELECT
    Date,
    Ticker,
    Adj_Close,
    Close,
    Volume
FROM market_prices
ORDER BY Date DESC, Ticker
LIMIT 20;

SELECT
    Ticker,
    MIN(Date) AS First_Date,
    MAX(Date) AS Last_Date,
    MIN(Adj_Close) AS Minimum_Price,
    MAX(Adj_Close) AS Maximum_Price,
    AVG(Adj_Close) AS Average_Price
FROM market_prices
GROUP BY Ticker
ORDER BY Ticker;


DROP TABLE IF EXISTS portfolio_holdings;

CREATE TABLE portfolio_holdings (
    Ticker VARCHAR(10),
    Asset_Class VARCHAR(30),
    Weight DOUBLE
);


INSERT INTO portfolio_holdings
    (Ticker, Asset_Class, Weight)
VALUES
    ('AAPL', 'Equity', 0.15),
    ('MSFT', 'Equity', 0.15),
    ('JPM', 'Equity', 0.15),
    ('NVDA', 'Equity', 0.15),
    ('SPY', 'Equity ETF', 0.20),
    ('GLD', 'Commodity ETF', 0.10),
    ('TLT', 'Bond ETF', 0.10);

SELECT
    Ticker,
    Asset_Class,
    Weight,
    Weight * 100 AS Weight_Percentage
FROM portfolio_holdings
ORDER BY Weight DESC;


SELECT
    SUM(Weight) AS Total_Weight,
    SUM(Weight) * 100 AS Total_Weight_Percentage
FROM portfolio_holdings;

DROP TABLE IF EXISTS asset_returns;

CREATE TABLE asset_returns AS

SELECT
    Date,
    Ticker,
    Adj_Close,

    (
        Adj_Close /
        LAG(Adj_Close) OVER (
            PARTITION BY Ticker
            ORDER BY Date
        )
    ) - 1 AS Daily_Return

FROM market_prices;

SELECT *
FROM asset_returns
ORDER BY Date, Ticker
LIMIT 20;

SELECT
    Ticker,

    COUNT(Daily_Return) AS Trading_Days,

    AVG(Daily_Return) AS Average_Daily_Return,

    STDDEV_SAMP(Daily_Return) AS Daily_Volatility,

    AVG(Daily_Return) * 252 AS Annualized_Return,

    STDDEV_SAMP(Daily_Return) * SQRT(252)
        AS Annualized_Volatility

FROM asset_returns

WHERE Daily_Return IS NOT NULL

GROUP BY Ticker

ORDER BY Annualized_Volatility DESC;


SELECT
    Date,
    Ticker,
    Daily_Return,
    Daily_Return * 100 AS Return_Percentage
FROM asset_returns
WHERE Daily_Return IS NOT NULL
ORDER BY Daily_Return DESC
LIMIT 10;

SELECT
    Date,
    Ticker,
    Daily_Return,
    Daily_Return * 100 AS Return_Percentage
FROM asset_returns
WHERE Daily_Return IS NOT NULL
ORDER BY Daily_Return ASC
LIMIT 10;

SELECT
    Ticker,
    YEAR(Date) AS Year,
    MONTH(Date) AS Month,

    AVG(Daily_Return) AS Average_Daily_Return,

    STDDEV_SAMP(Daily_Return) AS Monthly_Daily_Volatility

FROM asset_returns

WHERE Daily_Return IS NOT NULL

GROUP BY
    Ticker,
    YEAR(Date),
    MONTH(Date)

ORDER BY
    Year,
    Month,
    Ticker;


DROP TABLE IF EXISTS portfolio_daily_returns;

CREATE TABLE portfolio_daily_returns AS

SELECT
    r.Date,

    SUM(
        r.Daily_Return * p.Weight
    ) AS Portfolio_Return

FROM asset_returns r

JOIN portfolio_holdings p
    ON r.Ticker = p.Ticker

WHERE r.Daily_Return IS NOT NULL

GROUP BY r.Date

HAVING COUNT(DISTINCT r.Ticker) = 7;

SELECT *
FROM portfolio_daily_returns
ORDER BY Date
LIMIT 20;

SELECT

    COUNT(*) AS Trading_Days,

    AVG(Portfolio_Return)
        AS Average_Daily_Return,

    STDDEV_SAMP(Portfolio_Return)
        AS Daily_Volatility,

    AVG(Portfolio_Return) * 252
        AS Annualized_Return,

    STDDEV_SAMP(Portfolio_Return) * SQRT(252)
        AS Annualized_Volatility

FROM portfolio_daily_returns;



SELECT

    (
        AVG(Portfolio_Return) * 252
    )
    /
    (
        STDDEV_SAMP(Portfolio_Return) * SQRT(252)
    )
    AS Sharpe_Ratio

FROM portfolio_daily_returns;


WITH ranked_returns AS (

    SELECT
        Portfolio_Return,

        ROW_NUMBER() OVER (
            ORDER BY Portfolio_Return
        ) AS row_num,

        COUNT(*) OVER () AS total_rows

    FROM portfolio_daily_returns
)

SELECT

    Portfolio_Return AS Historical_VaR_95

FROM ranked_returns

WHERE row_num = CEIL(total_rows * 0.05);


WITH var_value AS (

    SELECT

        Portfolio_Return AS VaR_95

    FROM (

        SELECT
            Portfolio_Return,

            ROW_NUMBER() OVER (
                ORDER BY Portfolio_Return
            ) AS row_num,

            COUNT(*) OVER () AS total_rows

        FROM portfolio_daily_returns

    ) ranked

    WHERE row_num = CEIL(total_rows * 0.05)
)

SELECT

    AVG(p.Portfolio_Return)
        AS Expected_Shortfall_95

FROM portfolio_daily_returns p

CROSS JOIN var_value v

WHERE p.Portfolio_Return <= v.VaR_95;


WITH cumulative_returns AS (

    SELECT
        Date,
        Portfolio_Return,

        EXP(
            SUM(
                LN(1 + Portfolio_Return)
            ) OVER (
                ORDER BY Date
            )
        ) AS Cumulative_Return

    FROM portfolio_daily_returns
)

SELECT

    Date,
    Portfolio_Return,
    Cumulative_Return,

    (
        Cumulative_Return /
        MAX(Cumulative_Return) OVER (
            ORDER BY Date
            ROWS BETWEEN UNBOUNDED PRECEDING
            AND CURRENT ROW
        )
    ) - 1 AS Drawdown

FROM cumulative_returns

ORDER BY Date;


WITH cumulative_returns AS (

    SELECT
        Date,

        EXP(
            SUM(
                LN(1 + Portfolio_Return)
            ) OVER (
                ORDER BY Date
            )
        ) AS Cumulative_Return

    FROM portfolio_daily_returns
),

drawdowns AS (

    SELECT

        Date,
        Cumulative_Return,

        (
            Cumulative_Return /
            MAX(Cumulative_Return) OVER (
                ORDER BY Date
                ROWS BETWEEN UNBOUNDED PRECEDING
                AND CURRENT ROW
            )
        ) - 1 AS Drawdown

    FROM cumulative_returns
)

SELECT

    MIN(Drawdown) AS Maximum_Drawdown

FROM drawdowns;

SELECT

    Ticker,

    STDDEV_SAMP(Daily_Return)
        AS Daily_Volatility,

    STDDEV_SAMP(Daily_Return) * SQRT(252)
        AS Annualized_Volatility

FROM asset_returns

WHERE Daily_Return IS NOT NULL

GROUP BY Ticker

ORDER BY Annualized_Volatility DESC;


-- ============================================================
-- 21. ASSET PERFORMANCE RANKING
-- ============================================================

SELECT

    Ticker,

    AVG(Daily_Return) * 252
        AS Annualized_Return,

    STDDEV_SAMP(Daily_Return) * SQRT(252)
        AS Annualized_Volatility,

    (
        AVG(Daily_Return) * 252
    )
    /
    (
        STDDEV_SAMP(Daily_Return) * SQRT(252)
    )
        AS Return_to_Risk_Ratio

FROM asset_returns

WHERE Daily_Return IS NOT NULL

GROUP BY Ticker

ORDER BY Return_to_Risk_Ratio DESC;


SELECT

    Date,
    Portfolio_Return

FROM portfolio_daily_returns

ORDER BY Date DESC

LIMIT 30;


SELECT

    YEAR(Date) AS Year,
    MONTH(Date) AS Month,

    AVG(Portfolio_Return)
        AS Average_Daily_Return,

    STDDEV_SAMP(Portfolio_Return)
        AS Daily_Volatility,

    AVG(Portfolio_Return) * 252
        AS Annualized_Return

FROM portfolio_daily_returns

GROUP BY
    YEAR(Date),
    MONTH(Date)

ORDER BY
    Year,
    Month;


SELECT

    COUNT(*) AS Trading_Days,

    ROUND(
        AVG(Portfolio_Return) * 252 * 100,
        2
    ) AS Annualized_Return_Percent,

    ROUND(
        STDDEV_SAMP(Portfolio_Return)
        * SQRT(252) * 100,
        2
    ) AS Annualized_Volatility_Percent,

    ROUND(
        (
            AVG(Portfolio_Return) * 252
        )
        /
        (
            STDDEV_SAMP(Portfolio_Return)
            * SQRT(252)
        ),
        2
    ) AS Sharpe_Ratio

FROM portfolio_daily_returns;
