-- =====================================================================
-- datos-prueba.sql  ·  S16 Parte B · Datos de prueba de los 4 reportes
--
-- Requisitos: esquema biblioteca (postgres/init/01_esquema.sql) con los
-- libros y lectores semilla ya cargados (S14-carga-libros.sql y
-- S14-carga-lectores.sql con libros_semilla.csv y lectores_semilla.csv).
--
-- Uso (desde la raíz del repo):
--   docker compose exec postgres psql -U curso -d curso -f /scripts/datos-prueba.sql
--   docker compose exec postgres psql -U curso -d curso -f /scripts/reportes.sql
--
-- El script BORRA todos los préstamos y devoluciones y carga 13 préstamos
-- diseñados para los 8 casos de la sección 4 de S16. Se puede correr
-- cuantas veces se quiera. Todas las fechas son relativas a CURRENT_DATE
-- (hoy = d), así que los casos de mora siguen siéndolo cualquier día.
--
-- Lectores y libros se referencian por documento e ISBN (no por id), para
-- que el script no dependa del orden en que se generaron los IDENTITY.
--
-- ---------------------------------------------------------------------
-- PRÉSTAMOS DE PRUEBA (escritos ANTES de correr los reportes)
-- ---------------------------------------------------------------------
--  #  Lector (documento)          Libro (ISBN)                 Prestado  Esperada  Devuelto  Estado guardado
--  1  Mariana   (1000000001)      Cien años de soledad (..01)  d-60      d-46      d-50      devuelto
--  2  Mariana                     Rayuela              (..04)  d-45      d-31      d-35      devuelto
--  3  Mariana                     Ficciones            (..07)  d-30      d-16      d-20      devuelto
--  4  Santiago  (1000000002)      Cien años de soledad         d-55      d-41      d-42      devuelto
--  5  Santiago                    Rayuela                      d-40      d-26      d-27      devuelto
--  6  Santiago                    Don Quijote          (..09)  d-35      d-21      d-10      devuelto   <- caso 5 (devuelto tarde)
--  7  Juan David (1000000004)     Ficciones                    d-40      d-26      -         activo     <- mora 26 días (estado sin actualizar)
--  8  Juan David                  Cien años de soledad         d-20      d-6       -         en_mora    <- mora 6 días
--  9  Juan David                  Rayuela                      d-14      d         -         activo     <- caso 6 (vence hoy)
-- 10  Valentina (1000000003)      La sombra del viento (..10)  d-30      d-16      -         en_mora    <- mora 16 días
-- 11  Valentina                   Cien años de soledad         d-9       d+5       -         activo     (a tiempo)
-- 12  Camila    (1000000005)      Pedro Páramo         (..05)  d-16      d-2       -         activo     <- mora 2 días (estado sin actualizar)
-- 13  Camila                      Pedro Páramo                 d-70      d-56      d-58      devuelto
--  Nicolás (1000000012) no tiene préstamos  <- caso 8
--  El Aleph (..08) y el resto del catálogo no tienen préstamos  <- caso 1
--
-- Los préstamos 7 y 12 quedan con estado 'activo' aunque ya vencieron: así
-- se comprueba que los reportes calculan la mora con las fechas y no
-- confían en la columna estado (S15 §8.5: no hay trigger que la actualice).
--
-- ---------------------------------------------------------------------
-- RESULTADOS ESPERADOS (decididos antes de correr nada)
-- ---------------------------------------------------------------------
-- Reporte 1 (top 20 con empates, incluye libros con 0):
--   Cien años de soledad 4, Rayuela 3, Ficciones 2, Pedro Páramo 2,
--   Don Quijote 1, La sombra del viento 1, y después todos los demás libros
--   del catálogo con 0 (empatados en el puesto 7, así que WITH TIES los
--   incluye a todos: El Aleph aparece con 0).            -> casos 1 y 2
--   Reporte 1b (top 3 con WITH TIES): 4 filas, porque Ficciones y
--   Pedro Páramo empatan en el 3.er puesto.               -> caso 2
-- Reporte 2: Mariana Gómez Rojas 3 y Santiago Rodríguez Pérez 3 (empate).
--   Juan David tiene 3 préstamos pero 0 devueltos: no sale. -> casos 3 y 4
-- Reporte 3: Camila Hernández, Valentina López, Juan David Martínez
--   (3 filas, cada uno una vez). Santiago no sale (devolvió tarde pero
--   devolvió). Juan David no sale "dos veces".            -> casos 5, 7
-- Reporte 4: 4 filas, de más a menos días de mora:
--   Juan David / Ficciones 26, Valentina / La sombra del viento 16,
--   Juan David / Cien años de soledad 6, Camila / Pedro Páramo 2.
--   Rayuela de Juan David (vence hoy) NO sale: regla "<" estricto.
--   Santiago (devuelto tarde) NO sale.                    -> casos 5, 6, 7
-- Nicolás no aparece en ningún reporte ni rompe nada.     -> caso 8
-- =====================================================================
\set ON_ERROR_STOP on
SET search_path TO biblioteca, public;

