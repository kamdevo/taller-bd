# S19. Taller: detectar y corregir esquemas mal diseñados

**Módulo 5, semana 10, sesión 19 · Taller sincrónico (videollamada, salas por grupo de proyecto)**

En S18 la normalización empezaba con las reglas del negocio escritas y una tabla plana que se sabía que estaba mal. En la vida real el orden es otro: alguien hereda una base que **ya está funcionando**, con datos, y los síntomas llegan como quejas ("el reporte da un número raro", "no me deja registrar esto"). Este taller es una "clínica de esquemas": cuatro bases pequeñas de negocios distintos, cada una con un defecto de diseño diferente. Para cada una, el grupo encuentra el problema, lo **demuestra** con una consulta, propone el esquema corregido y **migra los datos** sin perder nada. La última parte aplica el mismo examen al esquema del proyecto, como borrador del Hito 3 (S20).

## Objetivos de la sesión

Al terminar, cada estudiante debe poder:

- Reconocer en un esquema existente las señales de un mal diseño: listas en una celda, columnas numeradas, datos de otra entidad, una clave sustituta sin la clave natural protegida, datos calculables.
- Convertir cada sospecha en evidencia con una consulta SQL sobre los datos, y explicar qué forma normal se incumple y por qué.
- Diseñar el esquema corregido y escribir la migración en SQL (`string_to_table`, `UNION ALL`, `INSERT … SELECT DISTINCT`, `ALTER TABLE`) dentro de una transacción, verificando que no se pierde ni se inventa ningún dato.
- Distinguir un dato redundante de uno histórico que solo se parece a uno redundante.
- Aplicar el mismo examen al esquema del propio proyecto.

## Guía corta de pre-lectura (antes de la sesión)

### 1. Señales de alarma

Ninguna de estas señales prueba por sí sola que el esquema esté mal, pero todas merecen una revisión:

| Señal | Ejemplo | Sospecha |
|---|---|---|
| Una columna que guarda varios valores separados por comas, `;` o espacios | `autores = 'Silberschatz, Korth, Sudarshan'` | No está en 1FN |
| Columnas numeradas | `telefono1`, `telefono2`, `telefono3` | Grupo repetido: no está en 1FN |
| Muchas columnas casi siempre en `NULL`, en paralelo | `hijo3`, `edad_hijo3` vacías en la mayoría de filas | Grupo repetido |
| Columnas con el nombre de **otra** entidad | `nombre_depto` dentro de `empleado` | Dependencia parcial o transitiva (2FN, 3FN) |
| El mismo texto largo repetido en muchas filas | El nombre completo de una facultad, fila tras fila | Determinante que no es clave |
| Una clave sustituta (`id serial`) sin `UNIQUE` sobre la clave natural | `nota(id, cod_est, cod_curso, …)` | Filas duplicadas; dependencias escondidas |
| Una columna que se puede calcular con otras | `subtotal = cantidad * precio` | Redundancia de un dato derivado |

Sobre la clave sustituta vale la pena detenerse. Una tabla con PK `id` parece estar automáticamente en 2FN ("la clave tiene un solo atributo"). No es así: las formas normales hablan de **todas** las claves candidatas, y si (`cod_est`, `cod_curso`) también identifica una nota, es candidata aunque nadie la haya declarado. Las dependencias de una parte de ella siguen ahí. **Agregar un `id` no normaliza nada**; solo cambia el nombre de la PK.

### 2. De la sospecha a la evidencia

Cada sospecha se confirma (o se descarta) con una consulta. Las de S15 y S17 alcanzan:

```sql
-- ¿Cuánto se repite un dato? (redundancia)
SELECT x, count(*) FROM t GROUP BY x ORDER BY count(*) DESC;

-- ¿Los datos contradicen X → Y? (S17, sección 5.3)
SELECT x FROM t GROUP BY x HAVING count(DISTINCT y) > 1;

-- ¿Hay filas repetidas en la clave natural? (clave sustituta sin UNIQUE)
SELECT a, b, count(*) FROM t GROUP BY a, b HAVING count(*) > 1;

-- ¿El dato derivado coincide con su cálculo?
SELECT * FROM t WHERE subtotal <> cantidad * precio;
```

Y para las listas en una celda, la evidencia suele ser una consulta que da una respuesta **equivocada**: `WHERE autores LIKE '%Korth%'` también encuentra a un autor llamado Korthals, y no encuentra `'korth'` si alguien lo escribió en minúscula.

### 3. Herramientas para migrar

