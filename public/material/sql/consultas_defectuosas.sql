-- =====================================================================
-- Universidad El Bosque - Bases de Datos 2
-- Taller de repaso: SQL avanzado aplicado sobre el esquema HR
-- Archivo: 02_consultas_defectuosas.sql
-- Corresponde a la seccion 6.12 del enunciado (Bloque I).
--
-- Las cinco consultas de este archivo SE EJECUTAN SIN ERROR y devuelven
-- un resultado INCORRECTO respecto al enunciado que dicen resolver.
--
-- Para cada una deben entregar, en el script de entrega:
--   1. El error detectado.
--   2. El mecanismo que lo produce (por que la base responde asi).
--   3. La consulta corregida, ejecutada, con su salida.
--
-- No basta con corregir la consulta: la explicacion del mecanismo es la
-- parte evaluable.
-- =====================================================================

SET LINESIZE 200
SET PAGESIZE 200

-- Si trabajan desde un usuario distinto de HR, descomenten la linea:
-- ALTER SESSION SET CURRENT_SCHEMA = HR;


-- ---------------------------------------------------------------------
-- CONSULTA I.1
-- Enunciado: todos los departamentos con la cantidad de empleados,
--            incluidos los departamentos que no tienen ninguno.
-- Pista: comparen el resultado contra el PASO 3 del script 01.
-- ---------------------------------------------------------------------
PROMPT
PROMPT ===== CONSULTA I.1 (defectuosa) =====

SELECT   d.department_name, COUNT(*) AS employee_count
FROM     HR.departments d
LEFT     JOIN HR.employees e ON d.department_id = e.department_id
GROUP BY d.department_name
ORDER BY d.department_name;


-- ---------------------------------------------------------------------
-- CONSULTA I.2
-- Enunciado: empleados que NO trabajan en los departamentos 10, 20 ni 30.
-- Pista: cuenten las filas devueltas y comparenlas con el total de
--        empleados menos los de esos tres departamentos.
-- ---------------------------------------------------------------------
PROMPT
PROMPT ===== CONSULTA I.2 (defectuosa) =====

SELECT last_name, department_id
FROM   HR.employees
WHERE  department_id NOT IN (10, 20, 30)
ORDER  BY department_id, last_name;


-- ---------------------------------------------------------------------
-- CONSULTA I.3
-- Enunciado: departamentos ubicados en Estados Unidos con su cantidad
--            de empleados.
-- Pista: hay DOS errores distintos en esta consulta, no uno.
-- ---------------------------------------------------------------------
PROMPT
PROMPT ===== CONSULTA I.3 (defectuosa) =====

SELECT   d.department_name, COUNT(*) AS employee_count
FROM     HR.departments d
LEFT     JOIN employees e ON d.department_id = e.department_id
LEFT     JOIN locations l ON d.location_id   = l.location_id
WHERE    l.country_id = 'US'
GROUP BY d.department_name
ORDER BY d.department_name;


-- ---------------------------------------------------------------------
-- CONSULTA I.4
-- Enunciado: el empleado mejor pagado de cada departamento.
-- Pista: cuenten cuantas filas devuelve por departamento.
-- ---------------------------------------------------------------------
PROMPT
PROMPT ===== CONSULTA I.4 (defectuosa) =====

SELECT   department_id, last_name, MAX(salary) AS max_salary
FROM     HR.employees
GROUP BY department_id, last_name
ORDER BY department_id, max_salary DESC;


-- ---------------------------------------------------------------------
-- CONSULTA I.5
-- Enunciado: promedio de comision de la compania, contando como CERO a
--            quienes no reciben comision.
-- Pista: comparen el resultado con SUM(commission_pct)/COUNT(*).
-- ---------------------------------------------------------------------
PROMPT
PROMPT ===== CONSULTA I.5 (defectuosa) =====

SELECT AVG(commission_pct) AS promedio_comision
FROM   employees;


PROMPT
PROMPT ===== Fin del bloque de consultas defectuosas =====
PROMPT Copien cada consulta al script de entrega, documenten el
PROMPT diagnostico y escriban debajo la version corregida.
PROMPT
