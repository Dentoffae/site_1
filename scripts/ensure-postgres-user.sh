#!/bin/sh
# Создаёт роль POSTGRES_USER с паролем POSTGRES_PASSWORD, если кластер уже был
# инициализирован с другим суперпользователем (том не пустой — init не выполняется).
set -eu

PGHOST="${PGHOST:-postgres}"
PGPORT="${PGPORT:-5432}"
export PGHOST PGPORT

try_psql() {
  user="$1"
  shift
  # -w: не ждать пароль с stdin (иначе compose зависает без TTY)
  PGPASSWORD="${POSTGRES_PASSWORD:-}" psql -w -h "$PGHOST" -p "$PGPORT" -U "$user" -d postgres "$@" >/dev/null 2>&1
}

# Сначала POSTGRES_USER из .env — тот же пароль редко подходит к «старому» autobizlab, лишняя попытка даёт FATAL в логах postgres.
SUPERUSER=""
seen=" "
for u in "${POSTGRES_USER:-autobizlab}" autobizlab admin postgres; do
  case "$seen" in *" $u "*) continue;; esac
  seen="$seen$u "
  if try_psql "$u" -c "SELECT 1"; then
    SUPERUSER="$u"
    break
  fi
done

if [ -z "$SUPERUSER" ]; then
  echo "ensure-postgres-user: не удалось подключиться к postgres как суперпользователь (autobizlab/admin/postgres)." >&2
  echo "Проверьте POSTGRES_PASSWORD в .env или подключитесь вручную и создайте роль ${POSTGRES_USER}." >&2
  exit 1
fi

export PGPASSWORD="${POSTGRES_PASSWORD:-}"

# Экранирование для литералов в SQL (апострофы удваиваются)
sql_quote() {
  printf '%s' "$1" | sed "s/'/''/g"
}

UE=$(sql_quote "$POSTGRES_USER")
PE=$(sql_quote "$POSTGRES_PASSWORD")

psql -w -h "$PGHOST" -p "$PGPORT" -U "$SUPERUSER" -d postgres -v ON_ERROR_STOP=1 <<EOF
DO \$body\$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '$UE') THEN
    EXECUTE format('CREATE ROLE %I WITH LOGIN SUPERUSER PASSWORD %L', '$UE', '$PE');
  ELSE
    EXECUTE format('ALTER ROLE %I WITH PASSWORD %L', '$UE', '$PE');
  END IF;
END\$body\$;
EOF

echo "ensure-postgres-user: роль ${POSTGRES_USER} готова (подключение как ${SUPERUSER})."
