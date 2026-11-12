-- S18. Taller: formas normales 1FN, 2FN, 3FN y FNBC
-- Caso: la planilla de servicios del Taller Automotriz El Pistón, ya en 1FN
-- (una fila por servicio hecho en una orden), con todo lo demás copiado
--
-- Uso (desde entorno-docker/, con este archivo copiado en postgres/scripts/):
--   docker compose exec postgres psql -U curso -d curso -f /scripts/S18-automotriz.sql
--
-- Se puede correr cuantas veces se quiera: borra y recrea el esquema
-- "automotriz" completo, sin tocar nada más de la base. Las tablas
-- normalizadas de la parte B se crean en este mismo esquema; al correr de
-- nuevo el script, se borran también.
-- Para trabajar después sobre estas tablas desde psql o pgAdmin:
--   SET search_path TO automotriz;

DROP SCHEMA IF EXISTS automotriz CASCADE;
CREATE SCHEMA automotriz;
SET search_path TO automotriz;

-- ---------------------------------------------------------------
-- servicio_plano: una fila por servicio de una orden.
-- Clave: (num_orden, cod_servicio). Sin FK: es la hoja de cálculo
-- importada tal cual.
-- ---------------------------------------------------------------

CREATE TABLE servicio_plano (
    num_orden        integer       NOT NULL,
    fecha_ingreso    date          NOT NULL,
    kilometraje      integer       NOT NULL,
    placa            char(6)       NOT NULL,
    modelo           varchar(30)   NOT NULL,
    marca            varchar(30)   NOT NULL,
    cedula_dueno     varchar(15)   NOT NULL,
    nombre_dueno     varchar(80)   NOT NULL,
    telefono_dueno   varchar(15)   NOT NULL,
    cod_servicio     char(3)       NOT NULL,
    nombre_servicio  varchar(60)   NOT NULL,
    precio_lista     integer       NOT NULL,
    precio_cobrado   integer       NOT NULL,
    cod_mecanico     char(3)       NOT NULL,
    nombre_mecanico  varchar(80)   NOT NULL,
    PRIMARY KEY (num_orden, cod_servicio)
);

INSERT INTO servicio_plano VALUES
    (5001, '2026-10-01', 45200, 'ABC123', 'Spark',  'Chevrolet', '1130000001', 'Sandra Patiño', '3001234567',
           'ACE', 'Cambio de aceite',           120000, 120000, 'M01', 'Rosa Quintero'),
    (5001, '2026-10-01', 45200, 'ABC123', 'Spark',  'Chevrolet', '1130000001', 'Sandra Patiño', '3001234567',
           'ALI', 'Alineación y balanceo',       80000,  80000, 'M02', 'Hernán Bedoya'),
    (5002, '2026-10-02', 88000, 'DEF456', 'Sail',   'Chevrolet', '16700002',   'Jorge Mejía',   '3104445566',
           'FRE', 'Cambio de pastillas de freno', 150000, 150000, 'M02', 'Hernán Bedoya'),
    (5002, '2026-10-02', 88000, 'DEF456', 'Sail',   'Chevrolet', '16700002',   'Jorge Mejía',   '3104445566',
           'ACE', 'Cambio de aceite',           120000, 110000, 'M01', 'Rosa Quintero'),
    (5003, '2026-10-05', 30100, 'GHI789', 'Logan',  'Renault',   '16700002',   'Jorge Mejía',   '3104445566',
           'DIA', 'Diagnóstico electrónico',     60000,  60000, 'M03', 'Ana Lucía Ríos'),
    (5003, '2026-10-05', 30100, 'GHI789', 'Logan',  'Renault',   '16700002',   'Jorge Mejía',   '3104445566',
           'BAT', 'Cambio de batería',          380000, 380000, 'M03', 'Ana Lucía Ríos'),
    (5004, '2026-10-09', 46900, 'ABC123', 'Spark',  'Chevrolet', '1130000001', 'Sandra Patiño', '3001234567',
           'DIA', 'Diagnóstico electrónico',     60000,  60000, 'M03', 'Ana Lucía Ríos'),
    (5005, '2026-10-14', 52000, 'JKL012', 'Duster', 'Renault',   '1144000003', 'Camilo Ibarra', '3157778899',
           'ACE', 'Cambio de aceite',           120000, 120000, 'M01', 'Rosa Quintero'),
    (5005, '2026-10-14', 52000, 'JKL012', 'Duster', 'Renault',   '1144000003', 'Camilo Ibarra', '3157778899',
           'FRE', 'Cambio de pastillas de freno', 150000, 150000, 'M02', 'Hernán Bedoya'),
    (5005, '2026-10-14', 52000, 'JKL012', 'Duster', 'Renault',   '1144000003', 'Camilo Ibarra', '3157778899',
           'ALI', 'Alineación y balanceo',       80000,  80000, 'M02', 'Hernán Bedoya'),
    (5006, '2026-10-20', 31500, 'GHI789', 'Logan',  'Renault',   '16700002',   'Jorge Mejía',   '3104445567',
           'ALI', 'Alineación y balanceo',       80000,  70000, 'M02', 'Hernán Bedoya');

-- ---------------------------------------------------------------
-- Verificación: 11 filas, 6 órdenes
-- ---------------------------------------------------------------

SELECT count(*) AS filas, count(DISTINCT num_orden) AS ordenes FROM servicio_plano;
