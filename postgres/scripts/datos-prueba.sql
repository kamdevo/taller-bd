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
-- El script BORRA todos los préstamos y devoluciones y carga 100 préstamos
-- inventados: 13 diseñados para los 8 casos de la sección 4 de S16, 6 más
-- de Juan David (caso 4) y 81 de relleno devueltos a tiempo, para que el
-- top 20 quede lleno de libros prestados. Se puede correr
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
-- 14-19  Juan David: Harry Potter, El principito, 1984, Sapiens, El nombre del
--         viento, Orgullo y prejuicio. Prestados d-5, vencen d+9, abiertos  <- caso 4
--         (queda con 9 préstamos y 0 devueltos)
-- 20-100  RELLENO: 81 préstamos devueltos a tiempo (devueltos 2 días antes de la
--         fecha esperada), prestados entre d-209 y d-30. Mariana y Santiago 5 cada uno;
--         Sebastián, Isabella, Andrés Felipe, Laura, Daniel, Sofía y Gabriela 5;
--         Valentina, Camila y los documentos ...14 a ...20, 4 cada uno.
--         No hay mora en el relleno: no cambia los reportes 3 ni 4.
--  Nicolás (1000000012) no tiene préstamos  <- caso 8
--  Sin préstamos: El Aleph (..08 y ..02), Breve historia del tiempo, Trilce,
--  Rayuela (..9990000005) y Veinte poemas de amor (..9990000006)  <- caso 1
--
-- Los préstamos 7 y 12 quedan con estado 'activo' aunque ya vencieron: así
-- se comprueba que los reportes calculan la mora con las fechas y no
-- confían en la columna estado (S15 §8.5: no hay trigger que la actualice).
--
-- ---------------------------------------------------------------------
-- RESULTADOS ESPERADOS (decididos antes de correr nada)
-- ---------------------------------------------------------------------
-- Reporte 1 (top 20, desempate por título): 20 filas, ninguna con 0.
--    1 Cien años de soledad 9         11 Sapiens 4
--    2 Don Quijote de la Mancha 8     12 Crimen y castigo 3
--    3 Rayuela 7                      13 El amor en los tiempos del cólera 3
--    4 El principito 6                14 Fahrenheit 451 3
--    5 Harry Potter 6                 15 La casa de los espíritus 3
--    6 1984 5                         16 Matilda 3
--    7 La sombra del viento 5         17 Orgullo y prejuicio 3
--    8 El nombre del viento 4         18 Alicia en el país de las maravillas 2
--    9 Ficciones 4                    19 Como agua para chocolate 2
--   10 Pedro Páramo 4                 20 Cosmos 2
--   Crónica de una muerte anunciada y Un mundo feliz también tienen 2, pero
--   van después en el alfabeto: quedan en los puestos 21 y 22, fuera. -> caso 2
--   Reporte 1b (libros sin préstamos): 6 filas, entre ellas El Aleph (las dos
--   ediciones) con 0: el LEFT JOIN los cuenta.            -> caso 1
-- Reporte 2: Mariana Gómez Rojas 8 y Santiago Rodríguez Pérez 8 (empate).
--   Nadie más pasa de 5 leídos.                           -> caso 3
--   Juan David tiene 9 préstamos (más que los ganadores) pero 0 devueltos:
--   no sale.                                              -> caso 4
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
--    RESTART IDENTITY reinicia los id, así los préstamos quedan con id 1 a 100
--    en el mismo orden de la lista de abajo.
TRUNCATE devolucion, prestamo RESTART IDENTITY;
UPDATE ejemplar SET estado = 'disponible' WHERE estado = 'prestado';

