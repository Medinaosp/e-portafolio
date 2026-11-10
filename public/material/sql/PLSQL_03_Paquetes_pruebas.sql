/* =============================================================================
   PL/SQL 03 - PAQUETES
   Script de pruebas para estudiantes
   Bases de Datos - Ingenieria de Sistemas - Universidad El Bosque
   Ing. Christian Felipe Duarte
   Oracle Database 19c
   -----------------------------------------------------------------------------
   COMO USARLO
   1. Ejecute el script COMPLETO como script (F5 en SQL Developer, o @archivo
      en SQL*Plus / SQLcl) en su propio esquema.
   2. Todas las tablas y secuencias usan el prefijo LAB_ para no tocar las
      tablas del taller. El script elimina y recrea SOLO esos objetos.
   3. Lea la salida de DBMS_OUTPUT: cada prueba imprime [OK] o [FALLA].
      Al final aparece un resumen con el total de pruebas.
   4. Si alguna prueba falla, no avance: lea el mensaje, revise el codigo
      del paquete y vuelva a ejecutar.

   CONTENIDO
   Parte 0  Limpieza de ejecuciones anteriores
   Parte 1  Esquema y datos de prueba
   Parte 2  pkg_assert: un paquete pequeno para verificar resultados
   Parte 3  pkg_inventario: especificacion y cuerpo
   Parte 4  Verificacion en el diccionario de datos
   Parte 5  Pruebas funcionales (P01 a P14)
   Parte 6  Transacciones: ROLLBACK y bitacora autonoma (P15 a P16)
   Parte 7  Dependencias: recompilar el cuerpo no invalida a nadie (P17)
   Parte 8  Resumen
   Parte 9  Retos para el estudiante
   ============================================================================= */

SET SERVEROUTPUT ON SIZE UNLIMITED
SET LINESIZE 200
SET PAGESIZE 100
SET FEEDBACK OFF

PROMPT
PROMPT ===== Parte 0. Limpieza de ejecuciones anteriores =====

DECLARE
    e_tabla_no_existe   EXCEPTION;
    e_secuencia_no_existe EXCEPTION;
    e_objeto_no_existe  EXCEPTION;
    PRAGMA EXCEPTION_INIT(e_tabla_no_existe,     -942);
    PRAGMA EXCEPTION_INIT(e_secuencia_no_existe, -2289);
    PRAGMA EXCEPTION_INIT(e_objeto_no_existe,    -4043);

    PROCEDURE eliminar(p_ddl VARCHAR2) IS
    BEGIN
        EXECUTE IMMEDIATE p_ddl;
    EXCEPTION
        -- Solo se ignora "el objeto no existe": cualquier otro error se propaga.
        WHEN e_tabla_no_existe OR e_secuencia_no_existe OR e_objeto_no_existe THEN
            NULL;
    END eliminar;
BEGIN
    eliminar('DROP PROCEDURE lab_sp_reporte_stock');
    eliminar('DROP PACKAGE pkg_inventario');
    eliminar('DROP PACKAGE pkg_assert');
    eliminar('DROP TABLE lab_movimiento   CASCADE CONSTRAINTS PURGE');
    eliminar('DROP TABLE lab_inventario   CASCADE CONSTRAINTS PURGE');
    eliminar('DROP TABLE lab_producto     CASCADE CONSTRAINTS PURGE');
    eliminar('DROP TABLE lab_categoria    CASCADE CONSTRAINTS PURGE');
    eliminar('DROP TABLE lab_bodega       CASCADE CONSTRAINTS PURGE');
    eliminar('DROP TABLE lab_log_errores  CASCADE CONSTRAINTS PURGE');
    eliminar('DROP SEQUENCE seq_lab_movimiento');
    eliminar('DROP SEQUENCE seq_lab_log');
    DBMS_OUTPUT.PUT_LINE('Limpieza terminada.');
END;
/

PROMPT
PROMPT ===== Parte 1. Esquema y datos de prueba =====

CREATE TABLE lab_categoria (
    id_categoria  NUMBER        CONSTRAINT pk_lab_categoria PRIMARY KEY,
    nombre        VARCHAR2(60)  NOT NULL
);

