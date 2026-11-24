# Sistema de Gestión Bibliotecaria
**Proyecto Final · Base de Datos Relacional**  
**Universidad del Valle · Bases de Datos (Cuarto Semestre)**  
**Grupo:** 80  

### Integrantes:
- **Andres Felipe Rengifo Rodriguez** - 202519613
- **Jose Manuel Cardona Gil** - 202521653
- **Juan Camilo Morales** - 202515391
- **Jorge Luis Castro** - 202517065

---

## 1. Descripción del Entorno

El proyecto se ejecuta en contenedores orquestados con **Docker Compose**, integrando el motor relacional, la interfaz visual de administración y el entorno de aplicación:

| Servicio | Imagen | Función en el Proyecto | Puerto Local |
|---|---|---|---|
| `postgres` | `postgres:16` | Motor de base de datos relacional (esquema `biblioteca` en 3FN/FNBC) | `localhost:5432` |
| `pgadmin` | `dpage/pgadmin4:8` | Interfaz web de administración gráfica | `localhost:5050` |
| `node` | `node:20-alpine` | Entorno para la API / Backend del proyecto | `localhost:3000` |

---

## 2. Estructura y Organización del Proyecto

El repositorio se encuentra organizado de forma modular, separando los scripts de ejecución de la base de datos, los talleres prácticos, las guías de estudio y las evidencias formales de cada entrega:

```text
taller-bd/
├── docker-compose.yml              # Configuración de servicios Docker (Postgres, pgAdmin, Node)
├── .env.example                    # Plantilla de variables de entorno
├── README.md                       # Documentación general y bitácora de entregas
│
├── entregas/                       # 📁 EVIDENCIAS Y ENTREGABLES FORMALES
│   ├── assets/                     # Capturas de comprobación organizadas por sesión
│   │   ├── Entrega_S14/            # Capturas de cargas CSV, bitácora y última línea de defensa
│   │   └── Entrega_S16/            # Capturas de los 4 reportes analíticos
│   ├── docs/                       # Documentación técnica de soporte
│   │   ├── S14-mapeo-y-criterios.md
│   │   └── S16-tabla-verificacion.md
│   └── SQL/                        # Copias de scripts y entregas teóricas por hito
│       ├── s16/consultas.sql       # Consultas analíticas y reportes
│       ├── s19/casos.sql           # Resolución de los 4 casos de esquemas mal diseñados
│       └── S20/Entrega.MD          # Documento formal de Normalización (Hito 3)
│
├── postgres/                       # 📁 COMPONENTES DE BASE DE DATOS
│   ├── init/
│   │   └── 01_esquema.sql          # Esquema inicial limpio y normalizado (Hito 3 en FNBC)
│   ├── scripts/                    # Scripts SQL montados en el contenedor (/scripts)
│   │   ├── Proyecto/               # Scripts propios del proyecto de biblioteca
│   │   │   ├── normalizacion.sql   # Migración transaccional a 3FN/FNBC (Hito 3)
│   │   │   ├── reportes.sql        # Vistas de los 4 reportes analíticos del sistema
│   │   │   ├── datos-prueba.sql    # Dataset controlado (100 préstamos) para pruebas
│   │   │   ├── S14-carga-libros.sql
│   │   │   ├── S14-carga-lectores.sql
│   │   │   └── S14-carga-prestamos.sql
│   │   ├── talleres/               # Prácticas y talleres sincrónicos de clase
│   │   │   ├── S16-tienda.sql
│   │   │   ├── S18-automotriz.sql
│   │   │   ├── S19-esquemas.sql
│   │   │   └── S20-rendimiento.sql # Esquema masivo para pruebas con EXPLAIN ANALYZE
│   │   └── datos/                  # Archivos CSV (semillas y datos propios)
│   └── data/                       # Almacenamiento persistente de PostgreSQL (ignorado en git)
│
├── MD/                             # 📁 Guías de laboratorio y talleres del curso (S14 a S20)
├── pgadmin/                        # Configuración y conexiones persistentes de pgAdmin
└── node/                           # Código fuente del backend / API
```

---

## 3. Puesta en Marcha (Comandos Rápidos)

