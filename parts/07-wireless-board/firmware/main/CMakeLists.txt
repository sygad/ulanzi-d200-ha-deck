idf_component_register(SRCS "main.c" "adb.c" "say.c" "net.c" "bridge.c" "console.c" "setup.c"
                    INCLUDE_DIRS "."
                    PRIV_REQUIRES usb esp_driver_uart esp_driver_gpio vfs esp_wifi esp_netif esp_event nvs_flash
                                  esp_http_server esp_http_client json mbedtls esp_timer app_update espcoredump
                    EMBED_FILES "deck/deckd" "deck/default-layout.bin")
