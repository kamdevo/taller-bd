# Hito 2 · Tabla de verificación de la Parte B (Reportes)

**Esquema:** `biblioteca` (`postgres/init/01_esquema.sql`)
**Datos de prueba:** `postgres/scripts/datos-prueba.sql` (100 préstamos inventados: 13 para los casos, 6 más de Juan David y 81 de relleno devueltos a tiempo; fechas relativas a `CURRENT_DATE`)
**Consultas de reportes:** `postgres/scripts/reportes.sql` (cada reporte guardado también como vista)
**Salida de psql:** `assets/Entrega_S16/salida-reportes.txt`
**Referencia:** Sección 4 de `docs/s16-taller-consultas.md` y sección 8 de `docs/s15-consultas-avanzadas_estudiante.md`

## Cómo reproducirlo

Con la base recién creada (esquema de `postgres/init/`) y los CSV semilla cargados:

```bash
docker compose exec postgres psql -U curso -d curso -v archivo=/scripts/datos/libros_semilla.csv   -f /scripts/S14-carga-libros.sql
docker compose exec postgres psql -U curso -d curso -v archivo=/scripts/datos/libros_propio.csv    -f /scripts/S14-carga-libros.sql
docker compose exec postgres psql -U curso -d curso -v archivo=/scripts/datos/lectores_semilla.csv -f /scripts/S14-carga-lectores.sql
docker compose exec postgres psql -U curso -d curso -f /scripts/datos-prueba.sql
docker compose exec postgres psql -U curso -d curso -f /scripts/reportes.sql
```

## Decisiones del grupo

| Decisión | Regla adoptada | Por qué |
|---|---|---|
| ¿Préstamo devuelto? | `estado = 'devuelto'` (y su fila en `devolucion`) | Lo registra el bibliotecario en el momento de la devolución. |
| ¿Préstamo en mora? | `estado <> 'devuelto' AND fecha_esperada_devolucion < CURRENT_DATE` | Se calcula con fechas. La columna `estado = 'en_mora'` no se actualiza sola al pasar la fecha (no hay trigger hasta el Hito 4), S15 §8.5. |
| Préstamo que vence hoy | **No** es mora (`<` estricto) | Tiene todo el día para devolverlo. |
| Libros sin préstamos (R1) | Se cuentan con 0 (`LEFT JOIN` + `count(p.id)`); entran al top solo si hay menos de 20 libros prestados | En una base recién cargada el reporte no queda vacío. |
| Empates en el top 20 (R1) | `ORDER BY prestamos DESC, titulo ASC LIMIT 20` | Siempre salen exactamente 20 filas. Si hay empate en el puesto 20, entra el que va primero en orden alfabético: el corte es fijo, no al azar. |
| Empates en el 1.er lugar (R2) | `= (SELECT max(...))` | "El **o los** lectores". |
| Unidad del reporte 4 | Una fila por **préstamo** | La notificación debe decir qué libro se debe y cuántos días de mora lleva. |

## Resultados esperados (escritos antes de correr)

Los préstamos de prueba y lo que debía devolver cada reporte están escritos en el encabezado de `datos-prueba.sql`, antes de cualquier consulta. Resumen (d = hoy):

| # | Lector | Libro | Esperada | Devuelto | `estado` guardado |
|---|---|---|---|---|---|
| 1–3 | Mariana | Cien años, Rayuela, Ficciones | d-46, d-31, d-16 | a tiempo | devuelto |
| 4–5 | Santiago | Cien años, Rayuela | d-41, d-26 | a tiempo | devuelto |
| 6 | Santiago | Don Quijote | d-21 | **d-10 (tarde)** | devuelto |
| 7 | Juan David | Ficciones | d-26 | — | activo (*sin actualizar*) |
| 8 | Juan David | Cien años | d-6 | — | en_mora |
| 9 | Juan David | Rayuela | **d (hoy)** | — | activo |
| 10 | Valentina | La sombra del viento | d-16 | — | en_mora |
| 11 | Valentina | Cien años | d+5 | — | activo |
| 12 | Camila | Pedro Páramo | d-2 | — | activo (*sin actualizar*) |
| 13 | Camila | Pedro Páramo | d-56 | a tiempo | devuelto |
| 14–19 | Juan David | Harry Potter, El principito, 1984, Sapiens, El nombre del viento, Orgullo y prejuicio | d+9 | — | activo (a tiempo) |
| 20–100 | Todos menos Juan David y Nicolás (Mariana y Santiago 5 cada uno, los demás 4 o 5) | 32 libros del catálogo | d-195 a d-16 | a tiempo (2 días antes) | devuelto |
| — | Nicolás | *(sin préstamos)* | | | |

