--------------------------------------------------------------------------------
-- UNIVERSIDAD EL BOSQUE - INGENIERIA DE SISTEMAS
-- Bases de Datos - Modulo 2 de 4: FUNCIONES ALMACENADAS
-- Oracle Database 19c
-- Docente: Ing. Christian Felipe Duarte
--------------------------------------------------------------------------------
-- COMO USAR ESTE ARCHIVO
--
--   1. Script independiente: crea sus propias tablas (prefijo FN_) y al final
--      las elimina. No necesita los otros modulos.
--   2. Avance PASO por PASO, no ejecute todo de una vez.
--   3. Cada paso trae QUE VAMOS A HACER / QUE DEBE OBSERVAR / RESULTADO ESPERADO.
--   4. Despues de CADA create function ejecute SHOW ERRORS: acostumbrese a leer
--      el error de compilacion antes de corregir.
--   5. Requisitos: usuario con CREATE TABLE, CREATE PROCEDURE y CREATE INDEX.
--------------------------------------------------------------------------------

SET SERVEROUTPUT ON SIZE UNLIMITED
SET LINESIZE 200
SET PAGESIZE 100

PROMPT ============================================================
PROMPT  MODULO 2 - FUNCIONES ALMACENADAS
PROMPT ============================================================


--------------------------------------------------------------------------------
-- PASO 0 - PREPARACION DEL ESQUEMA DE PRACTICA
--------------------------------------------------------------------------------
-- QUE VAMOS A HACER : crear las tablas FN_PROGRAMA, FN_ESTUDIANTE y FN_NOTA.
-- QUE DEBE OBSERVAR : el bloque inicial elimina los objetos previos para que
--                     el script se pueda repetir cuantas veces quiera.
-- RESULTADO ESPERADO: 3 programas, 8 estudiantes y 8 registros de notas.
--------------------------------------------------------------------------------
-- Se eliminan primero los programas almacenados y despues las tablas: el orden
-- importa, porque el indice basado en funcion desaparece junto con su tabla.
BEGIN
  FOR r IN (SELECT object_name, object_type FROM user_objects
             WHERE object_type IN ('FUNCTION','PACKAGE')
               AND object_name IN ('FN_NOTA_DEFINITIVA','FN_ESTADO','FN_PROMEDIO',
                                   'FN_LIMPIA_NOMBRE','FN_CUPO_PROGRAMA','FN_IVA',
                                   'PK_NOTAS')) LOOP
    EXECUTE IMMEDIATE 'DROP ' || r.object_type || ' ' || r.object_name;
  END LOOP;

  FOR r IN (SELECT table_name FROM user_tables
             WHERE table_name IN ('FN_NOTA','FN_ESTUDIANTE','FN_PROGRAMA')) LOOP
    EXECUTE IMMEDIATE 'DROP TABLE ' || r.table_name || ' CASCADE CONSTRAINTS';
  END LOOP;
END;
/

CREATE TABLE fn_programa (
  id_programa NUMBER(3) CONSTRAINT pk_fn_prog PRIMARY KEY,
  nombre      VARCHAR2(40) NOT NULL,
  cupo        NUMBER(4)
);

CREATE TABLE fn_estudiante (
  id_estudiante NUMBER(5) CONSTRAINT pk_fn_est PRIMARY KEY,
  nombre        VARCHAR2(40) NOT NULL,
  id_programa   NUMBER(3) CONSTRAINT fk_fn_est_prog REFERENCES fn_programa,
  promedio      NUMBER(3,2)
);

CREATE TABLE fn_nota (
  id_estudiante NUMBER(5) CONSTRAINT fk_fn_nota REFERENCES fn_estudiante,
  c1 NUMBER(3,2), c2 NUMBER(3,2), c3 NUMBER(3,2)
);

