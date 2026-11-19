# S20. Taller: desnormalización para rendimiento y Hito 3

**Módulo 5, semana 10, sesión 20 · Taller sincrónico (videollamada, salas por grupo de proyecto) · *checkpoint Hito 3***

S17 a S19 enseñaron a quitar la redundancia. Este taller cierra el módulo con la pregunta contraria: ¿cuándo vale la pena **volver a ponerla**, a propósito? La respuesta corta es "pocas veces, midiendo antes, y con un mecanismo que impida que la copia mienta". En la **parte A** se mide sobre una biblioteca grande generada por un script: primero la consulta normalizada, luego con índices, luego desnormalizada, y se ve qué pasa cuando alguien olvida actualizar la copia. En la **parte B**, cada grupo aplica a su esquema lo que encontró en S19, decide qué desnormaliza (si algo) y deja listo el Hito 3.

## Objetivos de la sesión

Al terminar, cada estudiante debe poder:

- Medir el tiempo de una consulta con `EXPLAIN ANALYZE` y señalar en el plan la parte que más cuesta.
- Explicar por qué un índice suele ser la primera respuesta a una consulta lenta, antes que desnormalizar, y crear uno.
- Desnormalizar un dato derivado (una columna calculada o una vista materializada), escribir la consulta que detecta cuando la copia se desincroniza y nombrar el mecanismo que la mantendría al día.
- Distinguir una desnormalización de un dato histórico que solo se parece a un dato redundante.
- Entregar el análisis de normalización del esquema del proyecto, con las correcciones aplicadas y las desnormalizaciones justificadas (Hito 3).

## Guía corta de pre-lectura (antes de la sesión)

### 1. Normalizar es el punto de partida, no la meta

Un esquema en 3FN guarda cada hecho una vez. El precio es que algunas preguntas necesitan juntar varias tablas: "¿cuántos ejemplares de este libro están disponibles?" exige recorrer `ejemplar` y `prestamo`. Con 30 libros no importa; con cientos de miles de préstamos y la pregunta repitiéndose en cada búsqueda del catálogo, puede empezar a notarse.

**Desnormalizar** es aceptar redundancia a propósito para que una consulta frecuente sea más barata. Es una decisión de diseño legítima, con tres condiciones:

1. **Se mide antes y después.** "Me parece que el join es lento" no basta. Muchas veces la consulta no es lenta, o se arregla con un índice (sección 4).
2. **Hay un mecanismo que mantiene la copia consistente** (sección 5). Desnormalizar sin él es volver a la planilla de S17.
3. **Queda documentada**: qué se copió, por qué, cómo se mantiene y cómo se detecta si se desincroniza.

### 2. Qué es (y qué no es) desnormalizar

| Forma | Ejemplo en la biblioteca | Qué se gana | Qué se arriesga |
|---|---|---|---|
| Guardar un dato derivado | `libro.disponibles` (ejemplares menos préstamos abiertos) | El catálogo no recorre los préstamos | Cada préstamo y devolución debe actualizarlo |
| Copiar una columna de otra tabla | `prestamo.nombre_lector` | El listado de préstamos no hace join con `lector` | Si el lector cambia de nombre, quedan copias viejas |
| Guardar un resumen | Una tabla o vista materializada con el top 20 de libros más prestados | El reporte se lee en vez de calcularse | El resumen se atrasa hasta que se recalcula |

Y lo que **no** es desnormalizar, aunque se parezca (S18, caso del precio cobrado; S19, caso 4): un dato que registra **cómo era algo en un momento**. El precio cobrado en una venta, la tarifa aplicada a un envío o el nombre del plan que tenía un socio cuando pagó dependen de la venta, el envío o el pago, no del estado actual del catálogo. Si la regla del negocio dice que deben conservarse aunque el catálogo cambie, guardarlos es **correcto en 3FN**: su determinante es la clave de la fila donde están.

### 3. Medir: `EXPLAIN ANALYZE`

`EXPLAIN` muestra el **plan** que el optimizador eligió para una consulta (el árbol de operadores de S9 y S13); `EXPLAIN ANALYZE` además la ejecuta y dice cuánto tardó cada parte:

```sql
EXPLAIN ANALYZE
SELECT … ;
```

```
 HashAggregate  (… ) (actual time=19.3..19.6 rows=5000 loops=1)
   ->  Hash Join  (…) (actual time=13.5..17.2 rows=15000 loops=1)
         ->  Seq Scan on prestamo p  (…) (actual time=11.5..11.8 rows=3750 loops=1)
               Filter: (fecha_devolucion IS NULL)
               Rows Removed by Filter: 300000
 …
 Execution Time: 19.760 ms
```

