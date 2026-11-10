-- =====================================================================
-- Bases de Datos 2 · Taller integrador — Banco Andino
-- 04_reto.sql   Reto final (25 minutos)
--
-- Trabajen en UNA SOLA CONEXIÓN: la pareja comparte el esquema.
-- Este es el ejercicio que se entrega.
-- Todo se resuelve con SQL. No se necesita PL/SQL.
-- =====================================================================

-- ---------------------------------------------------------------------
-- EL TICKET
--
--   De:    Gerencia de Operaciones, Banco Andino
--   Para:  Equipo de Base de Datos
--   Asunto: CRÍTICO — descuadres en transferencias
--
--   "Desde el puente festivo tenemos tres problemas:
--
--    1. La cuenta de compensación no cuadra. Hay días en que el total
--       debitado no coincide con el total acreditado, por montos
--       pequeños pero constantes. Contraloría ya abrió un caso.
--
--    2. Aparecieron transferencias donde al cliente le descontaron la
--       plata y nunca le llegó al destinatario. Otras al revés: llegó
--       al destino sin haber salido del origen. Nadie sabe cuántas son.
--
--    3. El tablero de la Vicepresidencia se demora casi un minuto en
--       abrir, y lo consultan cada media hora.
--
--    Adjunto la secuencia de sentencias que ejecuta el core cada vez
--    que se aplica una transferencia, y la consulta del tablero.
--    Necesitamos un diagnóstico y la corrección."
-- ---------------------------------------------------------------------


-- #####################################################################
-- PIEZA 1 — Lo que ejecuta el core al aplicar una transferencia
--
-- Caso real: la transferencia 950001, de la cuenta 1001 a la 1002,
-- por 300.000 pesos.
--
-- Ejecútelo tal como está y observe qué hace. NO lo corrija todavía.
-- #####################################################################

-- Deje las cuentas en un valor conocido antes de probar
UPDATE cuenta SET saldo = 1000000, version = 0 WHERE id_cuenta IN (1001, 1002);
UPDATE transferencia SET estado = 'REGISTRADA' WHERE id_transferencia = 950001;
COMMIT;

SELECT id_cuenta, saldo FROM cuenta WHERE id_cuenta IN (1001,1002) ORDER BY id_cuenta;

SELECT id_transferencia, cuenta_origen, cuenta_destino, valor, estado
FROM transferencia
WHERE id_transferencia = 950001;


--- inicio de lo que ejecuta el core -----------------------------------

-- 1. Débito del origen: la aplicación lee el saldo...
SELECT saldo FROM cuenta WHERE id_cuenta = 1001;
--> ...guarda ese número, le resta 300.000, y escribe el resultado:
UPDATE cuenta SET saldo = 1000000 WHERE id_cuenta = 1001;
COMMIT;

-- 2. Crédito del destino: lo mismo al otro lado
SELECT saldo FROM cuenta WHERE id_cuenta = 1002;
--> ...le suma 300.000 y escribe:
UPDATE cuenta SET saldo = 1300000 WHERE id_cuenta = 1002;
COMMIT;

-- 3. Los dos movimientos contables
INSERT INTO movimiento (id_movimiento, id_cuenta, id_transferencia, fecha_mov, tipo, valor)
VALUES (9500001, 1001, 950001, SYSDATE, 'DEBITO', 300000);
COMMIT;

INSERT INTO movimiento (id_movimiento, id_cuenta, id_transferencia, fecha_mov, tipo, valor)
VALUES (9500002, 1002, 950001, SYSDATE, 'CREDITO', 300000);
COMMIT;

-- 4. Y al final marca la transferencia
UPDATE transferencia SET estado = 'APLICADA' WHERE id_transferencia = 950001;
COMMIT;

--- fin de lo que ejecuta el core --------------------------------------

SELECT id_cuenta, saldo FROM cuenta WHERE id_cuenta IN (1001,1002) ORDER BY id_cuenta;


-- #####################################################################
-- PIEZA 2 — La consulta del tablero de la Vicepresidencia
-- #####################################################################

