-- =====================================================================
-- Bases de Datos 2 · Taller integrador — Banco Andino
-- 01_sesion_B.sql        >>>  CONEXIÓN B  <<<   (débito automático)
--
-- NO ejecute este archivo de corrido. Cada bloque dice PASO n:
-- ejecútelo con Ctrl+Enter cuando le toque, alternando con la conexión A.
--
-- ANTES DE EMPEZAR, verifique:
--   1. Autocommit APAGADO
--      Herramientas > Preferencias > Base de datos > Avanzado > Autoconfirmar
--   2. Que este SID sea DISTINTO al de la conexión A.
-- =====================================================================

SELECT 'CONEXIÓN B' AS ventana, SYS_CONTEXT('USERENV','SID') AS sid FROM dual;
SET Autocommit OFF;


-- #####################################################################
-- EJERCICIO 1.1 — El retiro que se pierde (actualización perdida)
-- #####################################################################

-- ... espere a que A haga sus PASOS 1 y 2 ...

-- PASO 3  (B)  "Mi proceso" también leyó el saldo
SELECT id_cuenta, saldo FROM cuenta WHERE id_cuenta = 1001;
--> ¿Qué valor ve? ¿Ve los 700.000 que A ya escribió pero no confirmó?
--  Anote la respuesta: es la lectura consistente de Oracle.
--
--  Respuesta: No veo los 700.000 ya que A no ha confirmado el cambio.
--
-- PASO 4  (B)  Leí 1.000.000 y calculé 1.000.000 - 200.000. Escribo.
UPDATE cuenta SET saldo = 800000 WHERE id_cuenta = 1001;
--> ESTA SENTENCIA NO RESPONDE. Queda esperando el bloqueo de A.
--  Déjela corriendo y observe. NO la cancele.

-- ... A hace COMMIT en su PASO 5: aquí su UPDATE se destraba solo ...

-- PASO 6  (B)  Ya respondió. Confirmo mi débito de 200.000.
COMMIT;

-- PASO 7  (B)
SELECT id_cuenta, saldo FROM cuenta WHERE id_cuenta = 1001;
--
--  Discutan con su pareja ANTES de mirar el resultado:
--  ¿debería quedar en 500.000 o en 800.000?
--  Y una más: si quedó en 800.000, ¿el banco perdió 300.000 o el cliente
--  se quedó con 300.000 que no eran suyos? No es la misma pregunta.


-- #####################################################################
-- EJERCICIO 1.2 — Defensa pesimista: SELECT ... FOR UPDATE
-- #####################################################################

-- ... A hizo su PASO 2: leyó Y bloqueó la fila ...

-- PASO 3  (B)  Intento leer con intención de escribir
SELECT id_cuenta, saldo
  FROM cuenta
 WHERE id_cuenta = 1001
   FOR UPDATE;
--> Se bloquea. A tiene la cuenta reservada.

-- PASO 4  (B)  Compruebe algo importante: una lectura NORMAL sí pasa.
--   Abra una tercera hoja de trabajo sobre ESTA misma conexión y ejecute:
--     SELECT saldo FROM cuenta WHERE id_cuenta = 1001;
--   Responde de inmediato. Consultar el saldo por la app nunca se bloquea,
--   aunque haya una transacción abierta sobre esa cuenta.

-- ... A hace UPDATE y COMMIT en su PASO 5 ...

-- PASO 6  (B)  Mi SELECT FOR UPDATE ya respondió, con el saldo NUEVO.
--   Descuento mis 200.000 sobre el valor actual, no sobre el que leí antes.
UPDATE cuenta SET saldo = saldo - 200000 WHERE id_cuenta = 1001;
COMMIT;

-- PASO 7  (B)
SELECT id_cuenta, saldo FROM cuenta WHERE id_cuenta = 1001;
--> 1.000.000 - 300.000 - 200.000 = 500.000.  Nada se perdió.


-- #####################################################################
-- EJERCICIO 1.3 — Defensa optimista: columna de versión
-- #####################################################################

-- ... A leyó saldo y version en su PASO 2. Nadie bloqueó nada ...