Lo mínimo para leerlo:

- Se lee **de adentro hacia afuera**: las líneas más indentadas se ejecutan primero.
- **`Execution Time`** al final: el tiempo total.
- **`Seq Scan`** recorre la tabla completa; **`Index Scan`** usa un índice. Un `Seq Scan` con muchas `Rows Removed by Filter` (aquí, recorrer 303 750 préstamos para quedarse con 3 750) es el primer sospechoso.
- `actual time=a..b`: `b` es cuándo terminó esa parte, en milisegundos desde que empezó la consulta.

Los tiempos dependen del computador y de qué tan "caliente" esté la base: se corre cada consulta **tres veces** y se anota el tiempo típico. Lo que se compara son los órdenes de magnitud (¿20 ms o 0,2 ms?), no los decimales.

### 4. Antes de desnormalizar: índices

Un **índice** es una estructura auxiliar (un árbol B, por defecto) que permite encontrar las filas con un valor dado sin recorrer toda la tabla, como el índice alfabético de un libro. **No es redundancia del modelo lógico**: no se consulta ni se actualiza a mano; el DBMS lo mantiene solo en cada `INSERT`, `UPDATE` y `DELETE`, así que no puede desincronizarse.

```sql
CREATE INDEX ejemplar_isbn_idx ON ejemplar (isbn);
-- índice parcial: solo las filas que cumplen la condición (los préstamos abiertos)
CREATE INDEX prestamo_abierto_idx ON prestamo (id_ejemplar) WHERE fecha_devolucion IS NULL;
```

Dos datos prácticos:

- PostgreSQL crea un índice automáticamente para cada `PRIMARY KEY` y cada `UNIQUE`, pero **no** para las columnas de una `FOREIGN KEY`. Los joins por FK (`ejemplar.isbn`, `prestamo.id_ejemplar`) son los primeros candidatos a un índice.
- Un índice no es gratis: ocupa espacio y hace un poco más lento cada `INSERT`. Se crean para consultas frecuentes, no "por si acaso" en todas las columnas.

El curso no profundiza en índices (cómo funciona un árbol B, cuándo el optimizador decide no usar uno); basta con saber que existen y que son lo primero que se prueba.

### 5. Mecanismos para que la copia no mienta

| Mecanismo | Cómo funciona | Cuándo sirve | Riesgo |
|---|---|---|---|
| La aplicación actualiza las dos cosas en la misma transacción | `BEGIN; INSERT INTO prestamo …; UPDATE libro SET disponibles = disponibles - 1 …; COMMIT;` | Hay un solo programa que escribe | Basta con que otro programa, o alguien en `psql`, lo olvide una vez |
| Un **trigger** | El DBMS ejecuta un `UPDATE` automáticamente después de cada `INSERT`/`UPDATE` en `prestamo` | La copia debe estar siempre al día | Se ve en M6 (Hito 4) |
| Una **vista materializada** | `CREATE MATERIALIZED VIEW … AS SELECT …` guarda el resultado; `REFRESH MATERIALIZED VIEW …` lo recalcula | Resúmenes que pueden estar atrasados unas horas (reportes) | Muestra datos viejos hasta el próximo `REFRESH` |
| Una **columna generada** | `subtotal integer GENERATED ALWAYS AS (cantidad * precio) STORED` | El dato derivado depende de columnas **de la misma fila** | Ninguno para la consistencia: no se puede escribir a mano |
| Una **restricción** | Una FK compuesta que obliga a que la copia coincida con el original (S18, solución de la parte C) | La copia es de una columna de otra tabla | Solo verifica, no actualiza |

Y en todos los casos, una **consulta de verificación** que compare la copia con su cálculo y devuelva las filas que no coinciden (S19, caso 4). Si devuelve 0 filas, la copia está bien; si no, se sabe exactamente dónde está el problema.

### 6. El Hito 3

El documento del proyecto (sección 8) pide: *esquema revisado, análisis de formas normales (mínimo 3FN) con evidencia de dependencias funcionales, ajustes aplicados si se encontraron anomalías, o desnormalización deliberada y justificada*, entregado como un **documento breve de normalización** (antes y después) más el **esquema SQL actualizado**. La rúbrica está en la sección 9 del mismo documento (6 puntos). La parte B de hoy está organizada para producir exactamente eso.

