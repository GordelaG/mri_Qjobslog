CREATE TABLE IF NOT EXISTS `mri_orgs_config` (
  `job_name` varchar(50) NOT NULL,
  `webhook` text DEFAULT NULL,
  `report_webhook` text DEFAULT NULL,
  `min_grade` int(11) DEFAULT 0,
  `log_title` varchar(100) DEFAULT NULL,
  `color` int(11) DEFAULT 3447003,
  `icon_url` text DEFAULT NULL,
  PRIMARY KEY (`job_name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `mri_duty_logs` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `job` varchar(50) DEFAULT NULL,
  `player_name` varchar(100) DEFAULT NULL,
  `citizenid` varchar(50) DEFAULT NULL,
  `grade` varchar(50) DEFAULT NULL,
  `discord_id` varchar(50) DEFAULT NULL,
  `status` varchar(50) DEFAULT NULL,
  `duration` int(11) DEFAULT 0,
  `created_at` timestamp NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  KEY `job_idx` (`job`),
  KEY `created_at_idx` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
