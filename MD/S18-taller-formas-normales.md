# S18. Taller: formas normales 1FN, 2FN, 3FN y FNBC

**Módulo 5, semana 9, sesión 18 · Taller sincrónico (videollamada, salas por grupo de proyecto)**

S17 dejó una regla ("todo determinante debe ser superclave") y tres maneras de incumplirla. Este taller les pone nombre: las formas normales. Como S10, introduce vocabulario nuevo, así que trae una **guía corta de pre-lectura**; el tiempo sincrónico se dedica a practicar: primero a diagnosticar relaciones pequeñas en papel, luego a normalizar paso a paso la planilla de un taller de carros, y por último a hacerlo de verdad en PostgreSQL, comprobando que no se pierde ni se inventa ninguna fila.

## Objetivos de la sesión

Al terminar, cada estudiante debe poder:

- Definir 1FN, 2FN, 3FN y FNBC, y explicar qué prohíbe cada una en términos de dependencias funcionales y claves.
- Determinar la forma normal más alta en la que está una relación, a partir de sus dependencias y sus claves candidatas.
- Normalizar una tabla hasta 3FN paso a paso, indicando en cada paso qué dependencia se elimina y por qué la descomposición no pierde información.
- Llevar la descomposición a PostgreSQL: limpiar los datos que contradicen una dependencia, crear las tablas con sus claves, cargarlas con `INSERT … SELECT DISTINCT` y verificar la reconstrucción con `EXCEPT`.
- Reconocer una relación que está en 3FN pero no en FNBC, y explicar qué se gana y qué se pierde al llevarla a FNBC.

## Guía corta de pre-lectura (antes de la sesión)

### 1. Dos términos que hacen falta

- **Clave candidata** (S10): superclave mínima. Una relación puede tener varias.
- **Atributo primo:** el que forma parte de **alguna** clave candidata. Los demás son **no primos**. En `aprobo_plano` (S17), con clave (`cod_est`, `cod_curso`), los primos son `cod_est` y `cod_curso`; `nombre`, `cod_prog`, `nombre_prog`, `nombre_curso`, `creditos` y `nota` son no primos.

Las formas normales se definen con las dependencias funcionales de S17. Cada una exige lo de la anterior y algo más: FNBC ⇒ 3FN ⇒ 2FN ⇒ 1FN.

### 2. Primera forma normal (1FN)

> Una relación está en **1FN** si todos sus atributos tienen valores **atómicos**: ni listas, ni conjuntos, ni grupos de columnas que repiten lo mismo.

Es la regla 3 de la relación en S9. Esta tabla no está en 1FN:

| isbn | titulo | autores |
|---|---|---|
| 9789701056783 | Fundamentos de bases de datos | Silberschatz, Korth, Sudarshan |

Para responder "¿qué libros escribió Korth?" hay que partir texto (`LIKE '%Korth%'`, que también encontraría a un "Korthals"), y no hay forma de poner una FK hacia una tabla de autores. La salida de "una columna por autor" (`autor1`, `autor2`, `autor3`) tampoco sirve: es un **grupo repetido**, limita a tres autores y obliga a buscar en tres columnas.

**Cómo se arregla:** una fila por valor, en una tabla aparte con la clave de la original (es la traducción de los atributos multivaluados de S11):

```
libro       (isbn PK, titulo)
libro_autor (isbn → libro, autor)        -- PK (isbn, autor)
```

Si la lista se "aplana" en la misma tabla (una fila por autor, repitiendo `isbn` y `titulo`), queda en 1FN, pero con redundancia: es lo que pasó con la planilla de S17, y lo arreglan las formas siguientes.

### 3. Segunda forma normal (2FN)

> Una relación está en **2FN** si está en 1FN y ningún atributo **no primo** depende de una **parte** de una clave candidata.

Solo puede fallar cuando hay una clave compuesta: si todas las claves candidatas tienen un solo atributo, no hay "partes", y una relación en 1FN ya está en 2FN.

