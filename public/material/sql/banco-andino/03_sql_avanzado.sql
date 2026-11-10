-- =====================================================================
-- Bases de Datos 2 · Taller integrador — Banco Andino
-- 03_sql_avanzado.sql   SQL analítico, jerárquico y MERGE
--
-- Trabajen en UNA SOLA CONEXIÓN: la pareja comparte el esquema.
-- Cada bloque trae una consulta RESUELTA que sirve de modelo, y una
-- consulta que ustedes deben ESCRIBIR. Complete las que dicen ESCRIBA.
-- =====================================================================

SET LINESIZE 220
SET PAGESIZE 60
SET TIMING ON
SET autocommit OFF

-- #####################################################################
-- EJERCICIO 3.1 — Ranking dentro de grupos
--
-- La vicepresidencia comercial quiere los 3 productos que más saldo
-- captan dentro de cada FAMILIA de productos, solo cuentas activas.
-- #####################################################################

-- MODELO (resuelto)
WITH captacion AS (
  SELECT f.id_producto  AS id_familia,
         f.nombre       AS familia,
         p.id_producto,
         p.nombre       AS producto,
         SUM(c.saldo)   AS saldo_captado,
         COUNT(*)       AS cuentas
    FROM cuenta c
    JOIN catalogo_producto p ON p.id_producto = c.id_producto
    JOIN catalogo_producto f ON f.id_producto = p.id_padre
   WHERE c.estado = 'ACTIVA'
   GROUP BY f.id_producto, f.nombre, p.id_producto, p.nombre
)
SELECT familia, producto, cuentas, ROUND(saldo_captado) AS saldo_captado, puesto
  FROM (SELECT v.*,
               ROW_NUMBER() OVER (PARTITION BY id_familia
                                  ORDER BY saldo_captado DESC) AS puesto
          FROM captacion v)
 WHERE puesto <= 3
 ORDER BY familia, puesto;

--
--  PREGUNTA 3.1 — Cambie DENSE_RANK por RANK y luego por ROW_NUMBER.
--  Explique en qué se diferencian los tres cuando hay empates, y cuál
--  usaría usted para un "top 3" que debe devolver exactamente 3 filas.
--
-- Respuesta: 
-- ROW_NUMBER(): Asigna un número único y continuo (1, 2, 3, 4). Si hay 
-- empate, lo rompe al azar. No repite puestos ni deja huecos.
-- RANK(): Repite el puesto en los empates, pero deja huecos después 
-- (1, 2, 2, 4).
-- DENSE_RANK(): Repite el puesto en los empates, pero sigue sin dejar 
-- huecos (1, 2, 2, 3).
-- Para un "Top 3" estricto de exactamente 3 filas se debe usar ROW_NUMBER(), 
-- ya que al no repetir números garantiza que el filtro puesto <= 3 devuelva 
-- un máximo de tres registros sin importar si hay valores empatados.
--
--  ESCRIBA 3.1 — La misma consulta, pero mostrando además qué porcentaje
--  representa cada producto sobre el saldo total captado por su familia.
--  Use RATIO_TO_REPORT o una función de ventana con SUM() OVER.
--  Cuidado: el porcentaje debe ser sobre la familia COMPLETA, no sobre
--  el top 3.
--
-- Respuesta: 

WITH captacion AS (
  SELECT f.id_producto  AS id_familia,
         f.nombre       AS familia,
         p.id_producto,
         p.nombre       AS producto,
         SUM(c.saldo)   AS saldo_captado,
         COUNT(*)       AS cuentas
    FROM cuenta c
    JOIN catalogo_producto p ON p.id_producto = c.id_producto
    JOIN catalogo_producto f ON f.id_producto = p.id_padre
   WHERE c.estado = 'ACTIVA'
   GROUP BY f.id_producto, f.nombre, p.id_producto, p.nombre
),
ranking_y_porcentaje AS (
  SELECT v.*,
         ROW_NUMBER() OVER (PARTITION BY id_familia
                            ORDER BY saldo_captado DESC) AS puesto,
         ROUND((saldo_captado / SUM(saldo_captado) OVER (PARTITION BY id_familia)) * 100, 2) AS porc_sobre_familia
    FROM captacion v
)
SELECT familia, 
       producto, 
       cuentas, 
       ROUND(saldo_captado) AS saldo_captado, 
       porc_sobre_familia,
       puesto
  FROM ranking_y_porcentaje
 WHERE puesto <= 3
 ORDER BY familia, puesto;


