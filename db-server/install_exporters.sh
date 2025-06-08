#!/bin/bash

# Скрипт установки экспортеров для мониторинга PostgreSQL
# Автор: Райшев А.И.
# Версия: 1.0

set -e  # Остановка при ошибке

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Версии компонентов
NODE_EXPORTER_VERSION="1.6.1"
POSTGRES_EXPORTER_VERSION="0.13.2"

# Пользователи
MONITOR_USER="monitoring"
POSTGRES_USER="postgres"

echo -e "${GREEN}=== Установка экспортеров для мониторинга PostgreSQL ===${NC}"

# Функция логирования
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}"
    exit 1
}

warning() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

# Проверка прав root
if [[ $EUID -ne 0 ]]; then
   error "Скрипт должен запускаться с правами root"
fi

# Создание пользователя для мониторинга
create_monitor_user() {
    log "Создание пользователя $MONITOR_USER..."
    if ! id "$MONITOR_USER" &>/dev/null; then
        useradd --no-create-home --shell /bin/false $MONITOR_USER
        log "Пользователь $MONITOR_USER создан"
    else
        warning "Пользователь $MONITOR_USER уже существует"
    fi
}

# Установка node_exporter
install_node_exporter() {
    log "Установка node_exporter версии $NODE_EXPORTER_VERSION..."
    
    # Скачивание
    cd /tmp
    wget -q "https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz"
    
    # Распаковка
    tar xzf "node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz"
    
    # Копирование исполняемого файла
    cp "node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64/node_exporter" /usr/local/bin/
    chown $MONITOR_USER:$MONITOR_USER /usr/local/bin/node_exporter
    chmod +x /usr/local/bin/node_exporter
    
    # Очистка
    rm -rf "node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64"*
    
    log "node_exporter установлен в /usr/local/bin/"
}

# Создание systemd сервиса для node_exporter
create_node_exporter_service() {
    log "Создание systemd сервиса для node_exporter..."
    
    cat > /etc/systemd/system/node_exporter.service << EOF
[Unit]
Description=Node Exporter
Wants=network-online.target
After=network-online.target

[Service]
User=$MONITOR_USER
Group=$MONITOR_USER
Type=simple
ExecStart=/usr/local/bin/node_exporter \\
    --collector.systemd \\
    --collector.processes \\
    --web.listen-address=:9100

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable node_exporter
    log "Systemd сервис node_exporter создан и включен"
}

# Установка postgres_exporter
install_postgres_exporter() {
    log "Установка postgres_exporter версии $POSTGRES_EXPORTER_VERSION..."
    
    # Скачивание
    cd /tmp
    wget -q "https://github.com/prometheus-community/postgres_exporter/releases/download/v${POSTGRES_EXPORTER_VERSION}/postgres_exporter-${POSTGRES_EXPORTER_VERSION}.linux-amd64.tar.gz"
    
    # Распаковка
    tar xzf "postgres_exporter-${POSTGRES_EXPORTER_VERSION}.linux-amd64.tar.gz"
    
    # Копирование исполняемого файла
    cp "postgres_exporter-${POSTGRES_EXPORTER_VERSION}.linux-amd64/postgres_exporter" /usr/local/bin/
    chown $MONITOR_USER:$MONITOR_USER /usr/local/bin/postgres_exporter
    chmod +x /usr/local/bin/postgres_exporter
    
    # Очистка
    rm -rf "postgres_exporter-${POSTGRES_EXPORTER_VERSION}.linux-amd64"*
    
    log "postgres_exporter установлен в /usr/local/bin/"
}

# Настройка доступа к PostgreSQL
setup_postgres_access() {
    log "Настройка доступа к PostgreSQL..."
    
    # Создание пользователя в PostgreSQL
    sudo -u $POSTGRES_USER psql -c "
    DO \$\$
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'postgres_exporter') THEN
            CREATE USER postgres_exporter;
        END IF;
    END
    \$\$;
    " || warning "Пользователь postgres_exporter уже может существовать"
    
    # Назначение прав
    sudo -u $POSTGRES_USER psql -c "GRANT pg_monitor TO postgres_exporter;" || warning "Права уже могут быть назначены"
    
    # Создание файла с переменными окружения
    cat > /etc/default/postgres_exporter << EOF
DATA_SOURCE_NAME="postgresql://postgres_exporter@localhost:5432/postgres?sslmode=disable"
PG_EXPORTER_EXTEND_QUERY_PATH="/etc/postgres_exporter/queries.yaml"
EOF
    
    # Создание директории для конфигурации
    mkdir -p /etc/postgres_exporter
    
    # Создание файла с дополнительными запросами
    cat > /etc/postgres_exporter/queries.yaml << EOF
