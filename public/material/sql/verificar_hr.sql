-- =====================================================================
-- Universidad El Bosque - Bases de Datos 2
-- Taller de repaso: SQL avanzado aplicado sobre el esquema HR
-- Archivo: 01_verifica_hr.sql
-- Proposito: comprobar que el esquema HR esta completo y con los datos
--            originales antes de iniciar el taller.
-- Uso: ejecutar UNA sola vez al comienzo de la sesion.
-- IMPORTANTE: este script es de solo lectura. No modifica datos.
-- =====================================================================

SET LINESIZE 200
SET PAGESIZE 200
SET FEEDBACK OFF
SET VERIFY OFF

-- Si trabajan desde un usuario distinto de HR, descomenten la linea:
-- ALTER SESSION SET CURRENT_SCHEMA = HR;

PROMPT
PROMPT ====================================================================
PROMPT PASO 1. Existencia de las siete tablas del esquema
PROMPT ====================================================================

COLUMN tabla        FORMAT A20
COLUMN estado       FORMAT A20

SELECT t.tabla,
       CASE WHEN u.table_name IS NULL THEN 'FALTA'
            ELSE 'OK'
       END AS estado
FROM  (SELECT 'REGIONS'     AS tabla FROM dual UNION ALL
       SELECT 'COUNTRIES'         FROM dual UNION ALL
       SELECT 'LOCATIONS'         FROM dual UNION ALL
       SELECT 'DEPARTMENTS'       FROM dual UNION ALL
       SELECT 'JOBS'              FROM dual UNION ALL
       SELECT 'EMPLOYEES'         FROM dual UNION ALL
       SELECT 'JOB_HISTORY'       FROM dual) t
LEFT   JOIN user_tables u ON u.table_name = t.tabla
ORDER  BY t.tabla;

PROMPT
PROMPT ====================================================================
PROMPT PASO 2. Conteo de filas contra los valores originales del esquema
PROMPT ====================================================================

COLUMN esperado FORMAT 9999
COLUMN real     FORMAT 9999

SELECT 'REGIONS'     AS tabla,  5 AS esperado, (SELECT COUNT(*) FROM HR.regions)     AS real FROM dual UNION ALL
SELECT 'COUNTRIES',            25,             (SELECT COUNT(*) FROM HR.countries)        FROM dual UNION ALL
SELECT 'LOCATIONS',            23,             (SELECT COUNT(*) FROM HR.locations)        FROM dual UNION ALL
SELECT 'DEPARTMENTS',          27,             (SELECT COUNT(*) FROM HR.departments)      FROM dual UNION ALL
SELECT 'JOBS',                 19,             (SELECT COUNT(*) FROM HR.jobs)             FROM dual UNION ALL
SELECT 'EMPLOYEES',           107,             (SELECT COUNT(*) FROM HR.employees)        FROM dual UNION ALL
SELECT 'JOB_HISTORY',          10,             (SELECT COUNT(*) FROM HR.job_history)      FROM dual
ORDER  BY 1;

PROMPT
PROMPT --> Si algun conteo real difiere del esperado, el esquema fue
PROMPT     modificado. Avisen al docente ANTES de continuar: varios
PROMPT     ejercicios del taller dependen de los datos originales.
PROMPT

PROMPT ====================================================================
PROMPT PASO 3. Casos borde de los que dependen los ejercicios
PROMPT ====================================================================

COLUMN caso_borde   FORMAT A38
COLUMN afectados    FORMAT 9999
COLUMN valor_original FORMAT 9999
COLUMN estado       FORMAT A10

SELECT c.caso_borde,
       c.afectados,
       c.valor_original,
       CASE WHEN c.afectados = c.valor_original THEN 'OK' ELSE 'ALTERADO' END AS estado
FROM  (
    SELECT 'Empleados sin jefe (manager_id nulo)'   AS caso_borde,
           (SELECT COUNT(*) FROM HR.employees WHERE manager_id IS NULL)     AS afectados,
           1 AS valor_original
    FROM dual
    UNION ALL
    SELECT 'Empleados sin departamento',
           (SELECT COUNT(*) FROM HR.employees WHERE department_id IS NULL),
           1
    FROM dual
    UNION ALL
    SELECT 'Empleados sin comision',
           (SELECT COUNT(*) FROM HR.employees WHERE commission_pct IS NULL),
           72
    FROM dual
    UNION ALL
    SELECT 'Departamentos sin empleados',
           (SELECT COUNT(*) FROM HR.departments d
            WHERE NOT EXISTS (SELECT 1 FROM HR.employees e
                              WHERE e.department_id = d.department_id)),
           16
    FROM dual
) c;

PROMPT
PROMPT ====================================================================
PROMPT PASO 4. Prueba rapida del comportamiento de los nulos
PROMPT ====================================================================
PROMPT La siguiente consulta DEBE devolver cero filas. Si devuelve filas,
PROMPT el esquema fue alterado y el ejercicio 6.5 pierde sentido.
PROMPT

SELECT COUNT(*) AS filas_devueltas
FROM   HR.employees
WHERE  employee_id NOT IN (SELECT manager_id FROM HR.employees);

PROMPT
PROMPT ====================================================================
PROMPT Verificacion terminada. A partir de aqui el taller es de solo
PROMPT lectura: no ejecuten INSERT, UPDATE, DELETE ni DDL sobre HR.
PROMPT ====================================================================

SET FEEDBACK ON
