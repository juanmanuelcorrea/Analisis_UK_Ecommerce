# Análisis de E-commerce con MySQL y Tableau  

![](https://www.ssi-schaefer.com/resource/blob/1207742/b5bdadcababc0904a574ea9d675870c3/e-commerce-hero-dam-image-en-31561--data.jpg)

## Descripción del Proyecto

Este proyecto consiste en un análisis completo de los datos de un e-commerce utilizando MySQL para la manipulación y análisis de datos, y Tableau para la visualización. El objetivo principal es extraer información valiosa a partir del dataset y responder diversas preguntas de negocio relacionadas con las ventas, devoluciones y comportamiento de los clientes.

A lo largo del proyecto, se llevan a cabo procesos de limpieza y transformación de datos, exploración de patrones de compra y segmentación de clientes mediante un Análisis RFM. Finalmente, los hallazgos clave se presentan en un dashboard interactivo en Tableau, facilitando la interpretación de los datos y la toma de decisiones.

Este documento detalla los objetivos del análisis, la estructura del proyecto, las soluciones implementadas, los principales hallazgos y la conclusión final.

## Objetivos

- **Explorar la evolución de las ventas** a lo largo del tiempo, analizando variaciones diarias, mensuales y por hora.
- **Evaluar el impacto de las devoluciones** en el volumen total de ventas y facturación.
- **Determinar los productos más vendidos** y su variabilidad en las ventas a lo largo del tiempo.
- **Identificar tendencias de compra por país**, permitiendo un análisis geográfico del negocio.
- **Segmentar a los clientes mediante un Análisis RFM** para definir perfiles de compradores según su frecuencia, recencia y gasto monetario.

## Dataset

Los datos utilizados en este proyecto provienen del siguiente dataset del **UC Irvine Machine Learning Repository**:  

🔗 [Online Retail Dataset](https://archive.ics.uci.edu/dataset/352/online+retail)  

> *"This is a transactional data set which contains all the transactions occurring between 01/12/2010 and 09/12/2011 for a UK-based and registered non-store online retail. The company mainly sells unique all-occasion gifts. Many customers of the company are wholesalers."*  

Este dataset contiene información detallada de transacciones realizadas por una empresa de comercio electrónico en el Reino Unido, incluyendo detalles como número de factura, productos comprados, cantidad, precios, fecha de compra y país del cliente.

## Estructura del Proyecto

### 1. Configuración de la Base de Datos

- **Creación de la Base de Datos**: En primer lugar, se creó una base de datos llamada `online_retail`.
- **Creación de la Tabla**: Se creó una tabla llamada `online_retail` que contiene los datos de cada una de las transacciones.

```sql
CREATE DATABASE online_retail;

USE online_retail;

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
```

### 2. Carga de Datos

- **Generación de Sentencias SQL para la Carga de Datos**:  Debido a errores en el *Import Wizard* de MySQL al procesar valores numéricos y fechas, se utilizó **Excel** para generar las sentencias `INSERT INTO` de manera manual. Esto se logró concatenando los valores de cada fila con la función `CONCAT`, asegurando que las fechas estuvieran en el formato correcto (`YYYY-MM-DD HH:MM:SS`) y reemplazando valores vacíos por `NULL`. El archivo [`insert_data.sql`](./insert_data.sql) contiene todas las sentencias SQL generadas para la carga de datos.
- **Verificación de la Carga y Número de Registros** : Una vez insertados los datos en la base de datos, se realizó una verificación de la carga para confirmar que el número de registros importados coincidiera con el dataset original. **Total de registros del dataset**: 541,909.

```sql
SELECT * FROM online_retail LIMIT 100;

SELECT COUNT(*) FROM online_retail;
```

### 3. Limpieza y Transformación de Datos

Se desarrollaron las siguientes queries en SQL para lograr la limpieza y transformación adecuada del dataset para su posterior análisis:

1. **Existencia de Filas con Valores Nulos**:  Se identificaron valores nulos en la columna `CustomerID`, lo que representa transacciones sin una asociación clara a un cliente (≈ 25% del dataset). Sin embargo, en lugar de eliminar estas filas completamente, se mantuvieron para el análisis de otras variables, ya que estos datos siguen siendo útiles. En su lugar, se creó una vista en la cual se eliminan estos valores nulos, necesaria para el posterior análisis de segmentación de clientes.

```sql
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

CREATE VIEW online_retail_with_customers AS
SELECT * FROM online_retail
WHERE CustomerID IS NOT NULL;

SELECT COUNT(*) FROM online_retail_with_customers;
```

2. **Eliminación de filas duplicadas**: Dado que la tabla no tenía un identificador único por fila, se generó una columna `row_id` temporal para detectar y eliminar duplicados. Se eliminó cualquier transacción repetida con los mismos valores en todas sus columnas.

```sql
SELECT InvoiceNo, StockCode, Description, Quantity, InvoiceDate, UnitPrice, CustomerID, Country, COUNT(*) AS total_duplicados
FROM online_retail
GROUP BY InvoiceNo, StockCode, Description, Quantity, InvoiceDate, UnitPrice, CustomerID, Country
HAVING total_duplicados > 1;

ALTER TABLE online_retail ADD COLUMN row_id INT AUTO_INCREMENT PRIMARY KEY;

DELETE FROM online_retail
WHERE row_id IN (
	SELECT row_id
	FROM (
		SELECT row_id, ROW_NUMBER() OVER (PARTITION BY InvoiceNo, StockCode, Description, Quantity, InvoiceDate, UnitPrice, CustomerID, Country) AS row_num
		FROM online_retail) as x
	WHERE x.row_num > 1);

ALTER TABLE online_retail DROP COLUMN row_id;
```

3. **Eliminación de filas con valores anómalos**:  Se eliminaron registros con valores negativos en `UnitPrice`, ya que representan casos no relevantes para el análisis, como pruebas internas o registros erróneos.

```sql
SELECT *
FROM online_retail
WHERE UnitPrice <= 0;

DELETE FROM online_retail
WHERE UnitPrice <= 0;
```

4. **Creación de campos adicionales**: Se añadió la columna `TotalPrice` que contiene el cálculo de las ventas totales por producto (en cada transacción) para facilitar el análisis.
   
```sql
ALTER TABLE online_retail ADD COLUMN TotalPrice DECIMAL(10, 2);

UPDATE online_retail 
SET TotalPrice = Quantity * UnitPrice;
```

### 4. Análisis Exploratorio de Datos (EDA)

Para comprender mejor el comportamiento de las ventas y los clientes, se desarrollaron diversas consultas en SQL enfocadas en responder preguntas clave del negocio. Estas queries permitieron identificar tendencias, patrones de compra, productos más vendidos, comportamiento por país y análisis de devoluciones, entre otros aspectos fundamentales.

1. **Ventas Totales por Día (1/12/2010 - 9/12-2011)**

```sql
SELECT
	DATE_FORMAT(InvoiceDate, '%Y-%m-%d') AS dia,
    SUM(TotalPrice) AS total_ventas
FROM online_retail
GROUP BY dia
ORDER BY dia;
```

2. **Ventas Promedio por Día (dic. 2010 - dic. 2011)**

```sql
SELECT
	DATE_FORMAT(InvoiceDate, '%Y-%m') AS mes,
	ROUND(SUM(TotalPrice) / COUNT(DISTINCT DATE(InvoiceDate)), 2) as promedio_ventas
FROM online_retail
GROUP BY mes
ORDER BY mes;
```

3. **Distribución de Ventas por Día de la Semana**

```sql
SELECT
	DAYNAME(InvoiceDate) AS dia_semana, 
	COUNT(DISTINCT InvoiceNo) AS total_compras, 
	SUM(TotalPrice) AS total_ventas
FROM online_retail
GROUP BY dia_semana
ORDER BY FIELD(dia_semana, 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday');
```

4. **Distribución de Ventas por Hora del Día**

```sql
SELECT
	HOUR(InvoiceDate) AS hora, 
	COUNT(DISTINCT InvoiceNo) AS total_transacciones, 
	SUM(TotalPrice) AS total_ventas
FROM online_retail
GROUP BY hora
ORDER BY hora;
```

5. **Top 10 Productos más Vendidos por Ventas en Valor Monetario y su Variabilidad Mensual**

```sql
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
```

6. **Ventas, Cantidad de Clientes y Cantidad de Compras por País**

```sql
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
```

7. **Productos más Vendidos por País**

```sql
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
```

8. **Devoluciones Totales en Cantidad de Facturas y en Valor Monetario**

```sql
SELECT 
    COUNT(DISTINCT CASE WHEN InvoiceNo LIKE 'C%' THEN InvoiceNo END) AS total_facturas_devueltas,
    COUNT(DISTINCT InvoiceNo) AS total_facturas,
    ABS(SUM(CASE WHEN InvoiceNo LIKE 'C%' THEN TotalPrice ELSE 0 END)) AS total_devoluciones,
    SUM(CASE WHEN InvoiceNo NOT LIKE 'C%' THEN TotalPrice ELSE 0 END) AS total_ventas
FROM online_retail;
```

9. **Top 10 Productos más Devueltos (por cantidad de unidades)**

```sql
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
```

### 5. Análisis RFM (Recency, Frequency, Monetary)

El análisis RFM es una técnica utilizada para segmentar clientes en función de su comportamiento de compra. Se basa en tres métricas clave:  

- **Recency (R):** Cuánto tiempo ha pasado desde la última compra del cliente.  
- **Frequency (F):** Cuántas veces ha comprado el cliente en un período determinado.  
- **Monetary (M):** Cuánto ha gastado el cliente en total.  

A través de consultas en SQL, se calcularon estos valores para cada cliente, permitiendo una segmentación más efectiva y la identificación de los grupos más valiosos para el negocio.  

```sql
CREATE TABLE analisis_rfm AS
SELECT 
    CustomerID,
    DATEDIFF('2011-12-09', MAX(DATE(InvoiceDate))) AS Recency,   -- Días desde la última compra
    COUNT(DISTINCT InvoiceNo) AS Frequency,                      -- Número de compras
    SUM(TotalPrice) AS Monetary                                  -- Gasto total
FROM online_retail_with_customers
GROUP BY CustomerID;

ALTER TABLE analisis_rfm ADD COLUMN R_Score INT;
ALTER TABLE analisis_rfm ADD COLUMN F_Score INT;
ALTER TABLE analisis_rfm ADD COLUMN M_Score INT;

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
```

#### **Segmentación de Clientes**  

Los clientes fueron categorizados en los siguientes segmentos según sus puntajes RFM:  

- **Clientes en Riesgo:** Clientes que hace mucho tiempo que no realizan una compra y corren el riesgo de perderse.  
- **Clientes Nuevos:** Clientes que han realizado su primera compra recientemente, pero aún no han demostrado lealtad.  
- **Mejores Clientes:** Aquellos con la mayor frecuencia de compra y el mayor gasto total en el negocio.  
- **Clientes Premium:** Una combinación de "Grandes Compradores" y "Clientes Frecuentes", es decir, clientes con alta frecuencia de compra y un gasto significativo.  
- **Grandes Compradores:** Clientes cuyo gasto total es alto, independientemente de la frecuencia de sus compras.  
- **Clientes Frecuentes:** Clientes que compran con regularidad, aunque su gasto total no sea necesariamente alto.  
- **Otros:** Clientes que no destacan en ninguna de las categorías anteriores.  

Esta segmentación facilita la toma de decisiones estratégicas, como el diseño de campañas de fidelización o la reactivación de clientes inactivos.  

```sql
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
```

### 6. Visualización en Tableau

Para comunicar los hallazgos del análisis de datos de manera clara y efectiva, se creó un dashboard interactivo en **Tableau**. La visualización de datos en Tableau permitió transformar las consultas en SQL en gráficos interactivos, a partir de los cuales se pueden identificar patrones clave en el comportamiento de los clientes y en la dinámica de las ventas del e-commerce.

El dashboard completo se encuentra publicado en **Tableau Public** y puede explorarse en el siguiente enlace:  

🔗 [**Ver Dashboard en Tableau Public**](https://public.tableau.com/views/E-CommerceProject_17403561047400/Dashboard1?:language=es-ES&:sid=&:redirect=auth&:display_count=n&:origin=viz_share_link)  

## Hallazgos

**Evolución de Ventas Semanales**

Se observa una clara tendencia creciente en las ventas a lo largo del tiempo, con un aumento notable en los últimos cuatro meses del dataset. Durante este período, las ventas semanales superan en varias ocasiones las £300K, lo que indica un fuerte crecimiento y demanda en el negocio. Este patrón sugiere que las estrategias implementadas en estos últimos meses han tenido un impacto positivo, con picos de ventas semanales que podrían estar asociados con factores estacionales, campañas promocionales exitosas o un incremento generalizado en la demanda.

**Patrones de Compra por Hora del Día**

La mayoría de las transacciones ocurren entre las 10:00 y las 16:00 horas, mostrando una distribución bastante equilibrada durante este intervalo. Aunque no se observa una hora específica con un volumen significativamente superior al de otras, el comportamiento general indica una actividad constante a lo largo de este período.

**Análisis de Productos Más Vendidos**

Los productos relacionados con decoración del hogar y regalos personalizados dominan la lista de los más vendidos, destacándose notablemente. El producto más vendido supera a los tres siguientes en más del 60% en ventas, lo que resalta su éxito abrumador y su posición dominante en el e-commerce. Además, se observa que, en promedio, los primeros cuatro productos presentan una menor variabilidad en sus ventas mensuales, lo que indica una demanda más estable y constante. En contraste, los siguientes seis productos en el top muestran una mayor fluctuación en las ventas mensuales, sugiriendo que su rendimiento puede estar más influenciado por factores estacionales o campañas específicas.

**Tendencias de Ventas por País**

El análisis geográfico destaca al Reino Unido como el mercado dominante, representando un 84% del total de las ventas. Este dato sugiere que la mayoría de los clientes del e-commerce residen en el Reino Unido, lo que refuerza la idea de que la plataforma tiene una fuerte presencia local. Los siguientes países en términos de volumen de ventas son Holanda, Irlanda, Alemania y Francia, lo que indica una concentración de ventas en Europa, especialmente en países cercanos geográficamente.

**Impacto de las Devoluciones en las Ventas**

Aproximadamente el 8% de las ventas totales corresponden a devoluciones, lo que tiene un impacto negativo significativo en los ingresos generales del e-commerce. Esta tasa de devoluciones, aunque relativamente baja, representa una parte considerable de las ventas que se pierden, lo que indica que hay áreas de mejora. Es crucial investigar las principales causas para reducir las mismas y mejorar la rentabilidad a largo plazo, optimizando la experiencia del cliente y la fidelización.

**Segmentación de Clientes según Análisis RFM**

La segmentación de clientes a través del análisis RFM (Recencia, Frecuencia y Valor Monetario) ha permitido identificar distintos grupos clave, como los "Mejores Clientes", "Clientes Premium" y "Clientes en Riesgo". Estos segmentos destacan no solo por su comportamiento de compra, sino también por su impacto en el negocio. Sin embargo, es importante notar que los segmentos de "Grandes Compradores" y "Clientes Frecuentes" son más específicos, ya que se caracterizan o bien por realizar compras menos frecuentes o por gastar menos en cada transacción. Esta clasificación proporciona una base sólida para diseñar estrategias de marketing y fidelización más personalizadas, permitiendo a la empresa enfocar sus esfuerzos en los segmentos más valiosos y desarrollar iniciativas específicas para reactivar a los clientes que se encuentran en riesgo de abandonar la plataforma.
