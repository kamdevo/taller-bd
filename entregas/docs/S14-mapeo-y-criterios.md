# Hito 2 · Mapeo CSV → esquema y criterios de carga

Esquema: `biblioteca` (`postgres/init/01_esquema.sql`). Cargas: `postgres/scripts/carga-libros.sql` y `carga-lectores.sql`.
Patrón: `COPY` a tabla de paso (todo texto) → validación con `CASE` → tabla final → bitácora `biblioteca.rechazo_carga`, todo en una transacción.

## 1. Mapeo CSV → esquema

### `libros_*.csv` (6 columnas)

| Columna del CSV | Tabla.columna destino | Transformación | Regla de validación (motivo) |
|---|---|---|---|
| `isbn` | `libro.isbn` (y `ejemplar.isbn`) | `trim` y se quitan guiones/espacios | no vacío ("isbn vacío"); 13 dígitos ("isbn no tiene 13 dígitos"); no existe ya en `libro` ("isbn ya existe en el catálogo"); no repetido en el archivo ("isbn repetido en el archivo") |
| `titulo` | `libro.titulo` | `trim` | no vacío ("título vacío"); ≤ 200 caracteres |
| `autor` | `libro.autor` | `trim` | no vacío ("autor vacío"); ≤ 150 caracteres |
| `categoria` | `libro.categoria` | `trim`; vacío → `NULL` | ≤ 80 caracteres |
| `anio_publicacion` | `libro.anio_publicacion` | `::integer` | solo dígitos ("año no numérico"); entre 1450 y el año actual ("año fuera de rango") |
| `ejemplares_disponibles` | `ejemplar` (n filas) | `generate_series(1, n)` → `numero_ejemplar` 1..n, `estado` = `disponible` | entero ("ejemplares no numérico"); ≥ 0 ("ejemplares negativo") |
| (línea completa) | — | — | exactamente 6 columnas ("tiene N columnas, se esperaban 6") |

### `lectores_*.csv` (5 columnas)

| Columna del CSV | Tabla.columna destino | Transformación | Regla de validación (motivo) |
|---|---|---|---|
| `documento` | `usuario.documento` | `trim` | no vacío; alfanumérico 4–20; no existe ya; no repetido en el archivo |
| `nombres` | `usuario.nombres` | `trim` | no vacío; ≤ 100 |
| `apellidos` | `usuario.apellidos` | `trim` | no vacío; ≤ 100 |
| `correo` | `usuario.correo` | `trim` y `lower` | no vacío; formato `algo@dominio.ext`; no existe ya; no repetido en el archivo (ya en minúsculas) |
| `telefono` | `usuario.telefono` | `trim`; vacío → `NULL` | opcional; si viene, 7–20 caracteres de `0-9 + ( ) -` |
| — (no viene en el CSV) | `usuario.password_hash` | `crypt(documento, gen_salt('bf'))` (pgcrypto) | — |
| — (no viene en el CSV) | `usuario.id_rol` | rol `lector` | — |

## 2. Criterios por tipo de error

### Libros (los 8 errores de `libros_semilla_con_errores.csv`)

| Línea | Error | Decisión | Motivo registrado | Por qué |
|---|---|---|---|---|
| 2 | ISBN que ya existe en el catálogo | **Rechazar** | isbn ya existe en el catálogo | El archivo es un alta, no una actualización. Así repetir la carga no duplica nada. |
| 3 | Título vacío | **Rechazar** | título vacío | El dato falta y no se puede adivinar. |
| 4 | Año no numérico (`dos`, en la columna del año) | **Rechazar** | año no numérico | No se interpreta texto como número. |
| 5 | Año en numerales romanos (`MCMXLIX`) | **Rechazar** | año no numérico | Convertir numerales romanos sería adivinar. |
| 6 | Columna de más | **Rechazar** | tiene 7 columnas, se esperaban 6 | No se sabe qué columna sobra. |
| 7 | Autor vacío | **Rechazar** | autor vacío | El dato falta. |
| 8 | ISBN vacío | **Rechazar** | isbn vacío | Es la clave primaria. |
| 9 | Ejemplares negativo | **Rechazar** | ejemplares negativo | Con el esquema actual una cantidad negativa crearía 0 copias sin error: se atrapa solo con esta regla. |

