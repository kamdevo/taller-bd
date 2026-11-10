-- CONSULTAS SQL DE LA PARTE A  (esquema "tienda", creado con S16-tienda.sql)
-- Uso: docker compose exec postgres psql -U curso -d curso -f /scripts/parte-a.sql

SET search_path TO tienda;

-- 1) Para el pedido 1003: nombre del cliente, nombre de cada producto, cantidad y subtotal (cantidad * precio_unitario).

SELECT p.id_pedido, c.nombre AS nombre_cliente, pr.nombre AS nombre_producto, d.cantidad, (d.cantidad * d.precio_unitario) AS subtotal
FROM pedido p
INNER JOIN cliente c ON c.id_cliente = p.id_cliente
INNER JOIN detalle d ON d.id_pedido = p.id_pedido
INNER JOIN producto pr ON pr.id_producto = d.id_producto
WHERE p.id_pedido = 1003;

-- 2) Cada cliente con el nombre del cliente que lo refirió; los que llegaron solos también deben aparecer.

SELECT cl.nombre AS cliente, re.nombre AS referido_por 
FROM cliente cl
LEFT JOIN cliente re ON cl.referido_por = re.id_cliente;

-- 3) Productos que nunca se han vendido (en ningún pedido, ni siquiera cancelado).

SELECT p.*
FROM producto p
WHERE NOT  EXISTS (
    SELECT 1 
    FROM detalle d 
    WHERE  p.id_producto = d.id_producto
);

-- 4) Cada cliente con su número de pedidos (todos, incluidos los cancelados), mostrando 0 para quien no tiene ninguno. Ordenado de más a menos pedidos.

SELECT c.id_cliente, c.nombre, COUNT(p.id_cliente) AS numero_pedidos
FROM cliente c
LEFT JOIN pedido p ON c.id_cliente = p.id_cliente
GROUP BY  c.id_cliente, c.nombre
ORDER BY numero_pedidos DESC;

-- 5) Total vendido por categoría, sin cancelados, de mayor a menor.

SELECT pr.categoria, SUM(d.cantidad*d.precio_unitario) AS total 
FROM producto pr
INNER JOIN detalle d ON pr.id_producto = d.id_producto
INNER JOIN pedido p ON p.id_pedido = d.id_pedido
WHERE p.estado <> 'cancelado'
GROUP BY pr.categoria
ORDER BY total DESC;

-- 6) Meses de 2026 en que las ventas (sin cancelados) pasaron de $200 000, con su total. Pista: extract(month FROM fecha) da el número del mes.

SELECT EXTRACT(MONTH FROM p.fecha) AS mes, SUM(d.cantidad*d.precio_unitario) AS total
FROM pedido p
JOIN detalle d ON d.id_pedido = p.id_pedido 
WHERE p.estado <> 'cancelado'
-- AND EXTRACT(YEAR FROM p.fecha) = 2026
GROUP BY EXTRACT(MONTH FROM p.fecha)
HAVING SUM(d.cantidad*d.precio_unitario) > 200000
ORDER BY mes;

-- 7) Productos cuyo precio es mayor que el precio promedio de su categoría.
WITH promedio_categorias AS (
SELECT p.categoria, AVG(p.precio) AS precio_promedio
FROM producto p
GROUP BY p.categoria
)

SELECT * 
FROM promedio_categorias pr
INNER JOIN producto p ON p.categoria = pr.categoria
WHERE pr.categoria = p.categoria AND p.precio > pr.precio_promedio;

-- 8) Clientes de Cali que han comprado al menos un accesorio, sin cancelados. Cada cliente una sola vez.

SELECT c.id_cliente, c.nombre, c.ciudad
FROM cliente c
WHERE c.ciudad = 'Cali' AND EXISTS (
    SELECT 1 
    FROM pedido p
    INNER JOIN detalle d ON d.id_pedido = p.id_pedido
    INNER JOIN producto pr ON pr.id_producto = d.id_producto
    WHERE p.id_cliente = c.id_cliente
    AND p.estado <> 'cancelado'
    AND pr.categoria = 'Accesorio'
)
ORDER BY c.id_cliente ASC;

