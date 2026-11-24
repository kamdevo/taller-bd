-- =====================================================================
-- carga-libros.sql
-- Carga un CSV de libros en biblioteca.libro + biblioteca.ejemplar.
--
-- Uso (desde la raíz del repo):
--   docker compose exec postgres psql -U curso -d curso -f /scripts/carga-libros.sql
--   docker compose exec postgres psql -U curso -d curso \
--     -v archivo=/scripts/datos/libros_semilla_con_errores.csv -f /scripts/carga-libros.sql
--
-- Columnas esperadas (6):
--   isbn, titulo, autor, categoria, anio_publicacion, ejemplares_disponibles
--
-- Patrón: COPY a tabla de paso (todo texto) -> validar -> tabla final -> bitácora.
-- Todo en una transacción. Se puede repetir sin duplicar datos.
-- =====================================================================
\set ON_ERROR_STOP on

\if :{?archivo}
\else
  \set archivo '/scripts/datos/libros_semilla.csv'
\endif

SET search_path TO biblioteca, public;

BEGIN;

-- Paso 1. Leer el archivo tal cual, una fila por línea (FORMAT text: el separador
-- es el tabulador, que no aparece en el CSV, así que ninguna línea se pierde).
CREATE TEMP TABLE stg_linea (
  n     INTEGER GENERATED ALWAYS AS IDENTITY,
  linea TEXT
) ON COMMIT DROP;

COPY stg_linea (linea) FROM :'archivo' WITH (FORMAT text);

-- Paso 2. Partir cada línea en campos (todo texto). La línea 1 (encabezado) y las
-- líneas en blanco se omiten, pero n conserva el número de línea original.
-- Corrección mecánica: el ISBN se normaliza quitando guiones y espacios.
CREATE TEMP TABLE stg_libro ON COMMIT DROP AS
SELECT n                                                   AS linea_csv,
       linea                                               AS contenido,
       cardinality(string_to_array(linea, ','))            AS num_campos,
       regexp_replace(trim(split_part(linea, ',', 1)), '[- ]', '', 'g') AS isbn,
       trim(split_part(linea, ',', 2))                     AS titulo,
       trim(split_part(linea, ',', 3))                     AS autor,
       trim(split_part(linea, ',', 4))                     AS categoria,
       trim(split_part(linea, ',', 5))                     AS anio_publicacion,
       trim(split_part(linea, ',', 6))                     AS ejemplares_disponibles,
       NULL::text                                          AS motivo
FROM stg_linea
WHERE n > 1 AND trim(linea) <> '';

-- Paso 3. Validar. El CASE se evalúa en orden: la primera regla que falla da el motivo.
-- Las comprobaciones de formato (regex) van ANTES de los casts, para que el cast sea seguro.
UPDATE stg_libro SET motivo = CASE
    WHEN num_campos <> 6                          THEN 'tiene ' || num_campos || ' columnas, se esperaban 6'
    WHEN isbn = ''                                THEN 'isbn vacío'
    WHEN isbn !~ '^[0-9]{13}$'                    THEN 'isbn no tiene 13 dígitos'
    WHEN titulo = ''                              THEN 'título vacío'
    WHEN autor = ''                               THEN 'autor vacío'
    WHEN length(titulo) > 200                     THEN 'título supera 200 caracteres'
    WHEN length(autor) > 150                      THEN 'autor supera 150 caracteres'
    WHEN length(categoria) > 80                   THEN 'categoría supera 80 caracteres'
    WHEN anio_publicacion !~ '^[0-9]{1,4}$'       THEN 'año no numérico'
    WHEN anio_publicacion::integer NOT BETWEEN 1450 AND extract(year FROM current_date)::integer
                                                  THEN 'año fuera de rango'
    WHEN ejemplares_disponibles !~ '^-?[0-9]{1,4}$' THEN 'ejemplares no numérico'
    WHEN ejemplares_disponibles::integer < 0      THEN 'ejemplares negativo'
    WHEN EXISTS (SELECT 1 FROM libro l WHERE l.isbn = stg_libro.isbn)
                                                  THEN 'isbn ya existe en el catálogo'
END;

-- Paso 4. Duplicados dentro del mismo archivo: se conserva la primera aparición.
UPDATE stg_libro s
SET motivo = 'isbn repetido en el archivo (primera aparición en la línea '
             || (SELECT min(p.linea_csv) FROM stg_libro p WHERE p.isbn = s.isbn AND p.motivo IS NULL) || ')'
WHERE s.motivo IS NULL
  AND EXISTS (SELECT 1 FROM stg_libro p
              WHERE p.isbn = s.isbn AND p.motivo IS NULL AND p.linea_csv < s.linea_csv);

-- Paso 5. Pasar las válidas a las tablas finales.
-- Criterio: categoría vacía se carga como NULL (la columna lo admite).
INSERT INTO libro (isbn, titulo, autor, categoria, anio_publicacion)
SELECT isbn, titulo, autor, NULLIF(categoria, ''), anio_publicacion::integer
FROM stg_libro
WHERE motivo IS NULL;

-- ejemplares_disponibles = n  ->  n filas en ejemplar (copias 1..n)
INSERT INTO ejemplar (isbn, numero_ejemplar)
SELECT s.isbn, g.n
FROM stg_libro s
CROSS JOIN LATERAL generate_series(1, s.ejemplares_disponibles::integer) AS g(n)
WHERE s.motivo IS NULL;

-- Paso 6. Bitácora de rechazos (conserva archivo, línea, contenido original y motivo).
INSERT INTO rechazo_carga (archivo, linea, contenido, motivo)
SELECT :'archivo', linea_csv, contenido, motivo
FROM stg_libro
WHERE motivo IS NOT NULL;

-- Resumen de esta corrida (now() es constante dentro de la transacción)
SELECT count(*) FILTER (WHERE motivo IS NULL)     AS cargadas,
       count(*) FILTER (WHERE motivo IS NOT NULL) AS rechazadas
FROM stg_libro;

SELECT linea, motivo, contenido
FROM rechazo_carga
WHERE fecha = now() AND archivo = :'archivo'
ORDER BY linea;

COMMIT;