INSERT INTO fn_programa VALUES (1,'Ingenieria de Sistemas',120);
INSERT INTO fn_programa VALUES (2,'Ingenieria Industrial',90);
INSERT INTO fn_programa VALUES (3,'Ingenieria Electronica',60);

INSERT INTO fn_estudiante VALUES (1,'  ana maria torres ',1,4.10);
INSERT INTO fn_estudiante VALUES (2,'Bernardo Pineda',1,2.80);
INSERT INTO fn_estudiante VALUES (3,'CAROLINA REYES',2,3.00);
INSERT INTO fn_estudiante VALUES (4,'Daniel Ospina',2,4.90);
INSERT INTO fn_estudiante VALUES (5,'Elena Marquez',3,2.00);
INSERT INTO fn_estudiante VALUES (6,'Felipe Cardenas',1,3.70);
INSERT INTO fn_estudiante VALUES (7,'Gabriela Nino',3,3.85);
INSERT INTO fn_estudiante VALUES (8,'Hector Valbuena',2,3.10);

INSERT INTO fn_nota VALUES (1,4.2,3.8,4.5);
INSERT INTO fn_nota VALUES (2,2.5,3.1,2.9);
INSERT INTO fn_nota VALUES (3,3.0,3.0,3.0);
INSERT INTO fn_nota VALUES (4,4.8,4.9,5.0);
INSERT INTO fn_nota VALUES (5,1.8,2.2,2.0);
INSERT INTO fn_nota VALUES (6,3.5,NULL,3.9);
INSERT INTO fn_nota VALUES (7,4.0,4.0,3.5);
INSERT INTO fn_nota VALUES (8,2.9,3.4,3.1);
COMMIT;

PROMPT Esquema de practica listo.


--------------------------------------------------------------------------------
-- PASO 1 - SU PRIMERA FUNCION
--------------------------------------------------------------------------------
-- QUE VAMOS A HACER : crear una funcion escalar que calcula la definitiva.
-- QUE DEBE OBSERVAR : el tipo del RETURN en la firma va SIN precision; la
--                     variable interna si la lleva. La barra final cierra el
--                     bloque para la herramienta, no es parte del lenguaje.
-- RESULTADO ESPERADO: "Function FN_NOTA_DEFINITIVA compiled" y SHOW ERRORS
--                     sin errores.
--------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_nota_definitiva (
  p_c1 IN NUMBER,
  p_c2 IN NUMBER,
  p_c3 IN NUMBER DEFAULT 0)
RETURN NUMBER
IS
  c_peso_final CONSTANT NUMBER := 0.4;
  v_nota NUMBER(3,2);
BEGIN
  v_nota := ROUND(NVL(p_c1,0)*0.3 + NVL(p_c2,0)*0.3 + NVL(p_c3,0)*c_peso_final, 2);
  RETURN v_nota;
END fn_nota_definitiva;
/
SHOW ERRORS


--------------------------------------------------------------------------------
-- PASO 2 - LAS TRES FORMAS DE INVOCARLA
--------------------------------------------------------------------------------
-- QUE VAMOS A HACER : usar la funcion desde una consulta, desde un bloque y
--                     de forma interactiva contra DUAL.
-- QUE DEBE OBSERVAR : en la consulta la funcion se ejecuta UNA VEZ POR FILA.
-- RESULTADO ESPERADO: 8 filas con la definitiva calculada, y dos lineas mas.
--------------------------------------------------------------------------------
SELECT e.nombre, n.c1, n.c2, n.c3,
       fn_nota_definitiva(n.c1, n.c2, n.c3) AS definitiva
  FROM fn_estudiante e JOIN fn_nota n ON n.id_estudiante = e.id_estudiante
 ORDER BY e.id_estudiante;

SELECT fn_nota_definitiva(3.5, 4.0, 2.8) AS prueba_directa FROM dual;

DECLARE
  v_def NUMBER(3,2);
