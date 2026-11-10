--------------------------------------------------------------------------------
-- UNIVERSIDAD EL BOSQUE - INGENIERIA DE SISTEMAS
-- Bases de Datos - Modulo 3 de 4: PROCEDIMIENTOS ALMACENADOS
-- Oracle Database 19c
-- Docente: Ing. Christian Felipe Duarte
--------------------------------------------------------------------------------
-- COMO USAR ESTE ARCHIVO
--
--   1. Script independiente: crea sus propias tablas (prefijo PR_) y al final
--      las elimina. No necesita los otros modulos.
--   2. Avance PASO por PASO. Cada paso trae QUE VAMOS A HACER / QUE DEBE
--      OBSERVAR / RESULTADO ESPERADO.
--   3. El PASO 8 pide abrir una SEGUNDA SESION. Tengalo presente antes de
--      empezar: es el unico paso que no se puede hacer solo con esta ventana.
--   4. Requisitos: usuario con CREATE TABLE, CREATE PROCEDURE y CREATE SEQUENCE.
--------------------------------------------------------------------------------

SET SERVEROUTPUT ON SIZE UNLIMITED
SET LINESIZE 200
SET PAGESIZE 100

PROMPT ============================================================
PROMPT  MODULO 3 - PROCEDIMIENTOS ALMACENADOS
PROMPT ============================================================


--------------------------------------------------------------------------------
-- PASO 0 - PREPARACION DEL ESQUEMA DE PRACTICA
--------------------------------------------------------------------------------
-- QUE VAMOS A HACER : crear estudiantes, asignaturas con cupo, matriculas y
--                     una tabla de log de errores.
-- QUE DEBE OBSERVAR : la columna ID_MATRICULA usa IDENTITY, la forma moderna
--                     de generar consecutivos desde 12c.
-- RESULTADO ESPERADO: 4 estudiantes, 3 asignaturas, 0 matriculas.
--------------------------------------------------------------------------------
BEGIN
  FOR r IN (SELECT object_name, object_type FROM user_objects
             WHERE object_type IN ('PROCEDURE','PACKAGE')
               AND object_name IN ('PR_REGISTRAR_MATRICULA','PR_LOG',
                                   'PR_ANULAR_MATRICULA','PK_MATRICULA')) LOOP
    EXECUTE IMMEDIATE 'DROP ' || r.object_type || ' ' || r.object_name;
  END LOOP;

  FOR r IN (SELECT table_name FROM user_tables
             WHERE table_name IN ('PR_MATRICULA','PR_ASIGNATURA','PR_ESTUDIANTE',
                                  'PR_LOG_ERROR')) LOOP
    EXECUTE IMMEDIATE 'DROP TABLE ' || r.table_name || ' CASCADE CONSTRAINTS';
  END LOOP;
END;
/

CREATE TABLE pr_estudiante (
  id_estudiante NUMBER(5) CONSTRAINT pk_pr_est PRIMARY KEY,
  nombre        VARCHAR2(40) NOT NULL,
  activo        CHAR(1) DEFAULT 'S' CONSTRAINT ck_pr_act CHECK (activo IN ('S','N'))
);

CREATE TABLE pr_asignatura (
  id_asignatura   NUMBER(5) CONSTRAINT pk_pr_asig PRIMARY KEY,
  titulo          VARCHAR2(40) NOT NULL,
  cupo_disponible NUMBER(3) NOT NULL
);

CREATE TABLE pr_matricula (
  id_matricula  NUMBER GENERATED ALWAYS AS IDENTITY
                CONSTRAINT pk_pr_mat PRIMARY KEY,
  id_estudiante NUMBER(5) CONSTRAINT fk_pr_mat_est REFERENCES pr_estudiante,
  id_asignatura NUMBER(5) CONSTRAINT fk_pr_mat_asig REFERENCES pr_asignatura,
  fecha         DATE DEFAULT SYSDATE,
  estado        VARCHAR2(12) DEFAULT 'ACTIVA'
);

