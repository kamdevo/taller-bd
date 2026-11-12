# S17. Redundancia, anomalías de actualización y dependencia funcional

**Módulo 5, semana 9, sesión 17 · Magistral (consumo asíncrono + espacio breve de preguntas)**

## Objetivos de la sesión

Al terminar, cada estudiante debe poder:

- Señalar la redundancia de una tabla (qué dato se repite y por qué) y estimar cuánto se repite con una consulta.
- Reconocer las tres anomalías de actualización (de modificación, de inserción y de borrado) y explicar por qué la redundancia las produce.
- Definir dependencia funcional (X → Y), escribir las de una tabla a partir de las reglas del negocio y usar SQL para comprobar que los datos no las contradicen.
- Relacionar dependencias funcionales con claves: una clave es un conjunto de atributos que determina a todos los demás, y una dependencia cuyo lado izquierdo no es clave es la señal de un mal diseño.
- Descomponer una tabla según sus dependencias funcionales sin perder información, y reconocer una descomposición mala por las filas espurias que produce.
- Revisar el esquema del proyecto buscando datos repetidos y datos derivados.

## Guía de lectura

### 1. Dos maneras de guardar lo mismo

Una biblioteca pequeña que todavía no tiene sistema suele llevar los préstamos en una hoja de cálculo: una fila por préstamo, con todo lo necesario a la vista.

| id | isbn | titulo | autor | documento | nombres | correo | fecha_prestamo | fecha_devolucion |
|---|---|---|---|---|---|---|---|---|
| 1 | …001 | Cien años de soledad | Gabriel García Márquez | …001 | Mariana | mariana.gomez@… | 2026-09-01 | 2026-09-10 |
| 3 | …001 | Cien años de soledad | Gabriel García Márquez | …004 | Juan David | juan.martinez@… | 2026-09-12 | |
| 4 | …007 | Ficciones | Jorge Luis Borges | …004 | Juan David | juan.martinez@… | 2026-09-20 | |
| 8 | …005 | Pedro Páramo | Juan Rulfo | …004 | Juan David | juan.martinez@… | 2026-10-05 | |

Es cómodo de leer y cualquier pregunta se responde sin joins. En S15 se trabajó con la misma información repartida en tres tablas: `libro`, `lector` y `prestamo`. Las dos versiones contienen los mismos datos. Esta sesión responde por qué la segunda es mejor, con un criterio que se pueda aplicar a cualquier tabla y no solo con la intuición de "así se hace": ese criterio es la **dependencia funcional**, y sobre ella se construyen las formas normales de S18.

### 2. El script de la sesión

El script [`S17-planilla.sql`](S17-planilla.sql) crea el esquema `planilla` con dos tablas "planas":

- `prestamo_plano`: los 8 préstamos de la hoja de cálculo, con los datos del libro y del lector copiados en cada fila. Los libros y lectores salen de los CSV semilla del proyecto.
- `aprobo_plano`: las matrículas de S15 en una sola tabla (estudiante, programa, curso y nota en cada fila). Se usa en la sección 6 y se retoma en S18.

```bash
# desde entorno-docker/, con el archivo copiado en postgres/scripts/
docker compose exec postgres psql -U curso -d curso -f /scripts/S17-planilla.sql
docker compose exec postgres psql -U curso -d curso
```

```sql
curso=# SET search_path TO planilla;
```

```
prestamo_plano (id_prestamo PK, isbn, titulo, autor, categoria,
                documento, nombres, apellidos, correo, telefono,
                fecha_prestamo, fecha_esperada, fecha_devolucion)
```

Las secciones 4 y 7 modifican estas tablas. Para volver al estado inicial, se corre otra vez el script.

### 3. Redundancia

Un dato es **redundante** cuando está guardado más de una vez, o cuando se puede calcular a partir de otros que ya están guardados. En la planilla, cada vez que Juan David pide un libro se copian otra vez su nombre, sus apellidos, su correo y su teléfono:

```sql
SELECT   nombres, count(*) AS veces
FROM     prestamo_plano
GROUP BY documento, nombres
ORDER BY veces DESC;
```

| nombres | veces |
|---|---|
| Juan David | 3 |
| Mariana | 2 |
| Camila | 1 |
| Valentina | 1 |
| Santiago | 1 |

Lo mismo con los libros: el título, el autor y la categoría de *Cien años de soledad* están escritos tres veces. Con 8 préstamos es poco; con una biblioteca real, de 50.000 préstamos al año, el correo de un lector frecuente puede aparecer cientos de veces.