-- 3. Los 100 préstamos (d = CURRENT_DATE).
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
  (13, '1000000005', '9780000000005', 2, -70, -56, 'devuelto'),  -- Camila / Pedro Páramo
  -- Juan David (caso 4): 6 préstamos más, abiertos y a tiempo (vencen en d+9).
  -- Queda con 9 préstamos y 0 devueltos: más préstamos que los ganadores del reporte 2.
  ( 14, '1000000004', '9780000000032', 2,   -5,    9, 'activo'),       -- Juan David / Harry Potter y la piedra filosofal (abierto, a tiempo)
  ( 15, '1000000004', '9780000000017', 2,   -5,    9, 'activo'),       -- Juan David / El principito (abierto, a tiempo)
  ( 16, '1000000004', '9780000000014', 2,   -5,    9, 'activo'),       -- Juan David / 1984 (abierto, a tiempo)
  ( 17, '1000000004', '9780000000022', 2,   -5,    9, 'activo'),       -- Juan David / Sapiens: de animales a dioses (abierto, a tiempo)
  ( 18, '1000000004', '9780000000031', 2,   -5,    9, 'activo'),       -- Juan David / El nombre del viento (abierto, a tiempo)
  ( 19, '1000000004', '9780000000028', 2,   -5,    9, 'activo'),       -- Juan David / Orgullo y prejuicio (abierto, a tiempo)
  -- Relleno (20-100): 81 préstamos devueltos a tiempo, repartidos entre los
  -- demás lectores (menos Juan David y Nicolás). Mariana y Santiago leen 5
  -- más cada uno (quedan con 8); ningún otro lector pasa de 5.
  ( 20, '1000000001', '9780000000009', 1,  -30,  -16, 'devuelto'),     -- Mariana / Don Quijote de la Mancha
  ( 21, '1000000001', '9780000000032', 1,  -37,  -23, 'devuelto'),     -- Mariana / Harry Potter y la piedra filosofal
  ( 22, '1000000001', '9780000000023', 1,  -44,  -30, 'devuelto'),     -- Mariana / El origen de las especies
  ( 23, '1000000001', '9780000000031', 1,  -51,  -37, 'devuelto'),     -- Mariana / El nombre del viento
  ( 24, '1000000001', '9780000000030', 1,  -58,  -44, 'devuelto'),     -- Mariana / Frankenstein
  ( 25, '1000000002', '9780000000029', 1,  -65,  -51, 'devuelto'),     -- Santiago / Drácula
  ( 26, '1000000002', '9780000000010', 1,  -72,  -58, 'devuelto'),     -- Santiago / La sombra del viento
  ( 27, '1000000002', '9780000000022', 1,  -79,  -65, 'devuelto'),     -- Santiago / Sapiens: de animales a dioses
  ( 28, '1000000002', '9780000000017', 1,  -86,  -72, 'devuelto'),     -- Santiago / El principito
  ( 29, '1000000002', '9780000000016', 1,  -93,  -79, 'devuelto'),     -- Santiago / Fahrenheit 451
  ( 30, '1000000006', '9780000000010', 2, -100,  -86, 'devuelto'),     -- Sebastián / La sombra del viento
  ( 31, '1000000006', '9780000000018', 1, -107,  -93, 'devuelto'),     -- Sebastián / Matilda
  ( 32, '1000000006', '9780000000002', 1, -114, -100, 'devuelto'),     -- Sebastián / El amor en los tiempos del cólera
  ( 33, '1000000006', '9780000000014', 1, -121, -107, 'devuelto'),     -- Sebastián / 1984
  ( 34, '1000000006', '9780000000017', 2, -128, -114, 'devuelto'),     -- Sebastián / El principito
  ( 35, '1000000007', '9780000000027', 1, -135, -121, 'devuelto'),     -- Isabella / Los miserables
  ( 36, '1000000007', '9780000000026', 1, -142, -128, 'devuelto'),     -- Isabella / Crimen y castigo
  ( 37, '1000000007', '9780000000017', 3, -149, -135, 'devuelto'),     -- Isabella / El principito
  ( 38, '1000000007', '9780000000011', 1, -156, -142, 'devuelto'),     -- Isabella / Como agua para chocolate
  ( 39, '1000000007', '9780000000006', 1, -163, -149, 'devuelto'),     -- Isabella / La casa de los espíritus
  ( 40, '1000000008', '9789990000003', 1, -170, -156, 'devuelto'),     -- Andrés Felipe / La vorágine
  ( 41, '1000000008', '9780000000028', 1, -177, -163, 'devuelto'),     -- Andrés Felipe / Orgullo y prejuicio
  ( 42, '1000000008', '9780000000004', 1, -184, -170, 'devuelto'),     -- Andrés Felipe / Rayuela
  ( 43, '1000000008', '9780000000007', 1, -191, -177, 'devuelto'),     -- Andrés Felipe / Ficciones
  ( 44, '1000000008', '9780000000032', 2, -198, -184, 'devuelto'),     -- Andrés Felipe / Harry Potter y la piedra filosofal
  ( 45, '1000000009', '9780000000014', 2, -205, -191, 'devuelto'),     -- Laura / 1984
  ( 46, '1000000009', '9780000000001', 1,  -32,  -18, 'devuelto'),     -- Laura / Cien años de soledad
  ( 47, '1000000009', '9780000000024', 1,  -39,  -25, 'devuelto'),     -- Laura / Veinte poemas de amor y una canción desesperada
  ( 48, '1000000009', '9780000000031', 2,  -46,  -32, 'devuelto'),     -- Laura / El nombre del viento
  ( 49, '1000000009', '9780000000019', 1,  -53,  -39, 'devuelto'),     -- Laura / Alicia en el país de las maravillas
  ( 50, '1000000010', '9780000000026', 2,  -60,  -46, 'devuelto'),     -- Daniel / Crimen y castigo
  ( 51, '1000000010', '9780000000009', 2,  -67,  -53, 'devuelto'),     -- Daniel / Don Quijote de la Mancha
  ( 52, '1000000010', '9780000000004', 2,  -74,  -60, 'devuelto'),     -- Daniel / Rayuela
  ( 53, '1000000010', '9780000000014', 3,  -81,  -67, 'devuelto'),     -- Daniel / 1984
  ( 54, '1000000010', '9780000000007', 2,  -88,  -74, 'devuelto'),     -- Daniel / Ficciones
  ( 55, '1000000011', '9780000000017', 4,  -95,  -81, 'devuelto'),     -- Sofía / El principito
  ( 56, '1000000011', '9789990000004', 1, -102,  -88, 'devuelto'),     -- Sofía / Ficciones
  ( 57, '1000000011', '9780000000012', 1, -109,  -95, 'devuelto'),     -- Sofía / El túnel
  ( 58, '1000000011', '9780000000015', 1, -116, -102, 'devuelto'),     -- Sofía / Un mundo feliz
  ( 59, '1000000011', '9780000000001', 2, -123, -109, 'devuelto'),     -- Sofía / Cien años de soledad
  ( 60, '1000000013', '9780000000009', 3, -130, -116, 'devuelto'),     -- Gabriela / Don Quijote de la Mancha
  ( 61, '1000000013', '9780000000010', 3, -137, -123, 'devuelto'),     -- Gabriela / La sombra del viento
  ( 62, '1000000013', '9780000000021', 1, -144, -130, 'devuelto'),     -- Gabriela / Cosmos
  ( 63, '1000000013', '9780000000004', 3, -151, -137, 'devuelto'),     -- Gabriela / Rayuela
  ( 64, '1000000013', '9780000000018', 2, -158, -144, 'devuelto'),     -- Gabriela / Matilda
  ( 65, '1000000003', '9780000000032', 3, -165, -151, 'devuelto'),     -- Valentina / Harry Potter y la piedra filosofal
  ( 66, '1000000003', '9780000000028', 2, -172, -158, 'devuelto'),     -- Valentina / Orgullo y prejuicio
  ( 67, '1000000003', '9780000000019', 2, -179, -165, 'devuelto'),     -- Valentina / Alicia en el país de las maravillas
  ( 68, '1000000003', '9780000000004', 1, -186, -172, 'devuelto'),     -- Valentina / Rayuela
  ( 69, '1000000005', '9780000000016', 2, -193, -179, 'devuelto'),     -- Camila / Fahrenheit 451
  ( 70, '1000000005', '9780000000010', 4, -200, -186, 'devuelto'),     -- Camila / La sombra del viento
  ( 71, '1000000005', '9780000000011', 2, -207, -193, 'devuelto'),     -- Camila / Como agua para chocolate
  ( 72, '1000000005', '9780000000009', 4,  -34,  -20, 'devuelto'),     -- Camila / Don Quijote de la Mancha
  ( 73, '1000000014', '9780000000001', 3,  -41,  -27, 'devuelto'),     -- Miguel Ángel / Cien años de soledad
  ( 74, '1000000014', '9780000000005', 1,  -48,  -34, 'devuelto'),     -- Miguel Ángel / Pedro Páramo
  ( 75, '1000000014', '9789990000001', 1,  -55,  -41, 'devuelto'),     -- Miguel Ángel / Pedro Páramo
  ( 76, '1000000014', '9780000000006', 2,  -62,  -48, 'devuelto'),     -- Miguel Ángel / La casa de los espíritus
  ( 77, '1000000015', '9780000000001', 4,  -69,  -55, 'devuelto'),     -- Paula Andrea / Cien años de soledad
  ( 78, '1000000015', '9780000000016', 3,  -76,  -62, 'devuelto'),     -- Paula Andrea / Fahrenheit 451
  ( 79, '1000000015', '9780000000018', 3,  -83,  -69, 'devuelto'),     -- Paula Andrea / Matilda
  ( 80, '1000000015', '9780000000002', 2,  -90,  -76, 'devuelto'),     -- Paula Andrea / El amor en los tiempos del cólera
  ( 81, '1000000016', '9780000000022', 2,  -97,  -83, 'devuelto'),     -- Julián / Sapiens: de animales a dioses
  ( 82, '1000000016', '9780000000032', 4, -104,  -90, 'devuelto'),     -- Julián / Harry Potter y la piedra filosofal
  ( 83, '1000000016', '9780000000009', 5, -111,  -97, 'devuelto'),     -- Julián / Don Quijote de la Mancha
  ( 84, '1000000016', '9780000000014', 4, -118, -104, 'devuelto'),     -- Julián / 1984
  ( 85, '1000000017', '9780000000022', 3, -125, -111, 'devuelto'),     -- Natalia / Sapiens: de animales a dioses
  ( 86, '1000000017', '9780000000026', 3, -132, -118, 'devuelto'),     -- Natalia / Crimen y castigo
  ( 87, '1000000017', '9780000000003', 1, -139, -125, 'devuelto'),     -- Natalia / Crónica de una muerte anunciada
  ( 88, '1000000017', '9780000000013', 1, -146, -132, 'devuelto'),     -- Natalia / Los detectives salvajes
  ( 89, '1000000018', '9780000000031', 3, -153, -139, 'devuelto'),     -- Felipe / El nombre del viento
  ( 90, '1000000018', '9780000000001', 1, -160, -146, 'devuelto'),     -- Felipe / Cien años de soledad
  ( 91, '1000000018', '9780000000002', 3, -167, -153, 'devuelto'),     -- Felipe / El amor en los tiempos del cólera
  ( 92, '1000000018', '9780000000006', 3, -174, -160, 'devuelto'),     -- Felipe / La casa de los espíritus
  ( 93, '1000000019', '9780000000009', 1, -181, -167, 'devuelto'),     -- Daniela / Don Quijote de la Mancha
  ( 94, '1000000019', '9780000000021', 2, -188, -174, 'devuelto'),     -- Daniela / Cosmos
  ( 95, '1000000019', '9780000000017', 5, -195, -181, 'devuelto'),     -- Daniela / El principito
  ( 96, '1000000019', '9780000000032', 5, -202, -188, 'devuelto'),     -- Daniela / Harry Potter y la piedra filosofal
  ( 97, '1000000020', '9780000000015', 2, -209, -195, 'devuelto'),     -- Óscar / Un mundo feliz
  ( 98, '1000000020', '9780000000003', 2,  -36,  -22, 'devuelto'),     -- Óscar / Crónica de una muerte anunciada
  ( 99, '1000000020', '9780000000009', 2,  -43,  -29, 'devuelto'),     -- Óscar / Don Quijote de la Mancha
  (100, '1000000020', '9780000000005', 2,  -50,  -36, 'devuelto')     -- Óscar / Pedro Páramo
) AS v (n, documento, isbn, ejemplar, dias_prestamo, dias_esperada, estado)
JOIN usuario u ON u.documento = v.documento
ORDER BY v.n;

