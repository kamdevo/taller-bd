-- =====================================================================
-- reportes.sql  ·  S16 Parte B · Los cuatro reportes del proyecto
-- Esquema: biblioteca (postgres/init/01_esquema.sql)
--
-- Uso (desde la raíz del repo, después de datos-prueba.sql):
--   docker compose exec postgres psql -U curso -d curso -f /scripts/reportes.sql
--
-- Cada reporte queda guardado como VISTA (para la API de M7) y luego se
-- consulta. Se puede correr cuantas veces se quiera (CREATE OR REPLACE).
--
-- DECISIONES DEL GRUPO (comunes a los 4 reportes)
--  * Lector = usuario con rol 'lector' (tabla usuario, opción 2 de S11).
--    Nombre, correo y teléfono están en usuario.
--  * El préstamo apunta a un ejemplar (isbn + numero_ejemplar), pero como el
--    ejemplar guarda el isbn, prestamo.isbn llega directo a libro: los
--    reportes agrupan por LIBRO (título), no por copia.
--  * Préstamo DEVUELTO  = estado = 'devuelto' (lo registra el bibliotecario
--    en el momento de la devolución, junto con la fila de devolucion).
--  * Préstamo EN MORA   = estado <> 'devuelto' AND fecha_esperada_devolucion < CURRENT_DATE.
--    La mora se CALCULA con fechas: la columna estado = 'en_mora' no se
--    actualiza sola cuando pasa la fecha (no hay trigger hasta el Hito 4),
--    así que no se confía en ella (S15 §8.5).
--  * Un préstamo que vence HOY todavía no está en mora ("<" estricto).
-- =====================================================================
\set ON_ERROR_STOP on
SET search_path TO biblioteca, public;


-- ---------------------------------------------------------------------
-- Reporte 1. Los 20 libros más prestados.
-- Devuelve: isbn, título, autor y número de préstamos (todos, abiertos y devueltos).
-- Decisiones:
--  * LEFT JOIN desde libro + count(p.id): los libros nunca prestados
--    aparecen con 0 (en una base recién cargada el reporte no queda vacío).
--  * LIMIT 20 con desempate por título (orden alfabético)
-- si hay empate en el puesto 20, entra el que va primero en el alfabeto
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW reporte_libros_mas_prestados AS
SELECT l.isbn, l.titulo, l.autor, count(p.id) AS prestamos
FROM libro l
LEFT JOIN prestamo p ON p.isbn = l.isbn
GROUP BY l.isbn, l.titulo, l.autor
ORDER BY prestamos DESC, titulo ASC
LIMIT 20;


\echo '=== Reporte 1: los 20 libros más prestados (con empates) ==='
SELECT * FROM reporte_libros_mas_prestados ORDER BY prestamos DESC, titulo;

-- Reporte 1b (solo prueba del caso 2): el mismo reporte con top 3.
-- Esperado: 4 filas, porque Ficciones y Pedro Páramo empatan en el 3.er puesto.
\echo '=== Reporte 1b (prueba de empates): top 3 con WITH TIES ==='
SELECT * FROM (
  SELECT l.titulo, count(p.id) AS prestamos
  FROM libro l
  LEFT JOIN prestamo p ON p.isbn = l.isbn
  GROUP BY l.isbn, l.titulo
  ORDER BY prestamos DESC
  FETCH FIRST 3 ROWS WITH TIES
) t
ORDER BY prestamos DESC, titulo;


-- ---------------------------------------------------------------------
-- Reporte 2. El o los lectores que más libros han leído.
-- Devuelve: documento, nombres, apellidos y número de libros leídos.
-- Decisiones:
--  * "Libro leído" = préstamo DEVUELTO (estado = 'devuelto'). Un lector con
--    muchos préstamos abiertos no gana por retener libros.
--  * "El o los": se comparan contra el máximo (= max), así que salen todos
--    los empatados en el primer lugar (no se usa LIMIT 1).
-- Esperado: Mariana Gómez Rojas 3 y Santiago Rodríguez Pérez 3.
--   Juan David Martínez (3 préstamos, 0 devueltos) no sale.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW reporte_lectores_que_mas_leen AS
WITH leidos AS (
  SELECT p.id_lector, count(*) AS libros_leidos
  FROM prestamo p
  WHERE p.estado = 'devuelto'
  GROUP BY p.id_lector
)
SELECT u.documento, u.nombres, u.apellidos, x.libros_leidos
FROM leidos x
JOIN usuario u ON u.id = x.id_lector
WHERE u.id_rol = (SELECT id FROM rol WHERE nombre = 'lector')
  AND x.libros_leidos = (SELECT max(libros_leidos) FROM leidos);

\echo '=== Reporte 2: el o los lectores que más libros han leído ==='
SELECT * FROM reporte_lectores_que_mas_leen ORDER BY apellidos, nombres;


-- ---------------------------------------------------------------------
-- Reporte 3. Lectores morosos.
-- Devuelve: documento, nombres y apellidos de cada lector con al menos un
-- préstamo vencido y no devuelto, UNA sola vez.
-- Decisiones:
--  * EXISTS en vez de JOIN: un lector con varios préstamos en mora no se
--    repite (no hace falta DISTINCT ni GROUP BY).
--  * Mora calculada con fechas ("<" estricto): ver decisiones comunes.
-- Esperado: Camila Hernández Torres, Valentina López Díaz y
--   Juan David Martínez Ruiz (3 filas). Santiago (devolvió tarde) no sale.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW reporte_lectores_morosos AS
SELECT u.documento, u.nombres, u.apellidos
FROM usuario u
WHERE EXISTS (SELECT 1
              FROM prestamo p
              WHERE p.id_lector = u.id
                AND p.estado <> 'devuelto'                       -- no devuelto
                AND p.fecha_esperada_devolucion < CURRENT_DATE); -- y ya vencido

\echo '=== Reporte 3: lectores morosos ==='
SELECT * FROM reporte_lectores_morosos ORDER BY apellidos, nombres;


-- ---------------------------------------------------------------------
-- Reporte 4. Préstamos en mora (la lista del botón "Enviar notificación").
-- Devuelve: una fila por PRÉSTAMO en mora, con el lector, su correo, su
-- teléfono, el libro, la fecha esperada y los días de mora.
-- Decisiones:
--  * La unidad es el préstamo, no el lector: un lector con dos préstamos
--    en mora sale dos veces (una por libro), así la notificación dice qué
--    libro debe y desde cuándo.
--  * Misma condición de mora que el reporte 3 ("<" estricto).
--  * dias_mora = CURRENT_DATE - fecha esperada (resta de date = días).
-- Esperado (4 filas): Juan David / Ficciones 26, Valentina / La sombra del
--   viento 16, Juan David / Cien años de soledad 6, Camila / Pedro Páramo 2.
--   Rayuela de Juan David (vence hoy) no sale.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW reporte_prestamos_en_mora AS
SELECT p.id                                  AS id_prestamo,
       u.nombres || ' ' || u.apellidos       AS lector,
       u.correo,
       u.telefono,
       l.titulo,
       p.fecha_esperada_devolucion,
       CURRENT_DATE - p.fecha_esperada_devolucion AS dias_mora
FROM prestamo p
JOIN usuario u ON u.id   = p.id_lector
JOIN libro   l ON l.isbn = p.isbn
WHERE p.estado <> 'devuelto'
  AND p.fecha_esperada_devolucion < CURRENT_DATE;

\echo '=== Reporte 4: préstamos en mora ==='
SELECT * FROM reporte_prestamos_en_mora ORDER BY dias_mora DESC, lector;