`aprobo_plano(cod_est, nombre, cod_prog, nombre_prog, cod_curso, nombre_curso, creditos, nota)`, clave (`cod_est`, `cod_curso`), con las dependencias de S17:

- `cod_est → nombre, cod_prog` (parte de la clave)
- `cod_curso → nombre_curso, creditos` (parte de la clave)
- `cod_prog → nombre_prog`
- `cod_est, cod_curso → nota` (la clave completa: no es problema)

No está en 2FN. **Cómo se arregla:** cada parte de la clave que determina algo se lleva a su propia tabla, **con todo lo que determina** (también lo que determina indirectamente: `cod_est` determina `nombre_prog` a través de `cod_prog`). En la tabla original queda la clave completa y lo que depende de ella completa:

```
estudiante_2fn (cod_est PK, nombre, cod_prog, nombre_prog)
curso          (cod_curso PK, nombre_curso, creditos)
aprobo         (cod_est, cod_curso, nota)          -- PK (cod_est, cod_curso)
```

### 4. Tercera forma normal (3FN)

> Una relación está en **3FN** si, para toda dependencia no trivial X → A, **X es superclave** o **A es primo**.

Dicho con las palabras de S17: no hay atributos no primos que dependan de otros atributos no primos (**dependencias transitivas**). `estudiante_2fn` está en 2FN (su clave tiene un solo atributo), pero no en 3FN: `cod_prog → nombre_prog`, `cod_prog` no es superclave y `nombre_prog` no es primo. "Ingeniería de Sistemas" se repite en cada estudiante del programa.

**Cómo se arregla:** igual que en S17, el determinante problemático se va a su propia tabla, donde sí es clave:

```
estudiante (cod_est PK, nombre, cod_prog → programa)
programa   (cod_prog PK, nombre_prog)
```

Con esto, `aprobo_plano` quedó en cuatro tablas: `programa`, `estudiante`, `curso` y `aprobo`. Es exactamente el esquema de matrículas de S9, S13 y S15. Ese esquema siempre estuvo en 3FN; ahora se sabe por qué.

### 5. Forma normal de Boyce-Codd (FNBC)

> Una relación está en **FNBC** si, para toda dependencia no trivial X → A, **X es superclave**.

Es la regla de S17 tal cual. La diferencia con 3FN es que FNBC **no** acepta la excepción "o A es primo". Casi siempre una tabla en 3FN también está en FNBC; la excepción aparece cuando hay **dos claves candidatas compuestas que se solapan**. Ejemplo:

`monitoria(cod_est, cod_curso, monitor)`. Reglas: cada monitor apoya **un solo** curso; en cada curso, cada estudiante tiene asignado **un solo** monitor.

| cod_est | cod_curso | monitor |
|---|---|---|
| Ana | Bases de Datos | Lucía |
| Bruno | Bases de Datos | Lucía |
| Diego | Bases de Datos | Tomás |
| Ana | Programación I | Mateo |

- Dependencias: `cod_est, cod_curso → monitor` y `monitor → cod_curso`.
- Claves candidatas: (`cod_est`, `cod_curso`) y (`cod_est`, `monitor`). Los tres atributos son primos.
- **3FN: sí.** En `monitor → cod_curso`, `monitor` no es superclave, pero `cod_curso` es primo: se acepta.
- **FNBC: no.** `monitor` no es superclave. Y hay redundancia: "Lucía apoya Bases de Datos" está escrito dos veces, y no se puede registrar un monitor nuevo hasta que tenga un estudiante asignado.

**Cómo se arregla:** `monitor_curso(monitor PK, cod_curso)` y `asignacion(cod_est, monitor)` con PK (`cod_est`, `monitor`). Es sin pérdida (se juntan por `monitor`, clave de la primera), pero tiene un costo: la regla "un solo monitor por estudiante en cada curso" ya no cabe en ninguna de las dos tablas. Nada impide asignarle a Ana a Lucía **y** a Tomás, los dos de Bases de Datos. Se dice que la descomposición **no preserva** la dependencia `cod_est, cod_curso → monitor`; para protegerla haría falta un trigger (M6).

