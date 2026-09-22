-- RO WHOLESALE DEALER MOBILE APP - MYSQL DATABASE SCHEMA
-- DATABASE NAME: ro_wholesale_db

CREATE DATABASE IF NOT EXISTS `ro_wholesale_db` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE `ro_wholesale_db`;

-- 1. USERS TABLE (Dealers)
CREATE TABLE IF NOT EXISTS `users` (
  `id` VARCHAR(64) NOT NULL,
  `email` VARCHAR(191) NOT NULL,
  `mobile` VARCHAR(20) NULL,
  `name` VARCHAR(128) NOT NULL,
  `password_hash` VARCHAR(255) NOT NULL,
  `business_name` VARCHAR(191) NULL,
  `owner_name` VARCHAR(128) NULL,
  `address` TEXT NULL,
  `status` ENUM('pending', 'approved', 'rejected') NOT NULL DEFAULT 'approved',
  `is_approved` TINYINT(1) NOT NULL DEFAULT 1,
  `reward_points` INT NOT NULL DEFAULT 0,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_users_email` (`email`),
  UNIQUE KEY `uk_users_mobile` (`mobile`),
  INDEX `idx_users_status` (`status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 2. USER ADDRESSES TABLE
CREATE TABLE IF NOT EXISTS `user_addresses` (
  `id` VARCHAR(64) NOT NULL,
  `user_id` VARCHAR(64) NOT NULL,
  `label` VARCHAR(64) NOT NULL DEFAULT 'Main Warehouse',
  `business_name` VARCHAR(191) NULL,
  `street` TEXT NOT NULL,
  `city` VARCHAR(100) NOT NULL,
  `state` VARCHAR(100) NOT NULL,
  `pincode` VARCHAR(20) NOT NULL,
  `phone` VARCHAR(20) NULL,
  `is_default` TINYINT(1) NOT NULL DEFAULT 0,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  INDEX `idx_addresses_user_id` (`user_id`),
  CONSTRAINT `fk_addresses_users` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 3. CATEGORIES TABLE
CREATE TABLE IF NOT EXISTS `categories` (
  `id` VARCHAR(64) NOT NULL,
  `key_name` VARCHAR(64) NOT NULL,
  `title` VARCHAR(128) NOT NULL,
  `badge_text` VARCHAR(64) NULL,
  `icon_color` VARCHAR(32) NULL,
  `image_url` VARCHAR(255) NULL,
  `display_order` INT NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_categories_key` (`key_name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 4. PRODUCTS TABLE
CREATE TABLE IF NOT EXISTS `products` (
  `id` VARCHAR(64) NOT NULL,
  `category_id` VARCHAR(64) NULL,
  `category_key` VARCHAR(64) NOT NULL,
  `sku` VARCHAR(64) NOT NULL,
  `name` VARCHAR(255) NOT NULL,
  `brand` VARCHAR(100) NOT NULL,
  `price` DECIMAL(10, 2) NOT NULL,
  `mrp` DECIMAL(10, 2) NOT NULL,
  `moq` VARCHAR(64) NULL,
  `badge` VARCHAR(64) NULL,
  `rating` VARCHAR(64) NULL,
  `img` VARCHAR(255) NULL,
  `description` TEXT NULL,
  `specs_json` JSON NULL,
  `features_json` JSON NULL,
  `applications` TEXT NULL,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_products_sku` (`sku`),
  INDEX `idx_products_category` (`category_key`),
  CONSTRAINT `fk_products_categories` FOREIGN KEY (`category_id`) REFERENCES `categories` (`id`) ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 5. ORDERS TABLE
CREATE TABLE IF NOT EXISTS `orders` (
  `order_id` VARCHAR(64) NOT NULL,
  `user_id` VARCHAR(64) NULL,
  `user_email` VARCHAR(191) NOT NULL,
  `user_name` VARCHAR(128) NOT NULL,
  `user_business` VARCHAR(191) NULL,
  `subtotal` DECIMAL(10, 2) NOT NULL DEFAULT 0.00,
  `discount` DECIMAL(10, 2) NOT NULL DEFAULT 0.00,
  `gst` DECIMAL(10, 2) NOT NULL DEFAULT 0.00,
  `delivery_fee` DECIMAL(10, 2) NOT NULL DEFAULT 0.00,
  `grand_total` DECIMAL(10, 2) NOT NULL DEFAULT 0.00,
  `payment_method` VARCHAR(100) NOT NULL DEFAULT 'UPI Direct QR Transfer',
  `delivery_address` TEXT NOT NULL,
  `delivery_note` TEXT NULL,
  `status` VARCHAR(100) NOT NULL DEFAULT 'Processing & Dispatched',
  `invoice_number` VARCHAR(64) NOT NULL,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`order_id`),
  UNIQUE KEY `uk_orders_invoice` (`invoice_number`),
  INDEX `idx_orders_user_id` (`user_id`),
  INDEX `idx_orders_user_email` (`user_email`),
  CONSTRAINT `fk_orders_users` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 6. ORDER ITEMS TABLE
CREATE TABLE IF NOT EXISTS `order_items` (
  `id` BIGINT AUTO_INCREMENT NOT NULL,
  `order_id` VARCHAR(64) NOT NULL,
  `product_id` VARCHAR(64) NULL,
  `product_name` VARCHAR(255) NOT NULL,
  `brand` VARCHAR(100) NULL,
  `unit_price` DECIMAL(10, 2) NOT NULL,
  `quantity` INT NOT NULL DEFAULT 1,
  `moq` VARCHAR(64) NULL,
  `img_src` VARCHAR(255) NULL,
  `sku` VARCHAR(64) NULL,
  PRIMARY KEY (`id`),
  INDEX `idx_order_items_order_id` (`order_id`),
  CONSTRAINT `fk_order_items_orders` FOREIGN KEY (`order_id`) REFERENCES `orders` (`order_id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 7. REWARDS HISTORY TABLE
CREATE TABLE IF NOT EXISTS `rewards_history` (
  `id` BIGINT AUTO_INCREMENT NOT NULL,
  `user_id` VARCHAR(64) NOT NULL,
  `order_id` VARCHAR(64) NULL,
  `order_amount` DECIMAL(10, 2) NOT NULL,
  `points_earned` INT NOT NULL,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  INDEX `idx_rewards_user_id` (`user_id`),
  CONSTRAINT `fk_rewards_users` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT `fk_rewards_orders` FOREIGN KEY (`order_id`) REFERENCES `orders` (`order_id`) ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 8. OTP CODES TABLE
CREATE TABLE IF NOT EXISTS `otp_codes` (
  `id` BIGINT AUTO_INCREMENT NOT NULL,
  `email` VARCHAR(191) NOT NULL,
  `otp_code` VARCHAR(10) NOT NULL,
  `expires_at` DATETIME NOT NULL,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  INDEX `idx_otp_email_expires` (`email`, `expires_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 9. SUPPORT TICKETS TABLE
CREATE TABLE IF NOT EXISTS `support_tickets` (
  `id` BIGINT AUTO_INCREMENT NOT NULL,
  `user_id` VARCHAR(64) NULL,
  `user_email` VARCHAR(191) NOT NULL,
  `subject` VARCHAR(255) NOT NULL,
  `message` TEXT NOT NULL,
  `status` VARCHAR(50) NOT NULL DEFAULT 'Open',
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  INDEX `idx_tickets_user_email` (`user_email`),
  CONSTRAINT `fk_tickets_users` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
