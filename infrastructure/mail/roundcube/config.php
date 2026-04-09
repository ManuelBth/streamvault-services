<?php
/*
 * RoundCube Webmail Configuration
 * StreamVault Mail Server
 */

// ─────────────────────────────────────────────────────────
// Database Setup (using PostgreSQL)
// ─────────────────────────────────────────────────────────
$config['db_dsn'] = 'pgsql://' . getenv('POSTGRES_USER') . ':' . getenv('POSTGRES_PASSWORD') . '@postgres:5432/' . getenv('POSTGRES_DB');
$config['db_dsn'] = 'pgsql://streamvault:streamvault2025@postgres:5432/streamvault';

// ─────────────────────────────────────────────────────────
// IMAP Settings
// ─────────────────────────────────────────────────────────
$config['default_host'] = 'imap://dovecot';
$config['default_port'] = 143;
$config['imap_auth_type'] = 'PLAIN';

// ─────────────────────────────────────────────────────────
// SMTP Settings
// ─────────────────────────────────────────────────────────
$config['smtp_server'] = 'smtp://postfix';
$config['smtp_port'] = 25;
$config['smtp_auth_type'] = 'PLAIN';

// ─────────────────────────────────────────────────────────
// Default Settings
// ─────────────────────────────────────────────────────────
$config['default_domain'] = 'streamvault.com';
$config['mail_domain'] = 'streamvault.com';

$config['des_key'] = 'rcmail-!24-byte-des-key-00!';

// ─────────────────────────────────────────────────────────
// Display Settings
// ─────────────────────────────────────────────────────────
$config['language'] = 'es_ES';
$config['timezone'] = 'America/Bogota';
$config['date_format'] = 'Y-m-d H:i';
$config['time_format'] = 'H:i';
$config['datestamp'] = 'Y-m-d';

// ─────────────────────────────────────────────────────────
// Product Name
// ─────────────────────────────────────────────────────────
$config['product_name'] = 'StreamVault Mail';

// ─────────────────────────────────────────────────────────
// Skin
// ─────────────────────────────────────────────────────────
$config['skin'] = 'elastic';

// ─────────────────────────────────────────────────────────
// Plugins
// ─────────────────────────────────────────────────────────
$config['plugins'] = [];

// ─────────────────────────────────────────────────────────
// Debug
// ─────────────────────────────────────────────────────────
$config['imap_debug'] = false;
$config['smtp_debug'] = false;

// ─────────────────────────────────────────────────────────
// Session (use database for sessions)
// ─────────────────────────────────────────────────────────
$config['session_type'] = 'php';
$config['session_cache_limiter'] = 'nocache';

// ─────────────────────────────────────────────────────────
// Enable caching
// ─────────────────────────────────────────────────────────
$config['enable_caching'] = true;

// ─────────────────────────────────────────────────────────
// Default folders
// ─────────────────────────────────────────────────────────
$config['default_folders'] = ['INBOX', 'Sent', 'Drafts', 'Trash', 'Junk'];
$config['sent_mbox'] = 'Sent';
$config['drafts_mbox'] = 'Drafts';
$config['trash_mbox'] = 'Trash';
$config['junk_mbox'] = 'Junk';