SELECT s.ciudad,
       COUNT(DISTINCT t.id_transferencia)  AS operaciones,
       ROUND(SUM(t.valor))                 AS valor_total,
       ROUND(AVG(t.valor))                 AS ticket
  FROM transferencia t
  JOIN cuenta        c ON c.id_cuenta   = t.cuenta_origen
  JOIN sucursal      s ON s.id_sucursal = c.id_sucursal
 WHERE TO_CHAR(t.fecha_transf, 'YYYY-MM') = '2026-03'
   AND t.estado = 'APLICADA'
 GROUP BY s.ciudad
 ORDER BY valor_total DESC;


-- #####################################################################
-- LO QUE HAY QUE ENTREGAR
-- #####################################################################
--
-- A. DIAGNÓSTICO  (4 puntos)
--
--    Identifique CUATRO defectos en la secuencia de la PIEZA 1.
--    Para cada uno indique:
--      - qué sentencia o qué parte de la secuencia lo causa
--      - cuál de los tres síntomas del ticket produce
--      - qué pasa en producción con 12.000 transferencias por hora
-- 
--  Respuesta: 
--  1. Defecto de concurrencia: actualización perdida
--     Parte que lo causa:
--      La aplicación primero consulta el saldo con:
--        SELECT saldo FROM cuenta WHERE id_cuenta = 1001;
--      Después calcula el nuevo saldo y lo guarda mediante:
--        UPDATE cuenta SET saldo = 700000
--          WHERE id_cuenta = 1001;
--      Síntoma que produce: Dos operaciones simultáneas pueden leer 
--      el mismo saldo y sobrescribir los cambios de la otra, provocando
--      pérdida de dinero.
--      Qué pasa en producción:Con 12.000 transferencias por hora, varias 
--      operaciones pueden modificar la misma cuenta al mismo tiempo. Esto 
--      puede generar saldos incorrectos y descuadres constantes.
-- 
--  2. Defecto de transaccionalidad: varios COMMIT
--    Parte que lo causa: Se utiliza un COMMIT después del débito, otro 
--    después del crédito y otros después de insertar los movimientos:
--      UPDATE cuenta SET saldo = 700000 ...
--      COMMIT;
--    Síntoma que produce: Si ocurre una falla después del débito y antes 
--    del crédito, el dinero queda descontado del origen, pero nunca llega 
--    al destino.
--    Qué pasa en producción: El sistema puede dejar miles de transferencias 
--    incompletas, con cuentas descuadradas y transferencias que no reflejan 
--    correctamente su estado.
--
--  3. Falta de validación de errores
--     Parte que lo causa: La aplicación ejecuta los UPDATE e INSERT y confirma 
--     los cambios sin verificar si todas las operaciones fueron exitosas ni si 
--     se afectó la cantidad de filas esperada.
--     Síntoma que produce: Los errores pasan inadvertidos. Una transferencia 
--     puede quedar incompleta o inconsistente sin generar una alerta clara.
--     Qué pasa en producción: Los descuadres pueden permanecer durante semanas 
--     porque el sistema no detecta ni reporta automáticamente las operaciones 
--     fallidas.
--
--  4. Defecto de rendimiento
--     Parte que lo causa: La aplicación hace un SELECT para leer el saldo, 
--     calcula el nuevo valor fuera de la base de datos y luego ejecuta un UPDATE 
--     con el valor calculado.
--     Síntoma que produce: Se generan consultas adicionales, más comunicación entre 
--     la aplicación y Oracle y mayor posibilidad de esperas entre transacciones.
--     Qué pasa en producción: Con 12.000 transferencias por hora, aumenta la carga 
--     de la base de datos, el tráfico entre aplicación y servidor y el tiempo de 
--     respuesta del sistema.
--
--    Pista: uno es de concurrencia, uno es de transaccionalidad, uno
--    hace que el problema pase inadvertido, y uno es de rendimiento.
--
--    Dos de ellos hay que REPRODUCIRLOS, no solo describirlos:
--      - el de concurrencia: ejecuten la secuencia desde las DOS
--        conexiones sobre la misma cuenta y muestren el resultado
--      - el de transaccionalidad: simulen una falla después del débito
--        y antes del crédito, y muestren el estado en que quedan las
--        dos cuentas y la transferencia
--
--
-- B. CORRECCIÓN  (4 puntos)
--
--    Reescriba la secuencia usando SQL. Debe cumplir las cinco cosas:
--      1. que dos operaciones simultáneas sobre la misma cuenta no
--         puedan perder dinero
--      2. que sea atómica: el débito, el crédito, los dos movimientos y
--         el cambio de estado ocurren todos, o no ocurre ninguno
--      3. que se note cuando algo no se aplicó, en lugar de pasar en
--         silencio
--      4. que no permita dejar una cuenta en saldo negativo
--      5. que dos transferencias cruzadas simultáneas (1001->1002 y
--         1002->1001) NO puedan provocar un interbloqueo
--
--    El punto 5 es el que distingue este caso: no basta con bloquear,
--    hay que bloquear EN UN ORDEN DETERMINISTA.
--
--    Dispone de las herramientas que ya vieron hoy:
--      - SELECT ... FOR UPDATE con ORDER BY   (parte 1)
--      - UPDATE ... SET col = col +/- n
--      - un solo COMMIT al final, o ROLLBACK
--      - la restricción CHECK que ya tiene la tabla CUENTA
--
--    Demuéstrelo: ejecute su versión desde las DOS conexiones al mismo
--    tiempo, en sentidos cruzados, y muestre que no hay ORA-00060 y que
--    los saldos cuadran. Documente cómo lo probó.
--
-- Respuesta: Versión Corregida
--
-- 0. PREPARAR LOS DATOS DE PRUEBA
-- Ejecutar UNA SOLA VEZ antes de comenzar
--
-- Eliminar movimientos creados en la prueba anterior
--
DELETE FROM movimiento
WHERE id_movimiento IN (9500001, 9500002);