CREATE TABLE pr_log_error (
  fecha   TIMESTAMP,
  unidad  VARCHAR2(40),
  codigo  NUMBER,
  mensaje VARCHAR2(400),
  traza   VARCHAR2(2000)
);

INSERT INTO pr_estudiante VALUES (101,'Ana Maria Torres','S');
INSERT INTO pr_estudiante VALUES (102,'Bernardo Pineda','S');
INSERT INTO pr_estudiante VALUES (103,'Carolina Reyes','N');   -- inactiva
INSERT INTO pr_estudiante VALUES (104,'Daniel Ospina','S');

INSERT INTO pr_asignatura VALUES (55,'Bases de Datos 1',2);    -- cupo pequeno a proposito
INSERT INTO pr_asignatura VALUES (56,'Bases de Datos 2',10);
INSERT INTO pr_asignatura VALUES (57,'Sistemas Operativos',0); -- sin cupo
COMMIT;

PROMPT Esquema de practica listo.


--------------------------------------------------------------------------------
-- PASO 1 - EL PROCEDIMIENTO MAS SIMPLE POSIBLE
--------------------------------------------------------------------------------
-- QUE VAMOS A HACER : crear un procedimiento sin parametros e invocarlo.
-- QUE DEBE OBSERVAR : el procedimiento NO devuelve valor y NO se puede usar
--                     dentro de un SELECT. Se invoca como una sentencia.
-- RESULTADO ESPERADO: una linea con el total de estudiantes activos.
--------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE pr_resumen
IS
  v_total NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_total FROM pr_estudiante WHERE activo = 'S';
  DBMS_OUTPUT.PUT_LINE('Estudiantes activos: ' || v_total);
END pr_resumen;
/
SHOW ERRORS

EXEC pr_resumen

BEGIN
  pr_resumen;        -- la misma invocacion, desde un bloque
END;
/


--------------------------------------------------------------------------------
-- PASO 2 - MODOS DE PARAMETRO IN, OUT E IN OUT
--------------------------------------------------------------------------------
-- QUE VAMOS A HACER : un procedimiento que recibe, devuelve y transforma.
-- QUE DEBE OBSERVAR : el parametro OUT llega siempre en NULL, sin importar lo
--                     que traiga la variable del llamador. El IN OUT si
--                     conserva el valor de entrada.
-- RESULTADO ESPERADO: v_salida queda con el nombre; v_contador entra en 10 y
--                     sale en 11.
--------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE pr_demo_modos (
  p_id       IN     pr_estudiante.id_estudiante%TYPE,
  p_nombre      OUT pr_estudiante.nombre%TYPE,
  p_contador IN OUT NUMBER)
IS
BEGIN
  DBMS_OUTPUT.PUT_LINE('Dentro: p_nombre llega como ' || NVL(p_nombre,'NULL'));
  DBMS_OUTPUT.PUT_LINE('Dentro: p_contador llega como ' || p_contador);

  SELECT nombre INTO p_nombre FROM pr_estudiante WHERE id_estudiante = p_id;
  p_contador := p_contador + 1;
END pr_demo_modos;
/
SHOW ERRORS

DECLARE
  v_salida   pr_estudiante.nombre%TYPE := 'VALOR PREVIO';
  v_contador NUMBER := 10;
BEGIN
  pr_demo_modos(p_id => 101, p_nombre => v_salida, p_contador => v_contador);
  DBMS_OUTPUT.PUT_LINE('Fuera : p_nombre   = ' || v_salida);
  DBMS_OUTPUT.PUT_LINE('Fuera : p_contador = ' || v_contador);
END;
/


--------------------------------------------------------------------------------
-- PASO 3 - UN PROCEDIMIENTO REAL: VALIDAR, ACTUAR, INFORMAR
--------------------------------------------------------------------------------
-- QUE VAMOS A HACER : registrar una matricula con tres validaciones y devolver
--                     el identificador generado.
-- QUE DEBE OBSERVAR : el orden del cuerpo. Primero se valida todo, despues se
--                     modifica. Asi no queda trabajo a medias si algo falla.
-- RESULTADO ESPERADO: compila sin errores.
--------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE pr_registrar_matricula (
  p_id_estudiante IN  pr_estudiante.id_estudiante%TYPE,
  p_id_asignatura IN  pr_asignatura.id_asignatura%TYPE,
  p_id_matricula  OUT pr_matricula.id_matricula%TYPE)