**Pre-trabajo (20 min, antes de la sesión):**

1. Copiar el script [`S20-rendimiento.sql`](S20-rendimiento.sql) (publicado en el LMS) en `entorno-docker/postgres/scripts/` y ejecutarlo (tarda unos segundos):

   ```bash
   docker compose exec postgres psql -U curso -d curso -f /scripts/S20-rendimiento.sql
   ```

   Crea el esquema `rendimiento`: 5 000 títulos, 15 000 ejemplares (3 por título), 2 000 lectores y 303 750 préstamos, de los cuales 3 750 están abiertos. Está en 3FN y solo tiene los índices de las PK.
2. Tener a mano la tabla de la parte B de S19 (el examen del esquema del proyecto), el `reportes.sql` y el `datos-prueba.sql` de S16.

## Mecánica (2 horas)

1. **(10 min) Encuadre.** El profesor corre `EXPLAIN ANALYZE` sobre una consulta de S15 y muestra cómo leer el plan (sección 3).
2. **(40 min) Parte A: medir, indexar, desnormalizar.** Sobre el esquema `rendimiento` (`SET search_path TO rendimiento;`), en parejas, con la tabla de mediciones de abajo.
3. **(60 min) Parte B: Hito 3 sobre el esquema propio.** Todo el grupo.
4. **(10 min) Cierre y checkpoint del Hito 3.** Cada grupo revisa la lista de la sección "Checkpoint". El profesor recuerda la fecha de entrega y que en M6 los triggers y procedimientos (Hito 4) son el lugar natural para mantener lo que se haya desnormalizado.

### Parte A: medir, indexar, desnormalizar

**A1. La consulta del catálogo.** La búsqueda del catálogo muestra, para cada título que coincide, cuántos ejemplares hay disponibles:

```sql
SELECT l.isbn, l.titulo, count(e.id_ejemplar) - count(p.id) AS disponibles
FROM   libro l
JOIN   ejemplar e      ON e.isbn = l.isbn
LEFT JOIN prestamo p   ON p.id_ejemplar = e.id_ejemplar
                      AND p.fecha_devolucion IS NULL
WHERE  l.titulo LIKE 'Libro 12%'
GROUP BY l.isbn, l.titulo;
```

(a) ¿Por qué `LEFT JOIN` y `count(p.id)`? (S15, sección 4.5.) (b) Correrla con `EXPLAIN ANALYZE` tres veces y anotar el tiempo. (c) ¿Qué nodo del plan se lleva la mayor parte del tiempo, y cuántas filas descarta?

**A2. Índices.** Crear los dos índices de la sección 4 y repetir A1 (b) y (c). ¿Qué nodo cambió? ¿Hubo que agregar alguna redundancia al modelo?

**A3. Desnormalizar `disponibles`.** (a) Agregar a `libro` una columna `disponibles` (`NOT NULL`, con un `CHECK` que no la deje ser negativa) y llenarla con un solo `UPDATE` que la calcule. Antes de correrlo, predecir cuántos libros deben quedar con 3 disponibles y cuántos con 2 (pista: los préstamos abiertos son los de los ejemplares múltiplos de 4; un libro tiene los ejemplares 3i-2, 3i-1 y 3i). (b) Escribir la consulta del catálogo usando la columna, medirla y anotar el tiempo. (c) Simular a alguien que registra un préstamo y olvida actualizar la copia:

```sql
INSERT INTO prestamo VALUES (400001, 1, '1000000001', CURRENT_DATE, CURRENT_DATE + 14, NULL);
```

Escribir una vista `descuadre` que devuelva los libros cuyo `disponibles` guardado no coincide con el calculado, y mostrar que encuentra el problema. (d) ¿Cuál mecanismo de la sección 5 usarían para mantener `disponibles` en el proyecto, y por qué?

**A4. El reporte de los 20 más prestados.** (a) Medir el reporte 1 de S15 sobre este esquema (préstamos → ejemplar → libro, agrupado por libro, `FETCH FIRST 20 ROWS WITH TIES`). (b) Guardarlo como vista materializada `top_prestados`, y medir `SELECT * FROM top_prestados`. (c) Simular un mes de mucho movimiento de un libro que no estaba en el top:

```sql
INSERT INTO prestamo
SELECT 500000 + g, 15000, (1000000001 + g % 2000)::text,
       DATE '2025-06-01', DATE '2025-06-15', DATE '2025-06-10'
FROM   generate_series(1, 4000) AS g;
```