-- #####################################################################
-- EJERCICIO 3.2 — Series de tiempo: acumulado y variación
--
-- Riesgo operativo quiere la evolución mensual del valor transferido
-- durante 2026, con el acumulado del año y la variación contra el mes
-- anterior. Es la base de las alertas por comportamiento atípico.
-- #####################################################################

-- MODELO (resuelto)
WITH mensual AS (
  SELECT TRUNC(fecha_transf, 'MM') AS mes,
         SUM(valor)                AS valor_transferido,
         COUNT(*)                  AS operaciones
    FROM transferencia
   WHERE fecha_transf >= DATE '2026-01-01'
     AND fecha_transf <  DATE '2027-01-01'
     AND estado = 'APLICADA'
   GROUP BY TRUNC(fecha_transf, 'MM')
)
SELECT TO_CHAR(mes,'YYYY-MM')                          AS mes,
       operaciones,
       ROUND(valor_transferido)                        AS valor,
       ROUND(SUM(valor_transferido) OVER (ORDER BY mes
             ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)) AS acumulado,
       ROUND(LAG(valor_transferido) OVER (ORDER BY mes)) AS mes_anterior,
       ROUND(100 * (valor_transferido - LAG(valor_transferido) OVER (ORDER BY mes))
                 / NULLIF(LAG(valor_transferido) OVER (ORDER BY mes),0), 1) AS var_pct
  FROM mensual
 ORDER BY mes;

--
--  PREGUNTA 3.2 — ¿Qué diferencia hay entre
--     ROWS  BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
--  y  RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW ?
--  Constrúyase un caso donde den resultados distintos.
--
-- Respuesta: La diferencia principal radica en cómo manejan las filas 
-- que tienen valores idénticos (empates) en la columna del ORDER BY:ROWS 
-- (Físico): Trabaja contando filas de forma exacta. ROWS BETWEEN UNBOUNDED 
-- PRECEDING AND CURRENT ROW sumará estrictamente desde la primera fila física 
-- del conjunto de datos hasta la fila actual en la que se encuentra el cursor, 
-- sin importar si hay fechas repetidas.
-- RANGE (Lógico): Trabaja comparando los valores de los datos. RANGE BETWEEN 
-- UNBOUNDED PRECEDING AND CURRENT ROW incluye la fila actual y todos sus pares 
-- de ordenación (filas que tengan exactamente el mismo valor en la columna de 
-- orden).
-- Caso donde dan resultados distintos: Dos transferencias se registran con el 
-- mismo mes o fecha exacta debido a una carga masiva y el ORDER BY es por esa 
-- fecha. Si en el "Mes 2" hay dos registros empatados con un valor de 100 cada 
-- uno: Con ROWS: En la primera fila del empate el acumulado será 100, y en la 
-- segunda fila del empate será 200 (va sumando fila por fila).Con RANGE: En 
-- ambas filas del empate el acumulado mostrará directamente 200, ya que el motor 
-- procesa el rango de valores idénticos de manera simultánea en el cálculo de 
-- la ventana.
--
--  ESCRIBA 3.2 — Agregue una columna con el promedio móvil de los
--  últimos 3 meses (mes actual y los dos anteriores), que es la línea
--  base contra la que riesgo compara cada mes.
-- 
-- Respuesta: 
WITH mensual AS (
  SELECT TRUNC(fecha_transf, 'MM') AS mes,
         SUM(valor)                AS valor_transferido,
         COUNT(*)                  AS operaciones
    FROM transferencia
   WHERE fecha_transf >= DATE '2026-01-01'
     AND fecha_transf <  DATE '2027-01-01'
     AND estado = 'APLICADA'
   GROUP BY TRUNC(fecha_transf, 'MM')
)
SELECT TO_CHAR(mes,'YYYY-MM')                          AS mes,
       operaciones,
       ROUND(valor_transferido)                        AS valor,
       ROUND(SUM(valor_transferido) OVER (ORDER BY mes
             ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)) AS acumulado,
       ROUND(LAG(valor_transferido) OVER (ORDER BY mes)) AS mes_anterior,
       ROUND(100 * (valor_transferido - LAG(valor_transferido) OVER (ORDER BY mes))
                 / NULLIF(LAG(valor_transferido) OVER (ORDER BY mes),0), 1) AS var_pct,
       ROUND(AVG(valor_transferido) OVER (ORDER BY mes
             ROWS BETWEEN 2 PRECEDING AND CURRENT ROW)) AS promedio_movil_3m
  FROM mensual
 ORDER BY mes;
