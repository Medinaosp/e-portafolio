-- =====================================================================
-- Bases de Datos 2 · Taller integrador — Banco Andino
-- 00_setup.sql   Creación del esquema y carga de datos
--
-- Lo ejecuta CADA PAREJA UNA SOLA VEZ, en UNA de sus dos conexiones.
-- Ejecútelo completo con "Run Script" (F5), NO con Ctrl+Enter.
--
-- Tarda entre 2 y 4 minutos. Mientras corre, lea el enunciado.
-- =====================================================================

SET SERVEROUTPUT ON
SET TIMING ON
SET LINESIZE 200
SET PAGESIZE 100
SET autocommit OFF

-- ---------------------------------------------------------------------
-- 0. ¿En qué sesión estoy?  Ejecute esto en LAS DOS conexiones.
--    Los dos números deben ser DISTINTOS. Si son iguales, no tiene dos
--    sesiones: abrió dos hojas de trabajo sobre la misma conexión.
-- ---------------------------------------------------------------------
SELECT USER                                  AS usuario,
       SYS_CONTEXT('USERENV','SID')          AS sid,
       SYS_CONTEXT('USERENV','SERVICE_NAME') AS servicio
  FROM dual;

-- ---------------------------------------------------------------------
-- 1. Limpieza previa
--    Si es la primera vez que ejecuta el taller, estas sentencias van a
--    devolver ORA-00942: table or view does not exist.
--    Es normal, ignórelo y siga.
-- ---------------------------------------------------------------------
DROP TABLE ajuste_saldo       CASCADE CONSTRAINTS PURGE;
DROP TABLE tarea_compensacion CASCADE CONSTRAINTS PURGE;
DROP TABLE notificacion       CASCADE CONSTRAINTS PURGE;
DROP TABLE movimiento         CASCADE CONSTRAINTS PURGE;
DROP TABLE transferencia      CASCADE CONSTRAINTS PURGE;
DROP TABLE cuenta             CASCADE CONSTRAINTS PURGE;
DROP TABLE catalogo_producto  CASCADE CONSTRAINTS PURGE;
DROP TABLE sucursal           CASCADE CONSTRAINTS PURGE;
DROP TABLE cliente            CASCADE CONSTRAINTS PURGE;

-- ---------------------------------------------------------------------
-- 2. Estructura
-- ---------------------------------------------------------------------

-- Catálogo de productos del banco, en tres niveles:
-- Línea de negocio > Familia > Producto.  Se usa en la CTE recursiva.
CREATE TABLE catalogo_producto (
  id_producto   NUMBER        NOT NULL,
  nombre        VARCHAR2(40)  NOT NULL,
  id_padre      NUMBER,
  CONSTRAINT pk_catprod   PRIMARY KEY (id_producto),
  CONSTRAINT fk_catprod_padre FOREIGN KEY (id_padre) REFERENCES catalogo_producto
);

CREATE TABLE sucursal (
  id_sucursal NUMBER        NOT NULL,
  nombre      VARCHAR2(40)  NOT NULL,
  ciudad      VARCHAR2(30)  NOT NULL,
  CONSTRAINT pk_sucursal PRIMARY KEY (id_sucursal)
);

CREATE TABLE cliente (
  id_cliente         NUMBER        NOT NULL,
  nombre             VARCHAR2(60)  NOT NULL,
  ciudad             VARCHAR2(30)  NOT NULL,
  segmento           VARCHAR2(12)  NOT NULL,
  fecha_vinculacion  DATE          NOT NULL,
  CONSTRAINT pk_cliente PRIMARY KEY (id_cliente),
  CONSTRAINT ck_cli_seg CHECK (segmento IN ('PREFERENCIAL','PYME','PERSONAL'))
);

