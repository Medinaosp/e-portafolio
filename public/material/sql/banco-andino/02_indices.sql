-- =====================================================================
-- Bases de Datos 2 · Taller integrador — Banco Andino
-- 02_indices.sql   Índices y optimización de consultas
--
-- IMPORTANTE: de aquí en adelante trabajen en UNA SOLA CONEXIÓN.
-- La pareja comparte el mismo esquema, y dos personas creando índices o
-- insertando en la misma tabla al mismo tiempo se bloquean entre sí.
-- Uno maneja el teclado, los dos discuten y anotan.
--
-- Ejecute bloque por bloque con Ctrl+Enter.
-- =====================================================================

SET TIMING ON
SET LINESIZE 200
SET PAGESIZE 1000
SET autocommit OFF

-- ---------------------------------------------------------------------
-- CÓMO VAMOS A MEDIR
--
-- En SQL Developer tiene tres herramientas. Úselas todas:
--
--   F10  Explain Plan   -> el plan que el optimizador PIENSA usar.
--                          No ejecuta la consulta. Es una estimación.
--   F6   Autotrace      -> ejecuta la consulta y muestra el plan REAL
--                          más las estadísticas de sesión.
--   F5   Run Script     -> para los bloques con SET TIMING.
--
-- Las dos cifras que importan:
--   COST            estimación del optimizador (sirve para comparar)
--   consistent gets bloques leídos de verdad (esta es la que no miente)
--
-- También puede pedir el plan por texto, así:
-- ---------------------------------------------------------------------

EXPLAIN PLAN FOR
SELECT COUNT(*) FROM transferencia WHERE estado = 'APLICADA';

SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY(format => 'BASIC +COST +ROWS'));


-- #####################################################################
-- EJERCICIO 2.1 — El informe de la Superintendencia
--
-- Todos los meses hay que reportar el valor y el número de
-- transferencias efectivamente aplicadas del mes anterior.
-- #####################################################################

-- PASO 1  Ejecute la consulta y mida
SELECT COUNT(*)          AS operaciones,
       SUM(valor)        AS valor_total,
       ROUND(AVG(valor)) AS ticket_promedio
  FROM transferencia
 WHERE fecha_transf >= DATE '2026-03-01'
   AND fecha_transf <  DATE '2026-04-01'
   AND estado        = 'APLICADA';

-- PASO 2  Vea el plan
EXPLAIN PLAN FOR
SELECT COUNT(*), SUM(valor)
  FROM transferencia
 WHERE fecha_transf >= DATE '2026-03-01'
   AND fecha_transf <  DATE '2026-04-01'
   AND estado        = 'APLICADA';

SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY(format => 'BASIC +COST +ROWS'));
--
--  ANOTE:  operación = TABLE ACCESS FULL  COST = 377   filas = 5685
--
--  PREGUNTA 2.1 — La tabla tiene 200.000 filas y la consulta devuelve
--  unos pocos miles. ¿Por qué el optimizador está leyendo la tabla
--  completa? ¿Es un error del optimizador?
--
-- Respuesta: La tabla tiene aproximadamente 200.000 filas, pero la 
-- consulta devuelve alrededor de 5.247 registros. El optimizador decide 
-- leer la tabla completa porque considera que usar el índice no sería más 
-- eficiente, debido a que debe consultar una cantidad considerable de filas 
-- y el costo de acceder mediante el índice sería mayor.
--


-- PASO 3  Cree el índice
CREATE INDEX ix_transf_fecha_estado ON transferencia (fecha_transf, estado);

EXEC DBMS_STATS.GATHER_TABLE_STATS(USER, 'TRANSFERENCIA', cascade => TRUE);

-- PASO 4  Repita la medición
EXPLAIN PLAN FOR
SELECT COUNT(*), SUM(valor)
  FROM transferencia
 WHERE fecha_transf >= DATE '2026-03-01'
   AND fecha_transf <  DATE '2026-04-01'
   AND estado        = 'APLICADA';

SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY(format => 'BASIC +COST +ROWS'));
--
--  ANOTE:  operación = COLLECTION ITERATOR PICKLER FETCH   COST = 29
--
--  PREGUNTA 2.2 — ¿Cuánto bajó el COST? Ejecute también con F6
--  (Autotrace) antes y después y compare los "consistent gets".
--
-- Respuesta: El costo bajó drásticamente de 377 a 29, lo que representa 
-- una reducción bastante grande en el esfuerzo estimado por el optimizador.
-- Consistent gets (Autotrace): Cayeron de miles a unas pocas decenas. Antes 
-- del índice, Oracle leía todos los bloques de la tabla en memoria (FULL SCAN); 
-- con el índice, va directo a las páginas exactas de los registros de marzo, 
-- ignorando el resto de la tabla.
--


-- PASO 5  El orden de las columnas SÍ importa
CREATE INDEX ix_transf_estado_fecha ON transferencia (estado, fecha_transf);

EXEC DBMS_STATS.GATHER_TABLE_STATS(USER, 'TRANSFERENCIA', cascade => TRUE);

-- Fuerce cada índice y compare
SELECT /*+ INDEX(t ix_transf_fecha_estado) */ COUNT(*)
  FROM transferencia t
 WHERE fecha_transf >= DATE '2026-03-01'
   AND fecha_transf <  DATE '2026-04-01'
   AND estado        = 'APLICADA';

SELECT /*+ INDEX(t ix_transf_estado_fecha) */ COUNT(*)
  FROM transferencia t
 WHERE fecha_transf >= DATE '2026-03-01'
   AND fecha_transf <  DATE '2026-04-01'
   AND estado        = 'APLICADA';
--
--  PREGUNTA 2.3 — ¿Cuál de los dos índices elige el optimizador cuando
--  no se le fuerza nada? Compare el COST de los dos SELECT anteriores.
--  Formule la regla general sobre el orden de columnas en un índice
--  compuesto, distinguiendo el predicado de IGUALDAD del de RANGO.
--
-- Respuesta: ¿Cuál elige? El optimizador elige IX_TRANF_ESTADO_FECHA por 
-- tener un menor esfuerzo estimado (COST = 22 frente a 35 del otro índice).
-- Regla general: Las columnas con filtros de IGUALDAD (=) deben ir primero 
-- y las de RANGO (>=, <, BETWEEN) al final. Esto permite a Oracle saltar 
-- directo al valor exacto y escanear secuencialmente el rango, reduciendo 
-- el trabajo interno.
--
--  PREGUNTA 2.4 — Suponga ahora que existe además un informe diario que
--  filtra SOLO por rango de fechas, sin estado. ¿Cuál de los dos índices
--  le sirve a ese informe y cuál no? ¿Cambia eso su recomendación?
--  Responda cuál de los dos conservaría en producción y por qué.
--
-- Respuesta: ¿Cuál sirve? Al informe diario solo le sirve IX_TRANSF_FECHA_ESTADO 
-- porque tiene la fecha como columna líder; el otro será ignorado porque Oracle 
-- no puede usar un índice compuesto si falta su primera columna en el WHERE.
-- Decisión en producción: Se debe conservar IX_TRANSF_FECHA_ESTADO. Aunque 
-- cuesta un poco más para el reporte mensual (35 vs 22), es el único capaz de dar 
-- cobertura a ambos informes a la vez, evitando duplicar almacenamiento y el 
-- sobrecosto de mantener dos índices activos en el banco.
--

-- Para el resto del taller trabajamos con IX_TRANSF_FECHA_ESTADO,
-- para no multiplicar índices. Su recomendación va en la entrega.
DROP INDEX ix_transf_estado_fecha;


-- #####################################################################
-- EJERCICIO 2.2 — El índice que existe y no se usa
--
-- El área de servicio al cliente busca por nombre y se queja de que la
-- pantalla de consulta se demora.
-- #####################################################################

-- PASO 1  Sin índice
EXPLAIN PLAN FOR
SELECT id_cliente, nombre, ciudad, segmento
  FROM cliente WHERE UPPER(nombre) = 'MARCELA ROJAS 4004';

SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY(format => 'BASIC +COST'));

-- PASO 2  Creo el índice "obvio"
CREATE INDEX ix_cliente_nombre ON cliente (nombre);
EXEC DBMS_STATS.GATHER_TABLE_STATS(USER, 'CLIENTE', cascade => TRUE);

EXPLAIN PLAN FOR
SELECT id_cliente, nombre, ciudad, segmento
  FROM cliente WHERE UPPER(nombre) = 'MARCELA ROJAS 4004';

SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY(format => 'BASIC +COST'));
--
--  PREGUNTA 2.5 — El índice existe y sigue haciendo FULL SCAN.
--  ¿Por qué? ¿Qué le hizo la consulta a la columna indexada?
--
-- Respuesta: Porque el índice tradicional guarda los nombres 
-- originales y no contiene las cadenas convertidas a mayúsculas.
--
-- Le aplicó la función UPPER en el WHERE. Al alterar los datos en 
-- tiempo de ejecución, Oracle no puede compararlos contra el índice 
-- y se ve obligado a recorrer la tabla entera fila por fila para 
-- calcular la función.
-- 

-- PASO 3  El índice que sí sirve
CREATE INDEX ix_cliente_nombre_upper ON cliente (UPPER(nombre));
EXEC DBMS_STATS.GATHER_TABLE_STATS(USER, 'CLIENTE', cascade => TRUE);

EXPLAIN PLAN FOR
SELECT id_cliente, nombre, ciudad, segmento
  FROM cliente WHERE UPPER(nombre) = 'MARCELA ROJAS 4004';

SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY(format => 'BASIC +COST'));

-- PASO 4  El mismo error, con fechas.  Este es el más común de todos,
--   y en banca aparece en cada extracto y en cada corte diario.
EXPLAIN PLAN FOR
SELECT COUNT(*) FROM transferencia WHERE TRUNC(fecha_transf) = DATE '2026-03-15';
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY(format => 'BASIC +COST'));

EXPLAIN PLAN FOR
SELECT COUNT(*) FROM transferencia
 WHERE fecha_transf >= DATE '2026-03-15'
   AND fecha_transf <  DATE '2026-03-16';
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY(format => 'BASIC +COST'));
--
--  PREGUNTA 2.6 — Las dos consultas devuelven exactamente lo mismo.
--  Compare los planes. Escriba la regla, en una frase, que todo
--  desarrollador debería tener presente al filtrar por fecha.
--
-- Respuesta: El plan de la primera consulta (con TRUNC) realiza un 
-- INDEX FAST FULL SCAN con un costo de 238, mientras que la segunda 
-- consulta optimizada realiza un INDEX RANGE SCAN con un costo de 3.
-- Regla para el desarrollador: Evita aplicar funciones (como TRUNC) 
-- sobre las columnas de fecha en el filtro WHERE; en su lugar, filtra 
-- mediante un rango de fechas con operadores de comparación (>= y <) 
-- para permitir que la base de datos aproveche los índices existentes.
--

-- #####################################################################
-- EJERCICIO 2.3 — Cuándo NO conviene un índice
-- #####################################################################

-- PASO 1  Un filtro que devuelve el 62% de la tabla
CREATE INDEX ix_transf_estado ON transferencia (estado);
EXEC DBMS_STATS.GATHER_TABLE_STATS(USER, 'TRANSFERENCIA', cascade => TRUE);

EXPLAIN PLAN FOR
SELECT COUNT(*), SUM(valor) FROM transferencia WHERE estado = 'APLICADA';
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY(format => 'BASIC +COST +ROWS'));

-- PASO 2  El mismo índice, con un valor poco frecuente
EXPLAIN PLAN FOR
SELECT COUNT(*), SUM(valor) FROM transferencia WHERE estado = 'REVERSADA';
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY(format => 'BASIC +COST +ROWS'));
--
--  PREGUNTA 2.7 — El mismo índice, la misma consulta, distinto valor:
--  en un caso se usa y en el otro no. ¿Cómo lo sabe el optimizador?
--  ¿Qué información necesita para tomar esa decisión?
--
-- Respuesta: ¿Cómo lo sabe? Calculando la cardinalidad (cantidad de 
-- filas que devuelve cada valor). Si el valor representa la mayoría de
-- la tabla (62%), prefiere leer la tabla completa; si el valor es muy
-- raro, usa el índice.
-- ¿Qué información necesita? Las estadísticas de la
-- tabla (num_rows) y, sobre todo, un histograma en la columna estado para
-- conocer la frecuencia de cada valor.
--
--  PREGUNTA 2.8 — Consulte la selectividad y el clustering factor:
--

