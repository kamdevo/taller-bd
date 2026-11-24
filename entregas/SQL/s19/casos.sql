-- =====================================================================
-- S19. Taller: detectar y corregir esquemas mal diseñados
-- Entregable del grupo: casos.sql  (Parte A: los cuatro casos)
-- Integrantes: ______________________________________________
-- =====================================================================


-- =====================================================================
-- CASO 1: GIMNASIO
-- =====================================================================
SET search_path TO gimnasio;

-- (a) DIAGNÓSTICO
-- Esquema: socio (id_socio PK, nombre, plan, valor_plan, clases)
-- Problema: Violación de 1FN. Contiene atributos multivaluados (múltiples clases mezcladas en una sola celda, separadas por ';').

-- (b) EVIDENCIA
SELECT count(*) AS socios_yoga_segun_el_sistema
FROM socio WHERE clases LIKE '%Yoga%';

-- (c) ESQUEMA CORREGIDO
--   plan (plan PK, valor_plan)
--   socio (id_socio PK, nombre, plan FK -> plan)
--   clase (nombre_clase PK)
--   inscripcion_clase (id_socio FK, nombre_clase FK, PK (id_socio, nombre_clase))

-- (d) MIGRACIÓN
BEGIN;

CREATE TABLE plan (
    plan        varchar(20) PRIMARY KEY,
    valor_plan  integer     NOT NULL
);

CREATE TABLE clase (
    nombre_clase  varchar(40) PRIMARY KEY
);

CREATE TABLE inscripcion_clase (
    id_socio      integer     NOT NULL REFERENCES socio,
    nombre_clase  varchar(40) NOT NULL REFERENCES clase,
    PRIMARY KEY (id_socio, nombre_clase)
);

CREATE TABLE pedazos AS
SELECT DISTINCT s.id_socio, initcap(trim(c)) AS nombre_clase -- initcap par poner en mayuscala la pprimera letra 
FROM socio s, string_to_table(s.clases, ';') AS c --string_to_table dividir el texto multivariable 
WHERE trim(c) <> ''; -- trim para eliminar lso espacios en blanco 

INSERT INTO plan SELECT DISTINCT plan, valor_plan FROM socio;
INSERT INTO clase SELECT DISTINCT nombre_clase FROM pedazos;
INSERT INTO inscripcion_clase SELECT id_socio, nombre_clase FROM pedazos;

ALTER TABLE socio ADD FOREIGN KEY (plan) REFERENCES plan;

-- (e) VERIFICACIÓN (antes de quitar lo viejo)
SELECT 'plan' AS tabla, 3 AS esperado, count(*) AS obtenido FROM plan
UNION ALL SELECT 'clase', 5, count(*) FROM clase
UNION ALL SELECT 'inscripcion_clase', 9, count(*) FROM inscripcion_clase
UNION ALL SELECT 'socio', 6, count(*) FROM socio;

ALTER TABLE socio DROP COLUMN valor_plan, DROP COLUMN clases;
DROP TABLE pedazos;
COMMIT;

-- PREGUNTA PROPIA: ¿En cuál tabla va el horario de clase, y por qué era imposible hacerlo bien con el diseño original?
-- RESPUESTA: El horario debe ir en la nueva tabla `clase`. En el diseño original era imposible registrarlo porque las clases no eran entidades separadas (solo eran texto).


-- =====================================================================
-- CASO 2: FARMACIA
-- =====================================================================
SET search_path TO farmacia;

-- (a) DIAGNÓSTICO
-- Esquema: formula (num_formula PK, fecha, doc_paciente, nombre_paciente, medicamento1, dosis1, medicamento2, dosis2, medicamento3, dosis3)
-- Problema: Violación de 1FN. Uso de columnas numeradas para repetir grupos de datos.

-- (b) EVIDENCIA
SELECT num_formula, medicamento1, medicamento2, medicamento3
FROM formula WHERE medicamento3 IS NOT NULL;

-- (c) ESQUEMA CORREGIDO
--   paciente (doc_paciente PK, nombre_paciente)
--   medicamento (nombre_medicamento PK)
--   formula (num_formula PK, fecha, doc_paciente FK -> paciente)
--   formula_medicamento (num_formula FK, nombre_medicamento FK, dosis, PK (num_formula, nombre_medicamento))

-- (d) MIGRACIÓN
BEGIN;