El espacio desperdiciado es el problema menor. El problema serio es que cada copia es una oportunidad para que los datos se contradigan entre sí, y eso es lo que muestran las anomalías.

### 4. Las tres anomalías de actualización

Una **anomalía de actualización** es un efecto indeseado de una operación normal (modificar, insertar o borrar) causado por el diseño de la tabla, no por un error del usuario. Las tres se prueban sobre la planilla.

#### 4.1 Anomalía de modificación

Juan David cambia de correo. Quien atiende el mostrador busca uno de sus préstamos y lo corrige ahí:

```sql
BEGIN;
UPDATE prestamo_plano
SET    correo = 'jd.martinez@correo-ejemplo.edu.co'
WHERE  id_prestamo = 3;

SELECT id_prestamo, nombres, correo
FROM   prestamo_plano
WHERE  documento = '1000000004'
ORDER BY id_prestamo;
```

| id_prestamo | nombres | correo |
|---|---|---|
| 3 | Juan David | jd.martinez@correo-ejemplo.edu.co |
| 4 | Juan David | juan.martinez@correo-ejemplo.edu.co |
| 8 | Juan David | juan.martinez@correo-ejemplo.edu.co |

Ahora la base dice dos cosas distintas sobre el mismo lector, y ninguna consulta puede saber cuál es la verdadera. El reporte de préstamos en mora de S15 le escribiría a la dirección vieja por dos de sus libros. El `UPDATE` correcto tenía que usar `WHERE documento = '1000000004'`, pero el diseño obliga a que **cada** cambio de un dato del lector toque **todas** sus filas, y basta con que una persona o un programa lo olvide una vez.

```sql
ROLLBACK;
```

#### 4.2 Anomalía de inserción

Daniela se inscribe en la biblioteca. Todavía no ha pedido nada prestado:

```sql
INSERT INTO prestamo_plano (documento, nombres, apellidos, correo, telefono)
VALUES ('1000000019', 'Daniela', 'Pineda Guzmán',
        'daniela.pineda@correo-ejemplo.edu.co', '3001000019');
```

```
ERROR:  null value in column "id_prestamo" of relation "prestamo_plano" violates not-null constraint
```

La tabla registra **préstamos**, y su clave es `id_prestamo`; un lector sin préstamos no tiene dónde guardarse. Lo mismo le pasa a un libro recién comprado que nadie ha pedido. Las salidas que suelen aparecer (inventar un préstamo falso, o quitar el `NOT NULL` y dejar filas con medio préstamo en `NULL`) son peores que el problema: los reportes de S15 contarían préstamos que no existieron.

#### 4.3 Anomalía de borrado

Camila tiene un solo préstamo, el 5 (*El Aleph*), que es además el único préstamo de ese libro. La biblioteca decide depurar los préstamos ya cerrados y borra ese:

```sql
BEGIN;
DELETE FROM prestamo_plano WHERE id_prestamo = 5;

SELECT count(*) FROM prestamo_plano WHERE documento = '1000000005';   -- 0
SELECT count(*) FROM prestamo_plano WHERE isbn = '9780000000008';     -- 0
ROLLBACK;
```

Al borrar un **préstamo** desaparecieron también una **lectora** y un **libro**: ya no existe en la base el correo de Camila, ni el autor de *El Aleph*. Se perdió información que nadie quería borrar, porque solo existía como copia dentro de una fila de otra cosa.

#### 4.4 Por qué no se arregla "teniendo cuidado"

Las tres anomalías tienen la misma causa: la tabla mezcla **tres cosas** (libros, lectores y préstamos) que tienen vidas independientes. Un lector existe antes de su primer préstamo y después del último; un libro también. Una tabla que solo puede guardar al lector "dentro" de un préstamo lo ata a la vida del préstamo.

Se podría intentar compensar con disciplina (actualizar siempre por `documento`, nunca borrar préstamos) o con código en la aplicación. Ambas soluciones dependen de que **todos** los programas y **todas** las personas que tocan la base lo hagan bien siempre. El diseño relacional busca lo contrario: que el esquema haga imposible guardar contradicciones, de la misma forma en que una PK hace imposible guardar dos filas con la misma clave (S10).

### 5. Dependencia funcional

#### 5.1 Definición

En la planilla, cada vez que aparece el ISBN `9780000000001` aparece con el título *Cien años de soledad*. No es casualidad: un ISBN identifica una edición de un libro, y una edición tiene un solo título. Esa regla se llama dependencia funcional.

