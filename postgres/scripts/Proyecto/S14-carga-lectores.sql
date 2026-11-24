-- =====================================================================
-- carga-lectores.sql
-- Carga un CSV de lectores en biblioteca.usuario (con id_rol = 'lector').
--
-- Uso (desde la raíz del repo):
--   docker compose exec postgres psql -U curso -d curso -f /scripts/carga-lectores.sql
--   docker compose exec postgres psql -U curso -d curso \
--     -v archivo=/scripts/datos/lectores_semilla_con_errores.csv -f /scripts/carga-lectores.sql
--
-- Columnas esperadas (5):  documento, nombres, apellidos, correo, telefono
-- >>> Si el CSV del curso tiene otro orden o más columnas, ajustar num_campos,
-- >>> los split_part del paso 2 y las reglas del paso 3.
--
-- Contraseña inicial: usuario.password_hash es NOT NULL y el CSV no la trae.
-- Se guarda con hash bcrypt del documento (pgcrypto), nunca en texto plano.
-- =====================================================================
\set ON_ERROR_STOP on

\if :{?archivo}
\else
  \set archivo '/scripts/datos/lectores_semilla.csv'
\endif

SET search_path TO biblioteca, public;

BEGIN;

-- Paso 1. Leer el archivo, una fila por línea.
CREATE TEMP TABLE stg_linea (
  n     INTEGER GENERATED ALWAYS AS IDENTITY,
  linea TEXT
) ON COMMIT DROP;

COPY stg_linea (linea) FROM :'archivo' WITH (FORMAT text);

-- Paso 2. Partir en campos. Correcciones mecánicas: trim y correo en minúsculas.
CREATE TEMP TABLE stg_lector ON COMMIT DROP AS
SELECT n                                          AS linea_csv,
       linea                                      AS contenido,
       cardinality(string_to_array(linea, ','))   AS num_campos,
       trim(split_part(linea, ',', 1))            AS documento,
       trim(split_part(linea, ',', 2))            AS nombres,
       trim(split_part(linea, ',', 3))            AS apellidos,
       lower(trim(split_part(linea, ',', 4)))     AS correo,
       trim(split_part(linea, ',', 5))            AS telefono,
       NULL::text                                 AS motivo
FROM stg_linea
WHERE n > 1 AND trim(linea) <> '';

-- Paso 3. Validar (primera regla que falla = motivo).
UPDATE stg_lector SET motivo = CASE
    WHEN num_campos <> 5                           THEN 'tiene ' || num_campos || ' columnas, se esperaban 5'
    WHEN documento = ''                            THEN 'documento vacío'
    WHEN documento !~ '^[A-Za-z0-9]{4,20}$'        THEN 'documento con formato inválido'
    WHEN nombres = ''                              THEN 'nombres vacío'
    WHEN apellidos = ''                            THEN 'apellidos vacío'
    WHEN length(nombres) > 100 OR length(apellidos) > 100
                                                   THEN 'nombre o apellido supera 100 caracteres'
    WHEN correo = ''                               THEN 'correo vacío'
    WHEN correo !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'
                                                   THEN 'correo inválido'
    WHEN length(correo) > 150                      THEN 'correo supera 150 caracteres'
    WHEN telefono <> '' AND telefono !~ '^[0-9+() -]{7,20}$'
                                                   THEN 'teléfono con formato inválido'
    WHEN EXISTS (SELECT 1 FROM usuario u WHERE u.documento = stg_lector.documento)
                                                   THEN 'documento ya existe en usuarios'
    WHEN EXISTS (SELECT 1 FROM usuario u WHERE u.correo = stg_lector.correo)
                                                   THEN 'correo ya existe en usuarios'
END;

-- Paso 4. Duplicados dentro del archivo (documento y correo): se conserva la primera aparición.
UPDATE stg_lector s
SET motivo = 'documento repetido en el archivo (primera aparición en la línea '
             || (SELECT min(p.linea_csv) FROM stg_lector p WHERE p.documento = s.documento AND p.motivo IS NULL) || ')'
WHERE s.motivo IS NULL
  AND EXISTS (SELECT 1 FROM stg_lector p
              WHERE p.documento = s.documento AND p.motivo IS NULL AND p.linea_csv < s.linea_csv);

UPDATE stg_lector s
SET motivo = 'correo repetido en el archivo (primera aparición en la línea '
             || (SELECT min(p.linea_csv) FROM stg_lector p WHERE p.correo = s.correo AND p.motivo IS NULL) || ')'
WHERE s.motivo IS NULL
  AND EXISTS (SELECT 1 FROM stg_lector p
              WHERE p.correo = s.correo AND p.motivo IS NULL AND p.linea_csv < s.linea_csv);

-- Paso 5. Insertar las válidas como usuarios con rol 'lector'.
INSERT INTO usuario (documento, nombres, apellidos, correo, telefono, password_hash, id_rol)
SELECT s.documento, s.nombres, s.apellidos, s.correo, NULLIF(s.telefono, ''),
       crypt(s.documento, gen_salt('bf')),
       (SELECT id FROM rol WHERE nombre = 'lector')
FROM stg_lector s
WHERE s.motivo IS NULL;

-- Paso 6. Bitácora.
INSERT INTO rechazo_carga (archivo, linea, contenido, motivo)
SELECT :'archivo', linea_csv, contenido, motivo
FROM stg_lector
WHERE motivo IS NOT NULL;

SELECT count(*) FILTER (WHERE motivo IS NULL)     AS cargadas,
       count(*) FILTER (WHERE motivo IS NOT NULL) AS rechazadas
FROM stg_lector;

SELECT linea, motivo, contenido
FROM rechazo_carga
WHERE fecha = now() AND archivo = :'archivo'
ORDER BY linea;

COMMIT;