-- Dejar la transferencia en estado REGISTRADA

UPDATE transferencia
SET estado = 'REGISTRADA'
WHERE id_transferencia = 950001;

-- Dejar las cuentas en valores conocidos

UPDATE cuenta
SET saldo = 1000000,
    version = 0
WHERE id_cuenta IN (1001, 1002);
COMMIT;

-- Verificar que todo quedó preparado

SELECT id_cuenta, saldo
FROM cuenta
WHERE id_cuenta IN (1001, 1002)
ORDER BY id_cuenta;

SELECT id_transferencia, cuenta_origen, cuenta_destino, valor, estado
FROM transferencia
WHERE id_transferencia = 950001;

-- 1. BLOQUEAR LAS DOS CUENTAS EN ORDEN DETERMINISTA

-- Ambas conexiones deben ejecutar este SELECT.
-- Siempre se bloquea primero la cuenta con menor ID.
-- Esto evita interbloqueos en transferencias cruzadas.

SELECT id_cuenta, saldo
FROM cuenta
WHERE id_cuenta IN (1001, 1002)
ORDER BY id_cuenta
FOR UPDATE;

-- 2. REALIZAR EL DÉBITO DEL ORIGEN
--
-- Se descuenta directamente sobre el saldo actual.
-- La condición saldo >= 300000 evita que quede negativo.

UPDATE cuenta
SET saldo = saldo - 300000
WHERE id_cuenta = 1001
  AND saldo >= 300000;

-- Verificar que el débito sí se realizó
SELECT id_cuenta, saldo
FROM cuenta
WHERE id_cuenta = 1001;

-- 3. REALIZAR EL CRÉDITO DEL DESTINO

UPDATE cuenta
SET saldo = saldo + 300000
WHERE id_cuenta = 1002;

-- Verificar saldos

SELECT id_cuenta, saldo
FROM cuenta
WHERE id_cuenta IN (1001, 1002)
ORDER BY id_cuenta;

-- 4. INSERTAR EL MOVIMIENTO CONTABLE DEL DÉBITO

INSERT INTO movimiento
(
    id_movimiento,
    id_cuenta,
    id_transferencia,
    fecha_mov,
    tipo,
    valor
)
VALUES
(
    9500001,
    1001,
    950001,
    SYSDATE,
    'DEBITO',
    300000
);

-- 5. INSERTAR EL MOVIMIENTO CONTABLE DEL CRÉDITO

INSERT INTO movimiento
(
    id_movimiento,
    id_cuenta,
    id_transferencia,
    fecha_mov,
    tipo,
    valor
)
VALUES
(
    9500002,
    1002,
    950001,
    SYSDATE,
    'CREDITO',
    300000
);

-- 6. CAMBIAR EL ESTADO DE LA TRANSFERENCIA