IS
  v_activo CHAR(1);
  v_cupo   pr_asignatura.cupo_disponible%TYPE;
  v_existe NUMBER;
BEGIN
  -- validacion 1: el estudiante existe y esta activo
  BEGIN
    SELECT activo INTO v_activo
      FROM pr_estudiante WHERE id_estudiante = p_id_estudiante;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      RAISE_APPLICATION_ERROR(-20011, 'Estudiante inexistente: ' || p_id_estudiante);
  END;

  IF v_activo = 'N' THEN
    RAISE_APPLICATION_ERROR(-20012, 'Estudiante inactivo: ' || p_id_estudiante);
  END IF;

  -- validacion 2: no puede repetir la misma asignatura activa
  SELECT COUNT(*) INTO v_existe
    FROM pr_matricula
   WHERE id_estudiante = p_id_estudiante
     AND id_asignatura = p_id_asignatura
     AND estado = 'ACTIVA';

  IF v_existe > 0 THEN
    RAISE_APPLICATION_ERROR(-20013, 'La matricula ya existe y esta activa');
  END IF;

  -- validacion 3: hay cupo. FOR UPDATE bloquea la fila hasta el fin de la
  -- transaccion, para que dos sesiones simultaneas no se pasen del cupo.
  BEGIN
    SELECT cupo_disponible INTO v_cupo
      FROM pr_asignatura WHERE id_asignatura = p_id_asignatura FOR UPDATE;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      RAISE_APPLICATION_ERROR(-20014, 'Asignatura inexistente: ' || p_id_asignatura);
  END;

  IF v_cupo <= 0 THEN
    RAISE_APPLICATION_ERROR(-20015, 'Sin cupo en la asignatura ' || p_id_asignatura);
  END IF;

  -- accion
  INSERT INTO pr_matricula (id_estudiante, id_asignatura)
       VALUES (p_id_estudiante, p_id_asignatura)
    RETURNING id_matricula INTO p_id_matricula;

  UPDATE pr_asignatura
     SET cupo_disponible = cupo_disponible - 1
   WHERE id_asignatura = p_id_asignatura;

  -- NOTA DE DISENO: aqui NO hay COMMIT. Quien abrio la transaccion la cierra.
END pr_registrar_matricula;
/
SHOW ERRORS


--------------------------------------------------------------------------------
-- PASO 4 - EL CAMINO FELIZ
--------------------------------------------------------------------------------
-- QUE VAMOS A HACER : matricular a dos estudiantes en Bases de Datos 1.
-- QUE DEBE OBSERVAR : el cupo baja de 2 a 0 y cada matricula devuelve su id.
-- RESULTADO ESPERADO: dos identificadores y cupo_disponible = 0.
--------------------------------------------------------------------------------
DECLARE
  v_id pr_matricula.id_matricula%TYPE;
BEGIN
  pr_registrar_matricula(101, 55, v_id);
  DBMS_OUTPUT.PUT_LINE('Matricula creada: ' || v_id);

  pr_registrar_matricula(102, 55, v_id);
  DBMS_OUTPUT.PUT_LINE('Matricula creada: ' || v_id);
  COMMIT;                       -- la transaccion la cierra el llamador
END;
/

SELECT id_asignatura, titulo, cupo_disponible FROM pr_asignatura ORDER BY 1;
SELECT * FROM pr_matricula ORDER BY id_matricula;


--------------------------------------------------------------------------------
-- PASO 5 - [ERRORES PROVOCADOS] LAS TRES VALIDACIONES
--------------------------------------------------------------------------------
-- QUE VAMOS A HACER : provocar los tres errores de negocio, uno por uno.
-- QUE DEBE OBSERVAR : el numero del error (-20011 a -20015) y como el mensaje
--                     explica la causa sin exponer detalles tecnicos.
-- RESULTADO ESPERADO: tres bloques que fallan, cada uno con su mensaje.
--------------------------------------------------------------------------------
-- 5.a estudiante inactivo
DECLARE v_id NUMBER;
BEGIN
  pr_registrar_matricula(103, 56, v_id);     -- Carolina esta inactiva