> En una relación R, el conjunto de atributos X **determina funcionalmente** al conjunto Y, y se escribe **X → Y**, si cualquier par de filas que tengan los mismos valores en X tienen también los mismos valores en Y.

Se lee "X determina a Y" o "Y depende funcionalmente de X". X es el **determinante**. "Funcional" viene de las matemáticas: para cada valor de X hay **un único** valor de Y, como una función.

Las dependencias de `prestamo_plano`, según las reglas de la biblioteca:

| Dependencia | Regla del negocio que la justifica |
|---|---|
| isbn → titulo, autor, categoria | Un ISBN identifica una edición, que tiene un título, un autor y una categoría |
| documento → nombres, apellidos, correo, telefono | Un documento identifica a una persona, que tiene un correo y un teléfono registrados |
| id_prestamo → isbn, documento, fecha_prestamo, fecha_esperada, fecha_devolucion | Un préstamo es de un libro, a un lector, en unas fechas |

Y algunas que **no** se cumplen:

| No es dependencia | Por qué |
|---|---|
| autor → titulo | Borges escribió *Ficciones* y *El Aleph* |
| fecha_prestamo → documento | El 12 de septiembre prestaron libros a Mariana y a Juan David |
| titulo → isbn | Hoy no hay dos títulos iguales en la planilla, pero el *Quijote* tiene decenas de ediciones, cada una con su ISBN |

#### 5.2 Las dependencias salen de las reglas, no de los datos

La última fila de la tabla anterior es la idea más importante de la sección. Una dependencia funcional es una afirmación sobre **todas las filas que la tabla podría llegar a tener**, no sobre las que tiene hoy. Mirando los datos actuales, `titulo → isbn` parece cumplirse, igual que `nombres → documento` (no hay dos lectores con el mismo nombre). Ninguna de las dos es una regla: en cuanto la biblioteca compre otra edición del *Quijote* o se inscriba otro Juan David, dejan de cumplirse.

Por eso las dependencias se escriben a partir de lo que se sabe del negocio (el documento del proyecto, las preguntas al cliente, el sentido común sobre qué identifica a qué). Los datos sirven para una sola cosa: **refutar**. Si dos filas coinciden en X y difieren en Y, X → Y es falsa; si no hay tal par, solo se sabe que los datos no la contradicen.

#### 5.3 Comprobar con SQL que los datos no la contradicen

La definición se traduce directamente en una consulta de S15: se agrupa por X y se buscan los grupos con más de un valor de Y.

```sql
-- ¿Hay algún isbn con más de un título, autor o categoría?
SELECT   isbn
FROM     prestamo_plano
GROUP BY isbn
HAVING   count(DISTINCT titulo) > 1
      OR count(DISTINCT autor) > 1
      OR count(DISTINCT categoria) > 1;      -- 0 filas: los datos no contradicen isbn → titulo, autor, categoria

-- ¿autor → titulo?
SELECT   autor, count(DISTINCT titulo)
FROM     prestamo_plano
GROUP BY autor
HAVING   count(DISTINCT titulo) > 1;         -- Jorge Luis Borges, 2: no es dependencia
```

Esta consulta es muy útil en la práctica: antes de separar una tabla (sección 7) o de cargar un CSV (S14), revela las filas que ya están en contradicción, como el correo de Juan David de la sección 4.1 si no se hubiera deshecho. Si devuelve filas para una dependencia que el negocio dice que existe, el problema son los datos, y hay que limpiarlos antes de reorganizar.

#### 5.4 Notación y dependencias triviales

- Con varios atributos se escriben sin llaves cuando no hay ambigüedad: `isbn → titulo, autor` equivale a `isbn → titulo` e `isbn → autor` (se puede partir el lado derecho; el izquierdo **no**).
- El lado izquierdo puede tener varios atributos: en `aprobo_plano`, `cod_est, cod_curso → nota` (la nota depende del estudiante **y** del curso, no de uno solo).
- Una dependencia es **trivial** si el lado derecho está contenido en el izquierdo, como `isbn, titulo → titulo`. Se cumple en cualquier tabla y no dice nada del negocio; en los análisis se omiten.

### 6. Dependencias funcionales y claves

#### 6.1 Una clave es una dependencia funcional