¿Qué muestra `top_prestados` ahora? ¿Y la consulta del punto (a)? Correr `REFRESH MATERIALIZED VIEW top_prestados;` y comparar. (d) Para la biblioteca del proyecto, ¿cada cuánto habría que refrescarla, y quién lo haría? ¿Es aceptable que el reporte esté atrasado?

**A5. ¿Derivado o histórico?** Con la regla por defecto del proyecto (plazo de 14 días), `fecha_esperada` se puede calcular como `fecha_prestamo + 14`. ¿Es redundante guardarla? Responder en dos casos: si el plazo nunca cambia, y si la biblioteca puede cambiar el plazo o dar plazos especiales.

**Tabla de mediciones** (una por pareja, en el entregable):

| Consulta | Sin índices | Con índices (A2) | Desnormalizada (A3 o A4) |
|---|---|---|---|
| Catálogo (`Libro 12%`) | | | |
| Top 20 más prestados | | (no aplica) | |

### Parte B: Hito 3 sobre el esquema propio

1. **Partir del examen de S19** (tabla de la parte B). Si quedó alguna tabla sin analizar, completarla primero.
2. **Aplicar las correcciones** que se propusieron, con una migración `postgres/scripts/normalizacion.sql` que siga la receta de S19 (sección 4): evidencia, `BEGIN`, crear, copiar, verificar con conteos y `EXCEPT`, quitar lo viejo, `COMMIT`. Si el esquema ya estaba en 3FN, este archivo puede no existir; lo que no puede faltar es la justificación en el documento.
3. **Actualizar el esquema de `postgres/init/`** para que una base vacía quede creada ya normalizada. Para probarlo **sin borrar la base del grupo**, crear una base aparte y correrlo ahí:

   ```bash
   docker compose exec postgres psql -U curso -d curso -c "CREATE DATABASE prueba_init;"
   docker compose exec postgres psql -U curso -d prueba_init -f /docker-entrypoint-initdb.d/01_esquema.sql
   ```

   (ajustando el nombre del archivo al del grupo). Si corre limpio, `DROP DATABASE prueba_init;`.
4. **Decidir qué se desnormaliza.** Como mínimo, revisar `ejemplares_disponibles` (o como se llame en el esquema) y el `estado` del préstamo, si existen. Para cada uno: ¿se calcula o se guarda? Si se guarda, ¿con qué mecanismo se mantiene (sección 5) y cuál es su consulta de verificación? Si el mecanismo es un trigger, se anota como pendiente para el Hito 4 y, mientras tanto, se deja la consulta de verificación. No desnormalizar nada también es una respuesta válida, si se justifica.
5. **Comprobar que los reportes siguen funcionando:** correr `datos-prueba.sql` y `reportes.sql` de S16 sobre el esquema nuevo (ajustando las consultas si cambiaron las tablas) y confirmar que los resultados esperados no cambiaron.
6. **Escribir el documento de normalización** (máximo 3 páginas), con estas secciones:
   1. Esquema antes (diagrama o lista de tablas).
   2. Dependencias funcionales por tabla, con la regla que justifica cada una, y claves candidatas.
   3. Forma normal de cada tabla y problemas encontrados, con la consulta de evidencia y su resultado.
   4. Cambios aplicados y cómo se migraron los datos (conteos antes y después).
   5. Desnormalizaciones deliberadas: qué, por qué (con medición si es por rendimiento), cómo se mantiene consistente y su consulta de verificación. O la justificación de por qué no hay ninguna.
   6. Esquema después, en 3FN o más (indicando cuál tabla queda en 3FN y no en FNBC, si alguna).

## Entregable

**Por grupo:**

En la fecha del Hito 3, en el repositorio del grupo: el documento de normalización, `postgres/init/` actualizado, `postgres/scripts/normalizacion.sql` (si hubo cambios) y los reportes de S16 corridos sobre el esquema nuevo.

## Checkpoint del Hito 3

| Pieza (rúbrica del Hito 3) | Dónde queda | Sesión |
|---|---|---|
| Análisis de formas normales con dependencias funcionales | Documento de normalización, secciones 2 y 3 | S18 (tarea), S19 (parte B) |
| Corrección de anomalías o desnormalización justificada | Documento, secciones 4 y 5; `normalizacion.sql` | S19, S20 |
| Esquema actualizado y coherente con el análisis | `postgres/init/`, probado en una base vacía; documento, sección 6 | S20 |

