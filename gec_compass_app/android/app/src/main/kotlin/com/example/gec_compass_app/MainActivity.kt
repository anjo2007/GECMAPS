package com.example.gec_compass_app

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel

class MainActivity : FlutterActivity() {
    private val STEP_CHANNEL = "com.gec.compass/step_detector"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, STEP_CHANNEL)
            .setStreamHandler(StepDetectorStreamHandler(this))
    }
}

class StepDetectorStreamHandler(private val context: Context) : EventChannel.StreamHandler, SensorEventListener {
    private var sensorManager: SensorManager? = null
    private var stepDetector: Sensor? = null
    private var eventSink: EventChannel.EventSink? = null

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
        sensorManager = context.getSystemService(Context.SENSOR_SERVICE) as SensorManager
        stepDetector = sensorManager?.getDefaultSensor(Sensor.TYPE_STEP_DETECTOR)
        if (stepDetector != null) {
            sensorManager?.registerListener(this, stepDetector, SensorManager.SENSOR_DELAY_FASTEST)
        } else {
            events?.error("SENSOR_UNAVAILABLE", "Hardware Step Detector is not available on this device.", null)
        }
    }

    override fun onCancel(arguments: Any?) {
        sensorManager?.unregisterListener(this)
        eventSink = null
    }

    override fun onSensorChanged(event: SensorEvent?) {
        if (event?.sensor?.type == Sensor.TYPE_STEP_DETECTOR) {
            eventSink?.success(1)
        }
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}
}