BEGIN
  v_def := fn_nota_definitiva(3.5, 4.0, 2.8);
  DBMS_OUTPUT.PUT_LINE('Desde PL/SQL: ' || v_def);
  -- notacion nombrada: obligatoria cuando se salta un parametro con DEFAULT
  v_def := fn_nota_definitiva(p_c1 => 3.5, p_c2 => 4.0);
  DBMS_OUTPUT.PUT_LINE('Con p_c3 por omision: ' || v_def);
END;
/


--------------------------------------------------------------------------------
-- PASO 3 - [ERROR PROVOCADO] LONGITUD EN EL TIPO DEL RETURN
--------------------------------------------------------------------------------
-- QUE VAMOS A HACER : escribir RETURN NUMBER(3,2) en la firma.
-- QUE DEBE OBSERVAR : el error aparece en COMPILACION. Ejecute SHOW ERRORS
--                     inmediatamente despues: ahi esta la linea exacta.
-- RESULTADO ESPERADO: "Warning: Function created with compilation errors" y
--                     un PLS-00103 en SHOW ERRORS.
--------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_estado (p_nota IN NUMBER)
RETURN VARCHAR2(12)
IS
BEGIN
  RETURN CASE WHEN p_nota >= 3 THEN 'APROBADO' ELSE 'REPROBADO' END;
END;
/
SHOW ERRORS

-- CORRECCION: el tipo del retorno se declara sin longitud.
CREATE OR REPLACE FUNCTION fn_estado (p_nota IN NUMBER)
RETURN VARCHAR2
IS
BEGIN
  RETURN CASE WHEN p_nota >= 3 THEN 'APROBADO' ELSE 'REPROBADO' END;
END;
/
SHOW ERRORS

SELECT nombre, promedio, fn_estado(promedio) AS estado
  FROM fn_estudiante ORDER BY id_estudiante;


--------------------------------------------------------------------------------
-- PASO 4 - [ERROR PROVOCADO] UNA RUTA SIN RETURN
--------------------------------------------------------------------------------
-- QUE VAMOS A HACER : dejar un IF sin ELSE, de modo que exista un camino que
--                     llega al END sin devolver nada.
-- QUE DEBE OBSERVAR : COMPILA sin errores. Falla solo cuando se invoca con un
--                     valor que toma la ruta sin RETURN.
-- RESULTADO ESPERADO: la primera consulta funciona; la segunda falla con
--                     ORA-06503: funcion sin valor de retorno.
--------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_promedio (p_id IN NUMBER)
RETURN NUMBER
IS
  v_prom NUMBER;
BEGIN
  SELECT promedio INTO v_prom FROM fn_estudiante WHERE id_estudiante = p_id;
  IF v_prom >= 3 THEN
    RETURN v_prom;
  END IF;
  -- si el promedio es menor que 3 no hay RETURN: ahi esta el defecto
END;
/
SHOW ERRORS

SELECT fn_promedio(1) AS promedio_ok FROM dual;    -- promedio 4.10, funciona
SELECT fn_promedio(2) AS promedio_falla FROM dual; -- promedio 2.80, ORA-06503

-- CORRECCION: toda ruta termina en RETURN y las excepciones se manejan.
CREATE OR REPLACE FUNCTION fn_promedio (p_id IN NUMBER)
RETURN NUMBER
IS
  v_prom NUMBER;
BEGIN
  SELECT promedio INTO v_prom FROM fn_estudiante WHERE id_estudiante = p_id;
  RETURN v_prom;
EXCEPTION
  WHEN NO_DATA_FOUND THEN
    RETURN NULL;                       -- decision explicita, no descuido
  WHEN TOO_MANY_ROWS THEN
    RAISE_APPLICATION_ERROR(-20001, 'Identificador duplicado: ' || p_id);
END;
/
SHOW ERRORS

SELECT fn_promedio(2)   AS ahora_si FROM dual;
SELECT fn_promedio(999) AS inexistente FROM dual;   -- devuelve NULL, no falla


