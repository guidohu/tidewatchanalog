import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.WatchUi;
using KPayClock.KPay as KPay;

var kpay as KPay.Core?;

class TideWatchView extends WatchUi.WatchFace {

    var mLastGpsLat;
    var mLastGpsLon;
    var mLastDatum;
    var mLastApiKey;

    // Cached configuration properties
    var mCachedTideUnits as Number = 0;
    var mCachedSwellUnits as Number = 1;
    var mCachedTideColorIdx as Number = 10;
    var mCachedGraphColorIdx as Number = 10;
    var mCachedBaseColorIdx as Number = 4;
    var mCachedHandColorIdx as Number = 4;
    var mCachedSecondHandColorIdx as Number = 2;
    var mCachedShowSwellGraph as Boolean = false;
    var mCachedShowSwellSummary as Boolean = false;
    var mCachedShowDate as Boolean = true;
    var mCachedShowMoonAndSun as Boolean = true;
    var mCachedTimeFormatVal as Number = 0;

    const METERS_TO_FEET = 3.28084;
    const STALE_DATA_THRESHOLD_SEC = 43200; // 12 hours
    const ERROR_DISPLAY_WINDOW_SEC = 300;   // 5 minutes
    const GRAPH_PAST_HOURS = 2;
    const GRAPH_FUTURE_HOURS = 16;
    const SCREEN_WIDTH_REFERENCE = 416.0;

    // Shape the cached tide/wave payloads are stored in. Versioned separately from
    // Version.STRING so bumping the app version never drops the cache; bump it only
    // when a release actually changes the layout of what is written to storage.
    const STORAGE_LAYOUT_VERSION = "2.2.0";

    // Vertical anchors of the dial layout, as a signed fraction of the dial radius
    // measured from the dial center (see dialY). Anchoring to the dial rather than to
    // the screen height keeps every row clear of the ticks on tall or square screens.
    // The location and swell summary sit in the upper half. The tide graph starts below
    // the day/date and battery blocks, with the next extreme and then the tide height
    // stacked underneath it, the last just clear of the 6 o'clock tick.
    const LAYOUT_LOCATION_R = -0.74;
    const LAYOUT_SWELL_R = -0.56;
    const LAYOUT_GRAPH_BASE_R = 0.52;
    const LAYOUT_GRAPH_HEIGHT_R = 0.42;
    const LAYOUT_EXTREMA_R = 0.60;
    const LAYOUT_TIDE_HEIGHT_R = 0.77;
    const LAYOUT_MESSAGE_R = 0.35;

    // Moon phase indicator: a small circle sitting just right of the battery at the
    // 9 o'clock position, sized to the battery icon's height. Only drawn on devices
    // with enough background memory to have synced astronomy data in the first place.
    const MOON_CIRCLE_RADIUS_PX = 6;
    const MOON_BATTERY_GAP_PX = 6;

    // Dial ring: ticks live between these radii. The day/date block is right-justified
    // just inside the 3 o'clock tick and the battery is left-justified opposite it,
    // just inside the 9 o'clock tick.
    const DIAL_TICK_OUTER_R = 0.97;
    const DIAL_TICK_MINOR_INNER_R = 0.92;
    const DIAL_TICK_MAJOR_INNER_R = 0.88;
    const DIAL_DAY_DATE_R = 0.80;
    const DIAL_BATTERY_R = 0.80;

    // Brightness of the secondary rows (location, day/date, battery, tide unit)
    // relative to the base color, so the tide height, curve and hands carry the glance.
    const SECONDARY_DIM = 0.60;

    // Extra hand length on top of the radius-relative base length, in reference pixels.
    const HAND_EXTENSION_PX = 5;
    const SECOND_HAND_EXTENSION_PX = 10;

    var mLastLazyDataUpdate as Number = 0;
    var mLastSettingsHash as Number = 0;
    var mLastDataUpdatedAt as Number = 0;
    var mLastSyncAttemptAt as Number = 0;

    var mCachedGraphBitmap as Graphics.BufferedBitmap? = null;
    var mLastGraphUpdateMinute as Number = -1;
    var mLastPowerMode as Boolean = false;
    var mLastGraphHash as Number = 0;

    // Tracks when the (expensive) graph min/max bounds were last recomputed. The
    // bounds are only consumed when the graph bitmap is (re)rendered, so they are
    // refreshed on the same 10-minute bucket / data-hash cadence rather than on
    // every one-minute update. See updateCacheAndCalculations.
    var mLastBoundsBucket as Number = -1;
    var mLastBoundsHash as Number = 0;

    var mBattery as Float = 0.0;

    var mCurrentHeight as Float = 0.0;
    var mNextExtremaStr as String? = null;
    var mDispUnit as String = "";
    var mTideNumStr as String = "";

    var mValidSwells as Array = [];
    var mSwellTexts as Array = [];

    var mMinH as Float = 9999.0;
    var mMaxH as Float = -9999.0;
    var mMinSwellH as Float = 9999.0;
    var mMaxSwellH as Float = -9999.0;
    var mMinT as Number = 0;
    var mMaxT as Number = 0;

    var mcTideData as Array<Array<Number>>? = null;

    var mcTideExtrema as Array<Array<Number>>? = null;
    var mcAstronomyData as Array<Array<Number>>? = null;
    var mcWaveData as Array<Array<Number?>>? = null;
    var mcTideUnitApi as Number? = null;
    var mcSwellUnitApi as Number? = null;
    var mcSpotName as String? = null;
    var mSyncError as Number? = null;
    var mErrorAt as Number? = null;
    var mWeatherError as Number? = null;

    var mScreenWidth as Number = 0;
    var mScreenHeight as Number = 0;
    var mScale as Float = 1.0;

    // Analog dial geometry, derived from the screen size in onLayout.
    var mCenterX as Float = 0.0;
    var mCenterY as Float = 0.0;
    var mDialRadius as Float = 0.0;
    var mFontAssistantSmall as Graphics.FontDefinition? = null;
    var mInLowPowerMode as Boolean = false;
    // Tracks the sleep state itself. mInLowPowerMode only follows it when the device
    // dims its always-on screen, but the second hand has to be hidden whenever the
    // watch face stops receiving per-second updates.
    var mIsSleeping as Boolean = false;
    var mDisableAlwaysOnScreen as Boolean = false;
    var mBatteryFont as Graphics.FontDefinition? = null;
    var mDayDateFont as Graphics.FontDefinition? = null;
    var mCurrentTideFont as Graphics.FontDefinition? = null;
    var mTideExtremeFont as Graphics.FontDefinition? = null;
    var mGraphLabelFont as Graphics.FontDefinition? = null;
    var mLocationFont as Graphics.FontDefinition? = null;

    /**
     * Constructor. Calls parent WatchFace constructor.
     */
    function initialize() {
        WatchFace.initialize();

        foregroundAppDelegate = self;

        getOrCreateAnonymousIdentifier();
        migrateSettings();

        var forecastWindow = Application.loadResource(Rez.Strings.ForecastWindow) as String;
        var forecastWindowSec = 48 * 3600;
        var forecastStartOffsetSec = 4 * 3600;
        if (forecastWindow.equals("short") || forecastWindow.equals("small")) {
            forecastWindowSec = 12 * 3600;
            forecastStartOffsetSec = 4 * 3600;
        }
        AppStorage.setForecastWindowSec(forecastWindowSec);
        AppStorage.setForecastStartOffsetSec(forecastStartOffsetSec);

        var disableAlwaysOnScreenVal = Application.loadResource(Rez.Strings.DisableAlwaysOnScreen) as String;
        mDisableAlwaysOnScreen = disableAlwaysOnScreenVal.equals("true");

        var location = readLocation();
        mLastGpsLat = location[0];
        mLastGpsLon = location[1];
        AppStorage.setTargetLocation(mLastGpsLat, mLastGpsLon);
        mLastDatum = Application.Properties.getValue("TideDatum");
        var apiKeyVal = Application.Properties.getValue("StormglassApiKey");
        mLastApiKey = (apiKeyVal instanceof String) ? apiKeyVal as String : "";

        cacheProperties();
        initializeKPay(true);
    }

    /**
     * Reads all required properties and caches them to avoid performance hits on update.
     */
    function cacheProperties() as Void {
        mCachedTideUnits = Application.Properties.getValue("TideUnits") as Number;
        mCachedSwellUnits = Application.Properties.getValue("SwellUnits") as Number;
        mCachedTideColorIdx = Application.Properties.getValue("TideColor") as Number;
        mCachedGraphColorIdx = Application.Properties.getValue("GraphColor") as Number;
        mCachedBaseColorIdx = Application.Properties.getValue("BaseColor") as Number;
        mCachedHandColorIdx = Application.Properties.getValue("HandColor") as Number;
        mCachedSecondHandColorIdx = Application.Properties.getValue("SecondHandColor") as Number;
        mCachedShowSwellGraph = Application.Properties.getValue("ShowSwellGraph") as Boolean;
        mCachedShowSwellSummary = Application.Properties.getValue("ShowSwellSummary") as Boolean;
        mCachedShowDate = Application.Properties.getValue("ShowDate") as Boolean;
        mCachedShowMoonAndSun = Application.Properties.getValue("ShowMoonAndSun") as Boolean;
        mCachedTimeFormatVal = Application.Properties.getValue("TimeFormat") as Number;
    }

    /**
     * Terminate hourly/periodic updates when entering low power sleep mode.
     */
    function onEnterSleep() as Void {
        mIsSleeping = true;
        if (!mDisableAlwaysOnScreen) {
            mInLowPowerMode = true;
        }
        WatchUi.requestUpdate();
    }

    /**
     * Restore standard rendering updates when leaving low power sleep mode.
     */
    function onExitSleep() as Void {
        mIsSleeping = false;
        mInLowPowerMode = false;
        WatchUi.requestUpdate();
    }

    /**
     * Resolves a custom Assistant font from a string resource configuration.
     * @param resourceId The symbol of the string resource defining the font name.
     * @return The loaded custom font, or null if the setting evaluates to an unsupported value.
     */
    function getFontFromResource(resourceId as Lang.ResourceId) as Graphics.FontDefinition? {
        var fontVal = WatchUi.loadResource(resourceId) as String;
        if (fontVal.equals("Inter_50px")) {
            return WatchUi.loadResource(Rez.Fonts.Inter_50px) as Graphics.FontDefinition;
        } else if (fontVal.equals("Inter_45px")) {
            return WatchUi.loadResource(Rez.Fonts.Inter_45px) as Graphics.FontDefinition;
        } else if (fontVal.equals("Inter_40px")) {
            return WatchUi.loadResource(Rez.Fonts.Inter_40px) as Graphics.FontDefinition;
        } else if (fontVal.equals("Inter_30px")) {
            return WatchUi.loadResource(Rez.Fonts.Inter_30px) as Graphics.FontDefinition;
        } else if (fontVal.equals("Inter_20px")) {
            return WatchUi.loadResource(Rez.Fonts.Inter_20px) as Graphics.FontDefinition;
        } else if (fontVal.equals("Inter_15px")) {
            return WatchUi.loadResource(Rez.Fonts.Inter_15px) as Graphics.FontDefinition;
        } else if (fontVal.equals("Inter_12px")) {
            return WatchUi.loadResource(Rez.Fonts.Inter_12px) as Graphics.FontDefinition;
        } else if (fontVal.equals("Inter_10px")) {
            return WatchUi.loadResource(Rez.Fonts.Inter_10px) as Graphics.FontDefinition;
        } else if (fontVal.equals("AssistantSmall")) {
            return WatchUi.loadResource(Rez.Fonts.AssistantSmall) as Graphics.FontDefinition;
        }
        return null;
    }