En S10 se definió una **superclave** como un conjunto de atributos que no se repite en ninguna fila, y una **clave candidata** como una superclave mínima. Con dependencias se dice lo mismo de otra forma: X es superclave de R si **X → todos los atributos de R**. Si dos filas coincidieran en X, coincidirían en todo, es decir, serían la misma fila.

En `prestamo_plano`, `id_prestamo` determina directamente las fechas, el `isbn` y el `documento`; y como `isbn` determina los datos del libro y `documento` los del lector, `id_prestamo` termina determinando todo. Es la clave.

`isbn` **no** es clave de la planilla: determina el título, el autor y la categoría, pero no el lector ni las fechas (*Cien años de soledad* se prestó tres veces). Lo mismo pasa con `documento`.

#### 6.2 El diagnóstico

La sección 4 mostró las anomalías; ahora se puede decir con precisión de dónde vienen. En la planilla hay dos dependencias cuyo determinante **no es clave**:

- `isbn → titulo, autor, categoria`
- `documento → nombres, apellidos, correo, telefono`

Cuando el determinante no es clave, su valor puede repetirse en muchas filas (el mismo ISBN en tres préstamos), y la dependencia obliga a repetir con él el lado derecho. Eso es la redundancia, y de la redundancia salen las anomalías. La dependencia `id_prestamo → …`, en cambio, no produce nada repetido: su determinante es clave, aparece una sola vez.

Esta es la regla que organiza todo el módulo:

> **Una tabla está bien diseñada cuando todo determinante de una dependencia no trivial es una superclave.**

En S18 esa regla tiene nombre (forma normal de Boyce-Codd, FNBC) y se presentan las formas normales anteriores (1FN, 2FN, 3FN), que son versiones más permisivas de la misma idea.

#### 6.3 Tres maneras de que el determinante no sea clave

`aprobo_plano` guarda una fila por nota, con su clave `(cod_est, cod_curso)`:

| cod_est | nombre | cod_prog | nombre_prog | cod_curso | nombre_curso | creditos | nota |
|---|---|---|---|---|---|---|---|
| 2610001 | Ana | 3743 | Ingeniería de Sistemas | 750006C | Bases de Datos | 4 | 4.5 |
| 2610001 | Ana | 3743 | Ingeniería de Sistemas | 750001C | Programación I | 3 | 3.8 |
| 2610004 | Diego | 3743 | Ingeniería de Sistemas | 750006C | Bases de Datos | 4 | 3.0 |
| … | | | | | | | |

Sus dependencias son:

| Dependencia | El determinante es… | Qué se repite |
|---|---|---|
| cod_est, cod_curso → nota | la clave completa | Nada: está bien |
| cod_est → nombre, cod_prog | **una parte** de la clave | El nombre y el programa de Ana, en cada curso que aprobó |
| cod_curso → nombre_curso, creditos | **una parte** de la clave | El nombre y los créditos de Bases de Datos, por cada estudiante que lo aprobó |
| cod_prog → nombre_prog | **un atributo que no es clave** ni parte de ella | "Ingeniería de Sistemas", por cada nota de cada estudiante del programa 3743 |

La última es una dependencia **transitiva**: `cod_est → cod_prog` y `cod_prog → nombre_prog`, así que el nombre del programa depende de la clave, pero "a través de" otro atributo. Los dos patrones (depender de una parte de la clave, depender de un atributo no clave) son exactamente lo que prohíben la 2FN y la 3FN de S18. Por ahora basta con reconocerlos.

### 7. La solución: descomponer

#### 7.1 Una tabla por determinante

Si el problema es que un determinante que no es clave convive con datos de otra cosa, la solución es darle su propia tabla, **en la que sí sea clave**. Se toma cada dependencia problemática y se saca a una tabla con su determinante y su lado derecho; en la tabla original queda el determinante, como clave foránea:

```sql
CREATE TABLE libro  AS SELECT DISTINCT isbn, titulo, autor, categoria          FROM prestamo_plano;   -- 5 filas
CREATE TABLE lector AS SELECT DISTINCT documento, nombres, apellidos, correo, telefono FROM prestamo_plano;   -- 5 filas
CREATE TABLE prestamo AS
       SELECT id_prestamo, isbn, documento, fecha_prestamo, fecha_esperada, fecha_devolucion
       FROM   prestamo_plano;                                                                -- 8 filas
```

(`CREATE TABLE … AS SELECT` crea la tabla con el resultado de la consulta, pero sin claves ni restricciones; en un esquema real se crean las tablas con su DDL completo y después se llenan con `INSERT … SELECT DISTINCT`, como en la tabla de paso de S14.)