Esa es la razón práctica por la que muchos diseños se quedan en 3FN: **a 3FN siempre se puede llegar sin perder información y sin perder dependencias; a FNBC, no siempre.** El Hito 3 pide como mínimo 3FN.

### 6. Resumen y receta

| Forma | Exige | Prohíbe (en la práctica) | Ejemplo de violación |
|---|---|---|---|
| 1FN | Valores atómicos | Listas en una celda, grupos `autor1`, `autor2`… | `autores = 'Silberschatz, Korth, Sudarshan'` |
| 2FN | 1FN + ningún no primo depende de una parte de una clave | Dependencias parciales | `cod_est → nombre` con clave (`cod_est`, `cod_curso`) |
| 3FN | Toda X → A no trivial: X superclave o A primo | Dependencias transitivas | `cod_prog → nombre_prog` |
| FNBC | Toda X → A no trivial: X superclave | Cualquier determinante que no sea clave | `monitor → cod_curso` |

**Receta para normalizar una tabla:**

1. Escribir sus dependencias a partir de las reglas del negocio (S17, sección 5.2), no de los datos.
2. Encontrar sus claves candidatas (con el cierre de S17, sección 9, si no es evidente).
3. Revisar cada dependencia contra la forma normal que se quiere alcanzar.
4. Por cada dependencia X → Y que la incumple: sacar una tabla nueva con X y **todo** lo que X determina; en la original, quitar lo que X determina y dejar X (será clave foránea). X es clave de la tabla nueva, así que la descomposición es sin pérdida (S17, sección 7.2).
5. Repetir con cada tabla resultante hasta que todas cumplan.

**Pre-trabajo (20 min, antes de la sesión):**

1. Leer esta pre-lectura y repasar las secciones 5 a 7 de la guía de S17.
2. Aplicar la receta a `aprobo_plano` por su cuenta y comparar con las secciones 3 y 4 de arriba.
3. Copiar el script [`S18-automotriz.sql`](S18-automotriz.sql) (publicado en el LMS) en `entorno-docker/postgres/scripts/`. **No** ejecutarlo todavía: la parte A se hace en papel.

## El caso: Taller Automotriz El Pistón

El taller lleva sus órdenes de servicio en una hoja de cálculo. Así se ven dos de sus filas:

| orden | fecha | km | placa | carro | dueño | teléfono | servicios | cobrado | mecánicos |
|---|---|---|---|---|---|---|---|---|---|
| 5002 | 2026-10-02 | 88000 | DEF456 | Chevrolet Sail | 16700002 Jorge Mejía | 3104445566 | FRE Pastillas de freno, ACE Cambio de aceite | 150000, 110000 | M02 Hernán Bedoya, M01 Rosa Quintero |
| 5005 | 2026-10-14 | 52000 | JKL012 | Renault Duster | 1144000003 Camilo Ibarra | 3157778899 | ACE Cambio de aceite, FRE Pastillas de freno, ALI Alineación | 120000, 150000, 80000 | M01 Rosa Quintero, M02 Hernán Bedoya, M02 Hernán Bedoya |

Las reglas del negocio, según el dueño del taller:

1. **Vehículos.** Cada vehículo se identifica por su placa y tiene un modelo (Spark, Sail, Logan, Duster…). Cada modelo es de una sola marca. El taller guarda el dueño **actual** de cada vehículo: un vehículo tiene un dueño registrado.
2. **Dueños.** De cada dueño se guardan cédula, nombre y un teléfono.
3. **Órdenes.** Cada orden tiene un número, la fecha de ingreso, el vehículo y el kilometraje con el que llegó. Un mismo vehículo puede volver muchas veces.
4. **Servicios.** El taller tiene un catálogo de servicios, cada uno con un código de tres letras, un nombre y un precio de lista. En una orden se hacen uno o varios servicios, cada uno a lo sumo una vez por orden. El precio cobrado puede ser distinto al de lista (descuentos).
5. **Mecánicos.** Cada servicio de una orden lo hace un solo mecánico. De cada mecánico se guardan un código y su nombre.