-- Solo se cambia si todavía estaba REGISTRADA.
-- Así se evita aplicar dos veces la misma transferencia.

UPDATE transferencia
SET estado = 'APLICADA'
WHERE id_transferencia = 950001
  AND estado = 'REGISTRADA';

-- 7. COMPROBAR EL RESULTADO ANTES DE CONFIRMAR

SELECT id_cuenta, saldo
FROM cuenta
WHERE id_cuenta IN (1001, 1002)
ORDER BY id_cuenta;

SELECT id_transferencia, estado
FROM transferencia
WHERE id_transferencia = 950001;

SELECT id_movimiento,
       id_cuenta,
       id_transferencia,
       tipo,
       valor
FROM movimiento
WHERE id_transferencia = 950001
ORDER BY id_movimiento;

-- 8. CONFIRMAR TODO JUNTO

COMMIT;

--
-- Se ejecutaron dos conexiones simultáneas sobre las mismas cuentas. La 
-- segunda conexión esperó el desbloqueo de la primera, pero no se produjo 
-- ORA-00060. Esto demuestra que el bloqueo en orden determinista evita el 
-- interbloqueo.
--
-- Prueba de transacción atómica: 

UPDATE cuenta
SET saldo = saldo - 300000
WHERE id_cuenta = 1001
  AND saldo >= 300000;
  
-- SIMULAR FALLA CON ROLLBACK;

  ROLLBACK;

  
  SELECT id_transferencia, estado
FROM transferencia
WHERE id_transferencia = 950001;

--
-- C. OPTIMIZACIÓN DE LA CONSULTA  (1 punto)
--
--      - Capture el plan actual y anote COST y consistent gets
--      - Identifique qué impide el uso del índice
--      - Reescriba la consulta y/o cree el índice necesario
--      - Capture el plan nuevo y anote la mejora
--      - Justifique el índice: qué consulta lo usa y por qué no bastaba
--        con los que ya existen
--
-- Respuesta: Plan actual:

EXPLAIN PLAN FOR

SELECT s.ciudad,
       COUNT(DISTINCT t.id_transferencia)  AS operaciones,
       ROUND(SUM(t.valor))                 AS valor_total,
       ROUND(AVG(t.valor))                 AS ticket
  FROM transferencia t
  JOIN cuenta        c ON c.id_cuenta   = t.cuenta_origen
  JOIN sucursal      s ON s.id_sucursal = c.id_sucursal
 WHERE TO_CHAR(t.fecha_transf, 'YYYY-MM') = '2026-03'
   AND t.estado = 'APLICADA'
 GROUP BY s.ciudad
 ORDER BY valor_total DESC;

SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY(format => 'BASIC +COST +ROWS'));

-- 1. ANOTAMOS: COST: Sucursal ->3, Transferencia -> 550 y Cuenta -> 68
--    consistent_gets: Sucursal -> 6, Transferencia -> 2013 y Cuenta -> 190
--
--  2. Qué impide el uso del índice: TO_CHAR(t.fecha_transf, 'YYYY-MM') = 
--  '2026-03' aplica la función TO_CHAR sobre la columna fecha_transf. 
--  Esa columna es la primera del índice ix_transf_fecha_estado (creado 
--  en la Parte 2), pero al transformarla con una función, los valores 
--  que se comparan (cadenas 'YYYY-MM') ya no corresponden a los valores 
--  crudos que están almacenados en las hojas del índice (fechas). Oracle 
--  no puede usar un índice B-tree normal para esa comparación tendría que 
--  aplicarle la función a cada entrada del índice para poder compararla, 
--  lo cual el índice no soporta, así que la única opción que le queda es 
--  recorrer la tabla completa.

-- 3. Corrección de la consulta:

SELECT s.ciudad,
       COUNT(DISTINCT t.id_transferencia)  AS operaciones,
       ROUND(SUM(t.valor))                 AS valor_total,
       ROUND(AVG(t.valor))                 AS ticket
  FROM transferencia t
  JOIN cuenta        c ON c.id_cuenta   = t.cuenta_origen
  JOIN sucursal      s ON s.id_sucursal = c.id_sucursal
 WHERE t.fecha_transf >= DATE '2026-03-01'
   AND t.fecha_transf <  DATE '2026-04-01'
   AND t.estado = 'APLICADA'
 GROUP BY s.ciudad
 ORDER BY valor_total DESC;