--


-- #####################################################################
-- EJERCICIO 3.3 — La misma respuesta, dos planes muy distintos
--
-- Se necesita, por cada cliente PREFERENCIAL, su última transferencia.
-- #####################################################################

-- VERSIÓN A — subconsulta correlacionada  (la que sale sola al escribir)
EXPLAIN PLAN FOR
SELECT cl.id_cliente, cl.nombre, t.id_transferencia, t.fecha_transf, t.valor
  FROM cliente       cl
  JOIN cuenta        c ON c.id_cliente = cl.id_cliente
  JOIN transferencia t ON t.cuenta_origen = c.id_cuenta
 WHERE cl.segmento = 'PREFERENCIAL'
   AND t.fecha_transf = (SELECT MAX(t2.fecha_transf)
                           FROM transferencia t2
                           JOIN cuenta c2 ON c2.id_cuenta = t2.cuenta_origen
                          WHERE c2.id_cliente = cl.id_cliente);

SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY(format => 'BASIC +COST +ROWS'));

-- VERSIÓN B — función analítica
EXPLAIN PLAN FOR
SELECT id_cliente, nombre, id_transferencia, fecha_transf, valor
  FROM (SELECT cl.id_cliente, cl.nombre, t.id_transferencia,
               t.fecha_transf, t.valor,
               ROW_NUMBER() OVER (PARTITION BY cl.id_cliente
                                  ORDER BY t.fecha_transf DESC) AS rn
          FROM cliente       cl
          JOIN cuenta        c ON c.id_cliente = cl.id_cliente
          JOIN transferencia t ON t.cuenta_origen = c.id_cuenta
         WHERE cl.segmento = 'PREFERENCIAL')
 WHERE rn = 1;

SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY(format => 'BASIC +COST +ROWS'));

--
--  PREGUNTA 3.3 — Compare los dos planes. ¿Cuántas veces se lee
--  TRANSFERENCIA en cada versión? ¿Cuál es el COST de cada una?
--
-- Respuesta: En ambas versiones se lee exactamente 1 vez (TABLE ACCESS 
-- FULL | TRANSFERENCIA en la fila con Id 7). Esto confirma que el 
-- optimizador de Oracle reescribió la subconsulta correlacionada (MAX) 
-- de la Versión A como una función analítica interna (VW_WIF_1) para 
-- evitar escanear la tabla dos veces.
-- Costo de cada una: 
-- Versión A: El costo total es de 1456.
-- Versión B (Segunda Imagen): El costo total es de 1355.
--
--  PREGUNTA 3.4 — Las dos consultas NO son totalmente equivalentes:
--  hay un caso en el que devuelven distinto número de filas. ¿Cuál es?
--  (pista: piense en un cliente que hizo dos transferencias el mismo
--  día a la misma hora, algo perfectamente normal en un pago de nómina)
--
-- Respuesta: Las dos consultas no arrojarán el mismo número de filas si 
-- un cliente tiene dos o más transferencias registradas con la misma fecha 
-- máxima exacta: 
-- Versión A (MAX): Devolverá todas las filas empatadas. Si el valor máximo 
-- de fecha se repite, la condición = traerá todos los registros que tengan 
-- esa misma marca de tiempo.
-- Versión B (ROW_NUMBER): Devolverá estrictamente una sola fila. La función 
-- asigna números secuenciales únicos (1, 2, 3...) incluso si hay empates. Al 
-- filtrar externamente por WHERE rn = 1, se queda con un solo registro y 
-- descarta los demás.
--
-- Punto C:

WITH JERARQUIA_PRODUCTO (id_producto, nombre, id_padre, id_linea, linea_negocio) AS (
  -- 1. MIEMBRO ANCLA: Selecciona las raíces (Nivel 1: Línea de Negocio)
  SELECT id_producto,
         nombre,
         id_padre,
         id_producto AS id_linea,
         nombre      AS linea_negocio
    FROM catalogo_producto
   WHERE id_padre IS NULL
  
  UNION ALL
  
  -- 2. MIEMBRO RECURSIVO: Se une con los hijos (Nivel 2 y Nivel 3)
  -- Manteniendo el id y nombre de la línea raíz a lo largo de las ramas
  SELECT h.id_producto,
         h.nombre,
         h.id_padre,
         p.id_linea,
         p.linea_negocio
    FROM catalogo_producto h
    JOIN JERARQUIA_PRODUCTO p ON h.id_padre = p.id_producto
),
saldos_por_producto AS (
  -- 3. Agrupamos y sumamos los saldos de las cuentas activas
  SELECT id_producto,
         SUM(saldo) AS saldo_total
    FROM cuenta
   WHERE estado = 'ACTIVA'
   GROUP BY id_producto
)
-- 4. CONSULTA FINAL: Consolidamos el dinero agrupando por Línea de Negocio
SELECT j.id_linea       AS id_linea_negocio,
       j.linea_negocio,
       ROUND(SUM(s.saldo_total)) AS saldo_captado
  FROM JERARQUIA_PRODUCTO j
  JOIN saldos_por_producto s ON s.id_producto = j.id_producto
 GROUP BY j.id_linea, j.linea_negocio
 ORDER BY saldo_captado DESC;


-- #####################################################################
-- EJERCICIO 3.4 — Jerarquías: la CTE recursiva
--
-- El catálogo tiene tres niveles: línea de negocio, familia y producto.
-- #####################################################################

-- MODELO (resuelto) — ruta completa de cada nodo del catálogo
WITH arbol (id_producto, nombre, id_padre, nivel, ruta) AS (
  SELECT id_producto, nombre, id_padre, 1, CAST(nombre AS VARCHAR2(400))
    FROM catalogo_producto
   WHERE id_padre IS NULL
  UNION ALL
  SELECT c.id_producto, c.nombre, c.id_padre, a.nivel + 1,
         a.ruta || ' > ' || c.nombre
    FROM catalogo_producto c
    JOIN arbol a ON c.id_padre = a.id_producto
)
SELECT LPAD(' ', (nivel-1)*3) || nombre AS jerarquia, nivel, ruta
  FROM arbol
 ORDER BY ruta;

-- El equivalente con CONNECT BY, sintaxis propia de Oracle
SELECT LPAD(' ', (LEVEL-1)*3) || nombre AS jerarquia,
       LEVEL AS nivel,
       SYS_CONNECT_BY_PATH(nombre, ' > ') AS ruta
  FROM catalogo_producto
 START WITH id_padre IS NULL
CONNECT BY PRIOR id_producto = id_padre
 ORDER SIBLINGS BY nombre;

