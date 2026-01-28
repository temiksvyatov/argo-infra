-- Инициализация баз данных и пользователей для PostgreSQL с mTLS

-- Создание пользователей
CREATE USER apidoc;
CREATE USER apiman;
CREATE USER kpi;

-- Создание баз данных
CREATE DATABASE apidoc OWNER apidoc;
CREATE DATABASE apiman OWNER apiman;
CREATE DATABASE kpi OWNER kpi;

-- Отзыв всех прав по умолчанию
REVOKE ALL ON DATABASE apidoc FROM PUBLIC;
REVOKE ALL ON DATABASE apiman FROM PUBLIC;
REVOKE ALL ON DATABASE kpi FROM PUBLIC;

-- Предоставление прав только владельцам
GRANT ALL PRIVILEGES ON DATABASE apidoc TO apidoc;
GRANT ALL PRIVILEGES ON DATABASE apiman TO apiman;
GRANT ALL PRIVILEGES ON DATABASE kpi TO kpi;

-- Подключение к каждой базе и настройка прав на схему public
\c apidoc
REVOKE ALL ON SCHEMA public FROM PUBLIC;
GRANT ALL ON SCHEMA public TO apidoc;
ALTER DEFAULT PRIVILEGES FOR USER apidoc IN SCHEMA public GRANT ALL ON TABLES TO apidoc;
ALTER DEFAULT PRIVILEGES FOR USER apidoc IN SCHEMA public GRANT ALL ON SEQUENCES TO apidoc;
ALTER DEFAULT PRIVILEGES FOR USER apidoc IN SCHEMA public GRANT ALL ON FUNCTIONS TO apidoc;

\c apiman
REVOKE ALL ON SCHEMA public FROM PUBLIC;
GRANT ALL ON SCHEMA public TO apiman;
ALTER DEFAULT PRIVILEGES FOR USER apiman IN SCHEMA public GRANT ALL ON TABLES TO apiman;
ALTER DEFAULT PRIVILEGES FOR USER apiman IN SCHEMA public GRANT ALL ON SEQUENCES TO apiman;
ALTER DEFAULT PRIVILEGES FOR USER apiman IN SCHEMA public GRANT ALL ON FUNCTIONS TO apiman;

\c kpi
REVOKE ALL ON SCHEMA public FROM PUBLIC;
GRANT ALL ON SCHEMA public TO kpi;
ALTER DEFAULT PRIVILEGES FOR USER kpi IN SCHEMA public GRANT ALL ON TABLES TO kpi;
ALTER DEFAULT PRIVILEGES FOR USER kpi IN SCHEMA public GRANT ALL ON SEQUENCES TO kpi;
ALTER DEFAULT PRIVILEGES FOR USER kpi IN SCHEMA public GRANT ALL ON FUNCTIONS TO kpi;

-- Создание тестовых таблиц для проверки от имени владельцев
\c apidoc
SET ROLE apidoc;
CREATE TABLE IF NOT EXISTS test_table (id SERIAL PRIMARY KEY, data TEXT);
INSERT INTO test_table (data) VALUES ('apidoc test data');
RESET ROLE;

\c apiman
SET ROLE apiman;
CREATE TABLE IF NOT EXISTS test_table (id SERIAL PRIMARY KEY, data TEXT);
INSERT INTO test_table (data) VALUES ('apiman test data');
RESET ROLE;

\c kpi
SET ROLE kpi;
CREATE TABLE IF NOT EXISTS test_table (id SERIAL PRIMARY KEY, data TEXT);
INSERT INTO test_table (data) VALUES ('kpi test data');
RESET ROLE;
