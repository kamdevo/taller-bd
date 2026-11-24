-- =====================================================================
-- normalizacion.sql  ·  Hito 3 (S20, parte B)
-- Script de normalización del esquema "biblioteca".
--
-- Integrantes: José Manuel Cardona Gil - 2521653
--              Juan Camilo Morales - 2515391
--              Andres Felipe Rengifo - 2519613
--              Jorge Luis Castro - 2517065

--
-- Uso (desde la raíz del repo, sobre la base que YA tiene el esquema del Hito 2):
--   docker compose exec -T postgres psql -U curso -d curso -f /scripts/normalizacion.sql
--   y después, para recrear los reportes:
--   docker compose exec -T postgres psql -U curso -d curso -f /scripts/reportes.sql
--
-- Todo corre en UNA transacción: si algo falla, la base queda como estaba.
-- Para probarlo sin tocar la base del grupo, usar una base aparte (prueba_init).
-- =====================================================================
\set ON_ERROR_STOP on


-- ---------------------------------------------------------------------
-- DECISIONES POR TABLA
-- ---------------------------------------------------------------------

-- Tabla ROL: no recibe ningún cambio porque es un catálogo estático.

-- Tabla USUARIO: se evaluó eliminar el id, ya que el documento es siempre diferente
-- para todas las personas y podría ser la PK.
    -- DECISIÓN: Se conserva id como PK sustituta porque permite corregir documento o
    -- correo con un solo UPDATE sobre una fila, sin propagar el cambio a prestamo y
    -- devolucion. Ambos siguen protegidos con UNIQUE como claves candidatas.

-- Tabla LIBRO: se evaluó crear una tabla de autores por si un libro tiene más de un
-- autor; también habría que decidir si las categorías serían una tabla estática o un string.
    -- DECISIÓN: Ya que el proyecto solo nos pide un autor por libro, no vemos necesario
    -- poner una tabla de autores.

-- Tabla EJEMPLAR: error en el estado (guardaba un dato que se puede calcular).
    -- DECISIÓN: modificar estado como un booleano donde
        -- true significa que el ejemplar del libro existe en la biblioteca (puede estar
        --   disponible para prestar o estar siendo prestado)
        -- false identifica que un ejemplar del libro no es prestable por alguna razón (baja)
        -- (Saber si un ejemplar está prestado lo define la tabla prestamo y no la tabla
        --   ejemplar, que solo dice si está activo o no con el booleano)

-- Tabla PRESTAMO: error con el estado; es mejor calcularlo mediante una vista.

-- Tabla DEVOLUCION: el id es redundante; id_prestamo pasa a ser la PK.

-- Tabla RECHAZO_CARGA: SE CONSERVA. Es la bitácora que escriben los tres scripts de
-- carga (S14) y la evidencia de "validación con bitácora" del Hito 2. No puede ser una
-- vista: las filas rechazadas no existen en ninguna otra tabla de donde leerlas.


SET search_path TO biblioteca, public;
BEGIN; -- Iniciar la transacción

-- ---------------------------------------------------------------------
-- 0. Conteos ANTES (para comparar al final)
-- ---------------------------------------------------------------------
CREATE TEMP TABLE conteo_antes ON COMMIT DROP AS
SELECT 'ejemplar' AS tabla, count(*) AS filas FROM ejemplar
UNION ALL SELECT 'ejemplar_baja', count(*) FROM ejemplar WHERE estado = 'baja'
UNION ALL SELECT 'prestamo',      count(*) FROM prestamo
UNION ALL SELECT 'devolucion',    count(*) FROM devolucion;

-- Protección: un préstamo marcado 'devuelto' SIN fila en devolucion perdería su
-- condición de devuelto al calcular el estado. Si existe alguno, se detiene todo.
DO $$
DECLARE n integer;
BEGIN
  SELECT count(*) INTO n
  FROM prestamo p
  WHERE p.estado = 'devuelto'
    AND NOT EXISTS (SELECT 1 FROM devolucion d WHERE d.id_prestamo = p.id);
  IF n > 0 THEN
    RAISE EXCEPTION '% préstamo(s) marcados "devuelto" no tienen fila en devolucion. Registrar sus devoluciones antes de migrar.', n;
  END IF;
