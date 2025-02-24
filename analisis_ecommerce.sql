#######################################################
-- CARGA DE DATOS
 
-- Crear base de datos
CREATE DATABASE online_retail;

USE online_retail;

-- Crear tabla
CREATE TABLE online_retail (
    InvoiceNo VARCHAR(20),
    StockCode VARCHAR(20),
    Description TEXT,
    Quantity INT,
    InvoiceDate DATETIME,
    UnitPrice DECIMAL(10, 2),
    CustomerID INT,
    Country VARCHAR(50)
);

-- Cargar datos en la tabla (insert_data.sql)

-- Verificar carga correcta y cantidad de registros
SELECT * FROM online_retail LIMIT 100;

SELECT COUNT(*) FROM online_retail;

#######################################################
-- LIMPIEZA Y TRANSFORMACION DE DATOS

-- Verificar columnas con valores nulos
SELECT 
    SUM(CASE WHEN InvoiceNo = '' THEN 1 ELSE 0 END) AS InvoiceNo_nulls,
    SUM(CASE WHEN StockCode = '' THEN 1 ELSE 0 END) AS StockCode_nulls,
    SUM(CASE WHEN Description = '' THEN 1 ELSE 0 END) AS Description_nulls,
    SUM(CASE WHEN Quantity IS NULL THEN 1 ELSE 0 END) AS Quantity_nulls,
    SUM(CASE WHEN InvoiceDate IS NULL THEN 1 ELSE 0 END) AS InvoiceDate_nulls,
    SUM(CASE WHEN UnitPrice IS NULL THEN 1 ELSE 0 END) AS UnitPrice_nulls,
    SUM(CASE WHEN CustomerID IS NULL THEN 1 ELSE 0 END) AS CustomerID_nulls,
    SUM(CASE WHEN Country = '' THEN 1 ELSE 0 END) AS Country_nulls
FROM online_retail;

-- Crear vista solo con las transacciones con CustomerID (identificadas)
CREATE VIEW online_retail_with_customers AS
SELECT * FROM online_retail
WHERE CustomerID IS NOT NULL;

SELECT COUNT(*) FROM online_retail_with_customers;

-- Verificar filas duplicadas
SELECT InvoiceNo, StockCode, Description, Quantity, InvoiceDate, UnitPrice, CustomerID, Country, COUNT(*) AS total_duplicados
FROM online_retail
GROUP BY InvoiceNo, StockCode, Description, Quantity, InvoiceDate, UnitPrice, CustomerID, Country
HAVING total_duplicados > 1;

-- Eliminar filas duplicadas

ALTER TABLE online_retail ADD COLUMN row_id INT AUTO_INCREMENT PRIMARY KEY;

DELETE FROM online_retail
WHERE row_id IN (
	SELECT row_id
	FROM (
		SELECT row_id, ROW_NUMBER() OVER (PARTITION BY InvoiceNo, StockCode, Description, Quantity, InvoiceDate, UnitPrice, CustomerID, Country) AS row_num
		FROM online_retail) as x
	WHERE x.row_num > 1);

ALTER TABLE online_retail DROP COLUMN row_id;

-- Verificar filas con precio negativo o igual a cero
SELECT *
FROM online_retail
WHERE UnitPrice <= 0;

-- Eliminar filas con precio negativo o igual a cero
DELETE FROM online_retail
WHERE UnitPrice <= 0;

-- Crear columna TotalPrice
ALTER TABLE online_retail ADD COLUMN TotalPrice DECIMAL(10, 2);

UPDATE online_retail 
SET TotalPrice = Quantity * UnitPrice;

#######################################################
-- ANALISIS EXPLORATORIO DE DATOS (EDA)

#################
-- ANALISIS DE SERIE TEMPORAL

-- Ventas totales por día (1/12/2010 - 9/12-2011)
SELECT
	DATE_FORMAT(InvoiceDate, '%Y-%m-%d') AS dia,
    SUM(TotalPrice) AS total_ventas 