    /**
     * Lifecycle method called when the layout of the watch face needs to be loaded.
     * Pre-calculates and caches device screen boundaries and dynamic scaling ratios.
     * @param dc The device context representing the watch screen.
     */
    function onLayout(dc as Dc) as Void {
        mScreenWidth = dc.getWidth();
        mScreenHeight = dc.getHeight();
        mScale = mScreenWidth.toFloat() / SCREEN_WIDTH_REFERENCE;
        mCenterX = mScreenWidth / 2.0;
        mCenterY = mScreenHeight / 2.0;
        mDialRadius = (mScreenWidth < mScreenHeight ? mScreenWidth : mScreenHeight) / 2.0;
        mFontAssistantSmall = WatchUi.loadResource(Rez.Fonts.AssistantSmall) as Graphics.FontDefinition;
        mBatteryFont = getFontFromResource(Rez.Strings.battery_font);
        mDayDateFont = getFontFromResource(Rez.Strings.day_date_font);
        mCurrentTideFont = getFontFromResource(Rez.Strings.current_tide_font);
        mTideExtremeFont = getFontFromResource(Rez.Strings.tide_extreme_font);
        mGraphLabelFont = getFontFromResource(Rez.Strings.graph_label_font);
        mLocationFont = getFontFromResource(Rez.Strings.location_font);
    }

    /**
     * Main rendering hook called on watch face update cycles.
     * Manages KiezelPay dialog displays, triggers data state updates, and routes rendering commands
     * to modular drawing sub-routines (dial ticks, face content and the analog hands).
     * @param dc The device context.
     */
    function onUpdate(dc as Dc) as Void {
        // Payment Dialog / Licensing Check
        if (kpay != null) {
            var kpayInstance = kpay as KPayClock.KPay.Core;
            if (!kpayInstance.isLicensed()) {
                if (kpayInstance.shouldShowDialog()) {
                    kpayInstance.drawDialog(dc);
                    return;
                }
            }
        }
        dc.setPenWidth(1);

        // Actual App
        var now = Time.now().value();
        var targetTideUnit = (mCachedTideUnits == DataKeys.SETTING_UNIT_FEET) ? DataKeys.UNIT_FEET : DataKeys.UNIT_METER;
        var targetSwellUnit = (mCachedSwellUnits == DataKeys.SETTING_UNIT_FEET) ? DataKeys.UNIT_FEET : DataKeys.UNIT_METER;
        var use24Hour = mCachedTimeFormatVal == DataKeys.TIME_FORMAT_24_H;

        // Fallback size setup in case onLayout wasn't triggered
        if (mScreenWidth == 0) {
            onLayout(dc);
        }

        updateCacheAndCalculations(now, targetTideUnit, targetSwellUnit, use24Hour);

        var tideColor = getColorFromIndex(mCachedTideColorIdx);
        var graphColor = getColorFromIndex(mCachedGraphColorIdx);
        var baseColor = getColorFromIndex(mCachedBaseColorIdx);

        if (mInLowPowerMode) {
            tideColor = blendWithBlack(tideColor, 0.95);
            graphColor = blendWithBlack(graphColor, 0.95);
            baseColor = blendWithBlack(baseColor, 0.85);
        }

        var handColor = getColorFromIndex(mCachedHandColorIdx);
        var secondColor = getColorFromIndex(mCachedSecondHandColorIdx);
        if (mInLowPowerMode) {
            handColor = blendWithBlack(handColor, 0.80);
        }

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        if (!mInLowPowerMode) {
            drawTicks(dc, baseColor);
        }
        drawFaceContent(dc, tideColor, graphColor, baseColor, use24Hour, now);

        // The hands go on last so they stay readable on top of the graph and the
        // tide readout, the way an analog dial reads.
        drawHands(dc, handColor, secondColor);
    }

    /**
     * Renders everything on the dial except the ticks and the hands: location,
     * tide graph, day/date, tide readout and battery. Bails out early with a status
     * message when there is no location configured or no tide data yet.
     * @param dc The device context.
     * @param tideColor Color of the tide height readout.
     * @param graphColor Color of the tide graph.
     * @param baseColor Color of the base text.
     * @param use24Hour True when times are formatted in 24-hour style.
     * @param now Current epoch timestamp.
     */
    function drawFaceContent(dc as Dc, tideColor as Number, graphColor as Number, baseColor as Number, use24Hour as Boolean, now as Number) as Void {
        // Error Check
        // The API key and GPS coordinates only change via onSettingsChanged, which
        // refreshes these cached members. Reading from the cache avoids three
        // Application.Properties lookups on every one-minute update. (StormglassApiKey
        // can be null or a non-String when the user clears the field in Connect IQ,
        // but mLastApiKey is always normalized to a String.)
        var hasApiKey = (mLastApiKey != null && !(mLastApiKey as String).equals(""));

        var gpsLat = mLastGpsLat as Application.Properties.ValueType;
        var gpsLon = mLastGpsLon as Application.Properties.ValueType;

        if (!LocationUtils.isLocationSetAndValid(gpsLat, gpsLon)) {
             drawDialInfo(dc, baseColor, now);

             var msg = WatchUi.loadResource(Rez.Strings.NoSpotSelected) as String;
             if (mLastDataUpdatedAt > 0) {
                 msg += "\nLast sync: ";
                 var info = Gregorian.info(new Time.Moment(mLastDataUpdatedAt), Time.FORMAT_SHORT);
                 var hourAmPm = formatHourAmPm(info.hour, use24Hour, false);
                 msg += hourAmPm[0].format(use24Hour ? "%02d" : "%d") + ":" + info.min.format("%02d") + hourAmPm[1];
             }
             drawCenteredText(dc, dialY(LAYOUT_MESSAGE_R), Graphics.FONT_XTINY, msg, baseColor);
             return;
        }

        if (mcTideData == null) {
            drawDialInfo(dc, baseColor, now);

            var msg = "Waiting for sync...\nFirst sync can take\nup to 15 minutes.";
            if (mSyncError != null) {
                if (mSyncError == DataKeys.ERROR_QUOTA_EXCEEDED) {
                    msg = "API Limit Reached";
                } else if (mSyncError == DataKeys.ERROR_NO_DATA) {
                    msg = "no tide data available";
                } else if (mSyncError <= DataKeys.ERROR_PHONE_CONN_MAX && mSyncError > DataKeys.ERROR_PHONE_CONN_MIN) {
                    msg = "no connection";
                } else {
                    msg = "sync error";
                }
            }
            var errColor = mSyncError != null ? Graphics.COLOR_RED : Graphics.COLOR_LT_GRAY;
            if (mInLowPowerMode) {
                errColor = blendWithBlack(errColor, 0.95);
            }
            drawCenteredText(dc, dialY(LAYOUT_MESSAGE_R), Graphics.FONT_XTINY, msg, errColor);
            return;
        }

        // Swell Section
        if (mCachedShowSwellSummary && !mInLowPowerMode) {
            drawSwellData(dc, baseColor, hasApiKey);
        }

        // Graph Section
        drawGraphs(dc, graphColor, baseColor, mCachedShowSwellGraph, now);

        // Battery and day/date flank the dial center, where the top of the graph
        // reaches, so they are drawn once the graph is down.
        drawDialInfo(dc, baseColor, now);

        // Next Extrema (drawn between the graph and the tide height)
        if (mNextExtremaStr != null && !mInLowPowerMode) {
            var nextExtrema = mNextExtremaStr as String;
            drawCenteredText(dc, dialY(LAYOUT_EXTREMA_R), getSecondaryFont(), nextExtrema, baseColor);
        }

        // Tide height at the bottom of the dial
        drawTideChangeText(dc, tideColor, baseColor, dialY(LAYOUT_TIDE_HEIGHT_R));

        // Spot Name or Error
        var isStale = (now - mLastDataUpdatedAt > STALE_DATA_THRESHOLD_SEC);
        if (isStale && System.getDeviceSettings().phoneConnected && mSyncError != DataKeys.ERROR_QUOTA_EXCEEDED) {
            if (now - mLastSyncAttemptAt > 300) {
                mLastSyncAttemptAt = now;
                scheduleNextBackgroundEvent(null);
            }
        }

        if (!mInLowPowerMode) {
            drawLocation(dc, baseColor, now);
        }
    }

    /**
     * Draws the two blocks flanking the dial center: the day/date at 3 o'clock and the
     * battery opposite it at 9 o'clock.
     * @param dc The device context.
     * @param baseColor Numeric color code for standard drawing.
     * @param now Current epoch timestamp.
     */
    function drawDialInfo(dc as Dc, baseColor as Number, now as Number) as Void {
        if (mCachedShowDate || mInLowPowerMode) {
            drawDayDate(dc, baseColor);
        }
        if (!mInLowPowerMode) {
            var batteryRightX = drawBattery(dc, baseColor);
            if (mCachedShowMoonAndSun) {
                drawMoonPhase(dc, baseColor, now, batteryRightX);
            }
        }
    }

