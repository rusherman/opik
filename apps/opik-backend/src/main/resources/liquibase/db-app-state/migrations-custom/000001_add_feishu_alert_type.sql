--liquibase formatted sql
--changeset DanielArian:custom_001_add_feishu_alert_type
--comment: [CUSTOM] Add 'feishu' to the alert_type ENUM column. Kept in migrations-custom/ (independent numbering) so it never collides with upstream prefixes on upgrade. See UPGRADE.md.

ALTER TABLE alerts
    MODIFY COLUMN alert_type ENUM('general', 'slack', 'pagerduty', 'feishu') NOT NULL DEFAULT 'general';

--rollback ALTER TABLE alerts MODIFY COLUMN alert_type ENUM('general', 'slack', 'pagerduty') NOT NULL DEFAULT 'general';