--------------------------------------------------------------------------------
-- PASO 5 - DETERMINISTIC E INDICE BASADO EN FUNCION
--------------------------------------------------------------------------------
-- QUE VAMOS A HACER : normalizar nombres y crear un indice sobre el resultado
--                     de la funcion.
-- QUE DEBE OBSERVAR : sin la palabra DETERMINISTIC, la creacion del indice
--                     falla. Es un requisito del motor, no una sugerencia.
-- RESULTADO ESPERADO: indice creado y la busqueda normalizada encuentra a
--                     Ana Maria Torres pese a los espacios y minusculas.
--------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_limpia_nombre (p_nombre IN VARCHAR2)
RETURN VARCHAR2 DETERMINISTIC
IS
BEGIN
  RETURN UPPER(TRIM(p_nombre));
END;
/
SHOW ERRORS

CREATE INDEX ix_fn_est_nombre ON fn_estudiante (fn_limpia_nombre(nombre));

SELECT id_estudiante, nombre
  FROM fn_estudiante
 WHERE fn_limpia_nombre(nombre) = 'ANA MARIA TORRES';

-- PARA PENSAR: una funcion que lee SYSDATE o consulta una tabla que cambia NO
-- es deterministica. Declararla asi no produce error: produce resultados
-- incorrectos que nadie detecta hasta que es tarde.


--------------------------------------------------------------------------------
-- PASO 6 - RESULT_CACHE
--------------------------------------------------------------------------------
-- QUE VAMOS A HACER : cachear el resultado de una consulta de referencia.
-- QUE DEBE OBSERVAR : ejecute la consulta dos veces seguidas. La segunda no
--                     vuelve a leer la tabla. Luego actualice FN_PROGRAMA y
--                     compruebe que Oracle invalida la entrada por si solo.
-- RESULTADO ESPERADO: el cupo cambia despues del UPDATE sin recrear nada.
--------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_cupo_programa (p_id IN NUMBER)
RETURN NUMBER RESULT_CACHE
IS
  v_cupo NUMBER;
BEGIN
  SELECT cupo INTO v_cupo FROM fn_programa WHERE id_programa = p_id;
  RETURN v_cupo;
EXCEPTION
  WHEN NO_DATA_FOUND THEN RETURN NULL;
END;
/
SHOW ERRORS

SELECT fn_cupo_programa(1) AS primera_vez FROM dual;
SELECT fn_cupo_programa(1) AS desde_cache FROM dual;

UPDATE fn_programa SET cupo = 130 WHERE id_programa = 1;
COMMIT;

SELECT fn_cupo_programa(1) AS tras_el_update FROM dual;   -- debe mostrar 130


--------------------------------------------------------------------------------
-- PASO 7 - [ERROR PROVOCADO] DML DENTRO DE UNA FUNCION INVOCADA DESDE SQL
--------------------------------------------------------------------------------
-- QUE VAMOS A HACER : una funcion que escribe en una tabla y luego invocarla
--                     desde una consulta.
-- QUE DEBE OBSERVAR : compila bien y funciona desde PL/SQL. Solo falla cuando
--                     se invoca DENTRO de una sentencia SQL.
-- RESULTADO ESPERADO: ORA-14551: no se puede realizar una operacion DML
--                     dentro de una consulta.
--------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_iva (p_valor IN NUMBER)
RETURN NUMBER
IS
BEGIN
  UPDATE fn_programa SET cupo = cupo WHERE id_programa = 1;   -- DML indebido
  RETURN ROUND(p_valor * 0.19, 2);
END;
/
SHOW ERRORS

SELECT fn_iva(100000) FROM dual;     -- aqui aparece el ORA-14551

-- CORRECCION: una funcion calcula, no modifica. Se quita el DML.
CREATE OR REPLACE FUNCTION fn_iva (p_valor IN NUMBER)
RETURN NUMBER
IS
  PRAGMA UDF;          -- optimiza la invocacion desde sentencias SQL