END $$;


-- ---------------------------------------------------------------------
-- 1. EJEMPLAR: estado -> activo (booleano)
-- ---------------------------------------------------------------------
-- Crea una nueva columna para ejemplar con datos booleanos, que no puede estar vacía
-- y se inicializa con true
ALTER TABLE ejemplar ADD COLUMN activo BOOLEAN NOT NULL DEFAULT true;
-- Actualiza la columna activo cuando encuentra un estado 'baja'
UPDATE ejemplar SET activo = false WHERE estado = 'baja';

-- Creamos una vista para saber el estado de un ejemplar mediante una consulta
CREATE VIEW ejemplar_estado AS
SELECT e.isbn, e.numero_ejemplar, e.activo,
    CASE -- funciona como un "dependiendo del caso"
        WHEN NOT e.activo THEN 'baja' -- si el ejemplar no está activo, colocar baja
        WHEN EXISTS (                 -- si existe un préstamo de ese ejemplar que no esté devuelto, colocar prestado
            SELECT 1 FROM prestamo p
            WHERE p.isbn = e.isbn AND p.numero_ejemplar = e.numero_ejemplar
              AND NOT EXISTS (SELECT 1 FROM devolucion d WHERE d.id_prestamo = p.id)
        ) THEN 'prestado'
        ELSE 'disponible' -- de lo contrario, colocar disponible
    END AS estado -- en la columna estado de esta vista
FROM ejemplar e;

-- Bloque de verificación
-- Compara el estado viejo (guardado) con el nuevo (calculado). Que haya diferencias NO
-- detiene la migración: el estado guardado no tenía quién lo mantuviera al día, así que las diferencias son la evidencia de la anomalía.
-- Lo que sí debe coincidir siempre es la baja.
DO $$ -- para poder ejecutar un bloque con IF
DECLARE n integer;
BEGIN
  SELECT count(*) INTO n
  FROM ejemplar e
  JOIN ejemplar_estado v USING (isbn, numero_ejemplar) -- USING es lo mismo que ON, pero más limpio
  WHERE e.estado::text <> v.estado; -- si encuentra una diferencia entre el estado viejo y el nuevo
  RAISE NOTICE 'ejemplar: % fila(s) con estado guardado distinto del calculado (evidencia)', n;

  IF EXISTS (SELECT 1 FROM ejemplar e JOIN ejemplar_estado v USING (isbn, numero_ejemplar)
             WHERE (e.estado = 'baja') <> (v.estado = 'baja')) THEN
    RAISE EXCEPTION 'Las bajas no coinciden entre el estado viejo y el calculado.';
  END IF;
END $$;

-- Eliminar lo viejo
ALTER TABLE ejemplar DROP COLUMN estado; -- eliminamos la columna que no sirve
DROP TYPE estado_ejemplar;               -- eliminamos el tipo ENUM


-- ---------------------------------------------------------------------
-- 2. PRESTAMO: el estado se calcula mediante una vista
-- ---------------------------------------------------------------------
-- 2.1 Vista que calcula el estado de cada préstamo
CREATE VIEW prestamo_estado AS
SELECT p.id, p.id_lector, p.isbn, p.numero_ejemplar, p.id_bibliotecario,
       p.fecha_prestamo, p.fecha_esperada_devolucion,
       d.fecha_devolucion,
       CASE
         WHEN d.id_prestamo IS NOT NULL THEN 'devuelto' -- cuando el id está en la tabla devolucion, colocar devuelto
         WHEN p.fecha_esperada_devolucion < CURRENT_DATE THEN 'en_mora' -- (CURRENT_DATE devuelve la fecha actual) si la fecha esperada de devolución es menor que hoy, colocar en_mora
         ELSE 'activo' -- de lo contrario, colocar activo
       END AS estado
