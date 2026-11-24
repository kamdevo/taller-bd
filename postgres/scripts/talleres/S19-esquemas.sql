-- S19. Taller: detectar y corregir esquemas mal diseñados
-- Cuatro esquemas pequeños, cada uno "en producción" en un negocio distinto:
--   gimnasio       socio
--   farmacia       formula
--   cursos_libres  inscripcion
--   envios         envio
--
-- Uso (desde entorno-docker/, con este archivo copiado en postgres/scripts/):
--   docker compose exec postgres psql -U curso -d curso -f /scripts/S19-esquemas.sql
--
-- Se puede correr cuantas veces se quiera: borra y recrea los cuatro
-- esquemas completos (incluidas las tablas que los grupos hayan creado en
-- ellos), sin tocar nada más de la base.
-- Para trabajar sobre un caso desde psql o pgAdmin, por ejemplo:
--   SET search_path TO gimnasio;

-- ---------------------------------------------------------------
-- Caso 1: gimnasio
-- ---------------------------------------------------------------

DROP SCHEMA IF EXISTS gimnasio CASCADE;
CREATE SCHEMA gimnasio;

CREATE TABLE gimnasio.socio (
    id_socio    integer      PRIMARY KEY,
    nombre      varchar(80)  NOT NULL,
    plan        varchar(20)  NOT NULL,
    valor_plan  integer      NOT NULL,
    clases      text                      -- clases inscritas, separadas por ';'
);

INSERT INTO gimnasio.socio VALUES
    (1, 'Laura Cifuentes',      'Mensual',     90000, 'Yoga; Spinning'),
    (2, 'Pedro Arango',         'Trimestral', 240000, 'Spinning avanzado'),
    (3, 'María Fernanda Lasso', 'Mensual',     90000, 'Pilates;yoga'),
    (4, 'Andrés Mosquera',      'Anual',      850000, 'Spinning; Funcional; Yoga '),
    (5, 'Sofía Reyes',          'Mensual',     90000, NULL),
    (6, 'Tomás Ortega',         'Anual',      850000, 'Funcional');

-- ---------------------------------------------------------------
-- Caso 2: farmacia
-- ---------------------------------------------------------------

DROP SCHEMA IF EXISTS farmacia CASCADE;
CREATE SCHEMA farmacia;

CREATE TABLE farmacia.formula (
    num_formula      integer      PRIMARY KEY,
    fecha            date         NOT NULL,
    doc_paciente     varchar(15)  NOT NULL,
    nombre_paciente  varchar(80)  NOT NULL,
    medicamento1     varchar(60)  NOT NULL,
    dosis1           varchar(40)  NOT NULL,
    medicamento2     varchar(60),
    dosis2           varchar(40),
    medicamento3     varchar(60),
    dosis3           varchar(40)
);

INSERT INTO farmacia.formula VALUES
    (701, '2026-10-01', '1110000111', 'Rosa Díaz',
          'Acetaminofén 500 mg', 'cada 8 h', 'Loratadina 10 mg', 'cada 24 h', NULL, NULL),
    (702, '2026-10-03', '1110000222', 'Óscar Paz',
          'Amoxicilina 500 mg', 'cada 8 h', NULL, NULL, NULL, NULL),
    (703, '2026-10-07', '1110000111', 'Rosa Díaz',
          'Ibuprofeno 400 mg', 'cada 12 h', 'Omeprazol 20 mg', 'cada 24 h', 'Acetaminofén 500 mg', 'cada 8 h'),
    (704, '2026-10-10', '1110000333', 'Elsa Mina',
          'Loratadina 10 mg', 'cada 24 h', 'Acetaminofén 500 mg', 'cada 6 h', NULL, NULL);

-- ---------------------------------------------------------------
-- Caso 3: cursos_libres
-- ---------------------------------------------------------------

DROP SCHEMA IF EXISTS cursos_libres CASCADE;
CREATE SCHEMA cursos_libres;