CREATE TABLE paciente (
    doc_paciente     varchar(15) PRIMARY KEY,
    nombre_paciente  varchar(80) NOT NULL
);

CREATE TABLE medicamento (
    nombre_medicamento  varchar(60) PRIMARY KEY
);

CREATE TABLE formula_medicamento (
    num_formula         integer     NOT NULL REFERENCES formula,
    nombre_medicamento  varchar(60) NOT NULL REFERENCES medicamento,
    dosis               varchar(40) NOT NULL,
    PRIMARY KEY (num_formula, nombre_medicamento)
);

CREATE TABLE lineas AS
SELECT num_formula, medicamento1 AS nombre_medicamento, dosis1 AS dosis 
FROM formula 
WHERE medicamento1 IS NOT NULL AND dosis1 IS NOT NULL
UNION ALL
SELECT num_formula, medicamento2, dosis2 
FROM formula 
WHERE medicamento2 IS NOT NULL AND dosis2 IS NOT NULL
UNION ALL
SELECT num_formula, medicamento3, dosis3 
FROM formula 
WHERE medicamento3 IS NOT NULL AND dosis3 IS NOT NULL;

INSERT INTO paciente SELECT DISTINCT doc_paciente, nombre_paciente FROM formula;
INSERT INTO medicamento SELECT DISTINCT nombre_medicamento FROM lineas;
INSERT INTO formula_medicamento SELECT num_formula, nombre_medicamento, dosis FROM lineas;

ALTER TABLE formula ADD FOREIGN KEY (doc_paciente) REFERENCES paciente;

-- (e) VERIFICACIÓN
SELECT 'paciente' AS tabla, 3 AS esperado, count(*) AS obtenido FROM paciente
UNION ALL SELECT 'medicamento', 5, count(*) FROM medicamento
UNION ALL SELECT 'formula', 4, count(*) FROM formula
UNION ALL SELECT 'formula_medicamento', 8, count(*) FROM formula_medicamento;

ALTER TABLE formula
    DROP COLUMN nombre_paciente,
    DROP COLUMN medicamento1, DROP COLUMN dosis1,
    DROP COLUMN medicamento2, DROP COLUMN dosis2,
    DROP COLUMN medicamento3, DROP COLUMN dosis3;
DROP TABLE lineas;
COMMIT;

-- PREGUNTA PROPIA: ¿Por qué no basta con agregar medicamento4 y dosis4?
-- RESPUESTA: Es ineficiente; el sistema vuelve a fallar si recetan 5 medicamentos, y obliga a usar múltiples OR para buscar una sola medicina.


-- =====================================================================
-- CASO 3: CURSOS LIBRES
-- =====================================================================
SET search_path TO cursos_libres;

-- (a) DIAGNÓSTICO
-- Esquema: inscripcion (id PK serial, doc_participante, nombre_participante, correo, cod_curso, nombre_curso, cod_sede, direccion_sede, valor_pagado)
-- Problema: Integridad de datos desprotegida. La clave primaria artificial (id) permite que la misma persona se inscriba dos veces en el mismo curso.

-- (b) EVIDENCIA
SELECT doc_participante, cod_curso, count(*) AS veces
FROM inscripcion GROUP BY doc_participante, cod_curso HAVING count(*) > 1;

-- (c) ESQUEMA CORREGIDO
--   sede (cod_sede PK, direccion_sede)
--   curso (cod_curso PK, nombre_curso, cod_sede FK -> sede)
--   participante (doc_participante PK, nombre_participante, correo UNIQUE)
--   inscripcion (doc_participante FK, cod_curso FK, valor_pagado, PK (doc_participante, cod_curso))

-- (d) MIGRACIÓN
BEGIN;

ALTER TABLE inscripcion RENAME TO inscripcion_vieja;

CREATE TABLE sede (
    cod_sede        char(2)     PRIMARY KEY,
    direccion_sede  varchar(60) NOT NULL
);

CREATE TABLE curso (
    cod_curso     char(3)     PRIMARY KEY,
    nombre_curso  varchar(60) NOT NULL,
    cod_sede      char(2)     NOT NULL REFERENCES sede
);

CREATE TABLE participante (
    doc_participante     varchar(15)  PRIMARY KEY,
    nombre_participante  varchar(80)  NOT NULL,
    correo               varchar(120) NOT NULL UNIQUE
);