SELECT column_name, num_distinct, num_nulls, density
  FROM user_tab_col_statistics
 WHERE table_name = 'TRANSFERENCIA'
   AND column_name IN ('ESTADO','FECHA_TRANSF','CUENTA_ORIGEN','CANAL');

SELECT index_name, num_rows, distinct_keys, clustering_factor, blevel, leaf_blocks
  FROM user_indexes WHERE table_name = 'TRANSFERENCIA';
--
--  ¿Qué le dice el CLUSTERING FACTOR de IX_TRANSF_FECHA_ESTADO comparado
--  con el de IX_TRANSF_ESTADO? ¿Por qué son tan distintos?
--
-- Respuesta: El CLUSTERING_FACTOR de IX_TRANSF_ESTADO (5.276) es muy bajo y 
-- eficiente, mientras que el de IX_TRANSF_FECHA_ESTADO (199.975) es pésimo 
-- porque iguala al total de filas.
--
-- Por qué son tan distintos: Porque los datos en el disco están físicamente 
-- agrupados y ordenados por su ESTADO, mientras que las FECHAS están dispersas 
-- de forma caótica por toda la tabla. 
--


-- #####################################################################
-- EJERCICIO 2.4 — El índice que evita tocar la tabla
-- #####################################################################

-- PASO 1  Cuentas más activas del trimestre
EXPLAIN PLAN FOR
SELECT cuenta_origen, COUNT(*) AS operaciones
  FROM transferencia
 WHERE fecha_transf >= DATE '2026-01-01'
   AND fecha_transf <  DATE '2026-04-01'
 GROUP BY cuenta_origen;

SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY(format => 'BASIC +COST'));
--> Fíjese: hay INDEX RANGE SCAN y ADEMÁS TABLE ACCESS BY INDEX ROWID.

-- PASO 2  Agrego la columna que falta al índice
CREATE INDEX ix_transf_fecha_origen ON transferencia (fecha_transf, cuenta_origen);
EXEC DBMS_STATS.GATHER_TABLE_STATS(USER, 'TRANSFERENCIA', cascade => TRUE);

EXPLAIN PLAN FOR
SELECT cuenta_origen, COUNT(*) AS operaciones
  FROM transferencia
 WHERE fecha_transf >= DATE '2026-01-01'
   AND fecha_transf <  DATE '2026-04-01'
 GROUP BY cuenta_origen;

SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY(format => 'BASIC +COST'));
--
--  PREGUNTA 2.9 — Desapareció el TABLE ACCESS. ¿Cómo se llama esta
--  técnica y por qué es tan efectiva? ¿Cuál es su límite: hasta dónde
--  tiene sentido seguir agregando columnas al índice?
--
-- Respuesta: 
-- Nombre de la técnica: Índice de Cobertura (Covering Index o Index-Only Scan).
-- Por qué es tan efectiva: Porque evita tocar la tabla física. Toda la 
-- información necesaria para el filtro (WHERE) y el resultado (SELECT/GROUP BY) 
-- ya está dentro del índice, resolviendo la consulta directamente desde allí.
-- Cuál es su límite: El impacto en las escrituras (INSERT, UPDATE, DELETE). 
-- Agregar demasiadas columnas sobrecarga el índice, consume más almacenamiento 
-- y vuelve lentas las modificaciones de datos debido a que la base de datos debe 
-- actualizar el índice en cada operación.
--


-- #####################################################################
-- EJERCICIO 2.5 — Lo que cuesta un índice
--
-- Hasta aquí solo hemos visto el beneficio. Ahora el precio.
-- #####################################################################

-- PASO 1  Cuántos índices tiene TRANSFERENCIA en este momento
SELECT index_name, leaf_blocks,
       ROUND(leaf_blocks * 8192 / 1024 / 1024, 2) AS mb_aprox
  FROM user_indexes WHERE table_name = 'TRANSFERENCIA';

-- PASO 2  Inserte 50.000 transferencias CON todos los índices y mida
--   (ejecute este bloque con F5 para ver el TIMING)
SET TIMING ON
INSERT INTO transferencia
  (id_transferencia, cuenta_origen, cuenta_destino, fecha_transf, valor, canal, estado)
SELECT 1000000 + LEVEL,
       MOD(LEVEL, 15000) + 1,
       MOD(LEVEL, 15000) + 15001,
       DATE '2026-06-01' + MOD(LEVEL,30), 100000, 'APP', 'REGISTRADA'
  FROM dual CONNECT BY LEVEL <= 50000;