CREATE TABLE cursos_libres.inscripcion (
    id                   serial       PRIMARY KEY,
    doc_participante     varchar(15)  NOT NULL,
    nombre_participante  varchar(80)  NOT NULL,
    correo               varchar(120) NOT NULL,
    cod_curso            char(3)      NOT NULL,
    nombre_curso         varchar(60)  NOT NULL,
    cod_sede             char(2)      NOT NULL,
    direccion_sede       varchar(60)  NOT NULL,
    valor_pagado         integer      NOT NULL
);

INSERT INTO cursos_libres.inscripcion
    (doc_participante, nombre_participante, correo, cod_curso, nombre_curso, cod_sede, direccion_sede, valor_pagado)
VALUES
    ('1140000900', 'Juliana Rey',   'juliana.rey@correo.com',   'C10', 'Guitarra básica',    'S1', 'Cra 5 # 10-20',  150000),
    ('1140000901', 'Mateo Gil',     'mateo.gil@correo.com',     'C10', 'Guitarra básica',    'S1', 'Cra 5 # 10-20',  150000),
    ('1140000900', 'Juliana Rey',   'juliana.rey@correo.com',   'C20', 'Fotografía digital', 'S2', 'Av 6N # 25-40', 200000),
    ('1140000902', 'Valeria Ospina','valeria.ospina@correo.com','C20', 'Fotografía digital', 'S2', 'Av 6N # 25-40', 180000),
    ('1140000901', 'Mateo Gil',     'mateo.gil@correo.com',     'C30', 'Cerámica',           'S1', 'Cra 5 # 10-20',  170000),
    ('1140000903', 'Esteban Cruz',  'esteban.cruz@correo.com',  'C10', 'Guitarra básica',    'S1', 'Cra 5 # 10-20',  150000),
    ('1140000900', 'Juliana Rey',   'juliana.rey@correo.com',   'C20', 'Fotografía digital', 'S2', 'Av 6N # 25-40', 200000),
    ('1140000902', 'Valeria Ospina','valeria.ospina@correo.com','C30', 'Cerámica',           'S1', 'Cra 5 # 10-20',  170000);

-- ---------------------------------------------------------------
-- Caso 4: envios
-- ---------------------------------------------------------------

DROP SCHEMA IF EXISTS envios CASCADE;
CREATE SCHEMA envios;

CREATE TABLE envios.envio (
    num_guia        char(3)       PRIMARY KEY,
    fecha           date          NOT NULL,
    ciudad_destino  varchar(40)   NOT NULL,
    departamento    varchar(40)   NOT NULL,
    zona            smallint      NOT NULL,
    tarifa_kg       integer       NOT NULL,
    peso_kg         numeric(5,1)  NOT NULL,
    valor           integer       NOT NULL
);

INSERT INTO envios.envio VALUES
    ('G01', '2026-10-01', 'Cali',     'Valle del Cauca', 1, 4000,  2.0,  8000),
    ('G02', '2026-10-01', 'Palmira',  'Valle del Cauca', 1, 4000,  5.5, 22000),
    ('G03', '2026-10-02', 'Bogotá',   'Bogotá D.C.',     2, 6000,  1.0,  6000),
    ('G04', '2026-10-02', 'Medellín', 'Antioquia',       2, 6000,  3.0, 18000),
    ('G05', '2026-10-05', 'Cali',     'Valle del Cauca', 1, 4000, 10.0, 40000),
    ('G06', '2026-10-06', 'Pasto',    'Nariño',          3, 9000,  2.5, 22500),
    ('G07', '2026-10-08', 'Bogotá',   'Bogotá D.C.',     2, 6000,  4.0, 42000),
    ('G08', '2026-10-09', 'Medellín', 'Antioquia',       2, 6000,  1.5,  9000);

-- ---------------------------------------------------------------
-- Verificación
-- ---------------------------------------------------------------

SELECT 'gimnasio.socio' AS tabla, count(*) AS filas FROM gimnasio.socio
UNION ALL SELECT 'farmacia.formula',        count(*) FROM farmacia.formula
UNION ALL SELECT 'cursos_libres.inscripcion', count(*) FROM cursos_libres.inscripcion
UNION ALL SELECT 'envios.envio',            count(*) FROM envios.envio;