CREATE TABLE lab_producto (
    id_producto   NUMBER        CONSTRAINT pk_lab_producto PRIMARY KEY,
    codigo        VARCHAR2(20)  NOT NULL CONSTRAINT uq_lab_producto_codigo UNIQUE,
    nombre        VARCHAR2(80)  NOT NULL,
    id_categoria  NUMBER        NOT NULL
                  CONSTRAINT fk_lab_producto_cat REFERENCES lab_categoria,
    precio        NUMBER(12,2)  NOT NULL CONSTRAINT ck_lab_producto_precio CHECK (precio > 0)
);

CREATE TABLE lab_bodega (
    id_bodega     NUMBER        CONSTRAINT pk_lab_bodega PRIMARY KEY,
    nombre        VARCHAR2(60)  NOT NULL
);

CREATE TABLE lab_inventario (
    id_producto   NUMBER  NOT NULL CONSTRAINT fk_lab_inv_producto REFERENCES lab_producto,
    id_bodega     NUMBER  NOT NULL CONSTRAINT fk_lab_inv_bodega   REFERENCES lab_bodega,
    cantidad      NUMBER  NOT NULL CONSTRAINT ck_lab_inv_cantidad CHECK (cantidad >= 0),
    CONSTRAINT pk_lab_inventario PRIMARY KEY (id_producto, id_bodega)
);

CREATE TABLE lab_movimiento (
    id_movimiento NUMBER       CONSTRAINT pk_lab_movimiento PRIMARY KEY,
    id_producto   NUMBER       NOT NULL,
    id_bodega     NUMBER       NOT NULL,
    tipo          VARCHAR2(10) NOT NULL CONSTRAINT ck_lab_mov_tipo CHECK (tipo IN ('ENTRADA', 'SALIDA')),
    cantidad      NUMBER       NOT NULL,
    fecha         DATE         DEFAULT SYSDATE NOT NULL
);

CREATE TABLE lab_log_errores (
    id_log        NUMBER          CONSTRAINT pk_lab_log PRIMARY KEY,
    origen        VARCHAR2(100)   NOT NULL,
    codigo_error  NUMBER,
    mensaje       VARCHAR2(4000),
    traza         VARCHAR2(4000),
    fecha         DATE            DEFAULT SYSDATE NOT NULL
);

CREATE SEQUENCE seq_lab_movimiento;
CREATE SEQUENCE seq_lab_log;

INSERT INTO lab_categoria VALUES (1, 'Herramientas');
INSERT INTO lab_categoria VALUES (2, 'Electricos');

INSERT INTO lab_producto VALUES (1, 'HR-0001', 'Martillo de una',     1, 35000);
INSERT INTO lab_producto VALUES (2, 'HR-0002', 'Destornillador pala', 1, 12000);
INSERT INTO lab_producto VALUES (3, 'EL-0001', 'Extension 5 metros',  2, 48000);

INSERT INTO lab_bodega VALUES (1, 'Bodega Norte');
INSERT INTO lab_bodega VALUES (2, 'Bodega Sur');

-- Stock inicial (las pruebas dependen de estos valores)
--   producto 1: bodega 1 = 100, bodega 2 = 40   -> total 140
--   producto 2: bodega 1 = 10
--   producto 3: bodega 1 = 5
INSERT INTO lab_inventario VALUES (1, 1, 100);
INSERT INTO lab_inventario VALUES (1, 2, 40);
INSERT INTO lab_inventario VALUES (2, 1, 10);
INSERT INTO lab_inventario VALUES (3, 1, 5);

COMMIT;

PROMPT Esquema LAB_ creado y datos cargados.

PROMPT
PROMPT ===== Parte 2. pkg_assert =====
-- Paquete de apoyo para las pruebas. Observe que tambien es un ejemplo de:
--   * sobrecarga: igual() existe para NUMBER y para VARCHAR2
--   * estado de sesion: los contadores sobreviven entre bloques anonimos

CREATE OR REPLACE PACKAGE pkg_assert IS
    PROCEDURE iniciar(p_titulo VARCHAR2);
    PROCEDURE igual(p_caso VARCHAR2, p_esperado NUMBER,   p_obtenido NUMBER);
    PROCEDURE igual(p_caso VARCHAR2, p_esperado VARCHAR2, p_obtenido VARCHAR2);
    PROCEDURE verdadero(p_caso VARCHAR2, p_condicion BOOLEAN);
    PROCEDURE resumen;
END pkg_assert;
/
SHOW ERRORS PACKAGE pkg_assert

