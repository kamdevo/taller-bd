#!/usr/bin/env bash
# Corre las cargas del laboratorio S14 y los reportes de S16 y guarda cada salida en proyecto-final/hito2/salidas/
# Uso (desde la raíz del repo, con la base recién creada y vacía):
#   bash postgres/scripts/correr-pruebas.sh
set -u
cd "$(dirname "$0")/../.."
OUT=proyecto-final/hito2/salidas
mkdir -p "$OUT"
PSQL="docker compose exec -T postgres psql -U curso -d curso"
D=/scripts/datos

correr() {  # correr <nombre-salida> <script> <csv>
  echo ">>> $1"
  $PSQL -v archivo="$D/$3" -f "/scripts/$2" 2>&1 | tee "$OUT/$1.txt"
}

correr 01-libros-limpio            S14-carga-libros.sql    libros_semilla.csv
correr 02-libros-con-errores       S14-carga-libros.sql    libros_semilla_con_errores.csv
correr 03-lectores-limpio          S14-carga-lectores.sql  lectores_semilla.csv
correr 04-lectores-con-errores     S14-carga-lectores.sql  lectores_semilla_con_errores.csv
correr 05-libros-csv-propio        S14-carga-libros.sql    libros_propio.csv
correr 06-libros-limpio-repetido   S14-carga-libros.sql    libros_semilla.csv   # no debe duplicar nada

# Prueba de la última línea de defensa: se anula la regla 'título vacío' y se recarga.
# Primero se borran los rechazos... no hace falta: la carga abortará y hará ROLLBACK completo.
echo ">>> 07-sin-regla-titulo (se espera ERROR del CHECK y ROLLBACK)"
sed "s/WHEN titulo = ''/WHEN false/" postgres/scripts/S14-carga-libros.sql \
  | $PSQL -v archivo="$D/libros_semilla_con_errores.csv" -f - 2>&1 | tee "$OUT/07-sin-regla-titulo.txt"

echo; echo "Conteos finales:"
$PSQL -c "SELECT (SELECT count(*) FROM biblioteca.libro) libros, (SELECT count(*) FROM biblioteca.ejemplar) ejemplares, (SELECT count(*) FROM biblioteca.usuario) usuarios, (SELECT count(*) FROM biblioteca.rechazo_carga) rechazos;" | tee "$OUT/08-conteos.txt"

# ---- S16 Parte B: datos de prueba y los 4 reportes ----
echo ">>> 09-datos-prueba"
$PSQL -f /scripts/datos-prueba.sql 2>&1 | tee "$OUT/09-datos-prueba.txt"
echo ">>> 10-reportes"
$PSQL -f /scripts/reportes.sql 2>&1 | tee "$OUT/10-reportes.txt"