BEGIN
  RETURN ROUND(p_valor * 0.19, 2);
END;
/
SHOW ERRORS

SELECT fn_iva(100000) AS iva FROM dual;


--------------------------------------------------------------------------------
-- PASO 8 - LA FUNCION DENTRO DE UN PAQUETE
--------------------------------------------------------------------------------
-- QUE VAMOS A HACER : mover la logica de notas a un paquete con dos unidades.
-- QUE DEBE OBSERVAR : la especificacion es el contrato publico; el cuerpo es
--                     la implementacion. Cambiar el cuerpo no invalida a quien
--                     invoca el paquete.
-- RESULTADO ESPERADO: paquete y cuerpo compilados, y la consulta funcionando.
--------------------------------------------------------------------------------
CREATE OR REPLACE PACKAGE pk_notas IS
  FUNCTION definitiva (p_c1 NUMBER, p_c2 NUMBER, p_c3 NUMBER DEFAULT 0)
    RETURN NUMBER;
  FUNCTION estado (p_nota NUMBER) RETURN VARCHAR2;
END pk_notas;
/
SHOW ERRORS

CREATE OR REPLACE PACKAGE BODY pk_notas IS

  FUNCTION definitiva (p_c1 NUMBER, p_c2 NUMBER, p_c3 NUMBER DEFAULT 0)
    RETURN NUMBER
  IS
  BEGIN
    RETURN ROUND(NVL(p_c1,0)*0.3 + NVL(p_c2,0)*0.3 + NVL(p_c3,0)*0.4, 2);
  END definitiva;

  FUNCTION estado (p_nota NUMBER) RETURN VARCHAR2
  IS
  BEGIN
    RETURN CASE
             WHEN p_nota IS NULL THEN 'SIN NOTA'
             WHEN p_nota >= 3    THEN 'APROBADO'
             ELSE                     'REPROBADO'
           END;
  END estado;

END pk_notas;
/
SHOW ERRORS

SELECT e.nombre,
       pk_notas.definitiva(n.c1, n.c2, n.c3) AS definitiva,
       pk_notas.estado(pk_notas.definitiva(n.c1, n.c2, n.c3)) AS estado
  FROM fn_estudiante e JOIN fn_nota n ON n.id_estudiante = e.id_estudiante
 ORDER BY e.id_estudiante;


--------------------------------------------------------------------------------
-- PASO 9 - DIAGNOSTICO CON EL DICCIONARIO DE DATOS
--------------------------------------------------------------------------------
-- QUE VAMOS A HACER : consultar estado, errores y fuente de sus objetos.
-- QUE DEBE OBSERVAR : los nombres se guardan en MAYUSCULAS. Si busca en
--                     minusculas no encuentra nada y parece que el objeto no
--                     existe.
-- RESULTADO ESPERADO: todos los objetos en estado VALID.
--------------------------------------------------------------------------------
SELECT object_name, object_type, status, last_ddl_time
  FROM user_objects
 WHERE object_type IN ('FUNCTION','PACKAGE','PACKAGE BODY')
 ORDER BY object_type, object_name;

SELECT name, type, line, position, text
  FROM user_errors
 ORDER BY name, sequence;

SELECT line, text FROM user_source
 WHERE name = 'FN_NOTA_DEFINITIVA' ORDER BY line;

-- dependencias: que se invalida si alguien altera FN_ESTUDIANTE
SELECT name, type FROM user_dependencies
 WHERE referenced_name = 'FN_ESTUDIANTE';