Requisitos: **Docker Desktop** iniciado.

```powershell
# 1. Levantar la base de datos en segundo plano
docker compose up -d postgres

# 2. Conectarse a la consola psql
docker compose exec postgres psql -U curso -d curso

# 3. Levantar pgAdmin (opcional)
docker compose up -d pgadmin
# Acceso web: http://localhost:5050
# Credenciales: estudiante@curso.edu.co / curso

# 4. Apagar los contenedores (los datos persisten)
docker compose down
```

### Reiniciar la base de datos limpia desde cero
Si se requiere regenerar la base limpia ejecutando el `01_esquema.sql` normalizado:
```powershell
docker compose down
# En Windows (PowerShell):
Remove-Item -Recurse -Force postgres/data/*
# Levantar de nuevo:
docker compose up -d postgres
```

---

## 4. Bitácora de Entregas

### 📌 Hito 2 (Sesión 14) · Esquema y Carga Masiva con Bitácora
- **Esquema:** Tablas con restricciones `CHECK` como última línea de defensa.
- **Scripts de Carga:** Validación fila a fila con inserción en tabla final o desvío a `rechazo_carga`.
- **Archivos y Evidencias:**
  - Mapeo y criterios: [`entregas/docs/S14-mapeo-y-criterios.md`](entregas/docs/S14-mapeo-y-criterios.md)
  - Capturas de comprobación: [`entregas/assets/Entrega_S14/`](entregas/assets/Entrega_S14/) (cargas limpias, manejo de errores, CSV propio y prueba de última línea de defensa con rollback).

---

### 📌 Sesión 16 · Consultas Avanzadas y Reportes
- Implementación de los 4 reportes analíticos de la biblioteca como vistas:
  1. *Top 20 libros más prestados* (manejo de empates y desempate alfabético).
  2. *Lector(es) con más libros leídos* (empates en primer lugar).
  3. *Lectores morosos* (subconsulta correlacionada con `EXISTS`).
  4. *Préstamos en mora* (cálculo dinámico de días de mora con `CURRENT_DATE`).
- **Archivos y Evidencias:**
  - Script SQL: [`entregas/SQL/s16/consultas.sql`](entregas/SQL/s16/consultas.sql) y [`postgres/scripts/Proyecto/reportes.sql`](postgres/scripts/Proyecto/reportes.sql)
  - Capturas de resultados: [`entregas/assets/Entrega_S16/`](entregas/assets/Entrega_S16/)

---

### 📌 Sesión 19 · Esquemas Mal Diseñados
- Diagnóstico de dependencias funcionales, cálculo de formas normales y migraciones controladas para 4 casos típicos de esquemas anómalos.
- **Archivo:** [`entregas/SQL/s19/casos.sql`](entregas/SQL/s19/casos.sql)

---

### 📌 Hito 3 (Sesión 20) · Normalización a FNBC y Rendimiento
- **Migración a FNBC:** Ejecución transaccional (`normalizacion.sql`) que resolvió las anomalías en el esquema:
  - **`ejemplar`:** Reemplazo de `estado` por `activo BOOLEAN`. Creación de la vista `ejemplar_estado` para calcular disponibilidad sin redundancia.
  - **`prestamo`:** Eliminación de la columna `estado`. Creación de la vista `prestamo_estado` para cálculo dinámico en función de devoluciones y mora.
  - **`devolucion`:** Eliminación de la clave subrogada `id`; `id_prestamo` se define como `PRIMARY KEY` natural.
  - **Índices FK:** Creación de `prestamo_ejemplar_idx` y `prestamo_lector_idx` para optimizar joins y consultas.
- **Validación limpia desde cero:** Actualización de [`postgres/init/01_esquema.sql`](postgres/init/01_esquema.sql) comprobada en base vacía (`prueba_init`).
- **Archivos:**
  - Script de migración: [`postgres/scripts/Proyecto/normalizacion.sql`](postgres/scripts/Proyecto/normalizacion.sql)
  - Documento de Normalización: [`entregas/SQL/S20/Entrega.MD`](entregas/SQL/S20/Entrega.MD)