### Lectores (los 6 errores de `lectores_semilla_con_errores.csv`)

| Línea | Error | Decisión | Motivo registrado | Por qué |
|---|---|---|---|---|
| 2 | Documento `1000000001` ya existe (lector duplicado) | **Rechazar** | documento ya existe en usuarios | Evita duplicar personas. |
| 3 | Correo vacío | **Rechazar** | correo vacío | El correo es obligatorio y único; no se puede adivinar. |
| 4 | Correo sin `@` | **Rechazar** | correo inválido | No se adivina el correo. |
| 5 | Teléfono `tres-cero-cero` | **Rechazar** | teléfono con formato inválido | El teléfono es opcional, pero un valor inválido no se carga a medias. Si el grupo prefiere cargar al lector con teléfono `NULL`, debe aplicarlo a todos los casos iguales. |
| 6 | Documento vacío | **Rechazar** | documento vacío | Es el identificador del usuario. |
| 7 | Nombres vacío | **Rechazar** | nombres vacío | El dato falta. |

Correcciones mecánicas que se aplican a todo el archivo sin rechazar: `trim` en todos los campos y correo en minúsculas (así `Ana@X.co` y `ana@x.co` cuentan como el mismo). Un documento o correo repetido dentro del mismo archivo rechaza la segunda aparición.

### Errores propios (CSV `libros_propio.csv`)

| Línea | Error | Decisión | Motivo registrado |
|---|---|---|---|
| 8 | Mismo ISBN dos veces en el archivo | **Rechazar** la segunda aparición | isbn repetido en el archivo (primera aparición en la línea 2) |
| 9 | Año en el futuro (2099) | **Rechazar** | año fuera de rango |
| 10 | ISBN con letras | **Rechazar** | isbn no tiene 13 dígitos |

### Criterios generales

- **Corregir** solo lo mecánico y que no cambia el significado: espacios (`trim`), correo en minúsculas, guiones del ISBN, campos opcionales vacíos → `NULL`.
- **Rechazar** todo dato faltante o ambiguo. Nunca se adivina.
- Un ISBN o documento que ya existe **no se actualiza**: se rechaza. Esto aplica igual a todos los casos.
- Las filas válidas del mismo archivo siempre entran; las malas quedan en la bitácora con archivo, línea, contenido original y motivo.

## 3. Prueba de la última línea de defensa

Se anuló la regla `WHEN titulo = '' THEN 'título vacío'` (cambiándola por `WHEN false`) y se recargó `libros_semilla_con_errores.csv`.

**Qué pasó:** la fila de la línea 3 llegó al `INSERT` y chocó con `CHECK (titulo <> '')` del esquema:

```
ERROR:  new row for relation "libro" violates check constraint "libro_titulo_check"
DETAIL:  Failing row contains (9780000000033, , Julio Cortázar, Novela, 1963, t).
```

- **Las demás filas de esa carga:** no se cargó ninguna, ni siquiera las válidas. Toda la carga está en una transacción, así que falla entera y se deshace (`ROLLBACK`).
- **La bitácora:** quedó sin ninguna fila nueva, porque los rechazos se insertan en esa misma transacción y también se deshicieron.
- **Conclusión:** es el mismo problema del `COPY` directo (todo o nada, un solo error a la vez, mensaje del motor y no del negocio). Las restricciones del esquema son la última defensa, no el validador de la carga.
- **Cuidado extra:** si se anula la regla "ejemplares negativo", no hay ningún error. `generate_series(1, -3)` no devuelve filas y el libro queda cargado con 0 copias. El esquema no cubre ese caso, así que solo la regla de validación lo protege.