-- OJO: la columna VERSION existe para el ejercicio de bloqueo optimista.
-- El CHECK de saldo es el que va a impedir dejar una cuenta en rojo.
CREATE TABLE cuenta (
  id_cuenta        NUMBER        NOT NULL,
  id_cliente       NUMBER        NOT NULL,
  id_producto      NUMBER        NOT NULL,
  id_sucursal      NUMBER        NOT NULL,
  saldo            NUMBER(16,2)  NOT NULL,
  saldo_retenido   NUMBER(16,2)  DEFAULT 0 NOT NULL,
  version          NUMBER        DEFAULT 0 NOT NULL,
  estado           VARCHAR2(10)  DEFAULT 'ACTIVA' NOT NULL,
  CONSTRAINT pk_cuenta      PRIMARY KEY (id_cuenta),
  CONSTRAINT fk_cta_cli     FOREIGN KEY (id_cliente)  REFERENCES cliente,
  CONSTRAINT fk_cta_prod    FOREIGN KEY (id_producto) REFERENCES catalogo_producto,
  CONSTRAINT fk_cta_suc     FOREIGN KEY (id_sucursal) REFERENCES sucursal,
  CONSTRAINT ck_cta_saldo   CHECK (saldo >= 0),
  CONSTRAINT ck_cta_estado  CHECK (estado IN ('ACTIVA','INACTIVA','EMBARGADA'))
);

-- Una transferencia toca DOS cuentas: origen y destino.
-- Ese detalle es el que hace distinto este caso.
CREATE TABLE transferencia (
  id_transferencia  NUMBER        NOT NULL,
  cuenta_origen     NUMBER        NOT NULL,
  cuenta_destino    NUMBER        NOT NULL,
  fecha_transf      DATE          NOT NULL,
  valor             NUMBER(16,2)  NOT NULL,
  canal             VARCHAR2(12)  NOT NULL,
  estado            VARCHAR2(12)  NOT NULL,
  CONSTRAINT pk_transferencia PRIMARY KEY (id_transferencia),
  CONSTRAINT fk_tr_origen  FOREIGN KEY (cuenta_origen)  REFERENCES cuenta,
  CONSTRAINT fk_tr_destino FOREIGN KEY (cuenta_destino) REFERENCES cuenta,
  CONSTRAINT ck_tr_estado  CHECK (estado IN ('REGISTRADA','APLICADA','RECHAZADA','REVERSADA')),
  CONSTRAINT ck_tr_valor   CHECK (valor > 0),
  CONSTRAINT ck_tr_distinta CHECK (cuenta_origen <> cuenta_destino)
);

-- Cada transferencia aplicada genera DOS movimientos: débito y crédito.
CREATE TABLE movimiento (
  id_movimiento     NUMBER        NOT NULL,
  id_cuenta         NUMBER        NOT NULL,
  id_transferencia  NUMBER,
  fecha_mov         DATE          NOT NULL,
  tipo              VARCHAR2(8)   NOT NULL,
  valor             NUMBER(16,2)  NOT NULL,
  CONSTRAINT pk_movimiento PRIMARY KEY (id_movimiento),
  CONSTRAINT fk_mov_cta    FOREIGN KEY (id_cuenta) REFERENCES cuenta,
  CONSTRAINT fk_mov_tr     FOREIGN KEY (id_transferencia) REFERENCES transferencia,
  CONSTRAINT ck_mov_tipo   CHECK (tipo IN ('DEBITO','CREDITO'))
);

-- OJO: la llave foránea NOTIFICACION.ID_TRANSFERENCIA queda SIN ÍNDICE
--      a propósito. En el ejercicio 1.5 vamos a ver qué provoca eso.
CREATE TABLE notificacion (
  id_notificacion   NUMBER        NOT NULL,
  id_transferencia  NUMBER        NOT NULL,
  canal             VARCHAR2(10)  NOT NULL,
  enviada           CHAR(1)       DEFAULT 'S' NOT NULL,
  CONSTRAINT pk_notificacion PRIMARY KEY (id_notificacion),
  CONSTRAINT fk_notif_tr     FOREIGN KEY (id_transferencia) REFERENCES transferencia
);

-- Cola de compensación interbancaria -> ejercicio de SKIP LOCKED
CREATE TABLE tarea_compensacion (
  id_tarea     NUMBER        NOT NULL,
  id_transferencia NUMBER    NOT NULL,
  estado       VARCHAR2(12)  DEFAULT 'PENDIENTE' NOT NULL,
  tomada_por   VARCHAR2(20),
  fecha_toma   TIMESTAMP,
  CONSTRAINT pk_tarea_comp PRIMARY KEY (id_tarea)
);

-- Ajustes de cierre (intereses, notas débito y crédito) -> ejercicio de MERGE
CREATE TABLE ajuste_saldo (
  id_cuenta  NUMBER        NOT NULL,
  delta      NUMBER(16,2)  NOT NULL,
  concepto   VARCHAR2(30)  NOT NULL
);

