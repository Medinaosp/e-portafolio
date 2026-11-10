-- =====================================================================
-- Optimización básica de consultas — Oracle 19c
-- 01_demos.sql : las cuatro demostraciones de la sesión
--
-- Ejecutar POR BLOQUES, no de corrido. Cada bloque termina en un plan
-- que hay que leer en pantalla antes de seguir.
--
-- Solo se usa EXPLAIN PLAN + DBMS_XPLAN.DISPLAY, que funciona con
-- privilegios normales. En SQL Developer también sirve F10.
-- =====================================================================

SET LINESIZE 200
SET PAGESIZE 200
SET TIMING ON


-- #####################################################################
-- DEMO 1 — Qué es un plan de ejecución
-- #####################################################################

EXPLAIN PLAN FOR
SELECT id_venta, fecha_venta, valor
  FROM venta
 WHERE id_cliente = 4321;

SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY(NULL, NULL, 'BASIC +COST +ROWS +PREDICATE'));

-- QUÉ SEÑALAR EN PANTALLA
--   Operation : TABLE ACCESS FULL VENTA  -> lee la tabla entera
--   Rows      : cuántas filas ESTIMA el motor que va a devolver
--   Cost      : unidad interna para comparar planes; no son segundos
--   Predicate Information: dice "filter" -> leyó todas las filas y luego
--                          descartó las que no cumplían


-- #####################################################################
-- DEMO 2 — Escaneo completo contra acceso por índice
-- #####################################################################

-- 2.1  Por la llave primaria ya hay índice: acceso directo.
EXPLAIN PLAN FOR
SELECT * FROM venta WHERE id_venta = 150000;
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY(NULL, NULL, 'BASIC +COST +ROWS'));
--   INDEX UNIQUE SCAN: baja por el árbol y devuelve una fila. Costo mínimo.

-- 2.2  Por id_cliente no hay índice, aunque exista la llave foránea.
EXPLAIN PLAN FOR
SELECT * FROM venta WHERE id_cliente = 4321;
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY(NULL, NULL, 'BASIC +COST +ROWS'));
--   300.000 filas leídas para devolver unas 15.

-- 2.3  Creamos el índice y repetimos la MISMA consulta.
CREATE INDEX idx_venta_cliente ON venta (id_cliente);
EXEC DBMS_STATS.GATHER_TABLE_STATS(USER, 'VENTA', cascade => TRUE);

EXPLAIN PLAN FOR
SELECT * FROM venta WHERE id_cliente = 4321;
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY(NULL, NULL, 'BASIC +COST +ROWS +PREDICATE'));
--   Ahora aparecen dos pasos encadenados:
--     INDEX RANGE SCAN            -> busca en el índice
--     TABLE ACCESS BY INDEX ROWID -> va por la fila completa
--   Y el predicado pasó de "filter" a "access". Compare el Cost con el
--   de la consulta anterior.

-- 2.4  El mismo índice, pero pidiendo media tabla.
EXPLAIN PLAN FOR
SELECT * FROM venta WHERE id_cliente BETWEEN 1 AND 10000;
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY(NULL, NULL, 'BASIC +COST +ROWS'));
--   El motor vuelve al escaneo completo POR DECISIÓN PROPIA.
--   Cuando hay que traer buena parte de la tabla, leerla de corrido sale
--   más barato que ir y volver miles de veces por el índice.
--   Moraleja: un índice no es una mejora automática.


-- #####################################################################
-- DEMO 3 — Tres formas de anular un índice sin darse cuenta
-- #####################################################################

CREATE INDEX idx_cliente_nombre    ON cliente (nombre);
CREATE INDEX idx_cliente_documento ON cliente (documento);
CREATE INDEX idx_venta_fecha       ON venta (fecha_venta);
BEGIN
  DBMS_STATS.GATHER_TABLE_STATS(USER, 'CLIENTE', cascade => TRUE);
  DBMS_STATS.GATHER_TABLE_STATS(USER, 'VENTA',   cascade => TRUE);
END;
/

-- ---------------------------------------------------------------------
-- 3.1  Una función sobre la columna
-- ---------------------------------------------------------------------
EXPLAIN PLAN FOR SELECT * FROM cliente WHERE nombre = 'GARCIA';
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY(NULL, NULL, 'BASIC +COST +ROWS'));   -- usa el índice

EXPLAIN PLAN FOR SELECT * FROM cliente WHERE UPPER(nombre) = 'GARCIA';
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY(NULL, NULL, 'BASIC +COST +ROWS'));   -- escaneo completo

--   El índice guarda 'Garcia', no UPPER('Garcia'). Ese valor no está en
--   el árbol, así que hay que calcular la función fila por fila.
--   Salida: un índice sobre la expresión.
CREATE INDEX idx_cliente_upper_nombre ON cliente (UPPER(nombre));
EXEC DBMS_STATS.GATHER_TABLE_STATS(USER, 'CLIENTE', cascade => TRUE);