El script `S18-automotriz.sql` trae esta información ya en 1FN: la tabla `servicio_plano`, con una fila por servicio de cada orden (11 filas, 6 órdenes), clave (`num_orden`, `cod_servicio`):

```
servicio_plano (num_orden, fecha_ingreso, kilometraje, placa, modelo, marca,
                cedula_dueno, nombre_dueno, telefono_dueno,
                cod_servicio, nombre_servicio, precio_lista, precio_cobrado,
                cod_mecanico, nombre_mecanico)
```

## Mecánica (2 horas)

1. **(10 min) Encuadre.** El profesor resuelve en vivo `aprobo_plano` con la receta (secciones 3 y 4 de la pre-lectura), dejando escrito en cada paso la dependencia que se elimina.
2. **(20 min) Parte A1: diagnóstico, en papel.** Para cada relación de la lista de abajo, el grupo escribe sus claves candidatas, la forma normal **más alta** en la que está, y la dependencia (o el atributo) que le impide subir a la siguiente.
3. **(30 min) Parte A2: El Pistón hasta 3FN, en papel (sin ejecutar el script).**
   - (a) Explicar por qué la hoja de cálculo original no está en 1FN y cómo se ve en 1FN (dibujar las tres filas de la orden 5005).
   - (b) Escribir todas las dependencias funcionales de `servicio_plano`, cada una con la regla del negocio que la justifica.
   - (c) Confirmar que (`num_orden`, `cod_servicio`) es la única clave candidata.
   - (d) Llevarla a 2FN: qué dependencias parciales hay y qué tablas salen.
   - (e) Llevar cada tabla a 3FN: qué dependencias transitivas hay y qué tablas salen. Para el esquema final, marcar PK y FK de cada tabla.
   - (f) ¿El esquema final está también en FNBC? Justificar.
   - (g) Si el taller quisiera saber quién era el dueño **el día de cada orden** (no el actual), ¿qué dependencia cambia y en qué tabla quedaría la cédula del dueño?
4. **(35 min) Parte B: la descomposición en PostgreSQL.** Ejecutar el script:

   ```bash
   docker compose exec postgres psql -U curso -d curso -f /scripts/S18-automotriz.sql
   docker compose exec postgres psql -U curso -d curso
   ```

   y dentro de `psql`: `SET search_path TO automotriz;`. El grupo escribe un archivo `normalizacion.sql` que:
   - (a) Por cada dependencia de A2 (b), corre la consulta de S17 (sección 5.3) que busca filas que la contradigan. Si alguna devuelve filas, decide cuál es el dato correcto, lo justifica en un comentario y lo corrige con un `UPDATE` **sobre `servicio_plano`**, antes de crear nada.
   - (b) Crea las tablas del esquema 3FN de A2 (e), con `PRIMARY KEY`, `REFERENCES` y `NOT NULL`, en el mismo esquema `automotriz`.
   - (c) Las llena con `INSERT INTO … SELECT DISTINCT … FROM servicio_plano`, en un orden que respete las FK, y muestra cuántas filas quedó en cada una.
   - (d) Reconstruye `servicio_plano` con joins (una vista, `CREATE VIEW reconstruida AS …`, con las columnas en el mismo orden) y comprueba con `EXCEPT`, **en los dos sentidos**, que no sobra ni falta ninguna fila.
   - (e) Demuestra con una sentencia por anomalía que las tres anomalías de S17 ya no ocurren: cambiar un teléfono, registrar un mecánico nuevo sin servicios, y borrar una orden sin perder el vehículo ni el servicio del catálogo. (Hacer (e) **después** de (d): (e) modifica los datos.)