| Para | SQL (PostgreSQL) |
|---|---|
| Partir un texto en filas | `string_to_table(autores, ',')`: una fila por cada pedazo. En el `FROM`: `FROM libro l, string_to_table(l.autores, ',') AS a` (una fila por libro y autor; un libro con `NULL` no produce filas) |
| Limpiar los pedazos | `trim(c)` quita espacios al inicio y al final; `initcap(c)` deja la primera letra de cada palabra en mayúscula; `lower(c)`, todo en minúscula |
| Pasar columnas numeradas a filas | `SELECT id, col1 FROM t UNION ALL SELECT id, col2 FROM t WHERE col2 IS NOT NULL UNION ALL …` |
| Llenar una tabla nueva sin repeticiones | `INSERT INTO nueva SELECT DISTINCT … FROM vieja` (S17, S18) |
| Agregar una FK o quitar columnas de una tabla existente | `ALTER TABLE t ADD FOREIGN KEY (col) REFERENCES otra, DROP COLUMN col2;` |
| Renombrar una tabla | `ALTER TABLE vieja RENAME TO nueva;` |
| Ofrecer un dato calculado sin guardarlo | `CREATE VIEW … AS SELECT …, cantidad * precio AS subtotal FROM …` |

`string_to_table` existe desde PostgreSQL 14 (el curso usa 16). En otros motores hay equivalentes (`STRING_SPLIT` en SQL Server, `JSON_TABLE` o una tabla de números en MySQL).

### 4. Una migración segura

Una base en producción no se arregla borrando columnas de una vez. El orden recomendado:

1. **Evidencia:** las consultas de la sección 2. Si aparecen datos que contradicen una dependencia o filas duplicadas, se decide cuál es el dato correcto **y se deja escrito por qué**.
2. **`BEGIN;`** Todo lo que sigue va en una transacción (S13): si algo falla, `ROLLBACK` deja la base como estaba.
3. **Crear** las tablas nuevas, con PK, FK, `NOT NULL` y `UNIQUE`.
4. **Copiar** los datos con `INSERT … SELECT`.
5. **Verificar:** contar filas (¿cuántas **deberían** salir? calcularlo antes), y comparar con `EXCEPT` lo que se puede reconstruir con joins contra lo que había.
6. **Quitar** lo viejo (`DROP COLUMN`, `DROP TABLE`) solo después de verificar.
7. **`COMMIT;`**

**Pre-trabajo (15 min, antes de la sesión):**

1. Leer esta pre-lectura y repasar la receta de S18 (sección 6 de su pre-lectura).
2. Copiar el script [`S19-esquemas.sql`](S19-esquemas.sql) (publicado en el LMS) en `entorno-docker/postgres/scripts/` y ejecutarlo:

   ```bash
   docker compose exec postgres psql -U curso -d curso -f /scripts/S19-esquemas.sql
   ```

3. Traer escritas las dependencias funcionales del esquema del proyecto, tabla por tabla, con la regla que justifica cada una (la tarea que dejó S18).

## Los cuatro casos

Cada caso vive en su propio esquema (`SET search_path TO gimnasio;`, etc.). Para cada uno, el grupo entrega:

- **(a) Diagnóstico:** qué está mal (cada caso tiene un problema principal, el que explica la queja, y al menos uno más), con las dependencias funcionales involucradas y la forma normal que se incumple (o, si no es de normalización, qué tipo de problema es).
- **(b) Evidencia:** una o más consultas que lo demuestran sobre los datos, con su resultado.
- **(c) Esquema corregido:** las tablas, con PK y FK.
- **(d) Migración:** el SQL, dentro de `BEGIN` … `COMMIT`, siguiendo la sección 4.
- **(e) Verificación:** conteos esperados frente a obtenidos, y la consulta de la queja original resuelta en el esquema nuevo.
- La pregunta propia de cada caso.

### Caso 1: gimnasio

```
socio (id_socio PK, nombre, plan, valor_plan, clases)
```

`clases` guarda las clases en las que está inscrito el socio, separadas por `;`. Cada plan (Mensual, Trimestral, Anual) tiene un valor fijo. Hay clases distintas con nombres parecidos: Spinning y Spinning avanzado.

> **La queja:** "Le pedí al sistema cuántos socios hay en Yoga para abrir otro grupo y me dijo 2, pero yo sé que son 3. Y en Spinning me dijo 3, cuando son 2."

**Pregunta propia:** después de migrar, el gimnasio quiere guardar el horario de cada clase (día y hora). ¿En cuál tabla va, y por qué habría sido imposible hacerlo bien con el diseño original?

### Caso 2: farmacia

```
formula (num_formula PK, fecha, doc_paciente, nombre_paciente,
         medicamento1, dosis1, medicamento2, dosis2, medicamento3, dosis3)
```

Cada fórmula médica tiene uno o varios medicamentos, cada uno con su dosis. Un mismo medicamento no aparece dos veces en la misma fórmula.

> **La queja:** "El médico le recetó cuatro medicamentos a un paciente y el sistema solo me deja registrar tres. Y para saber cuántas fórmulas llevan acetaminofén tengo que buscar en tres columnas."

**Pregunta propia:** ¿por qué no basta con agregar `medicamento4` y `dosis4`? Dar al menos dos razones.

### Caso 3: cursos libres

```
inscripcion (id PK serial, doc_participante, nombre_participante, correo,
             cod_curso, nombre_curso, cod_sede, direccion_sede, valor_pagado)
```

Un centro cultural ofrece cursos libres. Cada curso se dicta en una sola sede. Un participante se inscribe a lo sumo una vez en cada curso; el valor pagado puede tener descuento. El correo identifica a un participante (no hay dos participantes con el mismo correo).