    /**
     * Lazy updates storage values, extracts wave/tide data array limits, and processes extrema heights.
     * Calculates graphs min/max bounds and current tide levels.
     * @param now Current epoch timestamp.
     * @param targetTideUnit Unit system for tides (feet vs meters).
     * @param targetSwellUnit Unit system for swells (feet vs meters).
     * @param use24Hour Boolean indicating whether to format hours in 24h style.
     */
    function updateCacheAndCalculations(now as Number, targetTideUnit as Number, targetSwellUnit as Number, use24Hour as Boolean) as Void {
        var currentHash = mCachedTideUnits +
            (mCachedSwellUnits << 2) +
            (mCachedTideColorIdx << 4) +
            (mCachedGraphColorIdx << 8) +
            (mCachedBaseColorIdx << 12) +
            ((mCachedShowSwellGraph == true ? 1 : 0) << 16) +
            ((mCachedShowSwellSummary == true ? 1 : 0) << 17) +
            ((mCachedShowDate == true ? 1 : 0) << 18) +
            ((use24Hour == true ? 1 : 0) << 19);

        var dataUpdatedAt = AppStorage.getDataUpdatedAt();

        if (now - mLastLazyDataUpdate >= Constants.DATA_UPDATE_INTERVAL_SEC || currentHash != mLastSettingsHash || dataUpdatedAt != mLastDataUpdatedAt) {
            mLastLazyDataUpdate = now;
            mLastSettingsHash = currentHash;
            mLastDataUpdatedAt = dataUpdatedAt;

            mcTideData = AppStorage.getTideData();

            mcTideExtrema = AppStorage.getTideExtrema();
            mcAstronomyData = AppStorage.getAstronomyData();
            System.println("DEBUG-ASTRO view loaded astronomy data: " + mcAstronomyData);
            mcWaveData = AppStorage.getWaveData();
            mcTideUnitApi = AppStorage.getTideUnitApi();
            mcSwellUnitApi = AppStorage.getSwellUnitApi();
            mcSpotName = AppStorage.getSpotName();
            mSyncError = AppStorage.getSyncError();
            mErrorAt = AppStorage.getErrorAt();
            mWeatherError = AppStorage.getWeatherError();
        }

        // Battery is only rendered outside low-power mode (see the drawBattery call in
        // onUpdate), so skip the getSystemStats() call entirely while in the
        // always-on/sleep state. mBattery simply retains its last value there.
        if (!mInLowPowerMode) {
            var stats = System.getSystemStats();
            mBattery = stats.battery;
        }

        mCurrentHeight = 0.0;
        mNextExtremaStr = null;
        mValidSwells = [];
        mSwellTexts = [];
        mMinT = now - GRAPH_PAST_HOURS * Constants.SECONDS_IN_HOUR;
        mMaxT = now + GRAPH_FUTURE_HOURS * Constants.SECONDS_IN_HOUR;

        if (mcTideData != null && mcTideData.size() > 0) {
            var currWaveIdx = findCurrentTideState(now, targetTideUnit);
            findNextExtrema(now, targetTideUnit, use24Hour);

            // mValidSwells/mSwellTexts are consumed only by drawSwellData, which runs
            // exclusively when the swell summary is enabled and we're not in low-power
            // mode. Skip the full wave-array scan otherwise.
            if (mCachedShowSwellSummary && !mInLowPowerMode) {
                findCurrentSwell(now, targetSwellUnit, currWaveIdx);
            }

            // Graph bounds are only used when the cached graph bitmap is (re)rendered,
            // which fires on the same 10-minute bucket / data-hash transitions used in
            // drawGraphs. Recompute them on those transitions instead of rescanning the
            // full tide+wave arrays on every one-minute update. The mMaxH <= mMinH guard
            // forces a recompute whenever the bounds are in the invalid sentinel state
            // (e.g. the first frame after tide data first arrives).
            var graphBucket = (now / 60) / 10;
            var boundsHash = mLastSettingsHash + mLastDataUpdatedAt;
            if (graphBucket != mLastBoundsBucket || boundsHash != mLastBoundsHash || mMaxH <= mMinH) {
                mMinH = 9999.0;
                mMaxH = -9999.0;
                mMinSwellH = 9999.0;
                mMaxSwellH = -9999.0;
                calculateGraphBounds();
                mLastBoundsBucket = graphBucket;
                mLastBoundsHash = boundsHash;
            }
        } else {
            // No tide data: keep the bounds in the "invalid" sentinel state so the graph
            // stays hidden (drawGraphs guards on mMaxH > mMinH), matching prior behavior.
            mMinH = 9999.0;
            mMaxH = -9999.0;
            mMinSwellH = 9999.0;
            mMaxSwellH = -9999.0;
        }
    }

    function findCurrentTideState(now as Number, targetTideUnit as Number) as Number {
        var found = false;
        var currWaveIdx = -1;
        var tDataArray = mcTideData as Array;
        for (var i = 0; i < tDataArray.size() - 1; i++) {
            var p1 = tDataArray[i] as Array;
            var p2 = tDataArray[i + 1] as Array;
            var t1 = p1[0] as Number;
            var t2 = p2[0] as Number;
            if (now >= t1 && now <= t2) {
                var h1 = convertHeight(p1[1] as Number, mcTideUnitApi, DataKeys.UNIT_METER);
                var h2 = convertHeight(p2[1] as Number, mcTideUnitApi, DataKeys.UNIT_METER);
                // Guard against duplicate/adjacent equal timestamps to avoid a divide-by-zero.
                var span = (t2 - t1).toFloat();
                var ratio = (span != 0.0) ? (now - t1).toFloat() / span : 0.0;
                mCurrentHeight = h1 + (h2 - h1) * ratio;
                currWaveIdx = i;
                found = true;
                break;
            }
        }
        if (!found) {
            var pFirst = tDataArray[0] as Array;
            var pLast = tDataArray[tDataArray.size() - 1] as Array;
            if (now < (pFirst[0] as Number)) {
                mCurrentHeight = convertHeight(pFirst[1] as Number, mcTideUnitApi, DataKeys.UNIT_METER);
                currWaveIdx = 0;
            } else {
                mCurrentHeight = convertHeight(pLast[1] as Number, mcTideUnitApi, DataKeys.UNIT_METER);
                currWaveIdx = tDataArray.size() - 1;
            }
        }

        var dispHeight = convertHeight((mCurrentHeight * 100).toNumber(), DataKeys.UNIT_METER, targetTideUnit);
        mDispUnit = (targetTideUnit == DataKeys.UNIT_FEET) ? "ft" : "m";
        mTideNumStr = (targetTideUnit == DataKeys.UNIT_FEET) ? dispHeight.format("%.1f") : dispHeight.format("%.2f");
        
        return currWaveIdx;
    }

    function findNextExtrema(now as Number, targetTideUnit as Number, use24Hour as Boolean) as Void {
        if (mcTideExtrema != null) {
            for (var i = 0; i < mcTideExtrema.size(); i++) {
                var ext = mcTideExtrema[i] as Array?;
                if (ext == null) {
                    System.println("invalid data for tide extrema");
                    break;
                }
                if (ext[0] > now) {
                    var extTs = ext[0] as Number;
                    var rawExtH = ext[1] as Number;
                    var typeCode = ext[2];
                    var extType = (typeCode == DataKeys.TIDE_TYPE_HIGH) ? "High" : "Low";
                    var extInfo = Gregorian.info(new Time.Moment(extTs.toNumber()), Time.FORMAT_SHORT);
                    var hourAmPm = formatHourAmPm(extInfo.hour, use24Hour, false);
                    var extTimeStr = Lang.format("$1$:$2$$3$", [hourAmPm[0].format(use24Hour ? "%02d" : "%d"), extInfo.min.format("%02d"), hourAmPm[1]]);
                    var dispExtH = convertHeight(rawExtH, mcTideUnitApi, targetTideUnit);
                    var formatStr = (targetTideUnit == DataKeys.UNIT_FEET) ? "%.1f" : "%.2f";
                    mNextExtremaStr = Lang.format("$1$: $2$$3$ $4$", [extType, dispExtH.format(formatStr), mDispUnit, extTimeStr]);
                    break;
                }
            }
        }
    }

    function findCurrentSwell(now as Number, targetSwellUnit as Number, currWaveIdx as Number) as Void {
        if (mcWaveData != null) {
            var waveDataArray = mcWaveData as Array;
            var currentWave = null;
            
            var minDiff = 9999999;
            for (var i = 0; i < waveDataArray.size(); i++) {
                var wPoint = waveDataArray[i];
                if (wPoint != null && wPoint instanceof Array && wPoint.size() > 6 && wPoint[6] != null) {
                    var wTs = wPoint[6] as Number;
                    var diff = now - wTs;
                    if (diff < 0) { diff = -diff; }
                    if (diff < minDiff) {
                        minDiff = diff;
                        currentWave = wPoint;
                    }
                }
            }
            
            if (currentWave == null && waveDataArray.size() > 0) {
                if (currWaveIdx >= 0 && currWaveIdx < waveDataArray.size()) {
                    currentWave = waveDataArray[currWaveIdx];
                } else {
                    var tDataArray = mcTideData as Array;
                    var firstTide = tDataArray[0] as Array;
                    if (firstTide.size() > 0 && now < (firstTide[0] as Number)) {
                        currentWave = waveDataArray[0];
                    } else {
                        currentWave = waveDataArray[waveDataArray.size() - 1];
                    }
                }
            }

            if (currentWave != null && currentWave instanceof Array && currentWave.size() >= 6) {
                for (var s = 0; s < 2; s++) {
                    var h = currentWave[s*3];
                    var hvRaw = 0;
                    if (h != null) {
                        hvRaw = (h instanceof Number) ? h as Number : (h as Float).toNumber();
                    }
                    var pVal = currentWave[s*3+1];
                    var pValNum = 0;
                    if (pVal != null) {
                        pValNum = (pVal instanceof Number) ? pVal as Number : (pVal as Float).toNumber();
                    }
                    var dVal = currentWave[s*3+2];
                    var dValFloat = 0.0;
                    if (dVal != null) {
                        dValFloat = (dVal instanceof Number) ? (dVal as Number).toFloat() : dVal as Float;
                    }
                    if (hvRaw > 0 && pValNum > 0) {
                        mValidSwells.add([hvRaw, pValNum, dValFloat]);
                        var dispH = convertHeight(hvRaw, mcSwellUnitApi, targetSwellUnit);
                        var unit = (targetSwellUnit == DataKeys.UNIT_FEET) ? "ft" : "m";
                        var sStr = dispH.format("%.1f") + unit + "@" + pValNum.toString();
                        mSwellTexts.add(sStr);
                    }
                }
            }
        }
    }

    function calculateGraphBounds() as Void {
        var tDataArray = mcTideData as Array;
        for (var i = 0; i < tDataArray.size(); i++) {
            var p = tDataArray[i] as Array;
            var tTs = p[0] as Number;
            if (tTs >= mMinT - Constants.SECONDS_IN_HOUR && tTs <= mMaxT + Constants.SECONDS_IN_HOUR) {
                var h = p[1];
                if (h != null) {
                    var hFloat = convertHeight(h as Number, mcTideUnitApi, DataKeys.UNIT_METER);
                    if (hFloat < mMinH) { mMinH = hFloat; }
                    if (hFloat > mMaxH) { mMaxH = hFloat; }
                }
            }
        }
        
        if (mMinH == 9999.0) { mMinH = 0.0; mMaxH = 1.0; }
        if (mMaxH == mMinH) { mMaxH = mMinH + 1.0; }
        
        if (mcWaveData != null) {
            var wDataArray = mcWaveData as Array;
            for (var i = 0; i < wDataArray.size(); i++) {
                var wPoint = wDataArray[i];
                if (wPoint != null && wPoint instanceof Array && wPoint.size() >= 6) {
                    var wTs = (wPoint.size() > 6 && wPoint[6] != null) ? wPoint[6] as Number : null;
                    if (wTs != null && wTs >= mMinT - Constants.SECONDS_IN_HOUR && wTs <= mMaxT + Constants.SECONDS_IN_HOUR) {
                        for (var s = 0; s < 2; s++) {
                            var hVal = wPoint[s*3];
                            var pVal = wPoint[s*3+1];
                            var hv = 0;
                            if (hVal != null) {
                                hv = (hVal instanceof Number) ? hVal as Number : (hVal as Float).toNumber();
                            }
                            var pv = 0;
                            if (pVal != null) {
                                pv = (pVal instanceof Number) ? pVal as Number : (pVal as Float).toNumber();
                            }
                            if (hv > 0 && pv > 0) {
                                var h = convertHeight(hv, mcSwellUnitApi, DataKeys.UNIT_METER);
                                if (h < mMinSwellH) { mMinSwellH = h; }
                                if (h > mMaxSwellH) { mMaxSwellH = h; }
                            }
                        }
                    }
                }
            }
        }
        if (mMinSwellH == 9999.0) { mMinSwellH = 0.0; mMaxSwellH = 1.0; }
        if (mMaxSwellH == mMinSwellH) { mMaxSwellH = mMinSwellH + 1.0; }
    }