-- PASO 3  (B)  Leo lo mismo que A
SELECT id_cuenta, saldo, version FROM cuenta WHERE id_cuenta = 1001;

-- PASO 4  (B)  Y escribo PRIMERO
UPDATE cuenta
   SET saldo   = saldo - 200000,
       version = version + 1
 WHERE id_cuenta = 1001
   AND version   = 0;
COMMIT;
--> 1 fila actualizada: gané la carrera. La versión pasó de 0 a 1.

-- ... A intenta su UPDATE con version = 0 y actualiza 0 filas ...

-- PASO 7  (B)
SELECT id_cuenta, saldo, version FROM cuenta WHERE id_cuenta = 1001;
--
--  Nadie se bloqueó en ningún momento, y aun así no se perdió nada.
--  Ese es el trato del bloqueo optimista: cero espera, a cambio de
--  tener que reintentar cuando hay choque.


-- #####################################################################
-- EJERCICIO 1.4 — Repartir la cola de compensación: SKIP LOCKED
-- #####################################################################

-- ... A tomó 5 tareas en su PASO 1 y no ha confirmado ...

-- PASO 2  (B)  Pido 5 tareas
SELECT id_tarea, id_transferencia
  FROM tarea_compensacion
 WHERE estado = 'PENDIENTE'
   AND ROWNUM <= 5
   FOR UPDATE SKIP LOCKED;
--> Son tareas DISTINTAS a las de A, y la consulta no esperó nada.
--  Anote los id_tarea que le tocaron.

-- PASO 4  (B)  Marco las mías
UPDATE tarea_compensacion
   SET estado = 'COMPENSADA', tomada_por = 'PROCESO_B', fecha_toma = SYSTIMESTAMP
 WHERE id_tarea IN (6,7,8,9,10);     -- <-- reemplace por los ids que le tocaron
COMMIT;

-- PASO 6  (B)  Compare con A: no hay ni una tarea repetida.
SELECT estado, tomada_por, COUNT(*) FROM tarea_compensacion
 GROUP BY estado, tomada_por ORDER BY 1,2;


-- #####################################################################
-- EJERCICIO 1.5 — El bloqueo que nadie espera: FK sin índice
-- #####################################################################

-- ... A insertó una notificación de la transferencia 900001 y NO confirmó ...

-- PASO 2  (B)  Borro la transferencia 900005.
--   Esa transferencia NO tiene notificaciones ni movimientos: no tiene
--   nada que ver con lo que está haciendo A.
DELETE FROM transferencia WHERE id_transferencia = 900005;
--> SE BLOQUEA.
--  Sin índice sobre NOTIFICACION.ID_TRANSFERENCIA, Oracle protege la
--  integridad tomando un bloqueo de TABLA sobre el hijo.

-- ... A confirma en su PASO 4: aquí se destraba ...

-- PASO 5  (B)
ROLLBACK;

-- ... A crea el índice en su PASO 6 ...

-- (B)  Repitan el ejercicio completo desde el PASO 1 de A.
--   Ahora el DELETE responde de inmediato.


-- #####################################################################
-- EJERCICIO 1.6 — Interbloqueo: las dos transferencias cruzadas
-- #####################################################################

-- ... A empezó su transferencia 1001 -> 1002 y ya debitó la 1001 ...

-- PASO 2  (B)  Yo hago la transferencia INVERSA, 1002 -> 1001.
--   Primero debito mi origen, que es la 1002.
UPDATE cuenta SET saldo = saldo - 50000 WHERE id_cuenta = 1002;

-- ... A pide la 1002 en su PASO 3 y se queda esperando ...

-- PASO 4  (B)  Ahora acredito mi destino: la cuenta 1001, que A tiene
UPDATE cuenta SET saldo = saldo + 50000 WHERE id_cuenta = 1001;
--> Ciclo cerrado: A espera a B y B espera a A.
--  En unos segundos, una de las dos recibe ORA-00060.
--
--  Fíjense en algo: ninguna de las dos hizo nada raro. Las dos siguieron
--  la misma lógica correcta —debitar el origen, acreditar el destino—.
--  El interbloqueo apareció solo porque el orden de las cuentas era
--  distinto en cada transacción.

ROLLBACK;
