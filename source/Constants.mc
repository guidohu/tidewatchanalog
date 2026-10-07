import Toybox.Lang;

(:background)
module ConstantsBG {
    const SECONDS_IN_HOUR = 3600;
    const DATA_UPDATE_INTERVAL_SEC = 300; // 5 minutes
    const FAST_SYNC_FRESHNESS_THRESHOLD_SEC = 1800; // 30 minutes
    const SLOW_SYNC_FRESHNESS_THRESHOLD_SEC = 21600; // 6 hours
    const ASTRONOMY_FRESHNESS_THRESHOLD_SEC = 43200; // 12 hours
    // Background tasks get either a 32KB or a 64KB budget depending on the device.
    // getSystemStats().totalMemory reports the heap left after the code is loaded, so
    // a 64KB device never reports the full 65536; gate on anything above the 32KB tier.
    const ASTRONOMY_MIN_BACKGROUND_MEMORY_BYTES = 32768; // 32KB, exclusive
}

module Constants {
    const SECONDS_IN_HOUR = ConstantsBG.SECONDS_IN_HOUR;
    const DATA_UPDATE_INTERVAL_SEC = ConstantsBG.DATA_UPDATE_INTERVAL_SEC;
    const FAST_SYNC_FRESHNESS_THRESHOLD_SEC = ConstantsBG.FAST_SYNC_FRESHNESS_THRESHOLD_SEC;
    const SLOW_SYNC_FRESHNESS_THRESHOLD_SEC = ConstantsBG.SLOW_SYNC_FRESHNESS_THRESHOLD_SEC;
    const ASTRONOMY_FRESHNESS_THRESHOLD_SEC = ConstantsBG.ASTRONOMY_FRESHNESS_THRESHOLD_SEC;
    const ASTRONOMY_MIN_BACKGROUND_MEMORY_BYTES = ConstantsBG.ASTRONOMY_MIN_BACKGROUND_MEMORY_BYTES;
}
