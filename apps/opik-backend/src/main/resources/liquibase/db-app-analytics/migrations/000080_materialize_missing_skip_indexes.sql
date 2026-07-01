--liquibase formatted sql
--changeset thiagohora:000080_materialize_missing_skip_indexes
--comment: Add and materialize missing skip indexes that were not materialized in previous migrations

-- Add missing index from 000057 (project_id was added to experiment_items without an index)
ALTER TABLE ${ANALYTICS_DB_DATABASE_NAME}.experiment_items ON CLUSTER '${ANALYTICS_DB_CLUSTER_NAME}'
    ADD INDEX IF NOT EXISTS idx_experiment_items_project_id project_id TYPE minmax GRANULARITY 1;

ALTER TABLE ${ANALYTICS_DB_DATABASE_NAME}.experiment_items ON CLUSTER '${ANALYTICS_DB_CLUSTER_NAME}'
    MATERIALIZE INDEX idx_experiment_items_project_id;

-- Materialize index from 000075 (idx_optimizations_project_id was added without materialization)
ALTER TABLE ${ANALYTICS_DB_DATABASE_NAME}.optimizations ON CLUSTER '${ANALYTICS_DB_CLUSTER_NAME}'
    MATERIALIZE INDEX idx_optimizations_project_id;

--rollback ALTER TABLE ${ANALYTICS_DB_DATABASE_NAME}.experiment_items ON CLUSTER '${ANALYTICS_DB_CLUSTER_NAME}' DROP INDEX IF EXISTS idx_experiment_items_project_id;

