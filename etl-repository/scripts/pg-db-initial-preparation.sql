CREATE ROLE etl_schema LOGIN password 'etl_schema';
CREATE DATABASE etl_repository ENCODING 'UTF8' OWNER etl_schema;
\connect postgres://etl_schema:etl_schema@localhost/etl_repository;
CREATE SCHEMA etl_schema AUTHORIZATION etl_schema;