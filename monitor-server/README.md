# PostgreSQL Monitoring Stack

Система мониторинга PostgreSQL с использованием Prometheus, Grafana и InfluxDB.

## Компоненты

- **Prometheus** - сбор метрик
- **Grafana** - визуализация дашбордов  
- **InfluxDB** - хранение временных рядов
- **Node Exporter** - системные метрики
- **PostgreSQL Exporter** - метрики PostgreSQL
- **Telegram Webhook** - уведомления

## Дашборды

1. **Обзорный дашборд** - ключевые метрики системы
2. **PostgreSQL детальный** - детальная статистика БД
3. **Системный детальный** - мониторинг ресурсов
4. **Анализ производительности** - тренды и аналитика

## Запуск

```bash
docker-compose up -d