5. **(15 min) Parte C: 3FN o FNBC.** El taller decide asignar un responsable por área en cada orden: `responsable(num_orden, area, cod_mecanico)`, donde `area` es motor, frenos o eléctrico. Reglas: en cada orden, cada área tiene un solo responsable; cada mecánico trabaja en una sola área. El grupo responde: (a) dependencias y claves candidatas; (b) ¿está en 3FN? ¿en FNBC?; (c) la descomposición en FNBC; (d) qué regla deja de garantizar el esquema descompuesto, con un ejemplo de datos que la viole; (e) qué recomendarían al taller, y por qué.
6. **(10 min) Puesta en común y cierre.** Un grupo muestra su parte A2 y otro su parte B (en particular, qué encontró en el paso (a)). El profesor cierra recordando la tarea para S19 y S20: escribir las dependencias funcionales del esquema del proyecto, tabla por tabla, con la regla que justifica cada una (es la evidencia que pide el Hito 3).

### Relaciones de la parte A1

Cada una con todas sus dependencias no triviales.

| # | Relación | Dependencias |
|---|---|---|
| 1 | `Pasajero(cedula, nombre, telefonos)`, donde `telefonos` guarda textos como `'3001112233, 3154445566'` | `cedula → nombre, telefonos` |
| 2 | `Inscripcion(cod_est, cod_taller, fecha_inscripcion, nombre_taller)` | `cod_est, cod_taller → fecha_inscripcion`; `cod_taller → nombre_taller` |
| 3 | `Empleado(cedula, nombre, cod_depto, nombre_depto)` | `cedula → nombre, cod_depto`; `cod_depto → nombre_depto` |
| 4 | `Vuelo(num_vuelo, fecha, matricula_avion, cedula_piloto)` | `num_vuelo, fecha → matricula_avion, cedula_piloto` |
| 5 | `Municipio(cod_dane, nombre, departamento)` (dos municipios de departamentos distintos pueden llamarse igual, pero no dos del mismo departamento) | `cod_dane → nombre, departamento`; `nombre, departamento → cod_dane` |
| 6 | `Clase(cod_est, materia, profesor)`: cada profesor dicta una sola materia; cada estudiante ve cada materia con un solo profesor | `cod_est, materia → profesor`; `profesor → materia` |

Para la relación 1, responder además: ¿y si se cambia `telefonos` por `telefono1`, `telefono2`, `telefono3`?

## Entregable

**Por grupo**, subido al terminar la sesión:

1. Un documento con la tabla de la parte A1, las respuestas (a) a (g) de la parte A2 (con el esquema final, PK y FK marcadas) y las respuestas (a) a (e) de la parte C.
2. `normalizacion.sql` de la parte B, con comentarios que indiquen cada paso.
3. La salida de `psql` (texto o captura) de los pasos (a), (c) y (d) de la parte B.

## Rúbrica (checklist, calificación por grupo)

| Criterio | 0 | 1 | 2 |
|---|---|---|---|
| **Diagnóstico (parte A1)** | Menos de 3 relaciones bien diagnosticadas | 3 o 4 bien, o las 6 sin decir qué impide subir | Las 6 con forma normal, claves y la dependencia que impide subir (incluidas la 5 y la 6) |
| **Normalización en papel (parte A2)** | Faltan dependencias importantes, o el esquema final no está en 3FN | Esquema final en 3FN, pero faltan dependencias justificadas, el paso por 2FN o las respuestas (f) y (g) | Dependencias con su regla, pasos 1FN → 2FN → 3FN explicados, PK y FK marcadas, y (f) y (g) bien respondidas |
| **Descomposición en SQL (parte B)** | No corre, o no se verifica la reconstrucción | Corre y reconstruye, pero no se revisaron las dependencias antes de cargar, o falta la prueba de anomalías | Encuentra y corrige el dato que contradice una dependencia, carga con FK, verifica con `EXCEPT` en los dos sentidos y prueba las tres anomalías |
| **3FN frente a FNBC (parte C)** | No identifica las claves o la forma normal | Identifica 3FN y no FNBC, pero no explica qué regla se pierde | Claves, diagnóstico, descomposición, ejemplo de la regla perdida y una recomendación argumentada |

Máximo 8 puntos por grupo.