CREATE TABLE inscripcion (
    doc_participante  varchar(15) NOT NULL REFERENCES participante,
    cod_curso         char(3)     NOT NULL REFERENCES curso,
    valor_pagado      integer     NOT NULL,
    PRIMARY KEY (doc_participante, cod_curso)
);

INSERT INTO sede         SELECT DISTINCT cod_sede, direccion_sede FROM inscripcion_vieja;
INSERT INTO curso        SELECT DISTINCT cod_curso, nombre_curso, cod_sede FROM inscripcion_vieja;
INSERT INTO participante SELECT DISTINCT doc_participante, nombre_participante, correo FROM inscripcion_vieja;
INSERT INTO inscripcion  SELECT DISTINCT doc_participante, cod_curso, valor_pagado FROM inscripcion_vieja;

-- (e) VERIFICACIÓN
SELECT 'sede' AS tabla, 2 AS esperado, count(*) AS obtenido FROM sede
UNION ALL SELECT 'curso', 3, count(*) FROM curso
UNION ALL SELECT 'participante', 4, count(*) FROM participante
UNION ALL SELECT 'inscripcion', 7, count(*) FROM inscripcion;

DROP TABLE inscripcion_vieja;
COMMIT;

-- PREGUNTA PROPIA: ¿Por qué una PK de una sola columna no la pone en 2FN y qué habría evitado?
-- RESPUESTA: Un id autonumérico no soluciona el problema lógico. Faltó ponerle UNIQUE al documento y al curso para evitar cobrar e inscribir doble por error.


-- =====================================================================
-- CASO 4: ENVÍOS
-- =====================================================================
SET search_path TO envios;

-- (a) DIAGNÓSTICO
-- Esquema: envio (num_guia PK, fecha, ciudad_destino, departamento, zona, tarifa_kg, peso_kg, valor)
-- Problema: Violación de 3FN. La tabla guarda el valor total, que es calculable (peso_kg * tarifa_kg).

-- (b) EVIDENCIA
SELECT num_guia, ciudad_destino, peso_kg, tarifa_kg,
       valor AS valor_cobrado, peso_kg * tarifa_kg AS valor_correcto
FROM envio WHERE valor <> peso_kg * tarifa_kg;

-- (c) ESQUEMA CORREGIDO
--   zona (zona PK, tarifa_kg)
--   ciudad (ciudad PK, departamento, zona FK -> zona)
--   envio (num_guia PK, fecha, ciudad_destino FK -> ciudad, peso_kg)
--   vista envio_con_valor (valor se calcula, no se guarda)

-- (d) MIGRACIÓN
BEGIN;

CREATE TABLE envio_antes AS SELECT * FROM envio;

CREATE TABLE zona (
    zona       smallint PRIMARY KEY,
    tarifa_kg  integer  NOT NULL
);

CREATE TABLE ciudad (
    ciudad        varchar(40) PRIMARY KEY,
    departamento  varchar(40) NOT NULL,
    zona          smallint    NOT NULL REFERENCES zona
);

INSERT INTO zona   SELECT DISTINCT zona, tarifa_kg FROM envio;
INSERT INTO ciudad SELECT DISTINCT ciudad_destino, departamento, zona FROM envio;

ALTER TABLE envio ADD FOREIGN KEY (ciudad_destino) REFERENCES ciudad;
ALTER TABLE envio
    DROP COLUMN departamento,
    DROP COLUMN zona,
    DROP COLUMN tarifa_kg,
    DROP COLUMN valor;

CREATE VIEW envio_con_valor AS
SELECT num_guia, fecha, ciudad_destino, departamento, zona, tarifa_kg, peso_kg,
       peso_kg * tarifa_kg AS valor
FROM envio
JOIN ciudad ON ciudad.ciudad = envio.ciudad_destino
JOIN zona   USING (zona);

-- (e) VERIFICACIÓN
SELECT 'zona' AS tabla, 3 AS esperado, count(*) AS obtenido FROM zona
UNION ALL SELECT 'ciudad', 5, count(*) FROM ciudad
UNION ALL SELECT 'envio', 8, count(*) FROM envio;

DROP TABLE envio_antes;
COMMIT;

-- PREGUNTA PROPIA: ¿Qué cambiarían para que un aumento de tarifas no modifique envíos pasados?
-- RESPUESTA: Se debe guardar la tarifa histórica (tarifa_cobrada) en el envío. No es redundancia, es preservar el historial contable.
