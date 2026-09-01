import Toybox.ActivityMonitor;
import Toybox.Complications;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.WatchUi;

class ora_watchface_familyView extends WatchUi.WatchFace {

    private var _background as BitmapResource;
    private var _timePanel as BitmapResource;
    private var _heartRatePanel as BitmapResource;
    private var _stepsPanel as BitmapResource;
    private var _batteryPanel as BitmapResource;
    private var _jerseyTime as FontResource;
    private var _pressDate as FontResource;
    private var _jerseyStat as FontResource;
    private var _jerseySteps as FontResource;
    private var _jerseyBattery as FontResource;
    private var _heartRateComplicationId;
    private var _heartRateSubscribed as Boolean = false;

    function initialize() {
        WatchFace.initialize();
        _background = WatchUi.loadResource(Rez.Drawables.Background) as BitmapResource;
        _timePanel = WatchUi.loadResource(Rez.Drawables.TimePanel) as BitmapResource;
        _heartRatePanel = WatchUi.loadResource(Rez.Drawables.HeartRatePanel) as BitmapResource;
        _stepsPanel = WatchUi.loadResource(Rez.Drawables.StepsPanel) as BitmapResource;
        _batteryPanel = WatchUi.loadResource(Rez.Drawables.BatteryPanel) as BitmapResource;
        _jerseyTime = WatchUi.loadResource(Rez.Fonts.JerseyTime) as FontResource;
        _pressDate = WatchUi.loadResource(Rez.Fonts.PressDate) as FontResource;
        _jerseyStat = WatchUi.loadResource(Rez.Fonts.JerseyStat) as FontResource;
        _jerseySteps = WatchUi.loadResource(Rez.Fonts.JerseySteps) as FontResource;
        _jerseyBattery = WatchUi.loadResource(Rez.Fonts.JerseyBattery) as FontResource;
        _heartRateComplicationId = new Complications.Id(Complications.COMPLICATION_TYPE_HEART_RATE);
    }

    function onLayout(dc as Dc) as Void {
        if (!_heartRateSubscribed) {
            Complications.registerComplicationChangeCallback(method(:onHeartRateComplicationChanged));
            _heartRateSubscribed = Complications.subscribeToUpdates(_heartRateComplicationId);
        }
    }

    function onUpdate(dc as Dc) as Void {
        var clockTime = System.getClockTime();
        var timeString = Lang.format("$1$:$2$", [clockTime.hour.format("%02d"), clockTime.min.format("%02d")]);

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        // All coordinates are for the 360 x 360 FR265S display safe circle.
        dc.drawBitmap(0, 0, _background);
        dc.drawBitmap(65, 22, _timePanel);
        dc.drawBitmap(8, 177, _heartRatePanel);
        dc.drawBitmap(266, 177, _stepsPanel);
        dc.drawBitmap(97, 300, _batteryPanel);

        drawOutlinedText(dc, 180, 28, _jerseyTime, timeString, Graphics.COLOR_WHITE);
        drawOutlinedText(dc, 180, 106, _pressDate, getDateString(), Graphics.COLOR_WHITE);
        drawOutlinedText(dc, 51, 208, _jerseyStat, getHeartRateString(), Graphics.COLOR_WHITE);
        drawOutlinedText(dc, 309, 218, _jerseySteps, getStepsString(), Graphics.COLOR_WHITE);
        drawOutlinedText(dc, 208, 304, _jerseyBattery, getBatteryString(), Graphics.COLOR_WHITE);
    }

    private function drawOutlinedText(dc as Dc, x as Numeric, y as Numeric, font as FontType, text as String, color as ColorType) as Void {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x - 1, y, font, text, Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(x + 1, y, font, text, Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(x, y - 1, font, text, Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(x, y + 1, font, text, Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y, font, text, Graphics.TEXT_JUSTIFY_CENTER);
    }

    private function getDateString() as String {
        var info = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
        var days = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"];
        var months = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"];
        return Lang.format("$1$ $2$ $3$", [days[info.day_of_week], info.day.format("%02d"), months[info.month - 1]]);
    }

    private function getHeartRateString() as String {
        try {
            var heartRateComplication = Complications.getComplication(_heartRateComplicationId);
            if ((heartRateComplication != null) && (heartRateComplication.value != null)) {
                return heartRateComplication.value.toNumber().toString();
            }
        } catch (ex) {
            // The system HR complication can be unavailable while the sensor is off.
        }

        return "--";
    }

    function onHeartRateComplicationChanged(id as Complications.Id) as Void {
        if (id.equals(_heartRateComplicationId)) {
            WatchUi.requestUpdate();
        }
    }

    private function getStepsString() as String {
        var info = ActivityMonitor.getInfo();
        if ((info has :steps) && (info.steps != null)) {
            return info.steps.toNumber().toString();
        }
        return "0";
    }

    private function getBatteryString() as String {
        var percent = (System.getSystemStats().battery + 0.5).toNumber();
        return percent.toString() + "%";
    }
}