--
--  PREGUNTA 3.5 — ¿Qué ventaja tiene la CTE recursiva sobre CONNECT BY?
--  ¿Y qué le da CONNECT BY que la CTE no?
--
-- Respuesta: La CTE recursiva tiene la ventaja de ser un estándar universal 
-- (ANSI SQL) que funciona en cualquier base de datos y permite realizar 
-- uniones (JOIN) complejas más fácilmente. Por su parte, CONNECT BY ofrece 
-- una sintaxis mucho más corta y herramientas nativas optimizadas de Oracle 
-- (como SYS_CONNECT_BY_PATH o LEVEL) que facilitan el formateo del árbol con 
-- menos código.
--
--  ESCRIBA 3.3 — Saldo total captado por LÍNEA DE NEGOCIO.
--  Es decir: el saldo de "Cuenta de ahorros" debe sumar dentro de
--  "Banca Personas". Use la CTE recursiva para resolver a qué línea
--  pertenece cada producto hoja, y únala con los saldos de CUENTA.
--  Muestre además cuántas cuentas activas tiene cada línea.
--
-- Respuesta:
WITH arbol (id_producto, nombre, id_linea, nivel) AS (
  -- Caso base: las líneas de negocio (nivel 1, id_padre IS NULL).
  -- Cada una es su propia línea, por eso id_linea = id_producto.
  SELECT id_producto, nombre, id_producto, 1
    FROM catalogo_producto
   WHERE id_padre IS NULL
  UNION ALL
  -- Caso recursivo: cada hijo HEREDA la id_linea de su padre en el árbol,
  -- así el nieto (producto) queda etiquetado con la línea de su bisabuelo.
  SELECT c.id_producto, c.nombre, a.id_linea, a.nivel + 1
    FROM catalogo_producto c
    JOIN arbol a ON c.id_padre = a.id_producto
)
SELECT l.nombre AS linea_negocio,
       ROUND(SUM(c.saldo)) AS saldo_total,
       COUNT(*)            AS cuentas_activas
  FROM arbol a
  JOIN catalogo_producto l ON l.id_producto = a.id_linea   -- trae el NOMBRE de la línea
  JOIN cuenta c             ON c.id_producto = a.id_producto -- une por el producto hoja
 WHERE a.nivel = 3        -- nivel 3 = productos hoja, los únicos que CUENTA referencia
   AND c.estado = 'ACTIVA'
 GROUP BY l.nombre
 ORDER BY saldo_total DESC;
--
-- Punto D:

-- A. MERGE que aplica el ajuste SOLO si no deja la cuenta en negativo
MERGE INTO cuenta c
USING (SELECT id_cuenta, SUM(delta) AS delta
         FROM ajuste_saldo
        GROUP BY id_cuenta) a
   ON (c.id_cuenta = a.id_cuenta)
 WHEN MATCHED THEN
   UPDATE SET c.saldo   = c.saldo + a.delta,
              c.version = c.version + 1
   WHERE c.saldo + a.delta >= 0;   -- <-- aquí está la clave
COMMIT;

-- Cuentas cuyo ajuste NO se pudo aplicar completo (quedaron identificadas, sin tocar)
SELECT a.id_cuenta,
       c.saldo   AS saldo_actual,
       a.delta   AS ajuste_pendiente,
       c.saldo + a.delta AS saldo_que_habria_quedado
  FROM (SELECT id_cuenta, SUM(delta) AS delta
          FROM ajuste_saldo
         GROUP BY id_cuenta) a
  JOIN cuenta c ON c.id_cuenta = a.id_cuenta
 WHERE c.saldo + a.delta < 0
 ORDER BY saldo_que_habria_quedado;


-- #####################################################################
-- EJERCICIO 3.5 — MERGE: aplicar los ajustes del cierre mensual
--
-- Cada fin de mes se aplican intereses y cuotas de manejo. La tabla
-- AJUSTE_SALDO ya los tiene cargados.
-- #####################################################################

-- PASO 1  Antes
SELECT ROUND(SUM(saldo)) AS saldo_total, COUNT(*) AS cuentas FROM cuenta;
SELECT concepto, COUNT(*), SUM(delta) FROM ajuste_saldo GROUP BY concepto;