FROM prestamo p
LEFT JOIN devolucion d ON d.id_prestamo = p.id;

-- 2.2 Evidencia de problemas hasta el día de hoy: préstamos cuyo estado guardado no
-- coincide con el calculado (con los datos de prueba salen los préstamos 7 y 12:
-- guardados como 'activo' aunque ya vencieron)
SELECT p.id, p.estado AS guardado, v.estado AS calculado
FROM prestamo p
JOIN prestamo_estado v ON v.id = p.id
WHERE p.estado::text <> v.estado;

-- 2.3 Los reportes de S16 usaban prestamo.estado: hay que quitarlos antes de borrar la
-- columna (se recrean con reportes.sql, que ya usa la vista prestamo_estado)
DROP VIEW IF EXISTS reporte_lectores_que_mas_leen;
DROP VIEW IF EXISTS reporte_lectores_morosos;
DROP VIEW IF EXISTS reporte_prestamos_en_mora;

-- 2.4 Quitar lo viejo
ALTER TABLE prestamo DROP COLUMN estado;
DROP TYPE estado_prestamo;

-- 2.5 Índices en las columnas de las llaves foráneas (PostgreSQL no los crea solo).
-- Son los que usan la vista ejemplar_estado y los reportes.
CREATE INDEX IF NOT EXISTS prestamo_ejemplar_idx ON prestamo (isbn, numero_ejemplar);
CREATE INDEX IF NOT EXISTS prestamo_lector_idx   ON prestamo (id_lector);


-- ---------------------------------------------------------------------
-- 3. DEVOLUCION: se elimina el id redundante; id_prestamo pasa a ser la PK
-- ---------------------------------------------------------------------
-- 3.1 Guardar los datos para verificar después
CREATE TEMP TABLE devolucion_antes ON COMMIT DROP AS
SELECT id_prestamo, id_bibliotecario, fecha_devolucion FROM devolucion;

-- 3.2 Cambiar la clave primaria
ALTER TABLE devolucion DROP CONSTRAINT devolucion_id_prestamo_key; -- el UNIQUE ya no hace falta
ALTER TABLE devolucion DROP COLUMN id;                             -- también elimina la PK vieja
ALTER TABLE devolucion ADD PRIMARY KEY (id_prestamo);

-- 3.3 Verificar: no se perdió ni se inventó ninguna fila (ambas deben dar 0 filas)
SELECT * FROM devolucion_antes
EXCEPT
SELECT id_prestamo, id_bibliotecario, fecha_devolucion FROM devolucion;

SELECT id_prestamo, id_bibliotecario, fecha_devolucion FROM devolucion
EXCEPT
SELECT * FROM devolucion_antes;


-- ---------------------------------------------------------------------
-- 4. Conteos DESPUÉS: deben coincidir con los de antes
-- ---------------------------------------------------------------------
CREATE TEMP TABLE conteo_despues ON COMMIT DROP AS
SELECT 'ejemplar' AS tabla, count(*) AS filas FROM ejemplar
UNION ALL SELECT 'ejemplar_baja', count(*) FROM ejemplar WHERE NOT activo
UNION ALL SELECT 'prestamo',      count(*) FROM prestamo
UNION ALL SELECT 'devolucion',    count(*) FROM devolucion;

SELECT a.tabla, a.filas AS antes, d.filas AS despues, (a.filas = d.filas) AS coincide
FROM conteo_antes a JOIN conteo_despues d USING (tabla)
ORDER BY a.tabla;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM conteo_antes a JOIN conteo_despues d USING (tabla)
            WHERE a.filas <> d.filas) THEN
    RAISE EXCEPTION 'Los conteos antes y después no coinciden: se cancela la migración.';
  END IF;
END $$;

COMMIT;

-- Siguiente paso: correr reportes.sql para recrear las vistas de los 4 reportes.