CREATE OR REPLACE PACKAGE BODY pkg_assert IS
    -- Estado privado: vive mientras dure la sesion
    g_ok      PLS_INTEGER := 0;
    g_fallas  PLS_INTEGER := 0;

    PROCEDURE reportar(p_caso VARCHAR2, p_exito BOOLEAN, p_detalle VARCHAR2 DEFAULT NULL) IS
    BEGIN
        IF p_exito THEN
            g_ok := g_ok + 1;
            DBMS_OUTPUT.PUT_LINE('[OK]    ' || p_caso);
        ELSE
            g_fallas := g_fallas + 1;
            DBMS_OUTPUT.PUT_LINE('[FALLA] ' || p_caso || CASE WHEN p_detalle IS NOT NULL THEN ' -> ' || p_detalle END);
        END IF;
    END reportar;

    PROCEDURE iniciar(p_titulo VARCHAR2) IS
    BEGIN
        g_ok     := 0;
        g_fallas := 0;
        DBMS_OUTPUT.PUT_LINE('=== ' || p_titulo || ' ===');
    END iniciar;

    PROCEDURE igual(p_caso VARCHAR2, p_esperado NUMBER, p_obtenido NUMBER) IS
    BEGIN
        reportar(p_caso,
                 (p_esperado = p_obtenido) OR (p_esperado IS NULL AND p_obtenido IS NULL),
                 'esperado ' || NVL(TO_CHAR(p_esperado), 'NULL') ||
                 ', obtenido ' || NVL(TO_CHAR(p_obtenido), 'NULL'));
    END igual;

    PROCEDURE igual(p_caso VARCHAR2, p_esperado VARCHAR2, p_obtenido VARCHAR2) IS
    BEGIN
        reportar(p_caso,
                 (p_esperado = p_obtenido) OR (p_esperado IS NULL AND p_obtenido IS NULL),
                 'esperado "' || p_esperado || '", obtenido "' || p_obtenido || '"');
    END igual;

    PROCEDURE verdadero(p_caso VARCHAR2, p_condicion BOOLEAN) IS
    BEGIN
        -- NVL sobre BOOLEAN: una condicion NULL cuenta como falla
        reportar(p_caso, NVL(p_condicion, FALSE), 'la condicion no se cumplio');
    END verdadero;

    PROCEDURE resumen IS
    BEGIN
        DBMS_OUTPUT.PUT_LINE('------------------------------------------------');
        DBMS_OUTPUT.PUT_LINE('Pruebas exitosas: ' || g_ok);
        DBMS_OUTPUT.PUT_LINE('Pruebas fallidas: ' || g_fallas);
        DBMS_OUTPUT.PUT_LINE(CASE WHEN g_fallas = 0
                                  THEN 'RESULTADO: todas las pruebas pasaron.'
                                  ELSE 'RESULTADO: revise las pruebas marcadas con [FALLA].' END);
    END resumen;
END pkg_assert;
/
SHOW ERRORS PACKAGE BODY pkg_assert

PROMPT
PROMPT ===== Parte 3. pkg_inventario =====

-- -----------------------------------------------------------------------------
-- ESPECIFICACION: el contrato publico. Todo lo que esta aqui es visible
-- para cualquier usuario con privilegio EXECUTE sobre el paquete.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE PACKAGE pkg_inventario IS

    -- Constantes publicas
    c_version          CONSTANT VARCHAR2(10) := '1.0';
    c_max_movimiento   CONSTANT PLS_INTEGER  := 500;

    -- Catalogo de errores del modulo (rango -20101 a -20199)
    e_stock_insuficiente  EXCEPTION;
    e_cantidad_invalida   EXCEPTION;
    e_producto_no_existe  EXCEPTION;
    PRAGMA EXCEPTION_INIT(e_stock_insuficiente, -20101);
    PRAGMA EXCEPTION_INIT(e_cantidad_invalida,  -20102);
    PRAGMA EXCEPTION_INIT(e_producto_no_existe, -20103);

    -- Consulta de stock (sobrecargada)
    FUNCTION fn_stock_disponible(p_id_producto NUMBER, p_id_bodega NUMBER) RETURN NUMBER;
    FUNCTION fn_stock_disponible(p_id_producto NUMBER) RETURN NUMBER;

    -- Operaciones
    PROCEDURE sp_ingresar (p_id_producto NUMBER, p_id_bodega NUMBER, p_cantidad NUMBER);
    PROCEDURE sp_despachar(p_id_producto NUMBER, p_id_bodega NUMBER, p_cantidad NUMBER);

    -- Estado de la sesion
    FUNCTION fn_operaciones_sesion RETURN PLS_INTEGER;
    FUNCTION fn_fecha_carga        RETURN DATE;

