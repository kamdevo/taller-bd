-- Ejecutar primero: SET search_path TO automotriz;

-- (a) PASO 1: buscar filas que contradicen cada dependencia
-- (si devuelve filas, hay un dato inconsistente)
SELECT num_orden FROM servicio_plano GROUP BY num_orden
 HAVING COUNT(DISTINCT (fecha_ingreso, kilometraje, placa)) > 1;
SELECT placa FROM servicio_plano GROUP BY placa
 HAVING COUNT(DISTINCT (modelo, cedula_dueno)) > 1;
SELECT modelo FROM servicio_plano GROUP BY modelo
 HAVING COUNT(DISTINCT marca) > 1;
SELECT cedula_dueno FROM servicio_plano GROUP BY cedula_dueno
 HAVING COUNT(DISTINCT (nombre_dueno, telefono_dueno)) > 1;
SELECT cod_servicio FROM servicio_plano GROUP BY cod_servicio
 HAVING COUNT(DISTINCT (nombre_servicio, precio_lista)) > 1;
SELECT cod_mecanico FROM servicio_plano GROUP BY cod_mecanico
 HAVING COUNT(DISTINCT nombre_mecanico) > 1;

-- Corrección (EJEMPLO: cambiar por el dato correcto y justificar)
-- UPDATE servicio_plano SET modelo = 'Sail'
--  WHERE placa = 'DEF456';   -- justificación: ...

-- (b) PASO 2: crear tablas 3FN
CREATE TABLE dueno (
  cedula VARCHAR(15) PRIMARY KEY,
  nombre VARCHAR(80) NOT NULL,
  telefono VARCHAR(15) NOT NULL);
CREATE TABLE modelo (
  modelo VARCHAR(40) PRIMARY KEY,
  marca VARCHAR(40) NOT NULL);
CREATE TABLE mecanico (
  cod_mecanico VARCHAR(5) PRIMARY KEY,
  nombre_mecanico VARCHAR(80) NOT NULL);
CREATE TABLE servicio (
  cod_servicio CHAR(3) PRIMARY KEY,
  nombre_servicio VARCHAR(60) NOT NULL,
  precio_lista INTEGER NOT NULL);
CREATE TABLE vehiculo (
  placa VARCHAR(10) PRIMARY KEY,
  modelo VARCHAR(40) NOT NULL REFERENCES modelo,
  cedula_dueno VARCHAR(15) NOT NULL REFERENCES dueno);
CREATE TABLE orden (
  num_orden INTEGER PRIMARY KEY,
  fecha_ingreso DATE NOT NULL,
  kilometraje INTEGER NOT NULL,
  placa VARCHAR(10) NOT NULL REFERENCES vehiculo);
CREATE TABLE orden_servicio (
  num_orden INTEGER REFERENCES orden,
  cod_servicio CHAR(3) REFERENCES servicio,
  precio_cobrado INTEGER NOT NULL,
  cod_mecanico VARCHAR(5) NOT NULL REFERENCES mecanico,
  PRIMARY KEY (num_orden, cod_servicio));

-- (c) PASO 3: llenar en orden que respete las FK
INSERT INTO dueno SELECT DISTINCT cedula_dueno, nombre_dueno, telefono_dueno FROM servicio_plano;
INSERT INTO modelo SELECT DISTINCT modelo, marca FROM servicio_plano;
INSERT INTO mecanico SELECT DISTINCT cod_mecanico, nombre_mecanico FROM servicio_plano;
INSERT INTO servicio SELECT DISTINCT cod_servicio, nombre_servicio, precio_lista FROM servicio_plano;
INSERT INTO vehiculo SELECT DISTINCT placa, modelo, cedula_dueno FROM servicio_plano;
INSERT INTO orden SELECT DISTINCT num_orden, fecha_ingreso, kilometraje, placa FROM servicio_plano;
INSERT INTO orden_servicio SELECT DISTINCT num_orden, cod_servicio, precio_cobrado, cod_mecanico FROM servicio_plano;

SELECT 'dueno' tabla, COUNT(*) FROM dueno UNION ALL
SELECT 'modelo', COUNT(*) FROM modelo UNION ALL
SELECT 'mecanico', COUNT(*) FROM mecanico UNION ALL
SELECT 'servicio', COUNT(*) FROM servicio UNION ALL
SELECT 'vehiculo', COUNT(*) FROM vehiculo UNION ALL
SELECT 'orden', COUNT(*) FROM orden UNION ALL
SELECT 'orden_servicio', COUNT(*) FROM orden_servicio;

-- (d) PASO 4: reconstruir y comparar con EXCEPT en los dos sentidos
CREATE VIEW reconstruida AS
SELECT o.num_orden, o.fecha_ingreso, o.kilometraje, o.placa, v.modelo, m.marca,
       v.cedula_dueno, d.nombre, d.telefono,
       os.cod_servicio, s.nombre_servicio, s.precio_lista, os.precio_cobrado,
       os.cod_mecanico, me.nombre_mecanico
FROM orden o
JOIN vehiculo v ON v.placa = o.placa
JOIN modelo m ON m.modelo = v.modelo
JOIN dueno d ON d.cedula = v.cedula_dueno
JOIN orden_servicio os ON os.num_orden = o.num_orden
JOIN servicio s ON s.cod_servicio = os.cod_servicio
JOIN mecanico me ON me.cod_mecanico = os.cod_mecanico;

SELECT * FROM servicio_plano EXCEPT SELECT * FROM reconstruida;  -- debe dar 0 filas
SELECT * FROM reconstruida EXCEPT SELECT * FROM servicio_plano;  -- debe dar 0 filas

-- (e) PASO 5: anomalías (hacer DESPUÉS de (d))
-- Actualización: un solo UPDATE cambia el teléfono
UPDATE dueno SET telefono = '3000000000' WHERE cedula = '1144000003';
-- Inserción: mecánico nuevo sin servicios
INSERT INTO mecanico VALUES ('M09', 'Mecánico Nuevo');
-- Borrado: quitar la orden 5005 sin perder vehículo ni servicio
DELETE FROM orden_servicio WHERE num_orden = 5005;
DELETE FROM orden WHERE num_orden = 5005;
SELECT * FROM vehiculo WHERE placa = 'JKL012';  -- el vehículo sigue
SELECT * FROM servicio;                          -- el catálogo sigue completo