-- 9) Un compañero escribió esta consulta para "clientes que no han referido a nadie" y le devuelve 0 filas: SELECT nombre FROM cliente WHERE id_cliente NOT IN (SELECT referido_por FROM cliente); 
--    Explicar en un comentario por qué y escribir una versión correcta.
--
-- Consulta original (devuelve 0 filas):
--   SELECT nombre FROM cliente WHERE id_cliente NOT IN (SELECT referido_por FROM cliente);
--
-- EXPLICACIÓN: la columna referido_por es NULL para los clientes que llegaron solos,
-- así que la subconsulta devuelve una lista que contiene NULL, p. ej. (NULL, 1, 1, 2, ...).
-- "x NOT IN (a, b, NULL)" equivale a "x <> a AND x <> b AND x <> NULL".
-- La comparación x <> NULL nunca es verdadera ni falsa: es DESCONOCIDA (lógica de tres valores).
-- Un AND que incluye un DESCONOCIDO nunca llega a ser VERDADERO, así que el WHERE
-- descarta todas las filas y el resultado queda vacío, sin ningún error.
--
-- Corrección 1 (recomendada): NOT EXISTS, que no se ve afectado por los NULL.
SELECT c.nombre
FROM cliente c
WHERE NOT EXISTS (
    SELECT 1 
    FROM cliente r 
    WHERE r.referido_por = c.id_cliente
);

-- Corrección 2 (equivalente): sacar los NULL de la subconsulta.
SELECT nombre
FROM cliente
WHERE id_cliente NOT IN (SELECT referido_por FROM cliente WHERE referido_por IS NOT NULL);


-- 10) El o los clientes que más han gastado (sin cancelados), con su total.
WITH total_pedidos AS (
    SELECT p.id_cliente, SUM(d.cantidad * d.precio_unitario) AS total  
    FROM pedido p
    JOIN detalle d ON d.id_pedido = p.id_pedido
    WHERE p.estado <> 'cancelado'
    GROUP BY p.id_cliente
    ORDER BY p.id_cliente
)
, Ranking_cliente AS (
    SELECT c.id_cliente, c.nombre, t.total, DENSE_RANK() OVER (ORDER BY t.total DESC) AS posicion
    FROM cliente c 
    JOIN total_pedidos t ON t.id_cliente = c.id_cliente
)

SELECT * 
FROM Ranking_cliente
WHERE posicion = 1;


-- 11) Clientes que han comprado todos los productos de la categoría Grano, sin cancelados.
-- Versión principal: división con NOT EXISTS doble.
-- "Compró todos los Grano" = "no existe un producto Grano que no haya comprado (sin cancelados)".
SELECT c.id_cliente, c.nombre
FROM cliente c
WHERE NOT EXISTS (                       -- no existe...
    SELECT 1
    FROM producto pr
    WHERE pr.categoria = 'Grano'         -- ...un producto Grano...
      AND NOT EXISTS (                   -- ...que el cliente no haya comprado
          SELECT 1
          FROM pedido p
          JOIN detalle d ON d.id_pedido = p.id_pedido
          WHERE p.id_cliente = c.id_cliente
            AND d.id_producto = pr.id_producto
            AND p.estado <> 'cancelado'
      )
)
ORDER BY c.id_cliente;

-- Versión alternativa (reto R1): por conteo. Se usa COUNT(DISTINCT ...) porque un cliente
-- puede haber comprado el mismo producto en varios pedidos y COUNT(*) lo contaría dos veces.
WITH total_granos AS (
    SELECT COUNT(id_producto) AS n_granos
    FROM producto
    WHERE categoria = 'Grano'
)

SELECT c.id_cliente, c.nombre
FROM cliente c
INNER JOIN pedido p ON p.id_cliente = c.id_cliente
INNER JOIN detalle d ON d.id_pedido = p.id_pedido
INNER JOIN producto pr ON d.id_producto = pr.id_producto
WHERE pr.categoria = 'Grano' AND p.estado <> 'cancelado'
GROUP BY c.id_cliente, c.nombre
HAVING COUNT(DISTINCT d.id_producto) = (SELECT n_granos FROM total_granos);