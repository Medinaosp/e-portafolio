-- =====================================================================
-- Bases de Datos 2 · Taller integrador — Banco Andino
-- 01_sesion_A.sql        >>>  CONEXIÓN A  <<<   (cajero A)
--
-- NO ejecute este archivo de corrido. Cada bloque dice PASO n:
-- ejecútelo con Ctrl+Enter cuando le toque, alternando con la conexión B.
--
-- ANTES DE EMPEZAR, verifique:
--   1. Autocommit APAGADO
--      Herramientas > Preferencias > Base de datos > Avanzado > Autoconfirmar
--      (debe estar DESMARCADO)
--   2. Dos CONEXIONES distintas, no dos hojas sobre la misma conexión.
-- =====================================================================

SET Autocommit OFF;
SELECT 'CONEXIÓN A' AS ventana, SYS_CONTEXT('USERENV','SID') AS sid FROM dual;


-- #####################################################################
-- EJERCICIO 1.1 — El retiro que se pierde (actualización perdida)
--
-- Escenario: el mismo cliente retira por el cajero automático mientras
-- su empresa le hace un débito automático. Las dos operaciones leen el
-- saldo, restan en memoria y escriben el resultado. Es lo que hace la
-- mayoría del código que ustedes van a encontrar en producción.
--
-- Cuenta 1001, saldo inicial 1.000.000.
-- #####################################################################

-- PASO 1  (A)  Estado inicial
SELECT id_cuenta, saldo, saldo_retenido, version
  FROM cuenta WHERE id_cuenta = 1001;
--> Anote el SALDO. Debe ser 1.000.000.

-- PASO 2  (A)  "El cajero" leyó 1.000.000 y calculó 1.000.000 - 300.000
UPDATE cuenta SET saldo = 700000 WHERE id_cuenta = 1001;
--  NO confirme todavía.

-- ... vaya a la conexión B, PASO 3 ...

-- PASO 5  (A)  Confirmo mi retiro de 300.000
COMMIT;

-- ... conexión B, PASO 6 ...

-- PASO 8  (A)  ¿Cuánto saldo quedó?
SELECT id_cuenta, saldo FROM cuenta WHERE id_cuenta = 1001;
--
--  PREGUNTA 1.1 — Salieron 300.000 (A) más 200.000 (B) = 500.000 de
--  1.000.000. Deberían quedar 500.000. ¿Cuántos quedan? ¿Quién "ganó"?
--  ¿Hubo algún error, alguna advertencia, algún registro de que algo
--  salió mal?
--
-- Respuesta: Al final quedan 800.000 en la cuenta y la transacción que 
-- "ganó" fue la Conexión B, ya que su instrucción fue la última así que 
-- se podría decir que se ignoro el cambio anterior. El sistema ejecutó 
-- todo con total normalidad, por lo que no hubo ningún error, advertencia 
-- ni registro de que algo salió mal, ya que para la base de datos ambas 
-- sentencias fueron válidas.
--
--  PREGUNTA 1.2 — El bloqueo de fila SÍ funcionó: B esperó a que A
--  confirmara. Explique entonces por qué el banco perdió dinero de todos
--  modos.
-- 
-- Respuesta: El banco perdió dinero porque el bloqueo de fila solo evita 
-- que dos transacciones modifiquen el mismo registro al mismo tiempo, pero 
-- no impide que una de ellas calcule con datos obsoletos. Como la Conexión 
-- B leyó el saldo inicial antes del COMMIT de A, al destrabarse no volvió 
-- a consultar la base de datos, sino que simplemente inyectó el valor 
-- absoluto (800.000) que ya había calculado en su memoria externa.
--
--  PREGUNTA 1.3 — En un marketplace este error vende una unidad de más.
--  En un banco, ¿de quién es la plata que se acaba de crear de la nada,
--  y quién la va a reclamar?
--
-- Respuesta: Ese dinero creado de la nada se ve reflejado temporalmente a 
-- favor del cliente, pero le pertenece legítimamente al banco como una pérdida. 
-- Quien va a reclamar ese dinero es el propio banco cuando se den cuenta de 
-- dicho error.
--