## Tabla de verificación (casos de la sección 4)

| # | Caso | Reporte | Resultado esperado | Resultado obtenido | ¿Coincide? / Corrección |
|---|---|---|---|---|---|
| 1 | Un libro que nadie ha prestado | 1 / 1b | Hay más de 20 libros prestados, así que los de 0 no entran al top 20. El reporte 1b lista 6 libros con 0: Breve historia del tiempo, El Aleph (las dos ediciones), Rayuela (..9990000005), Trilce y Veinte poemas de amor (..9990000006). | ⏳ Pendiente de correr. | *Corregido:* la versión anterior partía de `prestamo` con `INNER JOIN` y ocultaba estos libros; ahora es `LEFT JOIN` desde `libro`. |
| 2 | Dos libros empatados en el último puesto del top | 1 | Cosmos, Crónica de una muerte anunciada y Un mundo feliz empatan con 2 en los puestos 20 a 22; entra Cosmos (primero en el alfabeto). Top 20 completo: Cien años 9, Don Quijote 8, Rayuela 7, El principito 6, Harry Potter 6, 1984 5, La sombra del viento 5, El nombre del viento 4, Ficciones 4, Pedro Páramo 4, Sapiens 4, Crimen y castigo 3, El amor en los tiempos del cólera 3, Fahrenheit 451 3, La casa de los espíritus 3, Matilda 3, Orgullo y prejuicio 3, Alicia 2, Como agua para chocolate 2, Cosmos 2. | ⏳ Pendiente de correr. | *Corregido:* el `LIMIT 20` anterior no tenía desempate, así que cortaba los empatados al azar; ahora el desempate por título está documentado. |
| 3 | Dos lectores empatados en el primer lugar | 2 | Mariana Gómez Rojas 8 y Santiago Rodríguez Pérez 8. Nadie más pasa de 5. | ⏳ Pendiente de correr. | |
| 4 | Lector con varios préstamos abiertos y ninguno devuelto | 2 | Juan David (9 préstamos, más que los ganadores, 0 devueltos) no sale. | ⏳ Pendiente de correr. | |
| 5 | Préstamo devuelto después de la fecha esperada | 3 y 4 | Santiago (Don Quijote, devuelto 11 días tarde) no sale en el 3 ni en el 4. | No sale en ninguno. | ✅ Coincide. |
| 6 | Préstamo abierto que vence hoy | 3 y 4 | Rayuela de Juan David no sale en el 4 (regla `<` estricto). Juan David sí sale en el 3, pero por sus otros préstamos. | Rayuela no aparece en el 4; Juan David sale en el 3 por Ficciones y Cien años. | ✅ Coincide. *Corregido:* antes este caso no existía en los datos. |
| 7 | Lector con dos préstamos en mora | 3 y 4 | Juan David: **1 vez** en el 3 y **2 veces** en el 4 (Ficciones 26 días, Cien años 6 días). | Reporte 3: 1 fila. Reporte 4: préstamos 7 (26 días) y 8 (6 días). | ✅ Coincide. *Corregido:* el reporte 4 agrupaba con `STRING_AGG` en una sola fila por lector; ahora es una fila por préstamo, con el título y los días de mora. |
| 8 | Lector sin ningún préstamo | Todos | Nicolás Cárdenas no aparece en ningún reporte ni produce errores. | No aparece en ninguno; los cuatro reportes corren sin error. | ✅ Coincide. |
| extra | Préstamo vencido con `estado = 'activo'` (estado sin actualizar) | 3 y 4 | Los préstamos 7 y 12 cuentan como mora aunque su `estado` diga `activo`. | Camila sale en el 3; los préstamos 7 y 12 salen en el 4. | ✅ Coincide. *Corregido:* antes los reportes filtraban por `estado = 'en_mora'` y estos préstamos se perdían. |

## Salida obtenida (resumen)

```
Reporte 3: Camila Hernández Torres · Valentina López Díaz · Juan David Martínez Ruiz   (3 filas)
Reporte 4:  7 | Juan David Martínez Ruiz | Ficciones            | 26
           10 | Valentina López Díaz     | La sombra del viento | 16
            8 | Juan David Martínez Ruiz | Cien años de soledad |  6
           12 | Camila Hernández Torres  | Pedro Páramo         |  2                          (4 filas)
```

La salida completa de `psql` está en `assets/Entrega_S16/salida-reportes.txt`. Las fechas absolutas cambian según el día en que se corra; los días de mora y las filas no cambian.
