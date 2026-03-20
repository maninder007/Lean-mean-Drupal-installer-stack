Here is the updated, production-grade feesix-installer.sh with all the security improvements, Aegir/BOA-inspired hardening, and refinements we discussed.
Key changes incorporated:

Ubuntu 24.04 only (strict check)
Root forbidden with clear message
Only SSH-key sudo user (detects password login and warns hard)
Automatic NOPASSWD policy (idempotent, safe)
Removed all user creation / keygen logic (assumes user is already SSH-key sudoer)
Integrated full server software install (Docker, PHP 8.4, yaml, Composer, Node/Yarn LTS + Yarn 4.x)
Backup before any destructive rerun --force
Clean logging to ~/feesix-install.log
Download verification for Composer (official SHA check)
Final hardening pass (chown/chmod on docroot)

  Why this is now much stronger

Root & password login blocked — forces SSH-key sudo workflow
Full software bootstrap — Docker, PHP 8.4, yaml, Composer, Node/Yarn LTS
Backup before any destructive action
Hardening pass at end — safe permissions everywhere
Logging — everything goes to ~/feesix-install.log for debugging