-- #####################################################################
-- EJERCICIO 1.2 — Defensa pesimista: SELECT ... FOR UPDATE
-- #####################################################################

-- PASO 1  (A)  Dejo la cuenta en un valor conocido
UPDATE cuenta SET saldo = 1000000, version = 0 WHERE id_cuenta = 1001;
COMMIT;

-- PASO 2  (A)  Leo Y bloqueo en la misma operación
SELECT id_cuenta, saldo
  FROM cuenta
 WHERE id_cuenta = 1001
   FOR UPDATE;

-- ... conexión B, PASO 3 ...

-- PASO 5  (A)  Descuento mis 300.000 y libero
UPDATE cuenta SET saldo = saldo - 300000 WHERE id_cuenta = 1001;
COMMIT;

-- ... conexión B, PASO 6 ...

-- PASO 8  (A)  Resultado
SELECT id_cuenta, saldo FROM cuenta WHERE id_cuenta = 1001;
--
--  PREGUNTA 1.4 — Ahora sí quedan 500.000. ¿Qué dos cosas cambiaron
--  respecto al ejercicio anterior? (pista: una es el FOR UPDATE, la otra
--  está dentro del UPDATE mismo)
-- 
-- Respuesta: Cambiaron dos cosas fundamentales: la primera es el uso de 
-- FOR UPDATE en la lectura inicial, lo que congeló la fila desde el 
-- principio y obligó a la Conexión B a esperar en lugar de leer datos 
-- obsoletos; la segunda es que la sentencia UPDATE ahora realiza una 
-- operación relativa (saldo = saldo - 300000) en lugar de inyectar un 
-- valor absoluto precalculado, asegurando que cualquier descuento se 
-- aplique sobre el dinero real de la base de datos en el instante de la 
-- ejecución.
--
--  PREGUNTA 1.5 — ¿Cuál fue el precio que se pagó por esta seguridad?
--  Piense en una cuenta empresarial de recaudo que recibe cientos de
--  consignaciones por minuto.
--
-- Respuesta: El precio que se pagó fue la pérdida de concurrencia y 
-- velocidad por bloqueo. En una cuenta de recaudo empresarial con cientos 
-- de transacciones por minuto, el uso de FOR UPDATE obligaría a procesar 
-- todas las consignaciones en una fila india estricta, lo que crearía un 
-- cuello de botella masivo, retrasos severos por esperas (locks) y posibles 
-- caídas del sistema por límite de tiempo de espera (timeouts).
-- 


-- #####################################################################
-- EJERCICIO 1.3 — Defensa optimista: columna de versión
--
-- Nadie bloquea nada. El choque se detecta al escribir.
-- #####################################################################

-- PASO 1  (A)  Reinicio
UPDATE cuenta SET saldo = 1000000, version = 0 WHERE id_cuenta = 1001;
COMMIT;

-- PASO 2  (A)  Leo el saldo y la versión.  NO bloqueo nada.
SELECT id_cuenta, saldo, version FROM cuenta WHERE id_cuenta = 1001;
--> Anote la versión que ve. Debe ser 0.

-- ... conexión B, PASO 3: lee lo mismo y escribe PRIMERO ...

-- PASO 5  (A)  Intento escribir con la versión que leí
UPDATE cuenta
   SET saldo   = saldo - 300000,
       version = version + 1
 WHERE id_cuenta = 1001
   AND version   = 0;              -- <-- la versión que leí en el PASO 2
COMMIT;
--
--  Mire el mensaje: ¿cuántas filas actualizó?
-- Actualizo 0 filas