-- MODELO (resuelto)
MERGE INTO cuenta c
USING (SELECT id_cuenta, SUM(delta) AS delta
         FROM ajuste_saldo
        GROUP BY id_cuenta) a
   ON (c.id_cuenta = a.id_cuenta)
 WHEN MATCHED THEN
   UPDATE SET c.saldo   = GREATEST(c.saldo + a.delta, 0),
              c.version = c.version + 1;
--> Mire el mensaje de SQL Developer: cuántas filas fusionó.
COMMIT;

-- PASO 2  Después
SELECT ROUND(SUM(saldo)) AS saldo_total FROM cuenta;

--
--  PREGUNTA 3.6 — ¿Por qué se agrupa la tabla de ajustes dentro del
--  USING en lugar de usarla directamente? ¿Qué error da Oracle si una
--  misma cuenta aparece dos veces en el origen?
--
-- Respuesta: Se agrupa porque MERGE exige una sola fila de origen por 
-- cada fila de destino. Si una cuenta tiene varios ajustes y no se 
-- agrupan, Oracle da error ORA-30926 (unable to get a stable set of rows).
--
--  PREGUNTA 3.7 — El GREATEST(..., 0) evita que el saldo quede negativo.
--  En un banco eso NO es una solución: si una cuota de manejo excede el
--  saldo, truncar a cero significa que el banco regaló la diferencia.
--  ¿Qué haría usted en un sistema real? Proponga el mecanismo, no solo
--  la crítica.
--
-- Respuesta: GREATEST(...,0) esconde la diferencia: si el ajuste supera el 
-- saldo, el banco pierde esa plata sin dejar rastro. En un sistema real, 
-- lo correcto es no aplicar el ajuste si dejaría el saldo negativo, y en su 
-- lugar registrar la cuenta como pendiente (tabla de excepciones o alerta) 
-- para que se gestione manualmente, en vez de truncar y ocultar la diferencia.
--
--  ESCRIBA 3.4 — Reescriba el MERGE para que las cuentas cuyo ajuste no
--  se pueda aplicar completo NO se toquen, y en cambio queden
--  identificadas. Pista: la cláusula WHERE de la actualización dentro
--  del MERGE, más una consulta que liste las excluidas.
-- 
-- Respuesta:
--
-- MERGE que aplica el ajuste SOLO si no deja la cuenta en negativo
MERGE INTO cuenta c
USING (SELECT id_cuenta, SUM(delta) AS delta
         FROM ajuste_saldo
        GROUP BY id_cuenta) a
   ON (c.id_cuenta = a.id_cuenta)
 WHEN MATCHED THEN
   UPDATE SET c.saldo   = c.saldo + a.delta,
              c.version = c.version + 1
   WHERE c.saldo + a.delta >= 0;
COMMIT;

-- Cuentas cuyo ajuste NO se pudo aplicar completo (quedan identificadas, sin tocar)
SELECT a.id_cuenta,
       c.saldo AS saldo_actual,
       a.delta AS ajuste_pendiente,
       c.saldo + a.delta AS saldo_que_habria_quedado
  FROM (SELECT id_cuenta, SUM(delta) AS delta
          FROM ajuste_saldo
         GROUP BY id_cuenta) a
  JOIN cuenta c ON c.id_cuenta = a.id_cuenta
 WHERE c.saldo + a.delta < 0
 ORDER BY saldo_que_habria_quedado;

--
-- Punto E:
--
SELECT cl.id_cliente, cl.nombre,
       TRUNC(SYSDATE - MAX(t.fecha_transf)) AS dias_inactividad,
       ROUND(SUM(c.saldo))                  AS saldo_total,
       COUNT(DISTINCT c.id_cuenta)          AS productos_contratados
  FROM cliente cl
  JOIN cuenta        c ON c.id_cliente = cl.id_cliente
  JOIN transferencia t ON t.cuenta_origen = c.id_cuenta
 WHERE cl.segmento = 'PREFERENCIAL'
 GROUP BY cl.id_cliente, cl.nombre
