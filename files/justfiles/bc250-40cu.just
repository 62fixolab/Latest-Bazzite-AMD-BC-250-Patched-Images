# BC-250 40CU helper commands.

bc250-cu-status:
    @sudo bc250-cu-live-manager status

bc250-cu-menu:
    @sudo bc250-cu-live-manager menu

bc250-cu-dry-run-40:
    @sudo bc250-cu-live-manager --dry-run enable all

bc250-cu-enable-40:
    @sudo bc250-cu-live-manager enable all

bc250-cu-save-boot:
    @sudo bc250-cu-live-manager write-service-table
    @sudo test -f /etc/bc250-cu-live-manager.conf || (echo "No saved 40CU boot table found; run ujust bc250-cu-menu or ujust bc250-cu-enable-40 first." >&2; exit 1)
    @sudo bc250-cu-live-manager install-service

bc250-cu-restore-24:
    @sudo bc250-cu-live-manager stock-dispatch

bc250-cu-disable-boot:
    @sudo bc250-cu-live-manager uninstall-service

bc250-cu-sweet-spot:
    @sudo bc250-governor-profile sweet-spot

bc250-cu-governor-restore:
    @sudo bc250-governor-profile restore
