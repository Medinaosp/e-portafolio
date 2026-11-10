-- =====================================================================
-- RETO FINAL - BANCO ANDINO
-- VERSION CORREGIDA
-- =====================================================================


-- #####################################################################
-- 0. PREPARAR LOS DATOS DE PRUEBA
-- Ejecutar UNA SOLA VEZ antes de comenzar
-- #####################################################################

-- Eliminar movimientos creados en la prueba anterior
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

-- #####################################################################
-- 1. BLOQUEAR LAS DOS CUENTAS EN ORDEN DETERMINISTA
-- #####################################################################

-- Ambas conexiones deben ejecutar este SELECT.
-- Siempre se bloquea primero la cuenta con menor ID.
-- Esto evita interbloqueos en transferencias cruzadas.

SELECT id_cuenta, saldo
FROM cuenta
WHERE id_cuenta IN (1001, 1002)
ORDER BY id_cuenta
FOR UPDATE;


-- #####################################################################
-- 2. REALIZAR EL DÉBITO DEL ORIGEN
-- #####################################################################

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


-- #####################################################################
-- 3. REALIZAR EL CRÉDITO DEL DESTINO
-- #####################################################################

UPDATE cuenta
SET saldo = saldo + 300000
WHERE id_cuenta = 1002;


-- Verificar saldos
SELECT id_cuenta, saldo
FROM cuenta
WHERE id_cuenta IN (1001, 1002)
ORDER BY id_cuenta;


-- #####################################################################
-- 4. INSERTAR EL MOVIMIENTO CONTABLE DEL DÉBITO
-- #####################################################################

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


-- #####################################################################
-- 5. INSERTAR EL MOVIMIENTO CONTABLE DEL CRÉDITO
-- #####################################################################

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


-- #####################################################################
-- 6. CAMBIAR EL ESTADO DE LA TRANSFERENCIA
-- #####################################################################

-- Solo se cambia si todavía estaba REGISTRADA.
-- Así se evita aplicar dos veces la misma transferencia.

UPDATE transferencia
SET estado = 'APLICADA'
WHERE id_transferencia = 950001
  AND estado = 'REGISTRADA';


-- #####################################################################
-- 7. COMPROBAR EL RESULTADO ANTES DE CONFIRMAR
-- #####################################################################

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


-- #####################################################################
-- 8. CONFIRMAR TODO JUNTO
-- #####################################################################

COMMIT;