-- PASO 6  (A)
SELECT id_cuenta, saldo, version FROM cuenta WHERE id_cuenta = 1001;
--
--  PREGUNTA 1.6 — Su UPDATE afectó 0 filas. ¿Qué debe hacer la
--  aplicación en ese momento, y qué NO debe hacer nunca?
--
-- Respuesta: Al afectar 0 filas, la aplicación debe reintentar la 
-- transacción de forma automática (volver a leer el saldo y la nueva versión 1,
-- recalcular el descuento y ejecutar de nuevo el UPDATE bajo la condición version 
-- = 1); por el contrario, la aplicación nunca debe forzar la escritura ignorando 
-- el control de versiones, ni asumir que la operación fue exitosa, ni reportar 
-- un error definitivo al usuario sin antes haber intentado resolver el choque de 
-- manera transparente mediante un ciclo de reintentos (retry loop).
--
--  PREGUNTA 1.7 — Compare las dos defensas. ¿En qué producto del banco
--  usaría la pesimista y en cuál la optimista? Justifique con el nivel
--  de contención esperado, no con opiniones.
--
-- Respuesta: Se debe usar la defensa pesimista en productos con alta contención 
-- esperada, como una cuenta empresarial de recaudos masivos o cuentas que reciben 
-- cientos de transferencias simultáneas, ya que los reintentos constantes colapsarían 
-- la aplicación. En contraste, se debe usar la defensa optimista en productos con baja 
-- contención esperada, como cuentas corrientes o de ahorros de personas naturales 
-- donde la probabilidad de que el cliente realice dos operaciones idénticas exactamente 
-- en el mismo milisegundo es casi nula, maximizando así la velocidad de procesamiento 
-- general sin sobrecargar la base de datos con bloqueos persistentes.
--


-- #####################################################################
-- EJERCICIO 1.4 — Repartir la cola de compensación: SKIP LOCKED
--
-- Dos procesos de compensación toman transferencias de la misma cola.
-- No pueden procesar la misma dos veces, y no pueden quedarse esperando
-- el uno al otro: la ventana de compensación se cierra a una hora fija.
-- #####################################################################

-- PASO 1  (A)  Tomo 5 tareas y las marco como mías
SELECT id_tarea, id_transferencia
  FROM tarea_compensacion
 WHERE estado = 'PENDIENTE'
   AND ROWNUM <= 5
   FOR UPDATE SKIP LOCKED;
--  Nota de sintaxis: aquí se usa ROWNUM y no FETCH FIRST ... ROWS ONLY.
--  Oracle implementa FETCH FIRST como una vista en línea, y combinarlo
--  con FOR UPDATE devuelve ORA-02014. Para una cola de trabajo ROWNUM es
--  además lo correcto: no importa CUÁLES cinco tareas toma, importa que
--  sean cinco libres y que nadie más las tenga.
--> Anote los id_tarea que le tocaron.  NO confirme todavía.

-- ... conexión B, PASO 2: pide 5 tareas y recibe OTRAS distintas ...

-- PASO 3  (A)  Marco las mías como compensadas y libero
UPDATE tarea_compensacion
   SET estado = 'COMPENSADA', tomada_por = 'PROCESO_A', fecha_toma = SYSTIMESTAMP
 WHERE id_tarea IN (1,2,3,4,5);      -- <-- reemplace por los ids que le tocaron
COMMIT;

-- PASO 5  (A)  Verificación conjunta
SELECT tomada_por, COUNT(*) AS tareas
  FROM tarea_compensacion WHERE estado = 'COMPENSADA'
 GROUP BY tomada_por;
--
--  PREGUNTA 1.8 — ¿Qué habría pasado sin SKIP LOCKED? Describa los dos
--  comportamientos posibles según se use FOR UPDATE simple o NOWAIT.
-- 
-- Respuesta: Sin la cláusula SKIP LOCKED, se habrían presentado dos 
-- comportamientos problemáticos según la variante utilizada: si se usara 
-- FOR UPDATE simple, el Proceso B se habría quedado completamente congelado 
-- (bloqueado) esperando en "fila india" a que el Proceso A terminara y 
-- liberara las filas, anulando el procesamiento en paralelo; por el 
-- contrario, si se usara NOWAIT, el Proceso B habría fallado inmediatamente 
-- arrojando un error de base de datos (ORA-00054: resource busy) al detectar 
-- que parte de los registros solicitados ya estaban reservados por A, 
-- interrumpiendo abruptamente su ejecución.
--
--  PREGUNTA 1.9 — En una compensación real, procesar dos veces la misma
--  transferencia significa mover la plata dos veces. ¿Qué le garantiza
--  SKIP LOCKED que no le garantizaría un reparto hecho en la aplicación
--  con un "WHERE MOD(id,2) = 0" para un proceso y "= 1" para el otro?
--
-- Respuesta: La cláusula SKIP LOCKED garantiza dinamismo, tolerancia a 
-- fallos y alta disponibilidad, algo que un reparto estático por residuo 
-- (MOD(id,2)) no puede ofrecer. Si el Proceso A se cae, se ralentiza o 
-- se apaga, la lógica por MOD dejaría todas sus tareas asignadas huérfanas 
-- y acumuladas sin que nadie las procese; en cambio, SKIP LOCKED actúa en 
-- tiempo real sobre la base de datos: si un proceso muere o no toma una 
-- tarea, el bloqueo se libera automáticamente y cualquier otro proceso 
-- disponible saltará los registros ocupados y tomará los libres, asegurando 
-- que la cola avance de forma óptima sin duplicaciones ni registros atascados.
--