FROM online_retail
GROUP BY dia
ORDER BY dia;

-- Ventas promedio por día (dic. 2010 - dic. 2011)
SELECT
	DATE_FORMAT(InvoiceDate, '%Y-%m') AS mes,
	ROUND(SUM(TotalPrice) / COUNT(DISTINCT DATE(InvoiceDate)), 2) as promedio_ventas
FROM online_retail
GROUP BY mes
ORDER BY mes;

-- Distribución de ventas por día de la semana
SELECT
	DAYNAME(InvoiceDate) AS dia_semana, 
	COUNT(DISTINCT InvoiceNo) AS total_compras, 
	SUM(TotalPrice) AS total_ventas
FROM online_retail
GROUP BY dia_semana
ORDER BY FIELD(dia_semana, 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday');

-- Distribución de ventas por hora del día
SELECT
	HOUR(InvoiceDate) AS hora, 
	COUNT(DISTINCT InvoiceNo) AS total_transacciones, 
	SUM(TotalPrice) AS total_ventas
FROM online_retail
GROUP BY hora
ORDER BY hora;

#################
-- ANALISIS POR PRODUCTO

-- Top 10 productos más vendidos por ventas en valor monetario y su variabilidad mensual
WITH ventas_mensuales_por_producto AS (
    SELECT 
        StockCode,
        DATE_FORMAT(InvoiceDate, '%Y-%m') AS mes,
        SUM(TotalPrice) AS total_ventas
    FROM online_retail
    GROUP BY StockCode, mes
),
coeficiente_variacion AS (
    SELECT 
        StockCode,
        ROUND(STDDEV(total_ventas) / AVG(total_ventas), 2) AS CV_mensual
    FROM ventas_mensuales_por_producto
    GROUP BY StockCode
)
SELECT
	a.StockCode,
    MAX(Description) AS Description,   -- Tomamos una descripción cualquiera del producto (similares entre sí)
	SUM(TotalPrice) AS total_ventas,
	SUM(Quantity) as total_unidades,
	COUNT(DISTINCT CustomerID) as total_clientes,
    b.CV_mensual
FROM online_retail a
JOIN coeficiente_variacion b ON a.StockCode = b.StockCode
WHERE Description NOT IN ('DOTCOM POSTAGE', 'POSTAGE')  -- Descartamos transacciones por pago de envíos
GROUP BY a.StockCode
ORDER BY total_ventas DESC
LIMIT 10;

#################
-- ANALISIS POR PAIS

-- Ventas, cantidad de clientes y cantidad de compras por país
SELECT
	Country,
    SUM(TotalPrice) AS total_ventas,
    COUNT(DISTINCT CustomerID) AS total_clientes,
    COUNT(DISTINCT InvoiceNo) AS total_compras,
    ROUND(COUNT(DISTINCT InvoiceNo) / COUNT(DISTINCT CustomerID), 2) AS compras_por_cliente,
    ROUND(SUM(TotalPrice) /  COUNT(DISTINCT InvoiceNo), 2) AS valor_promedio_compra
FROM online_retail
GROUP BY Country
ORDER BY total_ventas DESC;

-- Productos más vendidos por país
WITH ventas_por_producto_y_pais AS (
    SELECT 
        Country,
        StockCode,
        MAX(Description) AS Description,
        SUM(TotalPrice) AS total_ventas,
        ROW_NUMBER() OVER (PARTITION BY Country ORDER BY SUM(TotalPrice) DESC) AS rn
    FROM online_retail
    WHERE Description NOT IN ('DOTCOM POSTAGE', 'POSTAGE')
    GROUP BY Country, StockCode
)
SELECT Country, StockCode, Description, total_ventas
FROM ventas_por_producto_y_pais
WHERE rn = 1;

#################
-- ANALISIS DE DEVOLUCIONES

-- Devoluciones totales en cantidad de facturas y en valor monetario
SELECT 
    COUNT(DISTINCT CASE WHEN InvoiceNo LIKE 'C%' THEN InvoiceNo END) AS total_facturas_devueltas,
    COUNT(DISTINCT InvoiceNo) AS total_facturas,
    ABS(SUM(CASE WHEN InvoiceNo LIKE 'C%' THEN TotalPrice ELSE 0 END)) AS total_devoluciones,
    SUM(CASE WHEN InvoiceNo NOT LIKE 'C%' THEN TotalPrice ELSE 0 END) AS total_ventas
FROM online_retail;

-- Top 10 productos más devueltos (por cantidad de unidades)
SELECT 
    StockCode, 
    Description, 
    ABS(SUM(Quantity)) AS total_unidades_devueltas,
    COUNT(DISTINCT CustomerID) AS total_clientes,
    ABS(SUM(TotalPrice)) AS total_devoluciones
FROM online_retail
WHERE InvoiceNo LIKE 'C%' and StockCode <> 'M' -- Desconsideramos transacciones insertadas manualmente (sin StockCode)
GROUP BY StockCode, Description
ORDER BY total_unidades_devueltas DESC
LIMIT 10;

#################
-- ANALISIS RFM (Recency, Frequency, Monetary)

-- Calcular fecha de referencia (fecha más reciente en el dataset)
SELECT MAX(DATE(InvoiceDate)) AS fecha_maxima FROM online_retail_with_customers;
 
 -- Calcular Recency, Frequency y Monetary
CREATE TABLE analisis_rfm AS
SELECT 
    CustomerID,
    DATEDIFF('2011-12-09', MAX(DATE(InvoiceDate))) AS Recency,   -- Días desde la última compra
    COUNT(DISTINCT InvoiceNo) AS Frequency,                      -- Número de compras
    SUM(TotalPrice) AS Monetary                                  -- Gasto total
FROM online_retail_with_customers
GROUP BY CustomerID;

-- Crear columnas con scores del 1 (peor) al 4 (mejor)
ALTER TABLE analisis_rfm ADD COLUMN R_Score INT;
ALTER TABLE analisis_rfm ADD COLUMN F_Score INT;
ALTER TABLE analisis_rfm ADD COLUMN M_Score INT;

-- 
UPDATE analisis_rfm a
JOIN (
    SELECT CustomerID, NTILE(4) OVER (ORDER BY Recency DESC) AS R_Score
    FROM analisis_rfm
) b ON a.CustomerID = b.CustomerID
SET a.R_Score = b.R_Score;

UPDATE analisis_rfm a
JOIN (
    SELECT CustomerID, NTILE(4) OVER (ORDER BY Frequency ASC) AS F_Score
    FROM analisis_rfm
) b ON a.CustomerID = b.CustomerID
SET a.F_Score = b.F_Score;

UPDATE analisis_rfm a
JOIN (
    SELECT CustomerID, NTILE(4) OVER (ORDER BY Monetary ASC) AS M_Score
    FROM analisis_rfm
) b ON a.CustomerID = b.CustomerID
SET a.M_Score = b.M_Score;

-- Crear y asignar segmentos

ALTER TABLE analisis_rfm ADD COLUMN Segmento VARCHAR(50);

UPDATE analisis_rfm
SET Segmento = 
    CASE 
		WHEN R_Score = 1 THEN 'Clientes en Riesgo'
        WHEN R_Score = 4 AND F_Score = 1 THEN 'Clientes Nuevos'
        WHEN F_Score = 4 AND M_Score = 4 THEN 'Mejores Clientes'
        WHEN F_Score >= 3 AND M_Score >= 3 THEN 'Clientes Premium' -- Gran comprador + Cliente frecuente
        WHEN M_Score >= 3 THEN 'Grandes Compradores'
        WHEN F_Score >= 3 THEN 'Clientes Frecuentes'
        ELSE 'Otros'
    END;

SELECT * FROM analisis_rfm;



