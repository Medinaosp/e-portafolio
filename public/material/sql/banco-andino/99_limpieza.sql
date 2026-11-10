-- =====================================================================
-- Bases de Datos 2 · Taller integrador — Banco Andino
-- 99_limpieza.sql   Ejecutar al finalizar la sesión
-- =====================================================================

-- Cierre cualquier transacción abierta antes de limpiar
ROLLBACK;

DROP TABLE ajuste_saldo       CASCADE CONSTRAINTS PURGE;
DROP TABLE tarea_compensacion CASCADE CONSTRAINTS PURGE;
DROP TABLE notificacion       CASCADE CONSTRAINTS PURGE;
DROP TABLE movimiento         CASCADE CONSTRAINTS PURGE;
DROP TABLE transferencia      CASCADE CONSTRAINTS PURGE;
DROP TABLE cuenta             CASCADE CONSTRAINTS PURGE;
DROP TABLE catalogo_producto  CASCADE CONSTRAINTS PURGE;
DROP TABLE sucursal           CASCADE CONSTRAINTS PURGE;
DROP TABLE cliente            CASCADE CONSTRAINTS PURGE;

PURGE RECYCLEBIN;

SELECT table_name FROM user_tables ORDER BY 1;

PROMPT
PROMPT  Esquema limpio. Espacio liberado.