El resultado es el esquema de `reportes_demo` de S15 (allá la clave del préstamo se llama `id`). El `DISTINCT` es lo que elimina la redundancia: los tres *Cien años de soledad* quedan en una sola fila de `libro`. Si la consulta de la sección 5.3 hubiera encontrado un ISBN con dos títulos, aquí saldrían dos filas con el mismo ISBN y la PK de `libro` lo rechazaría: por eso se limpia antes.

En el nuevo esquema, cada anomalía desaparece:

| Anomalía | En la planilla | Con libro / lector / prestamo |
|---|---|---|
| Modificación | El correo de Juan David está en 3 filas | Está en 1 fila de `lector`; un `UPDATE` lo cambia para todos sus préstamos |
| Inserción | Daniela no se puede registrar sin un préstamo | Se inserta en `lector`, sin préstamos |
| Borrado | Borrar el préstamo 5 borra a Camila y *El Aleph* | Se borra una fila de `prestamo`; Camila y el libro siguen en sus tablas |

#### 7.2 Descomposición sin pérdida

Separar una tabla solo tiene sentido si se puede volver a armar. La planilla original se recupera con un join:

```sql
SELECT count(*)
FROM   prestamo p
JOIN   libro  l USING (isbn)
JOIN   lector r USING (documento);       -- 8: las mismas 8 filas de prestamo_plano
```

y con `EXCEPT` (S13) se puede comprobar que son exactamente las mismas filas (devuelve 0 filas en cada sentido). Una descomposición así se llama **sin pérdida** (*lossless join*). Lo es porque cada join se hace por una columna que es **clave** de una de las dos tablas: cada préstamo encuentra exactamente un libro y exactamente un lector.

#### 7.3 Una descomposición mala

No cualquier forma de partir una tabla funciona. Suponga que alguien separa la planilla así, porque "la fecha relaciona los dos lados":

```sql
CREATE TABLE r1 AS SELECT DISTINCT id_prestamo, isbn, fecha_prestamo FROM prestamo_plano;
CREATE TABLE r2 AS SELECT DISTINCT fecha_prestamo, documento         FROM prestamo_plano;

SELECT count(*) FROM r1 JOIN r2 USING (fecha_prestamo);    -- 14, no 8
```

| id_prestamo | isbn | fecha_prestamo | documento |
|---|---|---|---|
| 2 | …004 | 2026-09-12 | 1000000001 |
| 2 | …004 | 2026-09-12 | **1000000004** |
| 3 | …001 | 2026-09-12 | **1000000001** |
| 3 | …001 | 2026-09-12 | 1000000004 |

El 12 de septiembre se hicieron dos préstamos, a Mariana (…001) y a Juan David (…004). Al juntar por la fecha, cada préstamo de ese día se combina con los dos lectores, y aparecen filas que nunca existieron (las marcadas). Se llaman **tuplas espurias**. Paradójicamente, la descomposición "con pérdida" produce **más** filas, no menos: lo que se pierde es la información de cuál fila es la verdadera.

La causa es que `fecha_prestamo` no es clave de ninguna de las dos tablas (no se cumple `fecha_prestamo → documento`, sección 5.1). La regla práctica: **al partir una tabla, el atributo común debe ser clave de al menos una de las partes**, y eso se garantiza partiendo por las dependencias funcionales, como en 7.1.

### 8. Mirando el proyecto

En el Hito 3 (S20) cada grupo revisa su esquema con estas ideas. Lo que más suele aparecer en los esquemas de biblioteca:

- **Texto que se repite.** Si `libro` tiene una columna `autor` de texto y además `nacionalidad_autor`, hay una dependencia `autor → nacionalidad_autor` con determinante no clave: es el caso de `cod_prog → nombre_prog`. Lo mismo con `editorial` y `ciudad_editorial`. Una columna `categoria` de texto sola no tiene dependencia problemática, pero se presta a inconsistencias ("Ciencia Ficción" y "Ciencia ficción"); una tabla `categoria` con FK lo evita (es un `CHECK` o una tabla de referencia, más que normalización).
- **Datos de otra entidad copiados "para no hacer joins".** Un `prestamo` que guarda el nombre o el correo del lector además del `documento` es la planilla en pequeño.
- **Datos derivados.** El CSV de libros trae `ejemplares_disponibles`, que se puede calcular (ejemplares del libro menos préstamos abiertos). Guardarlo es redundancia: cada préstamo y cada devolución tienen que actualizarlo, y si una vez no se hace, el número miente (una anomalía de modificación). Lo mismo con una columna `estado = 'en mora'` (S15, sección 8.5). A veces se guarda a propósito, por rendimiento: es la **desnormalización** de S20, y se paga con un trigger que la mantenga al día (M6).
- **El CSV no es el esquema.** Los archivos semilla son planos porque son un formato de intercambio. La carga de S14 (tabla de paso → tablas reales) es exactamente la descomposición de la sección 7.