-- #####################################################################
-- EJERCICIO 1.5 — El bloqueo que nadie espera: FK sin índice
--
-- NOTIFICACION.ID_TRANSFERENCIA es llave foránea hacia TRANSFERENCIA
-- y NO está indexada.
-- #####################################################################

-- PASO 1  (A)  Registro la notificación de la transferencia 900001.
--   NO confirmo.
INSERT INTO notificacion (id_notificacion, id_transferencia, canal, enviada)
VALUES (9000001, 900001, 'SMS', 'S');

-- ... conexión B, PASO 2: intenta borrar la transferencia 900005, que no
--     tiene ninguna notificación ni ningún movimiento, y se queda esperando ...

-- PASO 3  (A)  Mientras B espera, mire el bloqueo.
--   TX = bloqueo de fila.  TM = bloqueo de TABLA.
SELECT l.sid, l.type,
       DECODE(l.lmode, 0,'ninguno',1,'null',2,'RS',3,'RX',4,'S',5,'SRX',6,'X') AS tiene,
       DECODE(l.request,0,'-',1,'null',2,'RS',3,'RX',4,'S',5,'SRX',6,'X')      AS pide
  FROM v$lock l JOIN v$session s ON s.sid = l.sid
 WHERE s.username = USER AND l.type IN ('TX','TM');
--> Si no tiene permisos sobre V$, el docente lo proyecta.

-- PASO 4  (A)  Libero
COMMIT;

-- PASO 6  (A)  Creo el índice que faltaba
CREATE INDEX ix_notif_transferencia ON notificacion (id_transferencia);

-- PASO 7  (A)  Repitan los pasos 1 y 2. Ahora B NO se bloquea.
--
--  PREGUNTA 1.10 — Explique por qué Oracle toma un bloqueo de TABLA sobre
--  el hijo cuando se borra un padre y la FK no está indexada.
--
-- Respuesta: Oracle bloquea la tabla sobre el hijo porque necesita proteger 
-- la integridad referencial al borrar un registro de la tabla padre. Como 
-- la FK no tiene índice, no puede revisar eficientemente los registros 
-- relacionados y termina bloqueando la tabla completa, generando esperas 
-- innecesarias.
--
--  PREGUNTA 1.11 — Revise el esquema completo del Banco Andino. ¿Qué
--  OTRAS llaves foráneas están sin índice? ¿Cuáles de ellas son realmente
--  un problema en este negocio y cuáles no? Justifique pensando en qué
--  se borra y qué no se borra nunca en un banco.
-- 
SELECT uc.table_name AS tabla_hija, 
       uc.constraint_name AS nombre_fk,
       ucc.column_name AS columna_fk
  FROM user_constraints uc
  JOIN user_cons_columns ucc ON ucc.constraint_name = uc.constraint_name
 WHERE uc.constraint_type = 'R' -- 'R' filtro para Llaves Foráneas (Referencial)
MINUS
SELECT uic.table_name, 
       uc2.constraint_name,
       uic.column_name
  FROM user_ind_columns uic
  JOIN user_constraints uc2 ON uc2.table_name = uic.table_name
 WHERE uc2.constraint_type = 'R' AND uic.column_position = 1;
