import Toybox.ActivityMonitor;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.WatchUi;

class ora_watchfaceView extends WatchUi.WatchFace {

    private var _background as BitmapResource;
    private var _headerLogo as BitmapResource;
    private var _mascotIdle as BitmapResource;
    private var _timePanel as BitmapResource;
    private var _datePanel as BitmapResource;
    private var _stepsPanel as BitmapResource;
    private var _recoveryPanel as BitmapResource;
    private var _statusPanel as BitmapResource;
    private var _jerseyTime as FontResource;
    private var _jerseySteps as FontResource;
    private var _jerseyRecovery as FontResource;
    private var _jerseyBattery as FontResource;
    private var _jerseyDate as FontResource;

    function initialize() {
        WatchFace.initialize();
        _background = WatchUi.loadResource(Rez.Drawables.Background) as BitmapResource;
        _headerLogo = WatchUi.loadResource(Rez.Drawables.HeaderLogoLayout) as BitmapResource;
        _mascotIdle = WatchUi.loadResource(Rez.Drawables.MascotIdleLayout) as BitmapResource;
        _timePanel = WatchUi.loadResource(Rez.Drawables.TimePanel) as BitmapResource;
        _datePanel = WatchUi.loadResource(Rez.Drawables.DatePanel) as BitmapResource;
        _stepsPanel = WatchUi.loadResource(Rez.Drawables.StepsPanelLayout) as BitmapResource;
        _recoveryPanel = WatchUi.loadResource(Rez.Drawables.RecoveryPanelLayout) as BitmapResource;
        _statusPanel = WatchUi.loadResource(Rez.Drawables.StatusPanelLayout) as BitmapResource;
        _jerseyTime = WatchUi.loadResource(Rez.Fonts.JerseyTime) as FontResource;
        _jerseySteps = WatchUi.loadResource(Rez.Fonts.JerseySteps) as FontResource;
        _jerseyRecovery = WatchUi.loadResource(Rez.Fonts.JerseyRecovery) as FontResource;
        _jerseyBattery = WatchUi.loadResource(Rez.Fonts.JerseyBattery) as FontResource;
        _jerseyDate = WatchUi.loadResource(Rez.Fonts.JerseyDate) as FontResource;
    }

    function onLayout(dc as Dc) as Void {
    }

    // Called when this View is brought to the foreground. Restore
    // the state of this View and prepare it to be shown. This includes
    // loading resources into memory.
    function onShow() as Void {
    }

    function onUpdate(dc as Dc) as Void {
        var clockTime = System.getClockTime();
        var timeString = Lang.format("$1$:$2$", [clockTime.hour.format("%02d"), clockTime.min.format("%02d")]);

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        // Pixel-art composition, aligned to the 360x360 FR265S safe circle.
        dc.drawBitmap(0, -6, _background);
        dc.drawBitmap(64, 14, _headerLogo);
        dc.drawBitmap(30, 78, _timePanel);
        dc.drawBitmap(107, 185, _mascotIdle);
        dc.drawBitmap(272, 180, _stepsPanel);
        dc.drawBitmap(27, 182, _recoveryPanel);
        dc.drawBitmap(87, 149, _datePanel);
        dc.drawBitmap(49, 281, _statusPanel);

        drawOutlinedText(dc, 186, 78, _jerseyTime, timeString, Graphics.COLOR_WHITE, 0);
        drawOutlinedText(dc, 184, 166, _jerseyDate, getDateString(), Graphics.COLOR_WHITE, 0);
        drawOutlinedText(dc, 310, 245, _jerseySteps, getStepsString(), Graphics.COLOR_WHITE, 0);
        drawOutlinedText(dc, 64, 251, _jerseyRecovery, getRecoveryString(), Graphics.COLOR_WHITE, 0);
        drawOutlinedText(dc, 112, 295, _jerseyBattery, getHeartRateString(), Graphics.COLOR_WHITE, 0);
        drawOutlinedText(dc, 195, 295, _jerseyBattery, getBatteryString(), Graphics.COLOR_WHITE, 0);
        drawOutlinedText(dc, 269, 295, _jerseyBattery, getCaloriesString(), Graphics.COLOR_WHITE, 0);
    }

    private function drawOutlinedText(dc as Dc, x as Numeric, y as Numeric, font as FontType, text as String, color as ColorType, outlineWidth as Number) as Void {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x - outlineWidth, y, font, text, Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(x + outlineWidth, y, font, text, Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(x, y - outlineWidth, font, text, Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(x, y + outlineWidth, font, text, Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y, font, text, Graphics.TEXT_JUSTIFY_CENTER);
    }

    private function getDateString() as String {
        var info = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
        var days = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"];
        var months = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"];
        return Lang.format("$1$ $2$ $3$", [days[info.day_of_week], info.day.format("%02d"), months[info.month - 1]]);
    }

    private function getStepsString() as String {
        var info = ActivityMonitor.getInfo();
        if ((info has :steps) && (info.steps != null)) {
            return info.steps.toString();
        }
        return "--";
    }

    private function getRecoveryString() as String {
        var info = ActivityMonitor.getInfo();
        if ((info has :timeToRecovery) && (info.timeToRecovery != null)) {
            var hours = (info.timeToRecovery / 3600.0).toNumber();
            return hours.toString() + " H";
        }
        return "-- H";
    }

    private function getHeartRateString() as String {
        var info = ActivityMonitor.getInfo();
        if ((info has :currentHeartRate) && (info.currentHeartRate != null) && (info.currentHeartRate != ActivityMonitor.INVALID_HR_SAMPLE)) {
            return info.currentHeartRate.toNumber().toString();
        }

        // On some watch-face updates currentHeartRate is null even though the
        // device has a recent wrist-HR sample. Read that latest valid sample.
        var history = ActivityMonitor.getHeartRateHistory(null, true);
        var sample = history.next();
        if ((sample != null) && (sample.heartRate != null) && (sample.heartRate != ActivityMonitor.INVALID_HR_SAMPLE)) {
            return sample.heartRate.toNumber().toString();
        }
        return "--";
    }

    private function getBatteryString() as String {
        var percent = (System.getSystemStats().battery + 0.5).toNumber();
        return percent.toString() + "%";
    }

    private function getCaloriesString() as String {
        var info = ActivityMonitor.getInfo();
        if ((info has :calories) && (info.calories != null)) {
            return info.calories.toNumber().toString();
        }
        return "--";
    }

    private function getDistanceString() as String {
        var info = ActivityMonitor.getInfo();
        if ((info has :distance) && (info.distance != null)) {
            return (info.distance / 1000.0).format("%.2f") + " KM";
        }
        return "-- KM";
    }

    // Called when this View is removed from the screen. Save the
    // state of this View here. This includes freeing resources from
    // memory.
    function onHide() as Void {
    }

    // The user has just looked at their watch. Timers and animations may be started here.
    function onExitSleep() as Void {
    }

    // Terminate any active timers and prepare for slow updates.
    function onEnterSleep() as Void {
    }

}