> **La queja:** "Contabilidad dice que Fotografía digital recaudó 200 000 pesos más de lo que hay en caja."

**Pregunta propia:** la tabla tiene una PK de una sola columna. ¿Por qué eso no la pone en 2FN? ¿Qué restricción le faltaba al diseño original, y qué habría evitado?

### Caso 4: envíos

```
envio (num_guia PK, fecha, ciudad_destino, departamento, zona, tarifa_kg, peso_kg, valor)
```

Una transportadora cobra por kilo según la zona de la ciudad de destino. Cada ciudad pertenece a un departamento y a una zona; cada zona tiene una tarifa por kilo. El valor de un envío es el peso por la tarifa.

> **La queja:** "Un cliente de Bogotá reclama que le cobramos de más."

**Pregunta propia:** la transportadora anuncia que en enero sube las tarifas. Con el esquema corregido, ¿qué pasa con el valor de los envíos de octubre cuando se cambie la tarifa de la zona? ¿Qué cambiarían en el diseño para que eso no pase, y eso es redundancia o no?

## Parte B: el esquema del proyecto

Con las dependencias que el grupo trajo escritas (pre-trabajo, punto 3), para **cada tabla** del esquema del proyecto:

| Tabla | Claves candidatas | Dependencias (con su regla) | Forma normal más alta | Problema encontrado | Evidencia (consulta) | Cambio propuesto |
|---|---|---|---|---|---|---|

- Revisar el esquema con la tabla de señales de la sección 1. En particular: columnas de texto que se repiten (autor, editorial, categoría), datos del lector copiados en otras tablas, claves sustitutas sin el `UNIQUE` de la clave natural (ISBN, documento, correo) y datos derivados (`ejemplares_disponibles`, un `estado` del préstamo).
- Si una tabla incumple 3FN, proponer la descomposición. **No** hace falta migrar todavía: eso, junto con la decisión de desnormalizar a propósito alguna columna, es el trabajo de S20.
- Si el grupo concluye que una tabla está bien, también lo escribe, con la justificación.

## Mecánica (2 horas)

1. **(10 min) Encuadre.** El profesor muestra en vivo `string_to_table` sobre un ejemplo propio (`libro` con `autores`), sin tocar los casos, y la idea de la sección 1 sobre la clave sustituta: "agregar un `id` no normaliza nada".
2. **(70 min) Parte A: los cuatro casos.** Se sugiere repartir: cada pareja del grupo toma dos casos (uno de los casos 1 y 2, y uno de los casos 3 y 4) y, a la mitad del tiempo, explica sus diagnósticos a la otra pareja, que los revisa. El grupo entrega un solo archivo `casos.sql` con los cuatro, cada uno con comentarios para (a) a (e) y la pregunta propia.
3. **(30 min) Parte B: el esquema del proyecto.** Todo el grupo junto, sobre la tabla de la parte B.
4. **(10 min) Puesta en común y cierre.** Dos grupos muestran el caso 3 o el 4 (en particular, cómo resolvieron la queja). El profesor recuerda que en S20 cada grupo migra su esquema, decide si desnormaliza algo y entrega el Hito 3; la tabla de la parte B es el punto de partida del documento de normalización.

## Entregable

**Por grupo**, subido al terminar la sesión:

1. `casos.sql`: los cuatro casos, cada uno con su diagnóstico, evidencia, esquema, migración y verificación en comentarios y SQL, más la respuesta a su pregunta propia.
2. La salida de `psql` (texto o captura) de las consultas de evidencia y de verificación.
3. La tabla de la parte B, completa para todas las tablas del esquema del proyecto.

## Rúbrica (checklist, calificación por grupo)

| Criterio | 0 | 1 | 2 |
|---|---|---|---|
| **Diagnóstico y evidencia (parte A)** | Menos de 3 casos con diagnóstico correcto | Los 4 diagnosticados, pero falta la evidencia en SQL o algún problema secundario (cada caso tiene más de uno) | Los 4 con todos sus problemas, la forma normal correcta y una consulta que los demuestra, incluida la que explica cada queja |
| **Migración (parte A)** | Las migraciones no corren, o pierden o duplican datos | Corren, pero falta la transacción, la verificación con conteos esperados o alguna PK, FK o `UNIQUE` | Las 4 corren dentro de una transacción, con restricciones completas, conteos esperados escritos antes y la queja resuelta en el esquema nuevo |
| **Preguntas propias (parte A)** | Sin responder o incorrectas | Respondidas, pero sin argumento (en particular la del caso 4) | Las 4 bien argumentadas; en el caso 4 distinguen un dato derivado de uno histórico |
| **Esquema del proyecto (parte B)** | La tabla falta o cubre menos de la mitad de las tablas | Todas las tablas, pero sin reglas que justifiquen las dependencias o sin evidencia | Todas las tablas con dependencias justificadas, forma normal, evidencia de los problemas y un cambio propuesto (o la justificación de que está bien) |

Máximo 8 puntos por grupo.