END pkg_inventario;
/
SHOW ERRORS PACKAGE pkg_inventario

-- -----------------------------------------------------------------------------
-- CUERPO: la implementacion. Lo que se declara aqui y no aparece en la
-- especificacion es PRIVADO.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE PACKAGE BODY pkg_inventario IS

    -- Estado privado de la sesion
    g_operaciones  PLS_INTEGER := 0;
    g_fecha_carga  DATE;

    -- ===== Subprogramas privados ============================================

    -- Bitacora en transaccion autonoma: sobrevive al ROLLBACK del llamador.
    PROCEDURE registrar_error(p_origen  VARCHAR2,
                              p_codigo  NUMBER,
                              p_mensaje VARCHAR2,
                              p_traza   VARCHAR2) IS
        PRAGMA AUTONOMOUS_TRANSACTION;
    BEGIN
        INSERT INTO lab_log_errores (id_log, origen, codigo_error, mensaje, traza)
        VALUES (seq_lab_log.NEXTVAL, p_origen, p_codigo,
                SUBSTR(p_mensaje, 1, 4000), SUBSTR(p_traza, 1, 4000));
        COMMIT;
    END registrar_error;

    PROCEDURE validar_cantidad(p_cantidad NUMBER) IS
    BEGIN
        IF p_cantidad IS NULL OR p_cantidad <= 0 OR p_cantidad > c_max_movimiento THEN
            RAISE_APPLICATION_ERROR(-20102,
                'Cantidad invalida: ' || NVL(TO_CHAR(p_cantidad), 'NULL') ||
                '. Debe estar entre 1 y ' || c_max_movimiento || '.');
        END IF;
    END validar_cantidad;

    PROCEDURE validar_producto(p_id_producto NUMBER) IS
        v_existe PLS_INTEGER;
    BEGIN
        SELECT COUNT(*)
          INTO v_existe
          FROM lab_producto
         WHERE id_producto = p_id_producto;

        IF v_existe = 0 THEN
            RAISE_APPLICATION_ERROR(-20103,
                'El producto ' || NVL(TO_CHAR(p_id_producto), 'NULL') || ' no existe.');
        END IF;
    END validar_producto;

    PROCEDURE registrar_movimiento(p_id_producto NUMBER,
                                   p_id_bodega   NUMBER,
                                   p_tipo        VARCHAR2,
                                   p_cantidad    NUMBER) IS
    BEGIN
        INSERT INTO lab_movimiento (id_movimiento, id_producto, id_bodega, tipo, cantidad)
        VALUES (seq_lab_movimiento.NEXTVAL, p_id_producto, p_id_bodega, p_tipo, p_cantidad);

        g_operaciones := g_operaciones + 1;
    END registrar_movimiento;

    -- ===== Subprogramas publicos ============================================

    FUNCTION fn_stock_disponible(p_id_producto NUMBER, p_id_bodega NUMBER) RETURN NUMBER IS
        v_cantidad NUMBER;
    BEGIN
        SELECT cantidad
          INTO v_cantidad
          FROM lab_inventario
         WHERE id_producto = p_id_producto
           AND id_bodega   = p_id_bodega;

        RETURN v_cantidad;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RETURN 0;   -- caso previsto: el producto no tiene registro en esa bodega
    END fn_stock_disponible;

    FUNCTION fn_stock_disponible(p_id_producto NUMBER) RETURN NUMBER IS
        v_total NUMBER;
    BEGIN
        SELECT NVL(SUM(cantidad), 0)
          INTO v_total
          FROM lab_inventario
         WHERE id_producto = p_id_producto;

        RETURN v_total;
    END fn_stock_disponible;

    PROCEDURE sp_ingresar(p_id_producto NUMBER, p_id_bodega NUMBER, p_cantidad NUMBER) IS
    BEGIN
        validar_producto(p_id_producto);
        validar_cantidad(p_cantidad);

        MERGE INTO lab_inventario i
        USING (SELECT p_id_producto AS id_producto, p_id_bodega AS id_bodega FROM dual) s
           ON (i.id_producto = s.id_producto AND i.id_bodega = s.id_bodega)
         WHEN MATCHED THEN
              UPDATE SET i.cantidad = i.cantidad + p_cantidad
         WHEN NOT MATCHED THEN
              INSERT (id_producto, id_bodega, cantidad)
              VALUES (s.id_producto, s.id_bodega, p_cantidad);

        registrar_movimiento(p_id_producto, p_id_bodega, 'ENTRADA', p_cantidad);
    EXCEPTION
        WHEN e_cantidad_invalida OR e_producto_no_existe THEN
            RAISE;   -- regla de negocio: sube tal cual, no es una falla tecnica
        WHEN OTHERS THEN
            registrar_error('pkg_inventario.sp_ingresar', SQLCODE, SQLERRM,
                            DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
            RAISE;
    END sp_ingresar;

    PROCEDURE sp_despachar(p_id_producto NUMBER, p_id_bodega NUMBER, p_cantidad NUMBER) IS
    BEGIN
        validar_producto(p_id_producto);
        validar_cantidad(p_cantidad);

        -- La condicion cantidad >= p_cantidad evita que dos sesiones
        -- despachen el mismo stock: la fila se bloquea al actualizar.
        UPDATE lab_inventario
           SET cantidad = cantidad - p_cantidad
         WHERE id_producto = p_id_producto
           AND id_bodega   = p_id_bodega
           AND cantidad   >= p_cantidad;

        IF SQL%ROWCOUNT = 0 THEN
            RAISE_APPLICATION_ERROR(-20101,
                'Stock insuficiente del producto ' || p_id_producto ||
                ' en la bodega ' || p_id_bodega ||
                ': disponible ' || fn_stock_disponible(p_id_producto, p_id_bodega) ||
                ', solicitado ' || p_cantidad || '.');
        END IF;

        registrar_movimiento(p_id_producto, p_id_bodega, 'SALIDA', p_cantidad);
    EXCEPTION
        WHEN e_stock_insuficiente OR e_cantidad_invalida OR e_producto_no_existe THEN
            RAISE;
        WHEN OTHERS THEN
            registrar_error('pkg_inventario.sp_despachar', SQLCODE, SQLERRM,
                            DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
            RAISE;
    END sp_despachar;

    FUNCTION fn_operaciones_sesion RETURN PLS_INTEGER IS
    BEGIN
        RETURN g_operaciones;
    END fn_operaciones_sesion;

    FUNCTION fn_fecha_carga RETURN DATE IS
    BEGIN
        RETURN g_fecha_carga;
    END fn_fecha_carga;

-- ===== Seccion de inicializacion ===========================================
-- Se ejecuta UNA sola vez por sesion: la primera vez que se referencia el paquete.
BEGIN
    g_fecha_carga := SYSDATE;
    DBMS_OUTPUT.PUT_LINE('[pkg_inventario] Paquete inicializado en esta sesion.');
END pkg_inventario;
/
SHOW ERRORS PACKAGE BODY pkg_inventario

PROMPT
PROMPT ===== Parte 4. Verificacion en el diccionario de datos =====

COLUMN object_name    FORMAT A20
COLUMN object_type    FORMAT A14
COLUMN status         FORMAT A8
COLUMN procedure_name FORMAT A24
COLUMN overload       FORMAT A8
COLUMN argument_name  FORMAT A16
COLUMN data_type      FORMAT A10

PROMPT -- Estado de los objetos (ambos deben estar VALID)
SELECT object_name, object_type, status
  FROM user_objects
 WHERE object_name IN ('PKG_INVENTARIO', 'PKG_ASSERT')
 ORDER BY object_name, object_type;

PROMPT -- Errores de compilacion (no debe devolver filas)
SELECT name, type, line, position, text
  FROM user_errors
 WHERE name IN ('PKG_INVENTARIO', 'PKG_ASSERT')
 ORDER BY name, type, sequence;

PROMPT -- Subprogramas PUBLICOS (los privados no aparecen)
SELECT procedure_name, overload
  FROM user_procedures
 WHERE object_name = 'PKG_INVENTARIO'
   AND procedure_name IS NOT NULL
 ORDER BY procedure_name, overload;

PROMPT -- Argumentos de la funcion sobrecargada
SELECT overload, position, argument_name, data_type
  FROM user_arguments
 WHERE package_name = 'PKG_INVENTARIO'
   AND object_name  = 'FN_STOCK_DISPONIBLE'
 ORDER BY overload, position;

BEGIN
    pkg_assert.iniciar('PL/SQL 03 - Pruebas de paquetes');
END;
/

DECLARE
    v_estado VARCHAR2(10);
    v_cuenta PLS_INTEGER;
BEGIN
    SELECT status INTO v_estado FROM user_objects
     WHERE object_name = 'PKG_INVENTARIO' AND object_type = 'PACKAGE';
    pkg_assert.igual('P00a La especificacion compila (VALID)', 'VALID', v_estado);

    SELECT status INTO v_estado FROM user_objects
     WHERE object_name = 'PKG_INVENTARIO' AND object_type = 'PACKAGE BODY';
    pkg_assert.igual('P00b El cuerpo compila (VALID)', 'VALID', v_estado);

    SELECT COUNT(*) INTO v_cuenta FROM user_procedures
     WHERE object_name = 'PKG_INVENTARIO' AND procedure_name = 'VALIDAR_CANTIDAD';
    pkg_assert.igual('P00c Un subprograma privado no figura en USER_PROCEDURES', 0, v_cuenta);
END;
/

PROMPT
PROMPT ===== Parte 5. Pruebas funcionales =====
PROMPT (Observe el mensaje de inicializacion: aparece una sola vez por sesion)

-- P01 a P05: consultas, constantes y sobrecarga
DECLARE
    v_fecha DATE;
BEGIN
    pkg_assert.igual('P01 Constante publica c_version', '1.0', pkg_inventario.c_version);

    pkg_assert.igual('P02 Stock del producto 1 en la bodega 1', 100,
                     pkg_inventario.fn_stock_disponible(1, 1));

    pkg_assert.igual('P03 Sobrecarga: stock total del producto 1', 140,
                     pkg_inventario.fn_stock_disponible(1));

    pkg_assert.igual('P04 Producto sin registro en la bodega devuelve 0', 0,
                     pkg_inventario.fn_stock_disponible(3, 2));

    v_fecha := pkg_inventario.fn_fecha_carga;
    pkg_assert.verdadero('P05 La inicializacion asigno la fecha de carga', v_fecha IS NOT NULL);
END;
/

-- P06 a P07: operaciones exitosas y estado de sesion
DECLARE
    v_ops_antes PLS_INTEGER;
BEGIN
    v_ops_antes := pkg_inventario.fn_operaciones_sesion;

    pkg_inventario.sp_ingresar(3, 2, 25);
    pkg_assert.igual('P06a Ingreso crea el registro en una bodega nueva', 25,
                     pkg_inventario.fn_stock_disponible(3, 2));
    pkg_assert.igual('P06b El total del producto 3 queda en 30', 30,
                     pkg_inventario.fn_stock_disponible(3));

    pkg_inventario.sp_despachar(1, 1, 30);
    pkg_assert.igual('P07a Despacho descuenta el stock (100 - 30)', 70,
                     pkg_inventario.fn_stock_disponible(1, 1));

    pkg_assert.igual('P07b El estado de sesion conto las 2 operaciones', v_ops_antes + 2,
                     pkg_inventario.fn_operaciones_sesion);
END;
/

-- P08: el estado de paquete persiste ENTRE bloques de la misma sesion
DECLARE
    v_ops PLS_INTEGER;
BEGIN
    v_ops := pkg_inventario.fn_operaciones_sesion;
    pkg_assert.verdadero('P08 El contador sigue vivo en un bloque nuevo (>= 2)', v_ops >= 2);
END;
/

-- P09: regla de negocio, stock insuficiente
BEGIN
    BEGIN
        pkg_inventario.sp_despachar(2, 1, 50);   -- solo hay 10
        pkg_assert.verdadero('P09a El despacho sin stock debia fallar', FALSE);
    EXCEPTION
        WHEN pkg_inventario.e_stock_insuficiente THEN
            pkg_assert.igual('P09a Se atrapa e_stock_insuficiente (-20101)', -20101, SQLCODE);
            DBMS_OUTPUT.PUT_LINE('        mensaje: ' || SQLERRM);
    END;

    pkg_assert.igual('P09b El stock no cambio tras el fallo', 10,
                     pkg_inventario.fn_stock_disponible(2, 1));
END;
/

-- P10: regla de negocio, cantidad invalida (cero, NULL y por encima del maximo)
DECLARE
    PROCEDURE probar(p_caso VARCHAR2, p_cantidad NUMBER) IS
    BEGIN
        pkg_inventario.sp_despachar(1, 1, p_cantidad);
        pkg_assert.verdadero(p_caso || ' debia fallar', FALSE);
    EXCEPTION
        WHEN pkg_inventario.e_cantidad_invalida THEN
            pkg_assert.igual(p_caso || ' -> e_cantidad_invalida', -20102, SQLCODE);
    END probar;
BEGIN
    probar('P10a Cantidad 0',    0);
    probar('P10b Cantidad NULL', NULL);
    probar('P10c Cantidad sobre c_max_movimiento', pkg_inventario.c_max_movimiento + 1);
END;
/

-- P11: regla de negocio, producto inexistente
BEGIN
    pkg_inventario.sp_ingresar(999, 1, 5);
    pkg_assert.verdadero('P11 Producto inexistente debia fallar', FALSE);
EXCEPTION
    WHEN pkg_inventario.e_producto_no_existe THEN
        pkg_assert.igual('P11 Se atrapa e_producto_no_existe (-20103)', -20103, SQLCODE);
END;
/

-- P12: falla tecnica (FK violada). El paquete la registra y la relanza.
DECLARE
    e_fk_violada EXCEPTION;
    PRAGMA EXCEPTION_INIT(e_fk_violada, -2291);
    v_logs_antes PLS_INTEGER;
    v_logs_despues PLS_INTEGER;
BEGIN
    SELECT COUNT(*) INTO v_logs_antes FROM lab_log_errores;

    BEGIN
        pkg_inventario.sp_ingresar(1, 99, 5);    -- la bodega 99 no existe
        pkg_assert.verdadero('P12a Bodega inexistente debia fallar', FALSE);
    EXCEPTION
        WHEN e_fk_violada THEN
            pkg_assert.igual('P12a La FK violada llega al llamador (ORA-02291)', -2291, SQLCODE);
    END;

    SELECT COUNT(*) INTO v_logs_despues FROM lab_log_errores;
    pkg_assert.igual('P12b El error tecnico quedo en la bitacora', v_logs_antes + 1, v_logs_despues);
END;
/

-- P13: un subprograma privado NO es accesible desde fuera del paquete
DECLARE
    e_compilacion EXCEPTION;
    PRAGMA EXCEPTION_INIT(e_compilacion, -6550);
BEGIN
    EXECUTE IMMEDIATE 'BEGIN pkg_inventario.validar_cantidad(10); END;';
    pkg_assert.verdadero('P13 Invocar un privado debia fallar', FALSE);
EXCEPTION
    WHEN e_compilacion THEN
        pkg_assert.verdadero('P13 El privado no es visible (PLS-00302)',
                             INSTR(SQLERRM, 'PLS-00302') > 0);
END;
/

-- P14: una funcion publica sin DML se puede usar dentro de SQL
DECLARE
    v_total NUMBER;
BEGIN
    SELECT pkg_inventario.fn_stock_disponible(1)
      INTO v_total
      FROM dual;
    pkg_assert.igual('P14 Funcion del paquete usada en un SELECT (70 + 40)', 110, v_total);
END;
/

PROMPT -- Reporte con la funcion del paquete dentro de SQL
COLUMN codigo FORMAT A10
COLUMN nombre FORMAT A22
SELECT p.codigo,
       p.nombre,
       pkg_inventario.fn_stock_disponible(p.id_producto, 1) AS bodega_norte,
       pkg_inventario.fn_stock_disponible(p.id_producto, 2) AS bodega_sur,
       pkg_inventario.fn_stock_disponible(p.id_producto)    AS total
  FROM lab_producto p
 ORDER BY p.codigo;

PROMPT
PROMPT ===== Parte 6. Transacciones y bitacora autonoma =====

-- P15: una excepcion NO revierte el trabajo previo de la transaccion
BEGIN
    pkg_inventario.sp_ingresar(2, 2, 15);
    BEGIN
        pkg_inventario.sp_despachar(2, 2, 100);   -- falla: solo hay 15
    EXCEPTION
        WHEN pkg_inventario.e_stock_insuficiente THEN
            NULL;   -- prevista en esta prueba: queremos ver que paso con el ingreso
    END;
    pkg_assert.igual('P15 El ingreso previo sigue pendiente tras la excepcion', 15,
                     pkg_inventario.fn_stock_disponible(2, 2));
END;
/

ROLLBACK;

-- P16: tras el ROLLBACK, el inventario vuelve al estado inicial,
--      pero la bitacora (transaccion autonoma) conserva la evidencia.
DECLARE
    v_logs PLS_INTEGER;
BEGIN
    pkg_assert.igual('P16a ROLLBACK revirtio el ingreso de P06', 0,
                     pkg_inventario.fn_stock_disponible(3, 2));
    pkg_assert.igual('P16b ROLLBACK revirtio el despacho de P07', 100,
                     pkg_inventario.fn_stock_disponible(1, 1));

    SELECT COUNT(*) INTO v_logs
      FROM lab_log_errores
     WHERE origen = 'pkg_inventario.sp_ingresar'
       AND codigo_error = -2291;
    pkg_assert.verdadero('P16c La bitacora sobrevivio al ROLLBACK', v_logs >= 1);
END;
/

PROMPT -- Contenido de la bitacora
COLUMN origen  FORMAT A28
COLUMN mensaje FORMAT A60
SELECT id_log, origen, codigo_error, mensaje
  FROM lab_log_errores
 ORDER BY id_log;

PROMPT
PROMPT ===== Parte 7. Dependencias =====
-- Las sentencias DDL hacen COMMIT implicito; por eso esta parte va al final.

CREATE OR REPLACE PROCEDURE lab_sp_reporte_stock IS
BEGIN
    FOR r IN (SELECT id_producto, codigo FROM lab_producto ORDER BY codigo) LOOP
        DBMS_OUTPUT.PUT_LINE(RPAD(r.codigo, 10) ||
                             LPAD(pkg_inventario.fn_stock_disponible(r.id_producto), 6));
    END LOOP;
END lab_sp_reporte_stock;
/
SHOW ERRORS PROCEDURE lab_sp_reporte_stock

-- Recompilar SOLO el cuerpo: los dependientes no se invalidan
ALTER PACKAGE pkg_inventario COMPILE BODY;

COLUMN referenced_name FORMAT A20
PROMPT -- Quien depende de pkg_inventario
SELECT name, type, referenced_name, referenced_type
  FROM user_dependencies
 WHERE referenced_name = 'PKG_INVENTARIO';

DECLARE
    v_estado VARCHAR2(10);
BEGIN
    SELECT status INTO v_estado FROM user_objects
     WHERE object_name = 'LAB_SP_REPORTE_STOCK';
    pkg_assert.igual('P17 Recompilar el cuerpo no invalida al dependiente', 'VALID', v_estado);
END;
/

PROMPT
PROMPT ===== Parte 8. Resumen =====

BEGIN
    pkg_assert.resumen;
END;
/

SET FEEDBACK ON

/* =============================================================================
   Parte 9. RETOS PARA EL ESTUDIANTE
   -----------------------------------------------------------------------------
   Reto 1. Traslado entre bodegas
     Agregue a pkg_inventario el procedimiento publico
         sp_trasladar(p_id_producto, p_bodega_origen, p_bodega_destino, p_cantidad)
     que reutilice sp_despachar y sp_ingresar. Si cualquiera de los dos falla,
     el traslado debe revertirse COMPLETO (use SAVEPOINT) y la excepcion debe
     llegar al llamador. Escriba las pruebas P20 (traslado valido), P21 (origen
     sin stock) y P22 (destino inexistente: verifique que el origen no cambio).

   Reto 2. Sobrecarga por codigo
     Sobrecargue sp_ingresar para que acepte el CODIGO del producto (VARCHAR2)
     en lugar del id. Reutilice la version por id; no duplique la logica.
     Consulte USER_ARGUMENTS y explique la columna OVERLOAD.

   Reto 3. Estado de paquete descartado (dos sesiones)
     Sesion A: ejecute pkg_inventario.sp_ingresar(1, 1, 5) y consulte
               pkg_inventario.fn_operaciones_sesion.
     Sesion B: ejecute ALTER PACKAGE pkg_inventario COMPILE BODY;
     Sesion A: vuelva a consultar fn_operaciones_sesion.
     Explique el error ORA-04068, por que el contador vuelve a 0 y que
     implicaciones tiene desplegar un cuerpo nuevo en produccion.

   Reto 4. Cambio en la especificacion
     Agregue una funcion nueva a la especificacion y recompile. Consulte el
     estado de LAB_SP_REPORTE_STOCK en USER_OBJECTS. Luego cambie la firma de
     fn_stock_disponible (por ejemplo, el nombre de un parametro) y repita.
     Compare ambos resultados con lo que paso en P17.

   Reto 5. Funciones con DML dentro de SQL
     Cree en el paquete una funcion publica que haga un INSERT en
     lab_movimiento y devuelva un numero. Invoquela desde un SELECT ... FROM dual.
     Documente el error ORA-14551 y explique por que Oracle lo impide.

   LIMPIEZA (opcional, cuando termine)
     Ejecute de nuevo la Parte 0.
   ============================================================================= */
