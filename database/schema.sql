-- Baseline schema for the "stub" service's MySQL (RDS) dependency.
--
-- Per the Day 2 spec: "Once you have a MySQL service deployed, you will
-- need to create a database called unicorndb and create the table
-- necessary to serve the requests... The table name is set to "unicorns"
-- in the application and cannot be changed."
--
-- Terraform in this starter kit does NOT create the RDS instance or run
-- this schema - that is participant work. Apply this manually (or via
-- your own automation) against the MySQL database you provision, e.g.:
--   mysql -h <rds-endpoint> -u <user> -p < database/schema.sql

CREATE DATABASE IF NOT EXISTS unicorndb;

USE unicorndb;

CREATE TABLE IF NOT EXISTS unicorns (
    unicornid varchar(256),
    unicornlocation varchar(256)
);