### 9. Nota breve: deducir dependencias

Con pocas dependencias, como en estos ejemplos, se ve a simple vista qué determina qué. Con más, se usan reglas de deducción, los **axiomas de Armstrong** (1974):

| Regla | Dice | Ejemplo |
|---|---|---|
| Reflexividad | Si Y ⊆ X, entonces X → Y | isbn, titulo → titulo (las triviales) |
| Aumento | Si X → Y, entonces X, Z → Y, Z | isbn → titulo, entonces isbn, documento → titulo, documento |
| Transitividad | Si X → Y y Y → Z, entonces X → Z | cod_est → cod_prog y cod_prog → nombre_prog, entonces cod_est → nombre_prog |

Con ellas se calcula el **cierre** de un conjunto de atributos, X⁺: todo lo que X determina, directa o indirectamente. Se empieza con X y se agrega el lado derecho de cada dependencia cuyo lado izquierdo ya esté dentro, hasta que no cambie nada. Por ejemplo, en `aprobo_plano`, {cod_est}⁺ = {cod_est, nombre, cod_prog, nombre_prog}, que no incluye `cod_curso` ni `nota`: `cod_est` solo no es clave. {cod_est, cod_curso}⁺ incluye todos los atributos: es superclave. Así se comprueba si un conjunto es clave sin mirar los datos. El curso no profundiza en esta teoría; basta con saber que existe y que formaliza lo que se hizo a mano en las secciones 5 y 6.

### 10. Resumen

| Concepto | Qué es | En la planilla |
|---|---|---|
| Redundancia | El mismo dato guardado varias veces, o un dato calculable guardado | El correo de Juan David, 3 veces |
| Anomalía de modificación | Cambiar un dato exige cambiar todas sus copias | Corregir el correo en una sola fila deja dos correos |
| Anomalía de inserción | No se puede guardar algo sin inventar otra cosa | Daniela no se puede registrar sin un préstamo |
| Anomalía de borrado | Borrar algo arrastra información que no se quería borrar | Borrar el préstamo 5 borra a Camila y a *El Aleph* |
| Dependencia funcional X → Y | Filas iguales en X son iguales en Y; sale de las reglas del negocio | isbn → titulo, autor, categoria |
| Superclave | X → todos los atributos | id_prestamo |
| Señal de mal diseño | Una dependencia cuyo determinante no es superclave | isbn → …, documento → … |
| Descomposición sin pérdida | Partir según las dependencias; el atributo común es clave de una parte | libro, lector, prestamo |
| Tuplas espurias | Filas falsas al juntar por un atributo que no es clave | Juntar por fecha_prestamo: 14 filas en vez de 8 |

| En SQL | Para |
|---|---|
| `GROUP BY x HAVING count(DISTINCT y) > 1` | Encontrar filas que contradicen x → y |
| `INSERT INTO t SELECT DISTINCT …` | Llenar la tabla nueva sin repeticiones |
| Join + `EXCEPT` contra la tabla original | Comprobar que la descomposición no pierde ni inventa filas |

En **S18** (taller) estas ideas se convierten en las formas normales 1FN, 2FN, 3FN y FNBC, empezando por `aprobo_plano`.

## Lectura del libro

**Silberschatz, Korth, Sudarshan, *Fundamentos de Bases de Datos*, 6ª ed.**

- Capítulo 8, "Diseño de bases de datos relacionales": secciones 8.1 (características de un buen diseño relacional: el problema de la redundancia y la descomposición, incluida la descomposición con pérdida) y 8.3.1 (claves y dependencias funcionales).
- Capítulo 8, sección 8.4.1 (cierre de un conjunto de dependencias funcionales y axiomas de Armstrong), en lectura rápida.


## Videos de YouTube alternativos

*(Pendiente: buscar en YouTube "anomalías de actualización base de datos", "dependencia funcional base de datos" y "descomposición sin pérdida", y confirmar contenido y disponibilidad antes de publicar.)*
