-- =====================================================================
-- S14-carga-prestamos.sql
-- Carga un CSV de préstamos en biblioteca.prestamo.
--
-- Uso (desde la raíz del repo):
--   docker compose exec postgres psql -U curso -d curso -f /scripts/S14-carga-prestamos.sql
--   docker compose exec postgres psql -U curso -d curso \
--     -v archivo=/scripts/datos/prestamos_semilla_100.csv -f /scripts/S14-carga-prestamos.sql
--
-- Columnas esperadas (8):
-- id, id_lector, isbn, numero_ejemplar, id_bibliotecario, fecha_prestamo, fecha_esperada_devolucion, estado
-- =====================================================================
\set ON_ERROR_STOP on

\if :{?archivo}
\else
  \set archivo '/scripts/datos/prestamos_semilla_100.csv'
\endif

SET search_path TO biblioteca, public;

BEGIN;

-- Paso 1. Leer el archivo tal cual, una fila por línea.
CREATE TEMP TABLE stg_linea (
  n     INTEGER GENERATED ALWAYS AS IDENTITY,
  linea TEXT
) ON COMMIT DROP;

COPY stg_linea (linea) FROM :'archivo' WITH (FORMAT text);

-- Paso 2. Partir cada línea en campos (todo texto). 
CREATE TEMP TABLE stg_prestamo ON COMMIT DROP AS
SELECT n                                                   AS linea_csv,
       linea                                               AS contenido,
       cardinality(string_to_array(linea, ','))            AS num_campos,
       trim(split_part(linea, ',', 1))                     AS id_csv,
       trim(split_part(linea, ',', 2))                     AS id_lector,
       regexp_replace(trim(split_part(linea, ',', 3)), '[- ]', '', 'g') AS isbn,
       trim(split_part(linea, ',', 4))                     AS numero_ejemplar,
       trim(split_part(linea, ',', 5))                     AS id_bibliotecario,
       trim(split_part(linea, ',', 6))                     AS fecha_prestamo,
       trim(split_part(linea, ',', 7))                     AS fecha_esperada_devolucion,
       trim(split_part(linea, ',', 8))                     AS estado,
       NULL::text                                          AS motivo
FROM stg_linea
WHERE n > 1 AND trim(linea) <> '';

-- Paso 3. Validar. El CASE se evalúa en orden.
UPDATE stg_prestamo SET motivo = CASE
    WHEN num_campos <> 8                                   THEN 'tiene ' || num_campos || ' columnas, se esperaban 8'
    WHEN id_lector !~ '^[0-9]+$'                           THEN 'id_lector no es numérico'
    WHEN isbn !~ '^[0-9]{13}$'                             THEN 'isbn no tiene 13 dígitos'
    WHEN numero_ejemplar !~ '^[0-9]+$'                     THEN 'numero_ejemplar no es numérico'
    WHEN id_bibliotecario !~ '^[0-9]+$'                    THEN 'id_bibliotecario no es numérico'
    WHEN fecha_prestamo !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'  THEN 'fecha_prestamo no tiene formato YYYY-MM-DD'
    WHEN fecha_esperada_devolucion !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' THEN 'fecha_esperada_devolucion no tiene formato YYYY-MM-DD'
    WHEN fecha_esperada_devolucion::date < fecha_prestamo::date THEN 'fecha esperada de devolución es anterior al préstamo'
    WHEN estado NOT IN ('activo', 'en_mora', 'devuelto')   THEN 'estado inválido'
    WHEN NOT EXISTS (SELECT 1 FROM usuario u WHERE u.id = stg_prestamo.id_lector::integer AND u.id_rol = (SELECT id FROM rol WHERE nombre = 'lector')) 
                                                           THEN 'id_lector no existe o no tiene rol lector'
    WHEN NOT EXISTS (SELECT 1 FROM usuario u WHERE u.id = stg_prestamo.id_bibliotecario::integer AND u.id_rol = (SELECT id FROM rol WHERE nombre = 'bibliotecario')) 
                                                           THEN 'id_bibliotecario no existe o no tiene rol bibliotecario'
    WHEN NOT EXISTS (SELECT 1 FROM ejemplar e WHERE e.isbn = stg_prestamo.isbn AND e.numero_ejemplar = stg_prestamo.numero_ejemplar::integer) 
                                                           THEN 'el ejemplar (isbn + numero) no existe en el inventario'
END;

-- Paso 4. Duplicados dentro del archivo (por id_csv).
UPDATE stg_prestamo s
SET motivo = 'id de préstamo repetido en el archivo (primera aparición en línea '
             || (SELECT min(p.linea_csv) FROM stg_prestamo p WHERE p.id_csv = s.id_csv AND p.motivo IS NULL) || ')'
WHERE s.motivo IS NULL
  AND EXISTS (SELECT 1 FROM stg_prestamo p
              WHERE p.id_csv = s.id_csv AND p.motivo IS NULL AND p.linea_csv < s.linea_csv);

-- Paso 5. Pasar las válidas a la tabla final. 
-- Nota: Omitimos el id_csv para que la base de datos genere el IDENTITY automáticamente, o lo mapeamos si es necesario.
INSERT INTO prestamo (id_lector, isbn, numero_ejemplar, id_bibliotecario, fecha_prestamo, fecha_esperada_devolucion, estado)
SELECT id_lector::integer, isbn, numero_ejemplar::integer, id_bibliotecario::integer, 
       fecha_prestamo::date, fecha_esperada_devolucion::date, estado::estado_prestamo
FROM stg_prestamo
WHERE motivo IS NULL;

-- Paso 6. Bitácora de rechazos.
INSERT INTO rechazo_carga (archivo, linea, contenido, motivo)
SELECT :'archivo', linea_csv, contenido, motivo
FROM stg_prestamo
WHERE motivo IS NOT NULL;

-- Resumen
SELECT count(*) FILTER (WHERE motivo IS NULL)     AS cargadas,
       count(*) FILTER (WHERE motivo IS NOT NULL) AS rechazadas
FROM stg_prestamo;

SELECT linea_csv AS linea, motivo, contenido
FROM stg_prestamo
WHERE motivo IS NOT NULL
ORDER BY linea_csv;

COMMIT;
