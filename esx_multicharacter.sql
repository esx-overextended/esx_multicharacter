CREATE TABLE IF NOT EXISTS `multicharacter_slots` (
    `identifier` VARCHAR(60) NOT NULL,
    `slots` INT(11) NOT NULL,

    PRIMARY KEY (`identifier`),
    INDEX `slots` (`slots`)
) ENGINE=InnoDB;

ALTER TABLE `users`
    ADD COLUMN IF NOT EXISTS `disabled` TINYINT(1) NULL DEFAULT 0;