    /**
     * Renders battery percentage number and status layout outline, left-justified at
     * the 9 o'clock tick so it mirrors the day/date block.
     * @param dc The device context.
     * @param baseColor Numeric color code for regular drawing.
     * @return The x coordinate of the right edge of the battery block.
     */
    function drawBattery(dc as Dc, baseColor as Number) as Number {
        var startX = (mCenterX - mDialRadius * DIAL_BATTERY_R).toNumber();
        var y = mCenterY.toNumber();
        var width = (24 * mScale).toNumber();
        var height = (12 * mScale).toNumber();
        var tipWidth = (2 * mScale).toNumber();
        var tipHeight = (6 * mScale).toNumber();
        var margin = (2 * mScale).toNumber();
        var fillWidth = ((width - margin * 2) * (mBattery / 100.0)).toNumber();
        if (fillWidth < 0) {
            fillWidth = 0;
        }

        var isLow = mBattery < 20.0;
        var color = dimmed(baseColor);
        if (mBattery < 10.0) {
            color = Graphics.COLOR_RED;
        } else if (isLow) {
            color = Graphics.COLOR_YELLOW;
        }

        dc.setColor(color, Graphics.COLOR_TRANSPARENT);

        // Draw battery outline. The icon is anchored at the tick so it never shifts.
        var iconY = y - height / 2;
        dc.drawRectangle(startX, iconY, width, height);
        dc.fillRectangle(startX + width, iconY + (height - tipHeight) / 2, tipWidth, tipHeight);

        // Fill battery level
        if (fillWidth > 0) {
            dc.fillRectangle(startX + margin, iconY + margin, fillWidth, height - margin * 2);
        }

        // The fill already conveys the level, so spell the number out only once it
        // drops into the warning range and the exact value starts to matter.
        var rightX = startX + width + tipWidth;
        if (isLow) {
            var font = mBatteryFont != null ? mBatteryFont : ((mFontAssistantSmall != null) ? mFontAssistantSmall : Graphics.FONT_XTINY);
            var percStr = mBattery.toNumber().toString() + "%";
            var textX = rightX + (4 * mScale).toNumber();
            dc.drawText(textX, y, font, percStr,
                        Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
            rightX = textX + dc.getTextWidthInPixels(percStr, font);
        }
        return rightX;
    }

    /**
     * Dims a color for the secondary rows so they sit behind the tide height, the
     * curve and the hands rather than competing with them.
     * @param color The base color to dim.
     * @return The dimmed color.
     */
    function dimmed(color as Number) as Number {
        return blendWithBlack(color, SECONDARY_DIM);
    }

    /**
     * The font shared by the small secondary rows: swell summary, next extreme and the
     * tide unit label. One step above the location font, one below the tide height.
     * @return The configured font, or the smallest system font as a fallback.
     */
    function getSecondaryFont() as Graphics.FontDefinition {
        return mTideExtremeFont != null ? mTideExtremeFont : Graphics.FONT_XTINY;
    }

    /**
     * Renders the dial ticks: one per five minutes, with the quarter hours
     * emphasized by a longer and thicker mark. Not drawn in always-on mode.
     * @param dc The device context.
     * @param baseColor Color of base text.
     */
    function drawTicks(dc as Dc, baseColor as Number) as Void {
        var majorColor = baseColor;
        var minorColor = blendWithBlack(baseColor, 0.60);

        var outer = mDialRadius * DIAL_TICK_OUTER_R;
        var minorInner = mDialRadius * DIAL_TICK_MINOR_INNER_R;
        var majorInner = mDialRadius * DIAL_TICK_MAJOR_INNER_R;
        var minorWidth = scaledPixels(2, 1);
        var majorWidth = scaledPixels(4, 2);

        for (var i = 0; i < 12; i++) {
            var angle = i * Math.PI / 6.0;
            var sin = Math.sin(angle);
            var cos = Math.cos(angle);
            var isMajor = (i % 3 == 0);
            var inner = isMajor ? majorInner : minorInner;

            dc.setPenWidth(isMajor ? majorWidth : minorWidth);
            dc.setColor(isMajor ? majorColor : minorColor, Graphics.COLOR_TRANSPARENT);
            dc.drawLine((mCenterX + outer * sin).toNumber(), (mCenterY - outer * cos).toNumber(),
                        (mCenterX + inner * sin).toNumber(), (mCenterY - inner * cos).toNumber());
        }
        dc.setPenWidth(1);
    }

    /**
     * Renders the hour, minute and second hands plus the center hub. The second hand
     * is skipped while asleep, when the watch face no longer receives per-second updates.
     * @param dc The device context.
     * @param handColor Color of the hour and minute hands.
     * @param secondColor Color of the second hand and hub.
     */
    function drawHands(dc as Dc, handColor as Number, secondColor as Number) as Void {
        var clockTime = System.getClockTime();
        var minuteFraction = (clockTime.min + clockTime.sec / 60.0) / 60.0;
        var hourAngle = ((clockTime.hour % 12) + minuteFraction) * Math.PI / 6.0;
        var minuteAngle = minuteFraction * 2.0 * Math.PI;

        drawHand(dc, hourAngle, mDialRadius * 0.50 + HAND_EXTENSION_PX * mScale, mDialRadius * 0.10, 5.5 * mScale, handColor);
        drawHand(dc, minuteAngle, mDialRadius * 0.76 + HAND_EXTENSION_PX * mScale, mDialRadius * 0.10, 4.0 * mScale, handColor);

        var hubColor = handColor;
        if (!mIsSleeping) {
            hubColor = secondColor;
            drawSecondHand(dc, clockTime.sec * Math.PI / 30.0, secondColor);
        }

        var hubRadius = scaledPixels(5, 2);
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(mCenterX.toNumber(), mCenterY.toNumber(), hubRadius + scaledPixels(2, 1));
        dc.setColor(hubColor, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(mCenterX.toNumber(), mCenterY.toNumber(), hubRadius);
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(mCenterX.toNumber(), mCenterY.toNumber(), scaledPixels(2, 1));
    }

    /**
     * Draws a single tapered hand with a black outline so it stays legible where it
     * crosses the tide graph.
     * @param dc The device context.
     * @param angle Hand angle in radians, clockwise from 12 o'clock.
     * @param length Distance from the center to the tip.
     * @param tail Distance the hand extends behind the center.
     * @param halfWidth Half of the hand width at its base.
     * @param color Fill color of the hand.
     */
    function drawHand(dc as Dc, angle as Float, length as Float, tail as Float, halfWidth as Float, color as Number) as Void {
        var outline = scaledPixels(2, 1).toFloat();

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon(getHandPoints(angle, length + outline, tail + outline, halfWidth + outline));
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon(getHandPoints(angle, length, tail, halfWidth));
    }

    /**
     * Draws the thin second hand with its counterweight.
     * @param dc The device context.
     * @param angle Hand angle in radians, clockwise from 12 o'clock.
     * @param color Color of the second hand.
     */
    function drawSecondHand(dc as Dc, angle as Float, color as Number) as Void {
        var sin = Math.sin(angle);
        var cos = Math.cos(angle);
        var length = mDialRadius * 0.86 + SECOND_HAND_EXTENSION_PX * mScale;
        var tipX = (mCenterX + length * sin).toNumber();
        var tipY = (mCenterY - length * cos).toNumber();
        var tailX = (mCenterX - mDialRadius * 0.20 * sin).toNumber();
        var tailY = (mCenterY + mDialRadius * 0.20 * cos).toNumber();

        var width = scaledPixels(3, 1);
        dc.setPenWidth(width + scaledPixels(2, 1));
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(tailX, tailY, tipX, tipY);

        dc.setPenWidth(width);
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(tailX, tailY, tipX, tipY);
        dc.setPenWidth(1);
    }

    /**
     * Builds the five corner points of a tapered hand, rotated around the dial center.
     * Local coordinates point towards 12 o'clock along -y and are rotated clockwise.
     * @param angle Hand angle in radians, clockwise from 12 o'clock.
     * @param length Distance from the center to the tip.
     * @param tail Distance the hand extends behind the center.
     * @param halfWidth Half of the hand width at its base.
     * @return Array of screen-space polygon points.
     */
    function getHandPoints(angle as Float, length as Float, tail as Float, halfWidth as Float) as Array<[Lang.Numeric, Lang.Numeric]> {
        var sin = Math.sin(angle);
        var cos = Math.cos(angle);
        var shoulder = -(length - halfWidth * 2.0);
        var local = [
            [-halfWidth, tail],
            [-halfWidth * 0.55, shoulder],
            [0.0, -length],
            [halfWidth * 0.55, shoulder],
            [halfWidth, tail]
        ];

        var points = new Array<[Lang.Numeric, Lang.Numeric]>[5];
        for (var i = 0; i < 5; i++) {
            var x = local[i][0] as Float;
            var y = local[i][1] as Float;
            points[i] = [(mCenterX + x * cos - y * sin).toNumber(), (mCenterY + x * sin + y * cos).toNumber()];
        }
        return points;
    }

    /**
     * Scales a reference pixel size to the current screen, never dropping below a
     * minimum so thin features stay visible on small displays.
     * @param reference Size in pixels at the reference screen width.
     * @param minimum Smallest acceptable result.
     * @return The scaled size in pixels.
     */
    function scaledPixels(reference as Lang.Numeric, minimum as Number) as Number {
        var value = (reference * mScale).toNumber();
        return value < minimum ? minimum : value;
    }

    /**
     * Renders the weekday abbreviation above the day of month, next to the 3 o'clock
     * position (e.g. "SUN" over "23").
     * @param dc The device context.
     * @param baseColor Numeric color code.
     */
    function drawDayDate(dc as Dc, baseColor as Number) as Void {
        var font = mDayDateFont != null ? mDayDateFont : Graphics.FONT_XTINY;
        var lineHeight = dc.getFontHeight(font);
        var x = (mCenterX + mDialRadius * DIAL_DAY_DATE_R).toNumber();
        var dayStr = getDay();
        var dateStr = getDate();

        dc.setColor(dimmed(baseColor), Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, (mCenterY - lineHeight / 2.0).toNumber(), font, dayStr,
                    Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.drawText(x, (mCenterY + lineHeight / 2.0).toNumber(), font, dateStr,
                    Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    /**
     * Renders current tide elevation value and rising/falling indicator arrow.
     * @param dc The device context.
     * @param tideColor Color for drawing tide numeric indicators.
     * @param baseColor Color used for the arrow, and for the value in always-on mode.
     * @param yVal Vertical center of the readout.
     */
    function drawTideChangeText(dc as Dc, tideColor as Number, baseColor as Number, yVal as Float) as Void {
        var tideFont = mCurrentTideFont != null ? mCurrentTideFont : Graphics.FONT_SMALL;
        var unitFont = getSecondaryFont();
        var numWidth = dc.getTextWidthInPixels(mTideNumStr, tideFont);
        var mWidth = dc.getTextWidthInPixels(mDispUnit, unitFont);

        var startX = (mScreenWidth - (numWidth + mWidth)) / 2;

        // The curve's slope at the now marker already shows whether the tide is
        // rising, so the value carries no arrow of its own.
        dc.setColor(mInLowPowerMode ? baseColor : tideColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(startX, yVal, tideFont, mTideNumStr, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.setColor(dimmed(baseColor), Graphics.COLOR_TRANSPARENT);
        dc.drawText(startX + numWidth, yVal, unitFont, mDispUnit, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    /**
     * Renders current swell data summaries (primary & secondary height, periods, directions).
     * @param dc The device context.
     * @param baseColor Default color of text.
     * @param hasApiKey True if a Stormglass API key is supplied.
     */
    function drawSwellData(dc as Dc, baseColor as Number, hasApiKey as Boolean) as Void {
        var swellY = dialY(LAYOUT_SWELL_R);
        var font = getSecondaryFont();
        if (!hasApiKey) {
            drawCenteredText(dc, swellY, font, "no stormglass.io key", baseColor);
        } else if (mWeatherError == DataKeys.ERROR_INVALID_KEY) {
            drawCenteredText(dc, swellY, font, "stormglass key invalid", Graphics.COLOR_RED);
        } else if (mWeatherError == DataKeys.ERROR_QUOTA_EXCEEDED) {
            drawCenteredText(dc, swellY, font, "swell API limit reached", Graphics.COLOR_RED);
        } else if (mWeatherError == DataKeys.ERROR_OTHER) {
            drawCenteredText(dc, swellY, font, "swell sync error", Graphics.COLOR_RED);
        } else if (mValidSwells.size() > 0) {
            var totalSwellW = 0;
            var arrowW = (10 * mScale).toNumber();
            var pad = (3 * mScale).toNumber();
            var sepW = dc.getTextWidthInPixels(" | ", font);
            for (var i = 0; i < mValidSwells.size(); i++) {
                totalSwellW += arrowW + pad + dc.getTextWidthInPixels(mSwellTexts[i] as String, font);
            }
            totalSwellW += (mValidSwells.size() - 1) * sepW;

            var curX = (mScreenWidth - totalSwellW) / 2;
            var curY = swellY.toNumber();
            for (var i = 0; i < mValidSwells.size(); i++) {
                var sv = mValidSwells[i] as Array;
                drawSwellArrow(dc, (curX + arrowW/2).toNumber(), curY, sv[2] as Float);
                curX += arrowW + pad;
                dc.setColor(baseColor, Graphics.COLOR_TRANSPARENT);
                dc.drawText(curX, curY, font, mSwellTexts[i] as String, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
                curX += dc.getTextWidthInPixels(mSwellTexts[i] as String, font);
                if (i < mValidSwells.size() - 1) {
                    dc.setColor(baseColor, Graphics.COLOR_TRANSPARENT);
                    dc.drawText(curX, curY, font, " | ", Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
                    curX += sepW;
                }
            }
        } else {
            drawCenteredText(dc, swellY, font, "no swell data available", baseColor);
        }
    }

    /**
     * Draws a small moon icon showing the lit part of the disc the way it appears in
     * the sky: in the northern hemisphere a waxing moon is lit from the right and a
     * waning moon keeps its left side lit; the southern hemisphere is mirrored. The
     * terminator is an ellipse whose half-width is r * cos(2 * PI * phase). Picks the
     * stored astronomy day whose timestamp is closest to now, and no-ops if no
     * astronomy data has been synced (e.g. on a device below the background memory
     * budget for this feature).
     * @param dc The device context.
     * @param baseColor Numeric color code for standard drawing.
     * @param now Current epoch timestamp.
     * @param leftX The x coordinate the indicator is placed to the right of (the
     *              battery block's right edge).
     */
    function drawMoonPhase(dc as Dc, baseColor as Number, now as Number, leftX as Number) as Void {
        if (mcAstronomyData == null || mcAstronomyData.size() == 0) {
            return;
        }

        var closest = null;
        var closestDelta = 999999999;
        for (var i = 0; i < mcAstronomyData.size(); i++) {
            var row = mcAstronomyData[i] as Array;
            var delta = (row[0] as Number) - now;
            if (delta < 0) {
                delta = -delta;
            }
            if (delta < closestDelta) {
                closestDelta = delta;
                closest = row;
            }
        }
        if (closest == null) {
            return;
        }

        var mpScaled = closest[3] as Number;
        var phase = mpScaled / 10000.0;
        var terminator = Math.cos(2.0 * Math.PI * phase);
        var waxing = phase < 0.5;
        var mirror = (mLastGpsLat != null && (mLastGpsLat as Float) < 0.0);

        var r = (MOON_CIRCLE_RADIUS_PX * mScale).toNumber();
        if (r < 4) {
            r = 4;
        }
        var cx = leftX + (MOON_BATTERY_GAP_PX * mScale).toNumber() + r;
        var cy = mCenterY.toNumber();
        var color = dimmed(baseColor);

        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawCircle(cx, cy, r);

        // Fill the lit part row by row, between the terminator and the lit limb.
        for (var dy = -r; dy <= r; dy++) {
            var w = Math.sqrt(r * r - dy * dy);
            var x0, x1;
            if (waxing) {
                x0 = w * terminator;
                x1 = w;
            } else {
                x0 = -w;
                x1 = -w * terminator;
            }
            if (mirror) {
                var t = x0;
                x0 = -x1;
                x1 = -t;
            }
            if (x1 - x0 >= 0.5) {
                dc.drawLine(cx + Math.round(x0).toNumber(), cy + dy, cx + Math.round(x1).toNumber() + 1, cy + dy);
            }
        }
    }

    /**
     * Draws the main tide elevation curve and optionally overlays swell metrics.
     * Places a red dot representing current time on the timeline grid.
     * @param dc The device context.
     * @param graphColor Color of tide line graph.
     * @param baseColor Color of swell layers and helper layouts.
     * @param showSwellGraph True if the swell graph layer is active.
     * @param now Current epoch timestamp.
     */
    function drawGraphs(dc as Dc, graphColor as Number, baseColor as Number, showSwellGraph as Boolean, now as Number) as Void {
        if (mMaxH > mMinH) {
            var graphY = dialY(LAYOUT_GRAPH_BASE_R);
            var graphHeight = mDialRadius * LAYOUT_GRAPH_HEIGHT_R;
            var graphMargin = 0.0;
            var drawWidth = mScreenWidth;
            
            var currentMinute = (now / 60) / 10;
            var currentHash = mLastSettingsHash + mLastDataUpdatedAt;
            var needsRedraw = false;
            
            if (mCachedGraphBitmap == null) {
                needsRedraw = true;
            } else if (currentMinute != mLastGraphUpdateMinute) {
                needsRedraw = true;
            } else if (mInLowPowerMode != mLastPowerMode) {
                needsRedraw = true;
            } else if (currentHash != mLastGraphHash) {
                needsRedraw = true;
            }

            var bitmapY = (graphY - graphHeight - 30 * mScale).toNumber();
            if (bitmapY < 0) { bitmapY = 0; }
            var bitmapHeight = (graphHeight + 60 * mScale).toNumber();
            if (bitmapY + bitmapHeight > mScreenHeight) {
                bitmapHeight = mScreenHeight - bitmapY;
            }

            if (needsRedraw) {
                mLastGraphUpdateMinute = currentMinute;
                mLastPowerMode = mInLowPowerMode;
                mLastGraphHash = currentHash;

                if (mCachedGraphBitmap == null && Graphics has :createBufferedBitmap) {
                    try {
                        var bitmapRef = Graphics.createBufferedBitmap({
                            :width => mScreenWidth,
                            :height => bitmapHeight
                        });
                        mCachedGraphBitmap = bitmapRef.get() as Graphics.BufferedBitmap;
                    } catch (e) {
                        mCachedGraphBitmap = null;
                    }
                }

                var targetDc = dc;
                var drawYOffset = 0;
                if (mCachedGraphBitmap != null) {
                    targetDc = mCachedGraphBitmap.getDc();
                    targetDc.setColor(Graphics.COLOR_TRANSPARENT, Graphics.COLOR_TRANSPARENT);
                    targetDc.clear();
                    drawYOffset = bitmapY;
                }
                
                // Shift graphY by drawYOffset so all dependent drawing coordinates are shifted appropriately into the bitmap space
                graphY = graphY - drawYOffset;

            // Tide Graph
            targetDc.setColor(graphColor, Graphics.COLOR_TRANSPARENT);
            var lastX = -1, lastY = -1;
            if (mcTideData != null) {
                var tDataArray = mcTideData as Array;
                for (var i = 0; i < tDataArray.size(); i++) {
                    var p = tDataArray[i] as Array;
                    var tTs = p[0] as Number;
                    var x = graphMargin + drawWidth * (tTs - mMinT).toFloat() / (mMaxT - mMinT).toFloat();
                    var hVal = p[1];
                    if (hVal != null) {
                        var hFloat = convertHeight(hVal as Number, mcTideUnitApi, DataKeys.UNIT_METER);
                        var y = graphY - graphHeight * (hFloat - mMinH) / (mMaxH - mMinH);
                        if (lastX >= 0 && (x >= -50 && x <= mScreenWidth + 50)) {
                            // Draw shade under the line (fades from solid to transparent towards the bottom)
                            if (!mInLowPowerMode) {
                                var N = 12;
                                for (var j = 0; j < N; j++) {
                                    var fraction = j.toFloat() / (N - 1).toFloat();
                                    var ratio = 0.05 + 0.60 * (1.0 - fraction * fraction);
                                    var shadeColor = blendWithBlack(graphColor, ratio);
                                    
                                    var ly1 = lastY + (graphY - lastY) * j.toFloat() / N.toFloat();
                                    var ly2 = lastY + (graphY - lastY) * (j + 1).toFloat() / N.toFloat();
                                    var ry1 = y + (graphY - y) * j.toFloat() / N.toFloat();
                                    var ry2 = y + (graphY - y) * (j + 1).toFloat() / N.toFloat();
                                    
                                    targetDc.setColor(shadeColor, Graphics.COLOR_TRANSPARENT);
                                    targetDc.fillPolygon([
                                        [lastX, ly1.toNumber()],
                                        [x.toNumber(), ry1.toNumber()],
                                        [x.toNumber(), ry2.toNumber()],
                                        [lastX, ly2.toNumber()]
                                    ] as Array<[Lang.Numeric, Lang.Numeric]>);
                                }
                            }

                            // Draw the actual line on top
                            targetDc.setColor(graphColor, Graphics.COLOR_TRANSPARENT);
                            targetDc.drawLine(lastX, lastY, x.toNumber(), y.toNumber());
                            targetDc.drawLine(lastX, lastY+1, x.toNumber(), y.toNumber()+1);
                        }
                        lastX = x.toNumber(); lastY = y.toNumber();
                    } else {
                        lastX = -1; // Gap in data
                    }
                }
            }

            // Swell Graph
            if (!mInLowPowerMode && showSwellGraph && mcWaveData != null) {
                var colors = [baseColor, baseColor, baseColor];
                for (var s = 0; s < 2; s++) {
                    var lastSX = -1, lastSY = -1;
                    var waveDataArray = mcWaveData as Array;
                    for (var i = 0; i < waveDataArray.size(); i++) {
                        var wPoint = waveDataArray[i];
                        if (wPoint == null || !(wPoint instanceof Array) || wPoint.size() < 6) { 
                            lastSX = -1; 
                            continue; 
                        }
                        var hVal = wPoint[s*3];
                        var pVal = wPoint[s*3+1];
                        var hv = 0;
                        if (hVal != null) {
                            hv = (hVal instanceof Number) ? hVal as Number : (hVal as Float).toNumber();
                        }
                        var pv = 0;
                        if (pVal != null) {
                            pv = (pVal instanceof Number) ? pVal as Number : (pVal as Float).toNumber();
                        }
                        
                        if (hv <= 0 || pv <= 0) { 
                            lastSX = -1; 
                            continue; 
                        }
                        
                        var wTs = (wPoint.size() > 6 && wPoint[6] != null) ? wPoint[6] as Number : null;
                        if (wTs != null) {
                            var h = convertHeight(hv, mcSwellUnitApi, DataKeys.UNIT_METER);
                            var sx = graphMargin + drawWidth * (wTs - mMinT).toFloat() / (mMaxT - mMinT).toFloat();
                            var sy = graphY - graphHeight * (h - mMinSwellH) / (mMaxSwellH - mMinSwellH);
                            if (lastSX >= 0 && (sx >= -50 && sx <= mScreenWidth + 50)) {
                                targetDc.setColor(colors[s], Graphics.COLOR_TRANSPARENT);
                                targetDc.drawLine(lastSX, lastSY, sx.toNumber(), sy.toNumber());
                                if (s == 0) { targetDc.drawLine(lastSX, lastSY+1, sx.toNumber(), sy.toNumber()+1); targetDc.drawLine(lastSX, lastSY-1, sx.toNumber(), sy.toNumber()-1); }
                            }
                            lastSX = sx.toNumber(); lastSY = sy.toNumber();
                        } else {
                            lastSX = -1;
                        }
                    }
                }
            }

            if (!mInLowPowerMode) {
                // Grid Lines (either meters or feet depending on settings)
                var tideUnits = mCachedTideUnits;
                var isFeet = (tideUnits == DataKeys.SETTING_UNIT_FEET);
                var factor = isFeet ? METERS_TO_FEET : 1.0;
                var minDisp = mMinH * factor;
                var maxDisp = mMaxH * factor;
                
                var gridStep = isFeet ? 1.0 : 0.5;
                var candidates;
                if (isFeet) {
                    candidates = [1.0, 2.0, 3.0, 4.0, 5.0, 8.0, 10.0, 15.0, 20.0, 25.0, 50.0] as Array<Float>;
                } else {
                    candidates = [0.5, 1.0, 1.5, 2.0, 2.5, 3.0, 4.0, 5.0, 10.0, 20.0] as Array<Float>;
                }
                
                for (var idx = 0; idx < candidates.size(); idx++) {
                    var stepVal = candidates[idx];
                    var startGrid = (Math.ceil(minDisp / stepVal) * stepVal).toFloat();
                    var labelCount = 0;
                    for (var val = startGrid; val < maxDisp; val += stepVal) {
                        labelCount++;
                    }
                    if (labelCount <= 3) {
                        gridStep = stepVal;
                        break;
                    }
                }
                
                var startGrid = (Math.ceil(minDisp / gridStep) * gridStep).toFloat();
                var unitStr = isFeet ? "ft" : "m";
                var gridLabels = [];
                
                for (var val = startGrid; val < maxDisp; val += gridStep) {
                    var hMeter = val / factor;
                    var gy = graphY - graphHeight * (hMeter - mMinH) / (mMaxH - mMinH);
                    
                    targetDc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
                    var dashLen = (4 * mScale).toNumber();
                    var gapLen = (4 * mScale).toNumber();
                    if (dashLen < 2) { dashLen = 2; }
                    if (gapLen < 2) { gapLen = 2; }
                    for (var gx = 0; gx < mScreenWidth; gx += dashLen + gapLen) {
                        var endX = gx + dashLen;
                        if (endX > mScreenWidth) { endX = mScreenWidth; }
                        targetDc.drawLine(gx, gy.toNumber(), endX, gy.toNumber());
                    }
                    
                    var formatStr = (gridStep.toFloat() - gridStep.toNumber().toFloat()) > 0.01 ? "%.1f" : "%.0f";
                    var labelText = val.format(formatStr) + unitStr;
                    gridLabels.add([gy.toNumber(), labelText]);
                }

                // Draw vertical line where the date is changing (midnight)
                var info = Gregorian.info(new Time.Moment(now), Time.FORMAT_SHORT);
                var todayMidnight = Gregorian.moment({
                    :year => info.year,
                    :month => info.month,
                    :day => info.day,
                    :hour => 0,
                    :minute => 0,
                    :second => 0
                }).value();
                
                var dateChangeTs = null;
                if (todayMidnight >= mMinT && todayMidnight <= mMaxT) {
                    dateChangeTs = todayMidnight;
                } else if (todayMidnight + 86400 >= mMinT && todayMidnight + 86400 <= mMaxT) {
                    dateChangeTs = todayMidnight + 86400;
                } else if (todayMidnight - 86400 >= mMinT && todayMidnight - 86400 <= mMaxT) {
                    dateChangeTs = todayMidnight - 86400;
                }
                
                if (dateChangeTs != null) {
                    var cx = graphMargin + drawWidth * (dateChangeTs - mMinT).toFloat() / (mMaxT - mMinT).toFloat();
                    targetDc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
                    var dashLen = (4 * mScale).toNumber();
                    var gapLen = (4 * mScale).toNumber();
                    if (dashLen < 2) { dashLen = 2; }
                    if (gapLen < 2) { gapLen = 2; }
                    var startY = graphY - graphHeight;
                    for (var gy = startY; gy < graphY; gy += dashLen + gapLen) {
                        var endY = gy + dashLen;
                        if (endY > graphY) { endY = graphY; }
                        targetDc.drawLine(cx.toNumber(), gy.toNumber(), cx.toNumber(), endY.toNumber());
                    }
                }

                // Draw sunrise/sunset markers (only populated on devices with enough
                // background memory to have synced astronomy data). A 48h graph window
                // can span two calendar days, so every stored day's sunrise/sunset that
                // falls inside the visible window gets its own marker.
                if (mCachedShowMoonAndSun && mcAstronomyData != null) {
                    var use24HourMarker = (mCachedTimeFormatVal == DataKeys.TIME_FORMAT_24_H);
                    for (var astroIdx = 0; astroIdx < mcAstronomyData.size(); astroIdx++) {
                        var astroRow = mcAstronomyData[astroIdx] as Array;
                        var sunriseTs = astroRow[1] as Number;
                        var sunsetTs = astroRow[2] as Number;
                        if (sunriseTs >= mMinT && sunriseTs <= mMaxT) {
                            drawGraphTimeMarker(targetDc, graphMargin, drawWidth, graphY, graphHeight, drawYOffset, sunriseTs, Graphics.COLOR_LT_GRAY, use24HourMarker);
                        }
                        if (sunsetTs >= mMinT && sunsetTs <= mMaxT) {
                            drawGraphTimeMarker(targetDc, graphMargin, drawWidth, graphY, graphHeight, drawYOffset, sunsetTs, Graphics.COLOR_LT_GRAY, use24HourMarker);
                        }
                    }
                }

                // Draw grid labels on the right side of the watch face on top of everything.
                // The top of the band reaches into the day/date block, which is drawn over
                // the graph afterwards, so drop any label that would end up behind it.
                targetDc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
                var font = mGraphLabelFont != null ? mGraphLabelFont : ((mFontAssistantSmall != null) ? mFontAssistantSmall : Graphics.FONT_XTINY);
                var infoBottom = 0.0;
                if (mCachedShowDate || mInLowPowerMode) {
                    var dayDateFont = mDayDateFont != null ? mDayDateFont : Graphics.FONT_XTINY;
                    infoBottom = mCenterY + targetDc.getFontHeight(dayDateFont);
                }
                for (var i = 0; i < gridLabels.size(); i++) {
                    var item = gridLabels[i] as Array;
                    var gy = item[0] as Number;
                    if (gy + drawYOffset < infoBottom) {
                        continue;
                    }
                    var labelText = item[1] as String;
                    targetDc.drawText(getRightEdgeX(gy + drawYOffset), gy, font, labelText, Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER);
                }
            }

            // Current Time Marker (using dynamic 'now' so marker moves!)
            var nowX = graphMargin + drawWidth * (now - mMinT).toFloat() / (mMaxT - mMinT).toFloat();
            if (nowX >= 0 && nowX <= mScreenWidth) {
                var markerColor = mInLowPowerMode ? blendWithBlack(Graphics.COLOR_RED, 0.95) : Graphics.COLOR_RED;
                targetDc.setColor(markerColor, Graphics.COLOR_TRANSPARENT);
                var markerY = graphY - graphHeight * (mCurrentHeight - mMinH) / (mMaxH - mMinH);
                targetDc.fillCircle(nowX.toNumber(), markerY.toNumber(), (6 * mScale).toNumber());
            }
            
            } // End of needsRedraw block

            // Finally, if we have a cached bitmap, draw it to the main dc
            if (mCachedGraphBitmap != null) {
                dc.drawBitmap(0, bitmapY, mCachedGraphBitmap);
            }
        }
    }

    /**
     * Draws a dashed vertical marker on the tide/swell graph at a given timestamp
     * (sunrise or sunset), with a small time label near the top of the dash. The
     * label is skipped (the dash is kept) when it would collide with the height-grid
     * labels on the right edge; reuses the same time-to-x mapping and dash/gap loop
     * as the midnight marker.
     * @param dc The device context (or buffered bitmap target).
     * @param graphMargin Left margin of the graph's drawable width.
     * @param drawWidth Drawable width of the graph.
     * @param graphY Y coordinate of the graph's baseline.
     * @param graphHeight Height of the graph band.
     * @param yOffset Screen y of the target's origin (non-zero when drawing into the
     *                cached graph bitmap), used to map back to screen space.
     * @param ts Epoch timestamp to mark.
     * @param color Numeric color code for the marker.
     * @param use24Hour True to format the label in 24-hour time.
     */
    function drawGraphTimeMarker(dc as Dc, graphMargin as Float, drawWidth as Number, graphY as Float, graphHeight as Float, yOffset as Number, ts as Number, color as Number, use24Hour as Boolean) as Void {
        var cx = graphMargin + drawWidth * (ts - mMinT).toFloat() / (mMaxT - mMinT).toFloat();
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        var dashLen = (4 * mScale).toNumber();
        var gapLen = (4 * mScale).toNumber();
        if (dashLen < 2) { dashLen = 2; }
        if (gapLen < 2) { gapLen = 2; }
        var startY = graphY - graphHeight;
        for (var gy = startY; gy < graphY; gy += dashLen + gapLen) {
            var endY = gy + dashLen;
            if (endY > graphY) { endY = graphY; }
            dc.drawLine(cx.toNumber(), gy.toNumber(), cx.toNumber(), endY.toNumber());
        }

        var info = Gregorian.info(new Time.Moment(ts), Time.FORMAT_SHORT);
        var hourAmPm = formatHourAmPm(info.hour, use24Hour, false);
        var label = hourAmPm[0].format(use24Hour ? "%02d" : "%d") + ":" + info.min.format("%02d") + hourAmPm[1];
        var font = mGraphLabelFont != null ? mGraphLabelFont : ((mFontAssistantSmall != null) ? mFontAssistantSmall : Graphics.FONT_XTINY);
        if (cx < getRightEdgeX(startY + yOffset) - (40 * mScale)) {
            dc.drawText(cx.toNumber(), startY.toNumber(), font, label, Graphics.TEXT_JUSTIFY_CENTER);
        }
    }

    /**
     * Renders the spot name or sync errors at the top of the display.
     * @param dc The device context.
     * @param baseColor Numeric color code for standard drawing.
     * @param now Current timestamp.
     */
    function drawLocation(dc as Dc, baseColor as Number, now as Number) as Void {
        var isStale = (now - mLastDataUpdatedAt > STALE_DATA_THRESHOLD_SEC);
        var showSyncError = (mSyncError != null && mErrorAt != null && (now - mErrorAt < ERROR_DISPLAY_WINDOW_SEC));

        var font = mLocationFont != null ? mLocationFont : ((mFontAssistantSmall != null) ? mFontAssistantSmall : Graphics.FONT_XTINY);
        if (showSyncError) {
            var errMsg = "sync error";
            var errColor = Graphics.COLOR_RED;
            if (mSyncError != null && mSyncError == DataKeys.ERROR_QUOTA_EXCEEDED) {
                errMsg = "API Limit Reached";
            } else if (mSyncError != null && mSyncError <= DataKeys.ERROR_PHONE_CONN_MAX && mSyncError > DataKeys.ERROR_PHONE_CONN_MIN) {
                errMsg = "no connection";
            }
            drawCenteredText(dc, dialY(LAYOUT_LOCATION_R), font, errMsg, errColor);
        } else if (mcSpotName != null) {
            var nameColor = dimmed(baseColor);
            if (isStale || mSyncError != null) {
                nameColor = Graphics.COLOR_YELLOW;
            }
            drawCenteredText(dc, dialY(LAYOUT_LOCATION_R), font, mcSpotName as String, nameColor);
        }
    }

    /**
     * Draws an arrow polygon pointing in the direction the swell is moving.
     * @param dc The device context.
     * @param x Center coordinate.
     * @param y Center coordinate.
     * @param direction Degree angle representing swell heading direction.
     */
    function drawSwellArrow(dc as Dc, x as Number, y as Number, direction as Float) as Void {
        var rad = (direction + 180.0) * Math.PI / 180.0;
        var cos = Math.cos(rad);
        var sin = Math.sin(rad);
        
        var xf = x.toFloat();
        var yf = y.toFloat();
        
        var px = 0.0; var py = -5.0 * mScale;
        var p0x = xf + px*cos - py*sin; var p0y = yf + px*sin + py*cos;
        px = -3.5 * mScale; py = 3.5 * mScale;
        var p1x = xf + px*cos - py*sin; var p1y = yf + px*sin + py*cos;
        px = 3.5 * mScale; py = 3.5 * mScale;
        var p2x = xf + px*cos - py*sin; var p2y = yf + px*sin + py*cos;
        
        var pts = [
            [p0x, p0y],
            [p1x, p1y],
            [p2x, p2y]
        ];
        dc.fillPolygon(pts as Array<[Lang.Numeric, Lang.Numeric]>);
    }

    /**
     * Converts a setting index to a Garmin Graphics COLOR_* constant or custom hex value.
     * @param idx The color property setting index.
     * @return Color hex integer.
     */
    function getColorFromIndex(idx as Number) as Number {
        if (idx == DataKeys.SETTING_COLOR_PINK) { return Graphics.COLOR_PINK; }
        if (idx == DataKeys.SETTING_COLOR_RED) { return Graphics.COLOR_RED; }
        if (idx == DataKeys.SETTING_COLOR_GREEN) { return Graphics.COLOR_GREEN; }
        if (idx == DataKeys.SETTING_COLOR_WHITE) { return Graphics.COLOR_WHITE; }
        if (idx == DataKeys.SETTING_COLOR_YELLOW) { return Graphics.COLOR_YELLOW; }
        if (idx == DataKeys.SETTING_COLOR_ORANGE) { return Graphics.COLOR_ORANGE; }
        if (idx == DataKeys.SETTING_COLOR_PURPLE) { return Graphics.COLOR_PURPLE; }
        if (idx == DataKeys.SETTING_COLOR_LT_GRAY) { return Graphics.COLOR_LT_GRAY; }
        if (idx == DataKeys.SETTING_COLOR_DK_GRAY) { return Graphics.COLOR_DK_GRAY; }
        if (idx == DataKeys.SETTING_COLOR_LIGHT_BLUE) { return 0x55AAFF; } // Light Blue
        if (idx == DataKeys.SETTING_COLOR_PETROL) { return 0x005F6B; } // Petrol
        if (idx == DataKeys.SETTING_COLOR_TURQUOISE) { return 0x00CCCC; } // Turquoise
        return Graphics.COLOR_BLUE; // Default/0
    }

    /**
     * Formats hours for AM/PM layout or 24-hour style format.
     * @param hour The hour value (0-23).
     * @param use24Hour True for 24h format; false for 12h format.
     * @param upperCase True to capitalize AM/PM suffix labels.
     * @return Array containing [hour_number, am_pm_suffix_string].
     */
    function formatHourAmPm(hour as Number, use24Hour as Boolean, upperCase as Boolean) as Array {
        var amPm = "";
        if (!use24Hour) {
            if (hour >= 12) {
                amPm = upperCase ? "PM" : "pm";
                if (hour > 12) { hour -= 12; }
            } else {
                amPm = upperCase ? "AM" : "am";
                if (hour == 0) { hour = 12; }
            }
        }
        return [hour, amPm];
    }

    /**
     * Resolves the current day of month (e.g. "23").
     * @return Formatted day-of-month string.
     */
    function getDate() as String {
        var today = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
        return today.day.format("%d");
    }

    /**
     * Resolves the abbreviated weekday in upper case (e.g. "SUN").
     * @return Active day-of-week string.
     */
    function getDay() as String {
        var todayMed = Gregorian.info(Time.now(), Time.FORMAT_MEDIUM);
        return (todayMed.day_of_week as String).toUpper();
    }

    /**
     * Resolves a screen-space y coordinate from a dial-relative layout anchor.
     * @param fraction Signed fraction of the dial radius, measured from the dial center.
     * @return The screen-space vertical coordinate.
     */
    function dialY(fraction as Float) as Float {
        return mCenterY + mDialRadius * fraction;
    }

    /**
     * Resolves the rightmost usable x coordinate for a given screen row, following the
     * circular screen edge so text near the top of the dial is not clipped away.
     * @param y Screen-space vertical coordinate of the row.
     * @return The x coordinate to right-justify against.
     */
    function getRightEdgeX(y as Lang.Numeric) as Number {
        var margin = 10 * mScale;
        var maxX = mScreenWidth - margin;
        var dy = y - mCenterY;
        var inside = mDialRadius * mDialRadius - dy * dy;
        if (inside <= 0.0) {
            return maxX.toNumber();
        }
        var edgeX = mCenterX + Math.sqrt(inside) - margin;
        return (edgeX < maxX ? edgeX : maxX).toNumber();
    }

    /**
     * Utility method to draw centered text layouts using custom fonts and colors.
     * @param dc The device context.
     * @param y Vertical center offset.
     * @param font The active Garmin font face.
     * @param text String label to draw.
     * @param color Graphics color to apply.
     */
    function drawCenteredText(dc as Dc, y as Lang.Numeric, font, text as String, color as Number) as Void {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(mScreenWidth / 2, y, font, text, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    /**
     * Converts a raw rawValue elevation between meter/feet metrics using calibration ratios.
     * @param rawValue The raw elevation value (multiplied by 100).
     * @param apiUnit Source API unit code.
     * @param targetUnit Output target unit code.
     * @return Correctly calibrated float value.
     */
    function convertHeight(rawValue as Number, apiUnit as Number?, targetUnit as Number) as Float {
        if (targetUnit != DataKeys.UNIT_METER && targetUnit != DataKeys.UNIT_FEET) {
            System.println("Invalid target unit: " + targetUnit);
        }
        var valFloat = rawValue.toFloat() / 100.0;
        if (apiUnit == null) { return valFloat; } // Assume already correct if unknown
        
        // API is Meters (18), Target is Feet (19)
        if (apiUnit == DataKeys.UNIT_METER && targetUnit == DataKeys.UNIT_FEET) {
            return valFloat * METERS_TO_FEET;
        }
        // API is Feet (19), Target is Meters (18)
        if (apiUnit == DataKeys.UNIT_FEET && targetUnit == DataKeys.UNIT_METER) {
            return valFloat / METERS_TO_FEET;
        }
        return valFloat;
    }

    /**
     * Blends a color with black to simulate opacity/transparency.
     * @param color The original 24-bit RGB color.
     * @param ratio The blending ratio (0.0 = completely black/transparent, 1.0 = original color).
     * @return The blended color integer.
     */
    function blendWithBlack(color as Number, ratio as Float) as Number {
        if (ratio <= 0.0) { return 0x000000; }
        if (ratio >= 1.0) { return color; }
        
        var rgb = getRgbFromColor(color);
        var r = (rgb[0] * ratio).toNumber();
        var g = (rgb[1] * ratio).toNumber();
        var b = (rgb[2] * ratio).toNumber();
        
        return (r << 16) | (g << 8) | b;
    }

    /**
     * Resolves standard Garmin system colors and custom hex colors to RGB components.
     */
    function getRgbFromColor(color as Number) as Array<Number> {
        switch (color) {
            case Graphics.COLOR_WHITE: return [255, 255, 255];
            case Graphics.COLOR_LT_GRAY: return [170, 170, 170];
            case Graphics.COLOR_DK_GRAY: return [85, 85, 85];
            case Graphics.COLOR_BLACK: return [0, 0, 0];
            case Graphics.COLOR_RED: return [255, 0, 0];
            case Graphics.COLOR_DK_RED: return [170, 0, 0];
            case Graphics.COLOR_ORANGE: return [255, 85, 0];
            case Graphics.COLOR_YELLOW: return [255, 255, 0];
            case Graphics.COLOR_GREEN: return [0, 255, 0];
            case Graphics.COLOR_DK_GREEN: return [0, 170, 0];
            case Graphics.COLOR_BLUE: return [0, 0, 255];
            case Graphics.COLOR_DK_BLUE: return [0, 0, 170];
            case Graphics.COLOR_PURPLE: return [170, 0, 255];
            case Graphics.COLOR_PINK: return [255, 0, 170];
            default:
                var r = (color >> 16) & 0xFF;
                var g = (color >> 8) & 0xFF;
                var b = color & 0xFF;
                return [r, g, b];
        }
    }

    /**
     * Lifecycle callback when the app stops.
     */
    function onStop(state as Dictionary?) as Void {
        if (kpay != null) {
            kpay.onStop();
        }
    }

    /**
     * Parses a generic coordinate value from an Object (e.g. String) to a Float.
     */
    function parseCoordinate(val as Object?, min as Float, max as Float) as Float {
        if (val instanceof String) {
            try {
                var f = val.toFloat();
                if (f != null && f >= min && f <= max) {
                    return f;
                }
            } catch (e) {
                System.println("Failed to parse coordinate: " + e.getErrorMessage());
            }
        }
        return 0.0;
    }

    function parseLatitude(val as Object?) as Float {
        return parseCoordinate(val, -90.0, 90.0);
    }

    function parseLongitude(val as Object?) as Float {
        return parseCoordinate(val, -180.0, 180.0);
    }

    /**
     * Reads the configured coordinates, mapping anything non-numeric or out of range to
     * 0.0. Both initialize and onSettingsChanged go through here so the cached copies
     * compare equal to the freshly read ones: a spurious difference would read as a
     * destination change and throw away the cached tide and swell data.
     * @return [latitude, longitude] as Floats.
     */
    function readLocation() as Array<Float> {
        var lat = LocationUtils.getAsFloat(Application.Properties.getValue("GpsLat"));
        var lon = LocationUtils.getAsFloat(Application.Properties.getValue("GpsLon"));
        if (!LocationUtils.isValidLatitude(lat)) {
            lat = 0.0;
        }
        if (!LocationUtils.isValidLongitude(lon)) {
            lon = 0.0;
        }
        return [lat, lon] as Array<Float>;
    }

    /**
     * Migrates settings stored as legacy Strings.
     */
    function migrateSettings() as Void {
        var gpsLat = Application.Properties.getValue("GpsLat");
        if (gpsLat instanceof String) {
            Application.Properties.setValue("GpsLat", parseLatitude(gpsLat));
            System.println("Migrated GpsLat from String to Float.");
        }
        
        var gpsLon = Application.Properties.getValue("GpsLon");
        if (gpsLon instanceof String) {
            Application.Properties.setValue("GpsLon", parseLongitude(gpsLon));
            System.println("Migrated GpsLon from String to Float.");
        }

        // The cached payloads are keyed to the storage layout, not to the app version.
        // Comparing the app version against the 2.2.0 layout marker matched on every
        // single start (this face restarted its versioning at 1.0.0), so the cache was
        // purged each time the watch face was relaunched - which is what happens
        // whenever another app is opened and left again.
        var lastLayout = AppStorage.getStorageLayout();
        var needsPurge = false;
        if (lastLayout == null) {
            // Installs from before the layout marker existed. Only the pre-2.2.0 keys
            // mark a payload this code cannot read; anything else is already in the
            // current shape and stays on screen.
            needsPurge = (Application.Storage.getValue("tideTimes") != null);
        } else {
            needsPurge = Version.isLowerThan(lastLayout, STORAGE_LAYOUT_VERSION);
        }

        if (needsPurge) {
            System.println("Migrating storage layout from " + (lastLayout == null ? "legacy" : lastLayout) + " to " + STORAGE_LAYOUT_VERSION);

            Application.Storage.deleteValue("tideTimes");
            Application.Storage.deleteValue("tideStartTime");
            Application.Storage.deleteValue("tideInterval");
            AppStorage.clearTideData();
            AppStorage.clearWaveData();
            AppStorage.setDataUpdatedAt(0);

            AppStorage.clearGeocodeUpdatedAt();
            AppStorage.clearWeatherUpdatedAt();
            AppStorage.clearTideTimelineUpdatedAt();
            AppStorage.clearTideExtremesUpdatedAt();
        }

        if (lastLayout == null || !lastLayout.equals(STORAGE_LAYOUT_VERSION)) {
            AppStorage.setStorageLayout(STORAGE_LAYOUT_VERSION);
        }

        var currentVersion = Version.STRING;
        var lastVersion = AppStorage.getAppVersion();
        if (lastVersion == null || !lastVersion.equals(currentVersion)) {
            AppStorage.setAppVersion(currentVersion);
        }
    }

    function getOrCreateAnonymousIdentifier() {
        return AppStorage.getOrCreateAnonymousUserId();
    }

    function logMemoryUsage() {
        var stats = System.getSystemStats();
        System.println("Memory: " + stats.usedMemory + " / " + stats.totalMemory);
    }

    /**
     * Instantiates or destroys the KiezelPay Core controller based on settings.
     * Once a purchase has been confirmed, the result is persisted to storage and
     * KiezelPay is never consulted again (see AppStorage.getIsPurchased): some users
     * saw isLicensed() flip back to false after a while and get re-prompted to pay
     * for an app they already own.
     */
    function initializeKPay(enableKPay as Boolean) as Boolean {
        var kpayChanged = false;
        if (enableKPay && !AppStorage.getIsPurchased()) {
            var kpayInstance = kpay;
            if (kpayInstance == null) {
                kpayInstance = new KPay.Core(getKPayConfig());
                kpay = kpayInstance;
                kpayChanged = true;
            }
            var isLicensed = kpayInstance.isLicensed();
            System.println("KiezelPay isLicensed: " + isLicensed);
            if (isLicensed) {
                AppStorage.setIsPurchased(true);
                kpay = null;
                kpayChanged = true;
            } else {
                kpayInstance.startPurchase();
            }
        } else {
            if (kpay != null) {
                kpay = null;
                kpayChanged = true;
            }
        }
        return kpayChanged;
    }

    /**
     * Handles user settings changes in the view.
     */
    function onSettingsChanged() {
        var rawLat = Application.Properties.getValue("GpsLat");
        var rawLon = Application.Properties.getValue("GpsLon");

        var location = readLocation();
        var gpsLat = location[0];
        var gpsLon = location[1];

        // Save sanitized float values back to properties if they were modified/migrated
        if (gpsLat != rawLat) {
            Application.Properties.setValue("GpsLat", gpsLat);
        }
        if (gpsLon != rawLon) {
            Application.Properties.setValue("GpsLon", gpsLon);
        }

        var kpayChanged = initializeKPay(true);

        var curDatum = Application.Properties.getValue("TideDatum");
        var apiKeyVal = Application.Properties.getValue("StormglassApiKey");
        var curApiKey = (apiKeyVal instanceof String) ? apiKeyVal as String : "";

        var needsSync = false;
        if (gpsLat != mLastGpsLat || gpsLon != mLastGpsLon || curDatum != mLastDatum || 
           (!curApiKey.equals(mLastApiKey)) || kpayChanged) {
            needsSync = true;
        }

        mLastGpsLat = gpsLat;
        mLastGpsLon = gpsLon;
        AppStorage.setTargetLocation(gpsLat, gpsLon);
        mLastDatum = curDatum;
        mLastApiKey = curApiKey;

        cacheProperties();

        if (needsSync) {
            TideWatchSettingsMenu.triggerImmediateSync(true);
        }
        
        WatchUi.requestUpdate();
    }

    /**
     * Handles background data in the view.
     */
    function onBackgroundData(data as Application.PersistableType) as Void {
        System.println("onBackgroundData called on View with data: " + (data == null ? "null" : data.toString()));
        logMemoryUsage();
        
        if (kpay != null && data instanceof Dictionary) {
            var kpayInstance = kpay as KPay.Core;
            kpayInstance.onBackgroundData(data as Dictionary);

            var event = data.get("kpay_event");
            if (event instanceof Dictionary) {
                var kpayStatus = event.get("status");
                System.println("KiezelPay background event status: " + kpayStatus);
            }
            var isLicensed = kpayInstance.isLicensed();
            System.println("KiezelPay isLicensed after sync: " + isLicensed);

            var response = (data as Dictionary)[kpayInstance.extraResponseKey];

            if (isLicensed) {
                // Purchase confirmed via background sync: persist it and drop the
                // KiezelPay instance so we stop calling it from here on.
                AppStorage.setIsPurchased(true);
                kpay = null;
            }

            if (response instanceof Boolean && response as Boolean) {
                AppStorage.setDataUpdatedAt(Time.now().value());
                WatchUi.requestUpdate();
            } else {
                // System.println("TideWatch Background service: kpay pass-through sync failed");
                logSyncError("kpay pass-through sync failed", AppStorage.getSyncError());
            }
        } else if (kpay == null && data instanceof Boolean) {
            if (data as Boolean) {
                AppStorage.setDataUpdatedAt(Time.now().value());
                WatchUi.requestUpdate();
            } else {
                // System.println("TideWatch Background service: sync failed");
                logSyncError("sync failed", AppStorage.getSyncError());
            }
        } else {
            // System.println("TideWatch Background service: unknown data format or failed sync");
            logSyncError("unknown data format or failed sync", AppStorage.getSyncError());
        }
        
        if (System has :ServiceDelegate) {
            var earliest = Time.now().add(new Time.Duration(Constants.DATA_UPDATE_INTERVAL_SEC));
            scheduleNextBackgroundEvent(earliest);
        }
    }

    /**
     * Translates a numeric background error code to a human-readable string and prints it.
     */
    function logSyncError(context as String, errorCode as Number?) as Void {
        var msg = "";
        if (errorCode == null) {
            msg = "unknown error";
        } else if (errorCode == DataKeys.ERROR_APP_ID_MISSING) {
            msg = "AppId missing from storage. Background sync aborted.";
        } else if (errorCode == DataKeys.ERROR_LOCATION_MISSING) {
            msg = "No Location Set or invalid range/type. Exit.";
        } else if (errorCode == DataKeys.ERROR_QUOTA_EXCEEDED) {
            msg = "API Quota Exceeded (402/429)!";
        } else if (errorCode == DataKeys.ERROR_NO_DATA) {
            msg = "no tide data available";
        } else if (errorCode == DataKeys.ERROR_INVALID_KEY) {
            msg = "API key is invalid";
        } else {
            msg = "error code " + errorCode;
        }
        System.println("TideWatch Background service: " + context + " (" + msg + ")");
    }

    /**
     * Retrieves the settings menu views and delegates.
     */
    function getSettingsView() {
        return [ new TideWatchSettingsMenu(), new TideWatchSettingsMenuDelegate() ] as [WatchUi.Views, WatchUi.InputDelegates];
    }
}