END;
/

-- 5.b matricula duplicada
DECLARE v_id NUMBER;
BEGIN
  pr_registrar_matricula(101, 55, v_id);     -- ya la tiene activa
END;
/

-- 5.c sin cupo
DECLARE v_id NUMBER;
BEGIN
  pr_registrar_matricula(104, 57, v_id);     -- Sistemas Operativos tiene cupo 0
END;
/


--------------------------------------------------------------------------------
-- PASO 6 - REGISTRAR EL ERROR SIN PERDER LA TRAZA
--------------------------------------------------------------------------------
-- QUE VAMOS A HACER : envolver la invocacion en un bloque que registra el
--                     error y lo vuelve a levantar.
-- QUE DEBE OBSERVAR : SQLCODE, SQLERRM y FORMAT_ERROR_BACKTRACE. El RAISE
--                     final es lo que impide que el error se pierda.
-- RESULTADO ESPERADO: el bloque falla, y ademas queda una fila en el log.
--------------------------------------------------------------------------------
DECLARE
  v_id NUMBER;
BEGIN
  pr_registrar_matricula(103, 56, v_id);
EXCEPTION
  WHEN OTHERS THEN
    INSERT INTO pr_log_error (fecha, unidad, codigo, mensaje, traza)
         VALUES (SYSTIMESTAMP, 'pr_registrar_matricula', SQLCODE, SQLERRM,
                 DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
    COMMIT;      -- el log se conserva
    RAISE;       -- el error sigue su camino hacia el llamador
END;
/

SELECT unidad, codigo, mensaje FROM pr_log_error ORDER BY fecha;

-- PARA PENSAR: si borra la linea del RAISE, el bloque termina "bien" y quien
-- invoco creera que la matricula se registro. Es la causa mas comun de datos
-- inconsistentes sin ningun mensaje de error.


--------------------------------------------------------------------------------
-- PASO 7 - TRANSACCION AUTONOMA PARA LA AUDITORIA
--------------------------------------------------------------------------------
-- QUE VAMOS A HACER : un procedimiento de log independiente de la transaccion
--                     del llamador.
-- QUE DEBE OBSERVAR : despues del ROLLBACK, la matricula desaparece pero el
--                     registro de log SOBREVIVE. Esa es la diferencia.
-- RESULTADO ESPERADO: 0 matriculas nuevas y una fila mas en PR_LOG_ERROR.
--------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE pr_log (
  p_unidad  IN VARCHAR2,
  p_mensaje IN VARCHAR2)
IS
  PRAGMA AUTONOMOUS_TRANSACTION;
BEGIN
  INSERT INTO pr_log_error (fecha, unidad, codigo, mensaje)
       VALUES (SYSTIMESTAMP, p_unidad, 0, p_mensaje);
  COMMIT;                        -- obligatorio en una transaccion autonoma
END pr_log;
/
SHOW ERRORS

DECLARE
  v_id NUMBER;
BEGIN
  pr_registrar_matricula(104, 56, v_id);
  pr_log('practica', 'Intento de matricula id ' || v_id);
  ROLLBACK;                      -- deshace la matricula, no el log
END;
/

SELECT COUNT(*) AS matriculas_asignatura_56 FROM pr_matricula WHERE id_asignatura = 56;
SELECT unidad, mensaje FROM pr_log_error ORDER BY fecha;


--------------------------------------------------------------------------------
-- PASO 8 - CONCURRENCIA: EL BLOQUEO DEL FOR UPDATE  [REQUIERE DOS SESIONES]
--------------------------------------------------------------------------------
-- QUE VAMOS A HACER : ver como el bloqueo evita que dos sesiones se pasen del
--                     cupo al mismo tiempo.
-- COMO HACERLO:
--   1. En ESTA sesion ejecute el bloque A. NO confirme todavia.
--   2. Abra una SEGUNDA sesion con el mismo usuario y ejecute el bloque B.
--      Observe que la segunda sesion queda ESPERANDO, no falla.
--   3. Vuelva a esta sesion y ejecute COMMIT.
--   4. Mire la segunda sesion: recien ahi continua, y ya ve el cupo real.
-- QUE DEBE OBSERVAR : la espera no es un error, es el mecanismo que garantiza
--                     que el cupo nunca quede en negativo.
--------------------------------------------------------------------------------
-- BLOQUE A (esta sesion)
DECLARE v_id NUMBER;
BEGIN
  pr_registrar_matricula(101, 56, v_id);
  DBMS_OUTPUT.PUT_LINE('Sesion A creo la matricula ' || v_id || ' y no confirma');
END;
/

-- BLOQUE B (copielo en la SEGUNDA sesion)
-- DECLARE v_id NUMBER;
-- BEGIN
--   pr_registrar_matricula(102, 56, v_id);
--   DBMS_OUTPUT.PUT_LINE('Sesion B creo la matricula ' || v_id);
--   COMMIT;
-- END;
-- /

COMMIT;   -- ejecute esto cuando la segunda sesion ya este esperando


--------------------------------------------------------------------------------
-- PASO 9 - SAVEPOINT: DESHACER SOLO UNA PARTE
--------------------------------------------------------------------------------
-- QUE VAMOS A HACER : registrar dos matriculas y revertir solo la segunda.
-- QUE DEBE OBSERVAR : ROLLBACK TO deshace hasta la marca, no toda la
--                     transaccion. La primera matricula sobrevive.
-- RESULTADO ESPERADO: queda una matricula nueva, no dos.
--------------------------------------------------------------------------------
DECLARE
  v_id NUMBER;
BEGIN
  pr_registrar_matricula(102, 56, v_id);
  DBMS_OUTPUT.PUT_LINE('Primera matricula: ' || v_id);

  SAVEPOINT antes_de_la_segunda;

  BEGIN
    pr_registrar_matricula(103, 56, v_id);   -- falla: estudiante inactivo
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK TO antes_de_la_segunda;
      DBMS_OUTPUT.PUT_LINE('Segunda revertida: ' || SQLERRM);
  END;

  COMMIT;
END;
/

SELECT id_matricula, id_estudiante, id_asignatura, estado
  FROM pr_matricula ORDER BY id_matricula;


--------------------------------------------------------------------------------
-- PASO 10 - EL PAQUETE: AGRUPAR Y OCULTAR
--------------------------------------------------------------------------------
-- QUE VAMOS A HACER : mover la operacion a un paquete con una funcion privada
--                     y dos procedimientos publicos.
-- QUE DEBE OBSERVAR : HAY_CUPO no aparece en la especificacion, asi que no se
--                     puede invocar desde afuera. Es logica interna.
-- RESULTADO ESPERADO: paquete y cuerpo compilados; la anulacion devuelve el
--                     cupo a la asignatura.
--------------------------------------------------------------------------------
CREATE OR REPLACE PACKAGE pk_matricula IS
  -- Contrato publico del modulo de matriculas.
  PROCEDURE registrar (p_est IN NUMBER, p_asi IN NUMBER, p_id OUT NUMBER);
  PROCEDURE anular    (p_id  IN NUMBER);
END pk_matricula;
/
SHOW ERRORS

CREATE OR REPLACE PACKAGE BODY pk_matricula IS

  -- privada: solo existe dentro del cuerpo
  FUNCTION hay_cupo (p_asi IN NUMBER) RETURN BOOLEAN
  IS
    v_cupo NUMBER;
  BEGIN
    SELECT cupo_disponible INTO v_cupo
      FROM pr_asignatura WHERE id_asignatura = p_asi;
    RETURN v_cupo > 0;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN RETURN FALSE;
  END hay_cupo;

  PROCEDURE registrar (p_est IN NUMBER, p_asi IN NUMBER, p_id OUT NUMBER)
  IS
  BEGIN
    IF NOT hay_cupo(p_asi) THEN
      RAISE_APPLICATION_ERROR(-20015, 'Sin cupo en la asignatura ' || p_asi);
    END IF;
    pr_registrar_matricula(p_est, p_asi, p_id);
  END registrar;

  PROCEDURE anular (p_id IN NUMBER)
  IS
    v_asi pr_matricula.id_asignatura%TYPE;
  BEGIN
    UPDATE pr_matricula SET estado = 'ANULADA'
     WHERE id_matricula = p_id AND estado = 'ACTIVA'
    RETURNING id_asignatura INTO v_asi;

    IF SQL%ROWCOUNT = 0 THEN
      RAISE_APPLICATION_ERROR(-20016, 'No hay matricula activa con id ' || p_id);
    END IF;

    UPDATE pr_asignatura SET cupo_disponible = cupo_disponible + 1
     WHERE id_asignatura = v_asi;
  END anular;

END pk_matricula;
/
SHOW ERRORS

DECLARE
  v_id NUMBER;
BEGIN
  pk_matricula.registrar(p_est => 104, p_asi => 56, p_id => v_id);
  DBMS_OUTPUT.PUT_LINE('Registrada por el paquete: ' || v_id);
  pk_matricula.anular(v_id);
  DBMS_OUTPUT.PUT_LINE('Anulada y cupo devuelto');
  COMMIT;
END;
/

SELECT id_asignatura, cupo_disponible FROM pr_asignatura ORDER BY 1;


--------------------------------------------------------------------------------
-- PASO 11 - PROCESAMIENTO MASIVO CON BULK COLLECT Y FORALL
--------------------------------------------------------------------------------
-- QUE VAMOS A HACER : cambiar el estado de todas las matriculas activas por
--                     lotes de 500, en lugar de fila por fila.
-- QUE DEBE OBSERVAR : LIMIT acota cuanta memoria de sesion se consume.
--                     SAVE EXCEPTIONS permite terminar el lote y revisar los
--                     fallos despues, en vez de abortar en el primero.
-- RESULTADO ESPERADO: el conteo de filas procesadas coincide con las activas.
--------------------------------------------------------------------------------
DECLARE
  TYPE t_ids IS TABLE OF pr_matricula.id_matricula%TYPE;
  v_ids   t_ids;
  v_total PLS_INTEGER := 0;
  CURSOR c IS SELECT id_matricula FROM pr_matricula WHERE estado = 'ACTIVA';
  e_bulk EXCEPTION;
  PRAGMA EXCEPTION_INIT(e_bulk, -24381);
BEGIN
  OPEN c;
  LOOP
    FETCH c BULK COLLECT INTO v_ids LIMIT 500;
    EXIT WHEN v_ids.COUNT = 0;

    BEGIN
      FORALL k IN 1..v_ids.COUNT SAVE EXCEPTIONS
        UPDATE pr_matricula SET estado = 'CERRADA' WHERE id_matricula = v_ids(k);
    EXCEPTION
      WHEN e_bulk THEN
        FOR i IN 1..SQL%BULK_EXCEPTIONS.COUNT LOOP
          DBMS_OUTPUT.PUT_LINE('Fallo el elemento ' ||
            SQL%BULK_EXCEPTIONS(i).ERROR_INDEX || ': ' ||
            SQLERRM(-SQL%BULK_EXCEPTIONS(i).ERROR_CODE));
        END LOOP;
    END;

    v_total := v_total + v_ids.COUNT;
  END LOOP;
  CLOSE c;
  DBMS_OUTPUT.PUT_LINE('Filas procesadas: ' || v_total);
  ROLLBACK;     -- no queremos conservar el cambio de estado en la practica
END;
/


--------------------------------------------------------------------------------
-- PASO 12 - PRIVILEGIOS, DEPENDENCIAS Y ESTADO
--------------------------------------------------------------------------------
-- QUE VAMOS A HACER : ver de que depende cada unidad y que se invalida al
--                     alterar una tabla.
-- QUE DEBE OBSERVAR : tras el ALTER TABLE aparecen objetos INVALID. Oracle los
--                     recompila en la siguiente invocacion, pero un despliegue
--                     serio los recompila antes, no despues.
-- RESULTADO ESPERADO: primero INVALID, luego todo VALID.
--------------------------------------------------------------------------------
SELECT name, type, referenced_name, referenced_type
  FROM user_dependencies
 WHERE referenced_name IN ('PR_MATRICULA','PR_ASIGNATURA','PR_ESTUDIANTE')
 ORDER BY name;

ALTER TABLE pr_matricula ADD (observacion VARCHAR2(60));

SELECT object_name, object_type, status FROM user_objects WHERE status = 'INVALID';

ALTER PROCEDURE pr_registrar_matricula COMPILE;
ALTER PACKAGE pk_matricula COMPILE BODY;

SELECT object_name, object_type, status
  FROM user_objects
 WHERE object_type IN ('PROCEDURE','PACKAGE','PACKAGE BODY')
 ORDER BY object_type;

-- El permiso para que otro esquema use la operacion, sin darle acceso a las
-- tablas, seria:  GRANT EXECUTE ON pk_matricula TO nombre_de_usuario;


--------------------------------------------------------------------------------
-- EJERCICIOS PROPUESTOS
--------------------------------------------------------------------------------
-- EJERCICIO 1 - Traslado de asignatura
--   Escriba PR_TRASLADAR(p_id_matricula, p_nueva_asignatura) que anule la
--   matricula actual, devuelva el cupo y cree una nueva en la otra asignatura.
--   Si la nueva no tiene cupo, nada debe quedar hecho.
--   Pista: SAVEPOINT al inicio y ROLLBACK TO en el manejador.
--   Logrado si: tras un traslado fallido, los cupos quedan exactamente igual
--   que antes de invocar el procedimiento.
--
-- EJERCICIO 2 - Parametro OUT con diagnostico
--   Modifique PR_REGISTRAR_MATRICULA para que ademas devuelva p_resultado con
--   el texto 'OK' o la causa del rechazo, sin levantar excepcion.
--   Pista: decida y documente en la cabecera cual es el contrato: excepciones
--   o codigo de retorno. Mezclar los dos estilos confunde a quien invoca.
--   Logrado si: los cuatro casos de prueba devuelven texto y ninguno falla.
--
-- EJERCICIO 3 - Procedimiento de cierre de periodo
--   Escriba PR_CERRAR_PERIODO que pase a estado 'CERRADA' todas las matriculas
--   activas con fecha anterior a un parametro, e informe cuantas cambio.
--   Pista: SQL%ROWCOUNT despues del UPDATE, sin bucle.
--   Logrado si: el procedimiento no usa ningun LOOP.
--
-- EJERCICIO 4 - Auditoria autonoma
--   Haga que PR_REGISTRAR_MATRICULA invoque a PR_LOG en cada rechazo.
--   Verifique que el log sobrevive aunque el llamador haga ROLLBACK.
--   Pista: el log debe registrarse ANTES del RAISE_APPLICATION_ERROR.
--   Logrado si: tras un rechazo y un ROLLBACK, la fila del log sigue ahi.
--
-- EJERCICIO 5 - Analisis
--   El PASO 11 hace ROLLBACK al final. Reescribalo para que confirme por
--   lotes, y explique en un comentario que riesgo introduce ese cambio si el
--   proceso se interrumpe a la mitad.
--   Pista: piense en como sabria el proceso donde reanudar.
--   Logrado si: su explicacion menciona el estado intermedio y como detectarlo.
--------------------------------------------------------------------------------


--------------------------------------------------------------------------------
-- LIMPIEZA - ejecute SOLO cuando haya terminado
--------------------------------------------------------------------------------
-- DROP PACKAGE pk_matricula;
-- DROP PROCEDURE pr_registrar_matricula;
-- DROP PROCEDURE pr_demo_modos;
-- DROP PROCEDURE pr_resumen;
-- DROP PROCEDURE pr_log;
-- DROP TABLE pr_matricula PURGE;
-- DROP TABLE pr_asignatura PURGE;
-- DROP TABLE pr_estudiante PURGE;
-- DROP TABLE pr_log_error PURGE;
--------------------------------------------------------------------------------