--------------------------------------------------------------------------------
-- PASO 10 - INVALIDACION Y RECOMPILACION
--------------------------------------------------------------------------------
-- QUE VAMOS A HACER : alterar la tabla y ver que ocurre con las funciones
--                     que dependen de ella.
-- QUE DEBE OBSERVAR : los objetos quedan INVALID. Oracle los recompila solo
--                     en la siguiente invocacion; aqui lo hacemos explicito.
-- RESULTADO ESPERADO: primero aparecen objetos INVALID, luego todos VALID.
--------------------------------------------------------------------------------
ALTER TABLE fn_estudiante ADD (observacion VARCHAR2(60));

SELECT object_name, status FROM user_objects WHERE status = 'INVALID';

ALTER FUNCTION fn_promedio COMPILE;
ALTER PACKAGE pk_notas COMPILE BODY;

SELECT object_name, status FROM user_objects
 WHERE object_type IN ('FUNCTION','PACKAGE','PACKAGE BODY');


--------------------------------------------------------------------------------
-- EJERCICIOS PROPUESTOS
--------------------------------------------------------------------------------
-- EJERCICIO 1 - Funcion de formato
--   Escriba FN_NOMBRE_CORTO que reciba el nombre completo y devuelva el primer
--   nombre y la inicial del primer apellido, por ejemplo "Ana M.".
--   Pista: INSTR y SUBSTR sobre el resultado de TRIM.
--   Logrado si: funciona con los 8 estudiantes, incluido el que tiene espacios.
--
-- EJERCICIO 2 - Funcion con consulta interna
--   Escriba FN_CANT_ESTUDIANTES que reciba un id de programa y devuelva
--   cuantos estudiantes tiene. Devuelva 0, no NULL, cuando el programa no
--   tenga estudiantes.
--   Pista: COUNT no levanta NO_DATA_FOUND; un SELECT ... INTO sobre una tabla
--   vacia con COUNT devuelve 0.
--   Logrado si: la consulta sobre los 3 programas suma 8.
--
-- EJERCICIO 3 - Funcion invocable desde SQL
--   Escriba FN_CLASIFICA_PROMEDIO que devuelva 'EXCELENTE' (4.5 o mas),
--   'BUENO' (3.5 a 4.49), 'ACEPTABLE' (3.0 a 3.49) o 'INSUFICIENTE'.
--   Use la funcion en un SELECT con GROUP BY para contar estudiantes por
--   clasificacion.
--   Pista: solo parametros IN y tipos SQL; nada de BOOLEAN.
--   Logrado si: la suma de los grupos es 8.
--
-- EJERCICIO 4 - Diagnostico
--   Cree a proposito una funcion que referencie una columna inexistente.
--   Sin mirar el editor, ubique el error consultando USER_ERRORS y corrijalo.
--   Pista: filtre por NAME y ordene por SEQUENCE.
--   Logrado si: puede indicar linea y columna del error antes de corregirlo.
--
-- EJERCICIO 5 - Empaquetar
--   Mueva FN_LIMPIA_NOMBRE y su ejercicio 1 al paquete PK_NOTAS. Agregue en la
--   especificacion un comentario que documente el contrato de cada funcion.
--   Pista: recuerde recompilar el cuerpo con ALTER PACKAGE ... COMPILE BODY.
--   Logrado si: las invocaciones anteriores siguen funcionando con el prefijo
--   del paquete y el diccionario reporta todo VALID.
--------------------------------------------------------------------------------


--------------------------------------------------------------------------------
-- LIMPIEZA - ejecute SOLO cuando haya terminado
--------------------------------------------------------------------------------
-- DROP PACKAGE pk_notas;
-- DROP FUNCTION fn_nota_definitiva;
-- DROP FUNCTION fn_estado;
-- DROP FUNCTION fn_promedio;
-- DROP FUNCTION fn_limpia_nombre;
-- DROP FUNCTION fn_cupo_programa;
-- DROP FUNCTION fn_iva;
-- DROP TABLE fn_nota PURGE;
-- DROP TABLE fn_estudiante PURGE;
-- DROP TABLE fn_programa PURGE;
--------------------------------------------------------------------------------
