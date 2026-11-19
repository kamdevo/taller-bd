--Crear el Script de normalizar para el esquema de la Base de Datos de la biblioteca

--Intregrantes : Andres Felipe Rengifo Rodriguez


-- La tabla ROl no resevira Ningunn cambio por q es unn catalogo Estatico 


--La Tabla de usuario dederia de eliminar el comando id ya q con documento es mas q suficiente como PK ya q el docuemnto simpre va a ser diferente paa todas las personas
    --DECICION : Se conserva id como PK sustituta porque permite corregir documento o correo con un solo UPDATE sobre una fila, sin propagar el cambio a prestamo y devolucion. Ambos siguen protegidos con UNIQUE como claves candidatas.

--Libro se deberia de craer una normalizacion en la parte de lectores por si un libro tiene mas de un lector , tendria q revisarse si las categorias van a ser una tabla estatica o uunn string 
    -- Decicion : Ya q el proyecto solo nos pide un autor por libro no vemos necesario ponerr una tabla de autores

--Ejemplar: error en el estado 
    --DECICION : modificar estado como un bolena donde 
        --true sifnifique q el ejemplar del libro este disppponivle para prestar o este siendo pretado 
        --false para identificar q un ejemplar de un libro no es displible paara ser ppretado por alguna razon 
        --(El saber si un ejemplar fue pretsaao lo define la tabla prestamo y no la tabla de ejemplarr solo dice si esta activo o no von el voleam)

SET search_path TO biblioteca, public;
BEGIN; -- Iniciar 

ALTER TABLE ejemplar ADD COLUMN activo BOOLEAN NOT NULL DEFAULT true; -- Cra una nuueva columna pppara ejemppplar donde esta contiennne boleanos la ccual no puede estar vacia y la ianicializa con true 
UPDATE ejemplar SET activo = false WHERE estado = 'baja'; --Actualiza la columa de activo cuanod encunettre un estado como baja

--Creamos una vista parra saber el estado de el jemppplar mediante una consulta 
CREATE VIEW ejemplar_estado AS
SELECT e.isbn, e.numero_ejemplar, e.activo,
    CASE --funciona como un dependiendo del caso
        WHEN NOT e.activo THEN 'baja' -- si el ejemplar no esta activo colocar baja 
        WHEN EXISTS (                  -- Si esxiste un ejemplar q este en la tabla de prestamo y no este devuelto colocar prestaddo
           SELECT 1 FROM prestamo p
           WHERE p.isbn = e.isbn AND p.numero_ejemplar = e.numero_ejemplar
             AND NOT EXISTS (SELECT 1 FROM devolucion d WHERE d.id_prestamo = p.id)
         ) THEN 'prestado'
         ELSE 'disponible' -- De lo contrario colocra disponible 
       END AS estado -- En la columna de esttado de esta wiew
FROM ejemplar e; 


--Bloque de verificacion 
DO $$ -- para poder ejecutarr un bloque con if 
BEGIN
IF EXISTS ( 
    SELECT 1
    FROM ejemplar e
    JOIN ejemplar_estado v USING (isbn, numero_ejemplar) -- USING ES LO MISMO Q ASER ON manera mas linpia de porgramar 
    WHERE e.estado::text <> v.estado -- si encuentra una diferenci entre el estdao viejo y el estado nuevo
) THEN -- Lanza el siguiente error 
    RAISE EXCEPTION 'El estado guardado no coincide con el calculado. Revisar antes de migrar.';
END IF;--Si no finaliza
END $$;

--Bloque para eliminar lo viejo 
ALTER TABLE ejemplar DROP COLUMN estado; -- ELiminamos la columna q no sirve 
DROP TYPE estado_ejemplar; -- Eliminamos el tipo ENUM

--Prestamo: Error con el estado este es mejor calcularmo mediante uan vista 
-- 1. Vista que calcula el estado de cada préstamo
CREATE VIEW prestamo_estado AS
SELECT p.id, p.id_lector, p.isbn, p.numero_ejemplar, p.id_bibliotecario,
       p.fecha_prestamo, p.fecha_esperada_devolucion,
       d.fecha_devolucion,
       CASE
         WHEN d.id_prestamo IS NOT NULL THEN 'devuelto' --Cuando el id este en la tabla de devolucion colocar devuelvoto
         WHEN p.fecha_esperada_devolucion < CURRENT_DATE THEN 'en_mora' -- (CURRENT_DATE deevuelve la fecha actual de la operacion ) -> si la fecha esperadda de deevolucion de es menor q hoy colocar el estado en mora 
         ELSE 'activo' -- De lo contrario colocar en activo
       END AS estado 
FROM prestamo p
LEFT JOIN devolucion d ON d.id_prestamo = p.id;


-- 2. Evidencia de problemas si ay problemas asta el dia de hoy : préstamos cuyo estado guardado no coincide con el calculado
SELECT p.id, p.estado AS guardado, v.estado AS calculado
FROM prestamo p
JOIN prestamo_estado v ON v.id = p.id
WHERE p.estado::text <> v.estado;

-- 3. Quitar lo viejo
ALTER TABLE prestamo DROP COLUMN estado;
DROP TYPE estado_prestamo;


--Devoluvion problema con el id redundante 

-- 1. Guardar el conteo para verificar después
CREATE TEMP TABLE devolucion_antes AS
SELECT id_prestamo, id_bibliotecario, fecha_devolucion FROM devolucion;

-- 2. Cambiar la clave primaria
ALTER TABLE devolucion DROP CONSTRAINT devolucion_id_prestamo_key;  -- el UNIQUE ya no hace falta
ALTER TABLE devolucion DROP COLUMN id;                              -- también elimina la PK vieja
ALTER TABLE devolucion ADD PRIMARY KEY (id_prestamo);

-- 2. Verificar: no se perdió ni se inventó ninguna fila (ambas deben dar 0 filas)
SELECT * FROM devolucion_antes
EXCEPT
SELECT id_prestamo, id_bibliotecario, fecha_devolucion FROM devolucion;

SELECT id_prestamo, id_bibliotecario, fecha_devolucion FROM devolucion
EXCEPT
SELECT * FROM devolucion_antes;

COMMIT;

--Eliminar la tabla de rechazo de carga ya q no es principal 