-- ---------------------------------------------------------------------
-- 3. Datos maestros
-- ---------------------------------------------------------------------

-- Nivel 1: líneas de negocio
INSERT INTO catalogo_producto VALUES (1,  'Banca Personas',      NULL);
INSERT INTO catalogo_producto VALUES (2,  'Banca Empresas',      NULL);
INSERT INTO catalogo_producto VALUES (3,  'Banca Patrimonial',   NULL);
-- Nivel 2: familias
INSERT INTO catalogo_producto VALUES (10, 'Depósito',            1);
INSERT INTO catalogo_producto VALUES (11, 'Crédito personas',    1);
INSERT INTO catalogo_producto VALUES (12, 'Medios de pago',      1);
INSERT INTO catalogo_producto VALUES (13, 'Depósito empresarial',2);
INSERT INTO catalogo_producto VALUES (14, 'Crédito empresarial', 2);
INSERT INTO catalogo_producto VALUES (15, 'Inversión',           3);
INSERT INTO catalogo_producto VALUES (16, 'Fiducia',             3);
-- Nivel 3: productos
INSERT INTO catalogo_producto VALUES (100,'Cuenta de ahorros',   10);
INSERT INTO catalogo_producto VALUES (101,'Cuenta corriente',    10);
INSERT INTO catalogo_producto VALUES (102,'CDT',                 10);
INSERT INTO catalogo_producto VALUES (103,'Libranza',            11);
INSERT INTO catalogo_producto VALUES (104,'Crédito de consumo',  11);
INSERT INTO catalogo_producto VALUES (105,'Tarjeta de crédito',  12);
INSERT INTO catalogo_producto VALUES (106,'Cuenta empresarial',  13);
INSERT INTO catalogo_producto VALUES (107,'Cupo rotativo',       14);
INSERT INTO catalogo_producto VALUES (108,'Fondo de inversión',  15);
INSERT INTO catalogo_producto VALUES (109,'Fiducia inmobiliaria',16);
COMMIT;

INSERT INTO sucursal VALUES (1,'Centro Internacional','Bogotá');
INSERT INTO sucursal VALUES (2,'Chapinero',           'Bogotá');
INSERT INTO sucursal VALUES (3,'El Poblado',          'Medellín');
INSERT INTO sucursal VALUES (4,'Granada',             'Cali');
INSERT INTO sucursal VALUES (5,'Alto Prado',          'Barranquilla');
INSERT INTO sucursal VALUES (6,'Cabecera',            'Bucaramanga');
INSERT INTO sucursal VALUES (7,'Circunvalar',         'Pereira');
INSERT INTO sucursal VALUES (8,'Centro',              'Cartagena');
COMMIT;

-- 20.000 clientes
INSERT /*+ APPEND */ INTO cliente (id_cliente, nombre, ciudad, segmento, fecha_vinculacion)
SELECT n,
       CASE MOD(n,8)
         WHEN 0 THEN 'Ana'     WHEN 1 THEN 'Carlos'  WHEN 2 THEN 'Lucía'
         WHEN 3 THEN 'Andrés'  WHEN 4 THEN 'Marcela' WHEN 5 THEN 'Julián'
         WHEN 6 THEN 'Patricia' ELSE 'Ricardo'
       END || ' ' ||
       CASE MOD(n,7)
         WHEN 0 THEN 'Rojas'   WHEN 1 THEN 'Cárdenas' WHEN 2 THEN 'Beltrán'
         WHEN 3 THEN 'Ocampo'  WHEN 4 THEN 'Salazar'  WHEN 5 THEN 'Quintero'
         ELSE 'Navarro'
       END || ' ' || n,
       CASE MOD(n,6) WHEN 0 THEN 'Bogotá'   WHEN 1 THEN 'Medellín'
                     WHEN 2 THEN 'Cali'     WHEN 3 THEN 'Barranquilla'
                     WHEN 4 THEN 'Pereira'  ELSE 'Bucaramanga' END,
       CASE MOD(n,10) WHEN 0 THEN 'PREFERENCIAL' WHEN 1 THEN 'PREFERENCIAL'
                      WHEN 2 THEN 'PYME'         ELSE 'PERSONAL' END,
       DATE '2020-01-01' + MOD(n, 2000)
  FROM (SELECT LEVEL n FROM dual CONNECT BY LEVEL <= 20000);
