UNIVERSIDAD DEL VALLE
Base de Datos · Grupo 80
Documento de Normalización (Hito 3)
José Manuel Cardona Gil - 2521653 · Juan Camilo Morales - 2515391
Andres Felipe Rengifo - 2519613 · Jorge Luis Castro - 2517065

1. Esquema antes de normalizar
El esquema inicial contaba con 7 tablas: rol (catálogo estático con los 4 perfiles), usuario (lectores, bibliotecarios, administrador y auditor), libro, ejemplar (copia física de un libro), prestamo, devolucion y rechazo_carga (bitácora de auditoría para filas rechazadas al cargar los CSV).

2 y 3. Claves, reglas, forma normal y problemas encontrados
Todas las tablas alcanzaron FNBC (Forma Normal de Boyce-Codd), la forma más estricta del análisis relacional.

| Tabla | Clave Candidata | Regla / Dependencias Funcionales | Forma Normal | Problema y Evidencia |
|---|---|---|---|---|
| rol | id o nombre | Cada id determina un único nombre y viceversa. | FNBC | Ninguno. Catálogo estático sin redundancias. |
| usuario | id, documento o correo | Cada persona tiene un único documento y correo. Determinan nombres, apellidos, teléfono, password_hash, rol y estado activo. | FNBC | Ninguno. Se conserva id como clave subrogada para permitir corregir documento o correo con un solo UPDATE sin propagar en cascada. |
| libro | isbn | El ISBN identifica unívocamente el libro y determina título, autor, categoría, año de publicación y activo. | FNBC | Ninguno. El alcance del proyecto establece un único autor principal por libro. |
| ejemplar | (isbn, numero_ejemplar) | La combinación de ISBN y número de copia identifica el ejemplar físico. | FNBC | Guardaba la columna estado ('disponible', 'prestado', 'baja'). Los estados 'prestado' y 'disponible' son datos derivados calculables cruzando prestamo y devolucion. Evidencia: comparación contra el estado calculado; 0 inconsistencias en bajas. |
| prestamo | id | Identifica la transacción de préstamo, determinando lector, copia física, bibliotecario y fechas. | FNBC | Guardaba estado ('activo', 'en_mora', 'devuelto'). Es un dato derivable dependiente del tiempo. Evidencia (SELECT p.id, p.estado, v.estado FROM prestamo p JOIN prestamo_estado v USING (id) WHERE p.estado <> v.estado): préstamos 7 y 12 figuraban como 'activo' cuando ya estaban en mora. |
| devolucion | id_prestamo (antes también id) | Un préstamo se devuelve a lo sumo una vez. id_prestamo determina bibliotecario y fecha de entrega. | FNBC | Poseía un id autonumérico redundante. Al ser una relación 1:1 con prestamo, id_prestamo es la clave primaria natural. Evidencia: validado con EXCEPT (cero registros duplicados o perdidos). |
| rechazo_carga | id | Cada registro identifica un rechazo de carga y determina archivo, línea, contenido, motivo y fecha. | FNBC | Ninguno. Tabla de bitácora requerida para trazabilidad del Hito 2. |

4. Cambios y migración aplicada
La migración se ejecutó dentro de una sola transacción segura (BEGIN ... COMMIT con ON_ERROR_STOP on). Se implementaron validaciones previas, verificación de diferencias de conjuntos mediante EXCEPT en devolucion, y comparación de conteos antes y después mediante tablas temporales:

| Tabla | Qué se hizo | Filas Antes | Filas Después | Coincide |
|---|---|:---:|:---:|:---:|
| ejemplar | Se reemplazó estado por activo (BOOLEAN). Si es false indica 'baja'. Para 'prestado' o 'disponible' se creó la vista ejemplar_estado. | 111 | 111 | Sí (t) |
| prestamo | Se eliminó la columna estado y se creó la vista prestamo_estado, que evalúa si hay devolución (devuelto), fecha_esperada < CURRENT_DATE (en_mora) o activo. | 100 | 100 | Sí (t) |
| devolucion | Se retiró el id redundante y se redefinió id_prestamo como PRIMARY KEY directa. | 88 | 88 | Sí (t) |
| Índices FK | Se crearon prestamo_ejemplar_idx y prestamo_lector_idx para optimizar joins y vistas. | N/A | N/A | Creados |

Los reportes de S16 se recrearon exitosamente usando prestamo_estado, arrojando exactamente los mismos resultados esperados. Asimismo, el archivo postgres/init/01_esquema.sql fue actualizado y verificado en una base de datos limpia (prueba_init).

5. Desnormalización
No se desnormalizó ninguna columna.
- Los estados de ejemplar y de préstamo se calculan dinámicamente con vistas, eliminando cualquier riesgo de anomalía por desincronización o falta de triggers.
- Para compensar el costo del cálculo en lecturas frecuentes, se crearon índices sobre las llaves foráneas (prestamo(isbn, numero_ejemplar) y prestamo(id_lector)), evitando escaneos secuenciales.
- La columna fecha_esperada_devolucion en prestamo no se considera desnormalización sino un dato histórico/regla de negocio: registra el plazo otorgado en el momento exacto del préstamo, el cual no debe mutar si las políticas de plazos de la biblioteca cambian a futuro.
- Para el Hito 4 quedan programados los triggers que validarán las restricciones dinámicas (rol correcto de usuario, unicidad de préstamos abiertos por ejemplar y coherencia temporal de fechas).

6. Esquema después
Todas las tablas del sistema se encuentran en FNBC (y por ende en 3FN). No existe ninguna tabla que cumpla 3FN pero incumpla FNBC, puesto que en todas las dependencias funcionales existentes el determinante es una superclave.