EXPLAIN PLAN FOR SELECT * FROM cliente WHERE UPPER(nombre) = 'GARCIA';
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY(NULL, NULL, 'BASIC +COST +ROWS'));

-- El mismo problema con fechas, que es como aparece en la vida real:
EXPLAIN PLAN FOR
SELECT * FROM venta WHERE TRUNC(fecha_venta) = DATE '2024-05-10';
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY(NULL, NULL, 'BASIC +COST +ROWS'));   -- no usa el índice

EXPLAIN PLAN FOR
SELECT * FROM venta
 WHERE fecha_venta >= DATE '2024-05-10'
   AND fecha_venta <  DATE '2024-05-11';
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY(NULL, NULL, 'BASIC +COST +ROWS'));   -- sí lo usa

-- ---------------------------------------------------------------------
-- 3.2  Conversión implícita de tipos
-- ---------------------------------------------------------------------
EXPLAIN PLAN FOR SELECT * FROM cliente WHERE documento = 1004321;    -- número
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY(NULL, NULL, 'BASIC +COST +ROWS +PREDICATE'));
--   Mire el predicado: aparece TO_NUMBER("DOCUMENTO"). Nadie escribió esa
--   función; la puso el motor para poder comparar texto con número.

EXPLAIN PLAN FOR SELECT * FROM cliente WHERE documento = '1004321';  -- texto
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY(NULL, NULL, 'BASIC +COST +ROWS +PREDICATE'));

-- ---------------------------------------------------------------------
-- 3.3  Comodín al principio
-- ---------------------------------------------------------------------
EXPLAIN PLAN FOR SELECT * FROM cliente WHERE nombre LIKE 'GARCIA%';
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY(NULL, NULL, 'BASIC +COST +ROWS'));   -- usa el índice

EXPLAIN PLAN FOR SELECT * FROM cliente WHERE nombre LIKE '%GARCIA';
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY(NULL, NULL, 'BASIC +COST +ROWS'));   -- imposible usarlo

--   Un índice ordena como un diccionario. Buscar lo que EMPIEZA por
--   "GARCIA" es abrirlo en la G. Buscar lo que TERMINA en "GARCIA"
--   obliga a leerlo entero. No hay índice convencional que lo resuelva.


-- #####################################################################
-- DEMO 4 — Selectividad: no toda columna merece un índice
-- #####################################################################

-- Cuántos valores distintos tiene cada columna (NUM_DISTINCT):
SELECT column_name, num_distinct
  FROM user_tab_col_statistics
 WHERE table_name = 'VENTA'
 ORDER BY num_distinct;

-- canal tiene 2 valores para 300.000 filas. Creemos el índice igual:
CREATE INDEX idx_venta_canal ON venta (canal);
EXEC DBMS_STATS.GATHER_TABLE_STATS(USER, 'VENTA', cascade => TRUE);

EXPLAIN PLAN FOR SELECT * FROM venta WHERE canal = 'WEB';
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY(NULL, NULL, 'BASIC +COST +ROWS'));
--   El optimizador lo ignora: el filtro deja pasar la mitad de la tabla,
--   así que el índice no descarta nada. Y no es gratis: ocupa espacio y
--   hay que mantenerlo en cada INSERT, UPDATE y DELETE.

DROP INDEX idx_venta_canal;


-- #####################################################################
-- CIERRE — Qué pasa si las estadísticas están viejas
-- #####################################################################

-- Le decimos al motor que VENTA tiene 100 filas cuando tiene 300.000.
-- Es lo que ocurre en producción cuando una tabla crece y nadie recolecta.
EXEC DBMS_STATS.SET_TABLE_STATS(USER, 'VENTA', numrows => 100, numblks => 5);

EXPLAIN PLAN FOR
SELECT c.nombre, SUM(v.valor)
  FROM venta v JOIN cliente c ON c.id_cliente = v.id_cliente
 GROUP BY c.nombre;
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY(NULL, NULL, 'BASIC +COST +ROWS'));

-- Ahora recolectamos de verdad y repetimos la MISMA consulta.
EXEC DBMS_STATS.GATHER_TABLE_STATS(USER, 'VENTA', cascade => TRUE);

EXPLAIN PLAN FOR
SELECT c.nombre, SUM(v.valor)
  FROM venta v JOIN cliente c ON c.id_cliente = v.id_cliente
 GROUP BY c.nombre;
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY(NULL, NULL, 'BASIC +COST +ROWS'));

--   El plan cambia sin tocar una letra de la consulta. La consulta nunca
--   estuvo mal: lo que estaba mal era lo que el motor creía saber.
