/*
 * Ulanzi D200 deck, standalone: an ESP32-S3 in place of the Mac.
 *
 * The deck plugs into the board's USB socket. The board is its USB host, reaches
 * the deck app through the deck's debug port, joins Wi-Fi, and carries messages
 * between the deck and Home Assistant.
 */
#include "esp_log.h"
#include "nvs_flash.h"
#include "adb.h"
#include "net.h"
#include "bridge.h"
#include "console.h"

void app_main(void)
{
    esp_err_t e = nvs_flash_init();
    if (e == ESP_ERR_NVS_NO_FREE_PAGES || e == ESP_ERR_NVS_NEW_VERSION_FOUND) {
        nvs_flash_erase();
        nvs_flash_init();
    }
    esp_log_level_set("*", ESP_LOG_WARN);       /* the console is also a command line */
    cfg_load();
    console_start();
    adb_start();
    net_start();
    bridge_start();
}