BEGIN;

-- 1. Bibliotecario que registra los préstamos y devoluciones.
INSERT INTO usuario (documento, nombres, apellidos, correo, telefono, password_hash, id_rol)
VALUES ('9000000001', 'Bibliotecario', 'De Prueba', 'bibliotecario.prueba@correo-ejemplo.edu.co',
        '3009000001', crypt('9000000001', gen_salt('bf')),
        (SELECT id FROM rol WHERE nombre = 'bibliotecario'))
ON CONFLICT (documento) DO NOTHING;

-- 2. Empezar de cero: los reportes se prueban solo con estos préstamos.
--    RESTART IDENTITY reinicia los id, así los préstamos quedan con id 1 a 13
--    en el mismo orden de la lista de abajo.
TRUNCATE devolucion, prestamo RESTART IDENTITY;
UPDATE ejemplar SET estado = 'disponible' WHERE estado = 'prestado';

-- 3. Los 13 préstamos (d = CURRENT_DATE).
--    El JOIN con usuario traduce el documento del lector a su id.
INSERT INTO prestamo (id_lector, isbn, numero_ejemplar, id_bibliotecario,
                      fecha_prestamo, fecha_esperada_devolucion, estado)
SELECT u.id, v.isbn, v.ejemplar,
       (SELECT id FROM usuario WHERE documento = '9000000001'),
       CURRENT_DATE + v.dias_prestamo,
       CURRENT_DATE + v.dias_esperada,
       v.estado::estado_prestamo
FROM (VALUES
  --  n  lector        libro            ej  prestado esperada estado
  ( 1, '1000000001', '9780000000001', 1, -60, -46, 'devuelto'),  -- Mariana / Cien años
  ( 2, '1000000001', '9780000000004', 1, -45, -31, 'devuelto'),  -- Mariana / Rayuela
  ( 3, '1000000001', '9780000000007', 1, -30, -16, 'devuelto'),  -- Mariana / Ficciones
  ( 4, '1000000002', '9780000000001', 2, -55, -41, 'devuelto'),  -- Santiago / Cien años
  ( 5, '1000000002', '9780000000004', 2, -40, -26, 'devuelto'),  -- Santiago / Rayuela
  ( 6, '1000000002', '9780000000009', 1, -35, -21, 'devuelto'),  -- Santiago / Quijote (devuelto tarde)
  ( 7, '1000000004', '9780000000007', 2, -40, -26, 'activo'),    -- Juan David / Ficciones (mora, estado sin actualizar)
  ( 8, '1000000004', '9780000000001', 3, -20,  -6, 'en_mora'),   -- Juan David / Cien años (mora)
  ( 9, '1000000004', '9780000000004', 3, -14,   0, 'activo'),    -- Juan David / Rayuela (vence hoy)
  (10, '1000000003', '9780000000010', 1, -30, -16, 'en_mora'),   -- Valentina / La sombra del viento (mora)
  (11, '1000000003', '9780000000001', 4,  -9,   5, 'activo'),    -- Valentina / Cien años (a tiempo)
  (12, '1000000005', '9780000000005', 1, -16,  -2, 'activo'),    -- Camila / Pedro Páramo (mora, estado sin actualizar)
  (13, '1000000005', '9780000000005', 2, -70, -56, 'devuelto')   -- Camila / Pedro Páramo
) AS v (n, documento, isbn, ejemplar, dias_prestamo, dias_esperada, estado)
JOIN usuario u ON u.documento = v.documento
ORDER BY v.n;

-- 4. Devoluciones de los 7 préstamos devueltos (id del préstamo = n de arriba).
INSERT INTO devolucion (id_prestamo, id_bibliotecario, fecha_devolucion)
SELECT v.id_prestamo,
       (SELECT id FROM usuario WHERE documento = '9000000001'),
       CURRENT_DATE + v.dias_devolucion
FROM (VALUES
  ( 1, -50),
  ( 2, -35),
  ( 3, -20),
  ( 4, -42),
  ( 5, -27),
  ( 6, -10),   -- Santiago devolvió el Quijote 11 días después de la fecha esperada
  (13, -58)
) AS v (id_prestamo, dias_devolucion);

-- 5. Los ejemplares de los préstamos abiertos quedan como prestados.
UPDATE ejemplar e SET estado = 'prestado'
FROM prestamo p
WHERE p.isbn = e.isbn AND p.numero_ejemplar = e.numero_ejemplar
  AND p.estado <> 'devuelto';

COMMIT;

-- Resumen de lo cargado: deben salir 13 filas.
-- Si salen menos, faltan lectores o libros: cargue primero los CSV semilla (S14).
SELECT p.id, u.nombres || ' ' || u.apellidos AS lector, l.titulo,
       p.fecha_prestamo, p.fecha_esperada_devolucion, d.fecha_devolucion, p.estado
FROM prestamo p
JOIN usuario u ON u.id = p.id_lector
JOIN libro   l ON l.isbn = p.isbn
LEFT JOIN devolucion d ON d.id_prestamo = p.id
ORDER BY p.id;