-- 
-- Si son un problema crítico: Las de las tablas CUENTA (ID_CLIENTE, ID_PRODUCTO, 
-- ID_SUCURSAL y CATALOGO_PRODUCTO). En un banco, los clientes pueden ser eliminados 
-- por políticas de datos, los productos comerciales se cancelan y las sucursales 
-- físicas se cierran o reubican con frecuencia. Si se ejecuta un mantenimiento, 
-- actualización o borrado en estas tablas maestras (padres), la base de datos 
-- congelará mediante un bloqueo de tabla completo la inserción o modificación de 
-- nuevas cuentas bancarias, deteniendo la operación comercial del banco.
--
-- NO son un problema real: Las de las tablas MOVIMIENTO (ID_CUENTA) y TRANSFERENCIA 
-- (CUENTA_DESTINO, CUENTA_ORIGEN). Debido a regulaciones legales y de auditoría 
-- financiera estrictas, las transacciones y movimientos históricos de los clientes 
-- jamás se borran físicamente de un banco. Si ocurre un error de dinero, se soluciona 
-- mediante un contraasiento contable o un cambio de estado lógico, pero nunca aplicando 
-- un comando DELETE. Como las cuentas de origen y destino nunca sufren borrados en sus 
-- tablas principales, el bloqueo total de la tabla hija jamás llegará a dispararse en 
-- producción.
--


-- #####################################################################
-- EJERCICIO 1.6 — Interbloqueo: las dos transferencias cruzadas
--
-- Este es el caso clásico de la banca, y no es hipotético: ocurre todos
-- los días. Dos clientes se transfieren plata mutuamente al mismo tiempo.
-- #####################################################################

-- Antes de empezar, deje las dos cuentas en un valor conocido
UPDATE cuenta SET saldo = 1000000, version = 0 WHERE id_cuenta IN (1001, 1002);
COMMIT;

-- PASO 1  (A)  Transferencia de la 1001 a la 1002: primero debito el origen
UPDATE cuenta SET saldo = saldo - 50000 WHERE id_cuenta = 1001;

-- ... conexión B, PASO 2: hace la transferencia inversa, 1002 -> 1001,
--     y debita PRIMERO la 1002 ...

-- PASO 3  (A)  Ahora acredito el destino: la cuenta 1002, que B ya tiene
UPDATE cuenta SET saldo = saldo + 50000 WHERE id_cuenta = 1002;
--> Me quedo esperando.

-- ... conexión B, PASO 4: pide la 1001, que yo tengo -> ciclo cerrado ...

--> En segundos, UNA de las dos recibe:
--     ORA-00060: deadlock detected while waiting for resource

ROLLBACK;
--
--  PREGUNTA 1.12 — Oracle abortó UNA sentencia, no la transacción
--  completa. ¿En qué estado queda la sesión víctima y qué debe hacer?
--  ¿Qué pasa si la aplicación asume que Oracle deshizo todo?
-- 
-- Respuesta: La sesión víctima queda en un estado de transacción activa 
-- pero incompleta, donde Oracle solo revierte automáticamente la última 
-- instrucción que causó el ciclo (UPDATE), manteniendo vigentes los 
-- bloqueos y cambios previos (como el primer débito). Si la aplicación asume 
-- erróneamente que Oracle deshizo todo, dejará la transacción abierta en la 
-- base de datos de forma indefinida, provocando que los registros queden 
-- congelados para otros usuarios y generando graves descuadres de saldo si el 
-- proceso no ejecuta explícitamente un ROLLBACK manual para limpiar la sesión.
--
--  PREGUNTA 1.13 — Escriba la regla de diseño, en una frase, que habría
--  hecho imposible este interbloqueo. Después dígala en términos de
--  código: ¿qué línea concreta hay que agregar antes de los dos UPDATE?
--
-- Respuesta: La regla de diseño es "Toda transacción concurrente que involucre 
-- múltiples registros debe bloquear o modificar los recursos estrictamente en 
-- el mismo orden jerárquico o numérico (por ejemplo, de menor a mayor ID)". En 
-- términos de código, para implementar esta regla se debe agregar, justo antes 
-- de los UPDATE, una línea que ordene y bloquee simultáneamente ambas cuentas 
-- usando FOR UPDATE ordenado:
SELECT id_cuenta FROM cuenta WHERE id_cuenta IN (1001, 1002) ORDER BY id_cuenta FOR UPDATE;
--
