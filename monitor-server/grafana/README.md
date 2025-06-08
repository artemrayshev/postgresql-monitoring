# Grafana Dashboards

## Импорт дашбордов:

1. Откройте Grafana: http://localhost:3000
2. Перейдите в Dashboards → Import
3. Скопируйте содержимое JSON файла
4. Вставьте в поле "Import via panel json"
5. Выберите Prometheus data source
6. Нажмите Import

## Дашборды:

- **overview-dashboard.json** - PostgreSQL - Обзорный дашборд
- **postgresql-detailed.json** - PostgreSQL - Детальный мониторинг
- **system-detailed.json** - Системный подробный
## Переменные:

- $database - фильтр по базам данных (в PostgreSQL дашборде)