pg_replication:
  query: "SELECT CASE WHEN NOT pg_is_in_recovery() THEN 0 ELSE GREATEST (0, EXTRACT(EPOCH FROM (now() - pg_last_xact_replay_timestamp()))) END AS lag"
  master: true
  metrics:
    - lag:
        usage: "GAUGE"
        description: "Replication lag behind master in seconds"

pg_postmaster:
  query: "SELECT pg_postmaster_start_time as start_time_seconds from pg_postmaster_start_time()"
  master: true
  metrics:
    - start_time_seconds:
        usage: "GAUGE"
        description: "Time at which postmaster started"
EOF
    
    chown -R $MONITOR_USER:$MONITOR_USER /etc/postgres_exporter
    
    log "Доступ к PostgreSQL настроен"
}

# Создание systemd сервиса для postgres_exporter
create_postgres_exporter_service() {
    log "Создание systemd сервиса для postgres_exporter..."
    
    cat > /etc/systemd/system/postgres_exporter.service << EOF
[Unit]
Description=Prometheus PostgreSQL Exporter
After=network.target

[Service]
Type=simple
Restart=always
User=$MONITOR_USER
Group=$MONITOR_USER
EnvironmentFile=/etc/default/postgres_exporter
ExecStart=/usr/local/bin/postgres_exporter \\
    --web.listen-address=:9187 \\
    --web.telemetry-path=/metrics

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable postgres_exporter
    log "Systemd сервис postgres_exporter создан и включен"
}

# Настройка firewall
setup_firewall() {
    log "Настройка firewall..."
    
    if command -v ufw &> /dev/null; then
        ufw allow 9100/tcp comment "Node Exporter"
        ufw allow 9187/tcp comment "PostgreSQL Exporter"
        log "UFW правила добавлены"
    elif command -v firewall-cmd &> /dev/null; then
        firewall-cmd --permanent --add-port=9100/tcp
        firewall-cmd --permanent --add-port=9187/tcp
        firewall-cmd --reload
        log "Firewalld правила добавлены"
    else
        warning "Firewall не найден, настройте порты 9100 и 9187 вручную"
    fi
}

# Запуск сервисов
start_services() {
    log "Запуск сервисов..."
    
    systemctl start node_exporter
    systemctl start postgres_exporter
    
    sleep 3
    
    # Проверка статуса
    if systemctl is-active --quiet node_exporter; then
        log "node_exporter запущен успешно"
    else
        error "Ошибка запуска node_exporter"
    fi
    
    if systemctl is-active --quiet postgres_exporter; then
        log "postgres_exporter запущен успешно"
    else
        error "Ошибка запуска postgres_exporter"
    fi
}

# Проверка работоспособности
check_exporters() {
    log "Проверка работоспособности экспортеров..."
    
    # Проверка node_exporter
    if curl -s http://localhost:9100/metrics | grep -q "node_cpu_seconds_total"; then
        log "node_exporter работает корректно"
    else
        error "node_exporter не отвечает или работает некорректно"
    fi
    
    # Проверка postgres_exporter
    if curl -s http://localhost:9187/metrics | grep -q "pg_up"; then
        log "postgres_exporter работает корректно"
    else
        error "postgres_exporter не отвечает или работает некорректно"
    fi
}

# Вывод информации
show_info() {
    echo
    echo -e "${GREEN}=== Установка завершена успешно ===${NC}"
    echo -e "${YELLOW}Порты экспортеров:${NC}"
    echo "  - node_exporter: http://$(hostname -I | awk '{print $1}'):9100/metrics"
    echo "  - postgres_exporter: http://$(hostname -I | awk '{print $1}'):9187/metrics"
    echo
    echo -e "${YELLOW}Управление сервисами:${NC}"
    echo "  systemctl status node_exporter"
    echo "  systemctl status postgres_exporter"
    echo "  systemctl restart node_exporter"
    echo "  systemctl restart postgres_exporter"
    echo
    echo -e "${YELLOW}Логи:${NC}"
    echo "  journalctl -u node_exporter -f"
    echo "  journalctl -u postgres_exporter -f"
}

# Основная функция
main() {
    log "Начало установки экспортеров..."
    
    # Обновление пакетов
    log "Обновление системы..."
    apt-get update -qq
    apt-get install -y wget curl
    
    # Выполнение установки
    create_monitor_user
    install_node_exporter
    create_node_exporter_service
    install_postgres_exporter
    setup_postgres_access
    create_postgres_exporter_service
    setup_firewall
    start_services
    check_exporters
    show_info
    
    log "Установка завершена успешно!"
}

# Запуск основной функции
main "$@"