COMMIT;

-- 30.000 cuentas
INSERT /*+ APPEND */ INTO cuenta (id_cuenta, id_cliente, id_producto, id_sucursal,
                                  saldo, saldo_retenido, version, estado)
SELECT n,
       MOD(n, 20000) + 1,
       100 + MOD(n, 10),
       MOD(n, 8) + 1,
       ROUND(DBMS_RANDOM.VALUE(50000, 90000000), -3),
       0, 0,
       CASE WHEN MOD(n,53) = 0 THEN 'INACTIVA' ELSE 'ACTIVA' END
  FROM (SELECT LEVEL n FROM dual CONNECT BY LEVEL <= 30000);
COMMIT;

-- Cuentas de laboratorio: valores conocidos para los ejercicios de la parte 1
UPDATE cuenta
   SET saldo = 1000000, saldo_retenido = 0, version = 0, estado = 'ACTIVA'
 WHERE id_cuenta IN (1001, 1002);
COMMIT;

-- 200.000 transferencias repartidas en dos años
INSERT /*+ APPEND */ INTO transferencia
  (id_transferencia, cuenta_origen, cuenta_destino, fecha_transf, valor, canal, estado)
SELECT n,
       MOD(n * 3, 30000) + 1,
       MOD(n * 7, 30000) + 1,
       DATE '2025-01-01' + MOD(n * 7, 730) + (MOD(n,24)/24),
       ROUND(DBMS_RANDOM.VALUE(20000, 8000000), -3),
       CASE MOD(n,4) WHEN 0 THEN 'APP'    WHEN 1 THEN 'WEB'
                     WHEN 2 THEN 'APP'    ELSE 'OFICINA' END,
       CASE
         WHEN MOD(n,100) < 62 THEN 'APLICADA'
         WHEN MOD(n,100) < 80 THEN 'REGISTRADA'
         WHEN MOD(n,100) < 93 THEN 'RECHAZADA'
         ELSE 'REVERSADA'
       END
  FROM (SELECT LEVEL n FROM dual CONNECT BY LEVEL <= 200000)
 WHERE MOD(n * 3, 30000) <> MOD(n * 7, 30000);
COMMIT;

-- Dos movimientos por cada transferencia aplicada: débito y crédito
INSERT /*+ APPEND */ INTO movimiento
  (id_movimiento, id_cuenta, id_transferencia, fecha_mov, tipo, valor)
SELECT ROWNUM,
       CASE WHEN m.lado = 1 THEN t.cuenta_origen ELSE t.cuenta_destino END,
       t.id_transferencia,
       t.fecha_transf,
       CASE WHEN m.lado = 1 THEN 'DEBITO' ELSE 'CREDITO' END,
       t.valor
  FROM transferencia t
 CROSS JOIN (SELECT 1 AS lado FROM dual UNION ALL SELECT 2 FROM dual) m
 WHERE t.estado = 'APLICADA';
COMMIT;

-- Notificaciones de las transferencias aplicadas
INSERT /*+ APPEND */ INTO notificacion (id_notificacion, id_transferencia, canal, enviada)
SELECT ROWNUM, id_transferencia,
       CASE MOD(id_transferencia,3) WHEN 0 THEN 'SMS'
                                    WHEN 1 THEN 'EMAIL' ELSE 'PUSH' END,
       'S'
  FROM transferencia
 WHERE estado = 'APLICADA';
COMMIT;

-- Transferencias de laboratorio SIN movimientos y SIN notificaciones,
-- para el ejercicio 1.5
INSERT INTO transferencia
  (id_transferencia, cuenta_origen, cuenta_destino, fecha_transf, valor, canal, estado)
SELECT 900000 + LEVEL, 1001, 1002, SYSDATE, 1000, 'WEB', 'REGISTRADA'
  FROM dual CONNECT BY LEVEL <= 10;
COMMIT;

-- Transferencia de laboratorio para el RETO (parte 4).
-- Valores conocidos: de la cuenta 1001 a la 1002, por 300.000.
-- No se genera al azar porque el enunciado del reto depende de estos valores.
INSERT INTO transferencia
  (id_transferencia, cuenta_origen, cuenta_destino, fecha_transf, valor, canal, estado)
VALUES (950001, 1001, 1002, SYSDATE, 300000, 'APP', 'REGISTRADA');
COMMIT;