--
-- Se reemplazó la comparación por texto (TO_CHAR(...) = '2026-03') 
-- por un rango explícito de fechas (>= y <), que no transforma la columna. 
-- Con esto, fecha_transf queda "limpia" en el WHERE, y el optimizador 
-- vuelve a poder usar el índice existente.
--
-- 4. Plan nuevo:

EXPLAIN PLAN FOR
SELECT /*+ INDEX(t IX_TRANSF_FECHA_ESTADO) */
       s.ciudad,
       COUNT(DISTINCT t.id_transferencia)  AS operaciones,
       ROUND(SUM(t.valor))                 AS valor_total,
       ROUND(AVG(t.valor))                 AS ticket
  FROM transferencia t
  JOIN cuenta        c ON c.id_cuenta   = t.cuenta_origen
  JOIN sucursal      s ON s.id_sucursal = c.id_sucursal
 WHERE t.fecha_transf >= DATE '2026-03-01'
   AND t.fecha_transf <  DATE '2026-04-01'
   AND t.estado = 'APLICADA'
 GROUP BY s.ciudad
 ORDER BY valor_total DESC;

SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY(format => 'BASIC +COST +ROWS'));

--
--  ANOTAMOS: COST: 29      consistent_gets: 11
-- 
-- 5. Justificación del Índice: El índice IX_TRANSF_FECHA_ESTADO es 
-- necesario porque es el único que permite filtrar eficientemente por rango 
-- de fechas y estado a la vez (como en los reportes del tablero). Los otros 
-- índices no servían para esto: PK_TRANSFERENCIA solo busca por ID exacto, e 
-- IX_TRANSF_FECHA_ORIGEN está pensado para auditar una cuenta específica, no 
-- para agrupar por ciudad. Aunque el optimizador prefirió un FULL SCAN en la 
-- prueba por el alto volumen de datos (~4.489 filas), el índice sigue siendo 
-- indispensable para consultas con rangos de fechas más cortos o estados menos 
-- comunes.
--
-- D. UNA RECOMENDACIÓN  (1 punto)
--
--    En un párrafo dirigido a la Gerencia de Operaciones: ¿qué práctica
--    debe cambiar el banco para que este problema no vuelva a aparecer?
--    No hable de esta consulta ni de estas sentencias: hable de la
--    organización. Considere que el descuadre existió durante semanas
--    antes de que alguien lo notara.
--
-- Respuesta: El banco debe exigir que todo código que module saldos de clientes 
-- pase por una revisión técnica obligatoria antes de llegar a producción, que 
-- verifique que las operaciones sean atómicas (un solo punto de confirmación, 
-- no varios), que bloqueen las cuentas de forma ordenada cuando se tocan varias 
-- a la vez, y que se pruebe con transacciones concurrentes reales, no solo con 
-- un usuario a la vez. Este tipo de errores no se nota en pruebas normales porque 
-- solo aparece bajo carga y con montos pequeños, así que también se necesitan alertas 
-- automáticas que detecten descuadres apenas ocurran, en vez de esperar a que alguien 
-- los note semanas después.
--
--
-- FORMATO DE ENTREGA
--   Un archivo .sql con la secuencia corregida y la consulta optimizada,
--   más un documento corto con las respuestas a A y D y las capturas de
--   los planes de ejecución del punto C.
-- #####################################################################


-- ---------------------------------------------------------------------
-- Zona de trabajo: escriba aquí su versión corregida
-- ---------------------------------------------------------------------

-- Sugerencia de estructura, para que no se pierdan:
--
--   1. Bloquee las DOS cuentas en una sola sentencia, ordenadas por
--      id_cuenta. Ese ORDER BY es lo que elimina el interbloqueo.
--   2. Debite el origen y acredite el destino, siempre sobre el valor
--      actual de la fila, nunca sobre un número leído antes.
--   3. Inserte los dos movimientos.
--   4. Cambie el estado de la transferencia, condicionado al estado
--      esperado.
--   5. Revise cuántas filas afectó cada sentencia antes de confirmar.
--   6. Un solo COMMIT al final; si algo salió mal, ROLLBACK.
