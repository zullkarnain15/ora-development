import Toybox.Activity;
import Toybox.Application;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.WatchUi;

class ora_wearable_pocView extends WatchUi.SimpleDataField {

    function initialize() {
        SimpleDataField.initialize();
        label = "ORA";
    }

    function compute(info as Activity.Info) as Numeric or Duration or String or Null {

        var startSeconds = 0;
        var distanceMeters = 0;
        var durationSeconds = 0;

        var startTime = info.startTime;
        if (startTime != null) {
            startSeconds = startTime.value();
        }

        var elapsedDistance = info.elapsedDistance;
        if (elapsedDistance != null) {
            distanceMeters = elapsedDistance.toNumber();
        }

        var timerTime = info.timerTime;
        if (timerTime != null) {
            durationSeconds = (timerTime / 1000).toNumber();
        }

        // The snapshot is updated once per data-field compute cycle. A zero
        // start time means the activity metadata is not available yet.
        if (startSeconds > 0) {
            (Application.getApp() as ora_wearable_pocApp).updateActivitySnapshot(startSeconds, distanceMeters, durationSeconds);
        }

        var distanceKm = distanceMeters / 1000.0;

        var hours = (durationSeconds / 3600).toNumber();
        var minutes = ((durationSeconds % 3600) / 60).toNumber();
        var seconds = (durationSeconds % 60).toNumber();

        var timeText =
            pad2(hours) + ":" +
            pad2(minutes) + ":" +
            pad2(seconds);

        return distanceKm.format("%.2f") + " KM " + timeText;
    }

    function onTimerStart() as Void {
        (Application.getApp() as ora_wearable_pocApp).beginActivity();
        System.println("ORA_TIMER_START");
    }

    // A stopped timer is not a completed/saved activity. Do not set PENDING
    // here; the FR55 Data Field baseline has no verified save callback.
    function onTimerStop() as Void {
        System.println("ORA_TIMER_STOP");
    }

    function onTimerPause() as Void {
        System.println("ORA_TIMER_PAUSE");
    }

    function onTimerResume() as Void {
        System.println("ORA_TIMER_RESUME");
    }

    function onTimerReset() as Void {
        System.println("ORA_TIMER_RESET");
        (Application.getApp() as ora_wearable_pocApp).logFinalSnapshot();
    }

    function pad2(value as Number) as String {
        if (value < 10) {
            return "0" + value.toString();
        }

        return value.toString();
    }
}
