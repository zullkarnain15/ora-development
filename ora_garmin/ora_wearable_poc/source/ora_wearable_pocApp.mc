import Toybox.Application;
import Toybox.Application.Storage;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

class ora_wearable_pocApp extends Application.AppBase {

    const STATUS_NONE = "NONE";
    const STATUS_PENDING = "PENDING";
    const STATUS_KEY = "ora.activity.status";
    const START_KEY = "ora.activity.start";
    const DISTANCE_KEY = "ora.activity.distance";
    const DURATION_KEY = "ora.activity.duration";
    const POC_TOKEN = "POC_TOKEN";

    function initialize() {
        AppBase.initialize();
    }

    // onStart() is called on application start up
    function onStart(state as Dictionary?) as Void {
    }

    // onStop() is called when your application is exiting
    function onStop(state as Dictionary?) as Void {
    }

    // A new activity must not inherit the start time or pending status of the
    // previous one. The first compute() call supplies the actual start time.
    function beginActivity() as Void {
        Storage.setValue(STATUS_KEY, STATUS_NONE);
        Storage.setValue(START_KEY, 0);
        Storage.setValue(DISTANCE_KEY, 0);
        Storage.setValue(DURATION_KEY, 0);
    }

    // Persist only the three raw activity values needed by the backend.
    // start is initialized once and remains unchanged for this activity.
    function updateActivitySnapshot(start as Number, distance as Number, duration as Number) as Void {
        var storedStart = readNumber(START_KEY);

        if (storedStart == 0 || storedStart != start) {
            Storage.setValue(STATUS_KEY, STATUS_NONE);
            Storage.setValue(START_KEY, start);
        }

        Storage.setValue(DISTANCE_KEY, distance);
        Storage.setValue(DURATION_KEY, duration);
    }

    // The result is compact JSON with exactly token, start, distance, duration.
    function buildPendingPayload() as String? {
        var status = Storage.getValue(STATUS_KEY) as String?;
        if (status == null || status != STATUS_PENDING) {
            return null;
        }

        return buildPayload(
            readNumber(START_KEY),
            readNumber(DISTANCE_KEY),
            readNumber(DURATION_KEY)
        );
    }

    function buildPayload(start as Number, distance as Number, duration as Number) as String {
        return "{\"token\":\"" + POC_TOKEN +
            "\",\"start\":" + start.toString() +
            ",\"distance\":" + distance.toString() +
            ",\"duration\":" + duration.toString() + "}";
    }

    function readNumber(key as String) as Number {
        var value = Storage.getValue(key);
        if (value == null) {
            return 0;
        }

        return value as Number;
    }

    // Logging-only read of the retained local activity snapshot.
    function logFinalSnapshot() as Void {
        System.println("ORA_FINAL_SNAPSHOT");
        System.println("start=" + readNumber(START_KEY).toString());
        System.println("distance=" + readNumber(DISTANCE_KEY).toString());
        System.println("duration=" + readNumber(DURATION_KEY).toString());
    }

    // Return the initial view of your application here
    function getInitialView() as [Views] or [Views, InputDelegates] {
        return [new $.ora_wearable_pocView()];
    }

}