COMMIT;
--> Anote el tiempo: 00.00.03.560

-- PASO 3  Ahora sin índices secundarios
DROP INDEX ix_transf_fecha_estado;
DROP INDEX ix_transf_estado;
DROP INDEX ix_transf_fecha_origen;

INSERT INTO transferencia
  (id_transferencia, cuenta_origen, cuenta_destino, fecha_transf, valor, canal, estado)
SELECT 2000000 + LEVEL,
       MOD(LEVEL, 15000) + 1,
       MOD(LEVEL, 15000) + 15001,
       DATE '2026-06-01' + MOD(LEVEL,30), 100000, 'APP', 'REGISTRADA'
  FROM dual CONNECT BY LEVEL <= 50000;
COMMIT;
--> Anote el tiempo: 00.00.00.796

-- PASO 4  Deje el esquema como debe quedar
DELETE FROM transferencia WHERE id_transferencia >= 1000000;
COMMIT;

CREATE INDEX ix_transf_fecha_estado ON transferencia (fecha_transf, estado);
CREATE INDEX ix_transf_fecha_origen ON transferencia (fecha_transf, cuenta_origen);
EXEC DBMS_STATS.GATHER_TABLE_STATS(USER, 'TRANSFERENCIA', cascade => TRUE);
--
--  PREGUNTA 2.10 — ¿Cuál fue la diferencia de tiempo? Extrapole:
--  el Banco Andino procesa 12.000 transferencias por hora en hora pico.
--  ¿Qué costo operativo tiene cada índice que se agrega "por si acaso"?
--
-- Respuesta: 
-- Diferencia de tiempo: Con índices tomó 3.56 segundos y sin ellos 0.79 
-- segundos; las inserciones se volvieron más lentas con índices.
-- Costo operativo: Cada índice "por si acaso" obliga a la base de datos a 
-- escribir en múltiples lugares a la vez. En hora pico (12,000 
-- transacciones por hora), esto genera cuellos de botella, mayor consumo 
-- de CPU/disco y lentitud para los clientes que usan la APP del banco.
-- 
--
--  PREGUNTA 2.11 — Proponga la lista DEFINITIVA de índices para este
--  esquema. Para cada uno escriba: qué consulta lo justifica, y por qué
--  no se puede resolver con otro índice ya existente. Tenga en cuenta
--  que TRANSFERENCIA tiene DOS llaves foráneas hacia CUENTA.
--
-- Respuesta: 
-- 1. ALTER TABLE transferencia ADD CONSTRAINT pk_transferencia PRIMARY KEY (id_transferencia);
-- Búsquedas directas de una transacción por su identificador único (por ejemplo, al dar clic 
-- al detalle de un movimiento en la banca móvil):
--
-- SELECT * FROM transferencia 
-- WHERE id_transferencia = 105432;
--
-- Ningún otro índice puede garantizar la unicidad de los registros ni resolver búsquedas por 
-- el ID de la transferencia.
--
-- 2. CREATE INDEX ix_transf_fecha_origen ON transferencia (fecha_transf, cuenta_origen);
-- Reportes masivos de auditoría o analítica del banco, como el conteo trimestral de transacciones 
-- por cuenta del Ejercicio 2.4:
--
-- SELECT cuenta_origen, COUNT(*) AS operaciones
--  FROM transferencia
-- WHERE fecha_transf >= DATE '2026-01-01'
--   AND fecha_transf <  DATE '2026-04-01'
-- GROUP BY cuenta_origen;
--
-- Al incluir tanto la fecha como la cuenta de origen, el optimizador hace un Index-Only Scan 
-- (obtiene los datos directamente del índice sin tocar la tabla física), algo imposible de 
-- lograr con índices individuales.
--
-- 3. CREATE INDEX ix_transf_cuenta_destino ON transferencia (cuenta_destino);
-- Consultar el historial de abonos o transferencias recibidas por un cliente específico:
--
-- SELECT * FROM transferencia 
-- WHERE cuenta_destino = 15045;
--
-- El índice anterior (IX_TRANSF_FECHA_ORIGEN) tiene como columnas la fecha y la cuenta de origen. 
-- El optimizador no puede usarlo para buscar directamente por la cuenta de destino.
--