-- 4. Devoluciones de los 7 préstamos devueltos de los casos (id del préstamo = n de arriba).
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

-- 4b. Devoluciones del relleno (préstamos 20 a 100): todos se devolvieron
--     a tiempo, 2 días antes de su fecha esperada.
INSERT INTO devolucion (id_prestamo, id_bibliotecario, fecha_devolucion)
SELECT p.id,
       (SELECT id FROM usuario WHERE documento = '9000000001'),
       p.fecha_esperada_devolucion - 2
FROM prestamo p
WHERE p.id >= 20 AND p.estado = 'devuelto';

-- 5. Los ejemplares de los préstamos abiertos quedan como prestados.
UPDATE ejemplar e SET estado = 'prestado'
FROM prestamo p
WHERE p.isbn = e.isbn AND p.numero_ejemplar = e.numero_ejemplar
  AND p.estado <> 'devuelto';

COMMIT;

-- Resumen de lo cargado: deben salir 100 filas.
-- Si salen menos, faltan lectores o libros: cargue primero los CSV semilla (S14).
SELECT p.id, u.nombres || ' ' || u.apellidos AS lector, l.titulo,
       p.fecha_prestamo, p.fecha_esperada_devolucion, d.fecha_devolucion, p.estado
FROM prestamo p
JOIN usuario u ON u.id = p.id_lector
JOIN libro   l ON l.isbn = p.isbn
LEFT JOIN devolucion d ON d.id_prestamo = p.id
ORDER BY p.id;