-- Cola de compensación
INSERT INTO tarea_compensacion (id_tarea, id_transferencia, estado)
SELECT LEVEL, LEVEL, 'PENDIENTE' FROM dual CONNECT BY LEVEL <= 200;
COMMIT;

-- Ajustes de cierre para el MERGE
INSERT INTO ajuste_saldo (id_cuenta, delta, concepto)
SELECT MOD(LEVEL * 17, 30000) + 1,
       CASE WHEN MOD(LEVEL,3) = 0 THEN -25000 ELSE 40000 END,
       CASE WHEN MOD(LEVEL,3) = 0 THEN 'CUOTA MANEJO' ELSE 'ABONO INTERESES' END
  FROM dual CONNECT BY LEVEL <= 500;
COMMIT;

-- ---------------------------------------------------------------------
-- 4. Índices que SÍ dejamos creados
--    MOVIMIENTO.ID_TRANSFERENCIA sí queda indexada: así el ejercicio 1.5
--    aísla una sola causa, la de NOTIFICACION.
-- ---------------------------------------------------------------------
CREATE INDEX ix_mov_transferencia ON movimiento (id_transferencia);

-- ---------------------------------------------------------------------
-- 5. Estadísticas
--    Sin estadísticas frescas el optimizador adivina y los planes que
--    van a leer no significan nada.
-- ---------------------------------------------------------------------
EXEC DBMS_STATS.GATHER_TABLE_STATS(USER, 'CATALOGO_PRODUCTO',  cascade => TRUE);
EXEC DBMS_STATS.GATHER_TABLE_STATS(USER, 'SUCURSAL',           cascade => TRUE);
EXEC DBMS_STATS.GATHER_TABLE_STATS(USER, 'CLIENTE',            cascade => TRUE);
EXEC DBMS_STATS.GATHER_TABLE_STATS(USER, 'CUENTA',             cascade => TRUE);
EXEC DBMS_STATS.GATHER_TABLE_STATS(USER, 'TRANSFERENCIA',      cascade => TRUE);
EXEC DBMS_STATS.GATHER_TABLE_STATS(USER, 'MOVIMIENTO',         cascade => TRUE);
EXEC DBMS_STATS.GATHER_TABLE_STATS(USER, 'NOTIFICACION',       cascade => TRUE);
EXEC DBMS_STATS.GATHER_TABLE_STATS(USER, 'TAREA_COMPENSACION', cascade => TRUE);

-- ---------------------------------------------------------------------
-- 6. Verificación — anote estos números
-- ---------------------------------------------------------------------
SELECT 'CATALOGO_PRODUCTO'  AS tabla, COUNT(*) AS filas FROM catalogo_producto
UNION ALL SELECT 'CLIENTE',            COUNT(*) FROM cliente
UNION ALL SELECT 'CUENTA',             COUNT(*) FROM cuenta
UNION ALL SELECT 'TRANSFERENCIA',      COUNT(*) FROM transferencia
UNION ALL SELECT 'MOVIMIENTO',         COUNT(*) FROM movimiento
UNION ALL SELECT 'NOTIFICACION',       COUNT(*) FROM notificacion
UNION ALL SELECT 'TAREA_COMPENSACION', COUNT(*) FROM tarea_compensacion;

-- Las dos cuentas de laboratorio: las dos deben tener 1.000.000
SELECT id_cuenta, id_cliente, saldo, saldo_retenido, version, estado
  FROM cuenta WHERE id_cuenta IN (1001, 1002) ORDER BY id_cuenta;

-- La transferencia del reto: de la 1001 a la 1002, por 300.000
SELECT id_transferencia, cuenta_origen, cuenta_destino, valor, estado
  FROM transferencia WHERE id_transferencia = 950001;

-- Índices que existen en este momento: los de las restricciones más el
-- de MOVIMIENTO. Todo lo demás lo van a crear ustedes, y lo van a justificar.
SELECT table_name, index_name, uniqueness
  FROM user_indexes ORDER BY table_name, index_name;

PROMPT
PROMPT ======================================================================
PROMPT  Esquema Banco Andino listo.
PROMPT  Abra la SEGUNDA conexión y verifique que el SID sea distinto.
PROMPT  Continúe con 01_sesion_A.sql y 01_sesion_B.sql
PROMPT ======================================================================