HAVING MAX(t.fecha_transf) < SYSDATE - 120
 ORDER BY dias_inactividad DESC;
 --

-- #####################################################################
-- EJERCICIO 3.6 — PIVOT y LISTAGG
-- #####################################################################

-- MODELO (resuelto) — valor transferido por canal y trimestre, en columnas
SELECT canal,
       ROUND(t1) AS t1, ROUND(t2) AS t2, ROUND(t3) AS t3, ROUND(t4) AS t4
  FROM (SELECT canal,
               'T' || TO_CHAR(fecha_transf,'Q') AS trimestre,
               valor
          FROM transferencia
         WHERE fecha_transf >= DATE '2026-01-01'
           AND fecha_transf <  DATE '2027-01-01'
           AND estado = 'APLICADA')
 PIVOT (SUM(valor) FOR trimestre IN ('T1' AS t1, 'T2' AS t2,
                                     'T3' AS t3, 'T4' AS t4))
 ORDER BY canal;

-- MODELO (resuelto) — los 10 clientes con más saldo y qué productos tienen
SELECT cl.id_cliente, cl.nombre, cl.segmento,
       ROUND(SUM(c.saldo)) AS saldo_total,
       COUNT(*)            AS cuentas,
       LISTAGG(DISTINCT p.nombre, ', ')
         WITHIN GROUP (ORDER BY p.nombre) AS productos
  FROM cliente cl
  JOIN cuenta  c ON c.id_cliente  = cl.id_cliente
  JOIN catalogo_producto p ON p.id_producto = c.id_producto
 WHERE c.estado = 'ACTIVA'
 GROUP BY cl.id_cliente, cl.nombre, cl.segmento
 ORDER BY saldo_total DESC
 FETCH FIRST 10 ROWS WITH TIES;

--
--  PREGUNTA 3.8 — ¿Qué diferencia hay entre FETCH FIRST 10 ROWS ONLY y
--  FETCH FIRST 10 ROWS WITH TIES? ¿En cuál de los dos casos puede
--  devolver más de 10 filas y por qué?
--
-- Respuesta: FETCH FIRST 10 ROWS ONLY corta exactamente en 10 filas, sin 
-- importar empates: si hay dos clientes con el mismo saldo justo en la 
-- posición 10-11, descarta uno arbitrariamente.
-- FETCH FIRST 10 ROWS WITH TIES respeta los empates en el ORDER BY: si la 
-- fila 10 y la fila 11 tienen el mismo saldo_total, incluye a ambas.
-- ¿Cuál puede devolver más de 10 filas? WITH TIES — porque no corta en seco 
-- en la posición 10, sino que incluye todas las filas que empatan en el valor 
-- de ordenamiento con la última fila del corte.
--
--  ESCRIBA 3.5 — Un informe de "clientes en fuga": clientes
--  PREFERENCIAL cuya última transferencia tiene más de 120 días,
--  mostrando cuántos días llevan inactivos, su saldo total y cuántos
--  productos tienen contratados.
--
-- Respuesta:
--
SELECT cl.id_cliente, cl.nombre,
       TRUNC(SYSDATE - MAX(t.fecha_transf)) AS dias_inactividad,
       ROUND(SUM(c.saldo))                  AS saldo_total,
       COUNT(DISTINCT c.id_cuenta)          AS productos_contratados
  FROM cliente cl
  JOIN cuenta        c ON c.id_cliente = cl.id_cliente
  JOIN transferencia t ON t.cuenta_origen = c.id_cuenta
 WHERE cl.segmento = 'PREFERENCIAL'
 GROUP BY cl.id_cliente, cl.nombre
HAVING MAX(t.fecha_transf) < SYSDATE - 120
 ORDER BY dias_inactividad DESC;
--
-- Justificación: Agrupa por cliente, calcula su última transferencia (MAX),
-- su saldo total (SUM) y cuántas cuentas tiene (COUNT DISTINCT); el HAVING 
-- deja solo a los que llevan más de 120 días sin transferir.