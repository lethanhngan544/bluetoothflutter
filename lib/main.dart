import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:fl_chart/fl_chart.dart';

void main() => runApp(const MaterialApp(home: BluetoothApp()));

class BluetoothApp extends StatefulWidget {
  const BluetoothApp({super.key});
  @override
  State<BluetoothApp> createState() => _BluetoothAppState();
}

class _BluetoothAppState extends State<BluetoothApp> {
  BluetoothState _bluetoothState = BluetoothState.UNKNOWN;
  BluetoothConnection? _connection;
  List<BluetoothDevice> _devices = [];
  bool _isConnected = false;
  final TextEditingController _textController = TextEditingController();

  String _buffer = '';
  List<FlSpot> _points = [];
  double _x = 0;

  @override
  void initState() {
    super.initState();
    _askPermissions();
    FlutterBluetoothSerial.instance.state.then((state) {
      setState(() => _bluetoothState = state);
    });
    _getPairedDevices();
  }

  Future<void> _askPermissions() async {
    await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location, // Required for scanning
    ].request();
  }

  Future<void> _getPairedDevices() async {
    final devices = await FlutterBluetoothSerial.instance.getBondedDevices();
    setState(() {
      _devices = devices;
    });
  }

  void _connectToDevice(BluetoothDevice device) async {
    try {
      final conn = await BluetoothConnection.toAddress(device.address);
      setState(() {
        _connection = conn;
        _isConnected = true;
      });

      print('Connected to the device');

      // Start listening to incoming data
      _connection!.input!.listen((Uint8List data) {
        _buffer += String.fromCharCodes(data);

        if (_buffer.contains('\n')) {
          List<String> lines = _buffer.split('\n');
          _buffer = lines.removeLast(); // Save incomplete chunk

          for (String line in lines) {
            final tokens = line.trim().split(' ');
            for (var token in tokens) {
              final value = double.tryParse(token);
              if (value != null) {
                setState(() {
                  _points.add(FlSpot(_x++, value));
                  if (_points.length > 1000) {
                    _points.removeRange(0, _points.length - 1000);
                  }
                });
              }
            }
          }
        }
      });
    } catch (e) {
      print('Cannot connect, exception occurred');
      print(e);
    }
  }

  void _sendText() {
    if (_connection != null && _isConnected) {
      final text = _textController.text;
      _connection!.output.add(Uint8List.fromList(text.codeUnits));
      _connection!.output.allSent;
      _textController.clear();
    }
  }

  @override
  void dispose() {
    _connection?.dispose();
    _textController.dispose();
    super.dispose();
  }

  Widget _controlButton(String label, String charToSend) {
    return ElevatedButton(
      onPressed: () {
        if (_connection != null && _isConnected) {
          _connection!.output.add(Uint8List.fromList(charToSend.codeUnits));
        }
      },
      child: Text(label),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Classic Bluetooth with ESP32')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: _isConnected
            ? Column(
                children: [
                  Text('Connected !'),
                  TextField(controller: _textController),
                  ElevatedButton(
                      onPressed: _sendText, child: const Text("Send")),

                  // ⏺️ Waveform mode buttons
                  Wrap(
                    spacing: 8,
                    children: [
                      _controlButton("Sine", '0'),
                      _controlButton("Square", '1'),
                      _controlButton("Triangle", '2'),
                      _controlButton("Sawtooth", '3'),
                    ],
                  ),

                  // ⏺️ Frequency controls
                  Wrap(
                    spacing: 8,
                    children: [
                      _controlButton("Freq -5", '4'),
                      _controlButton("Freq +5", '6'),
                      _controlButton("Freq -1", '7'),
                      _controlButton("Freq +1", '9'),
                    ],
                  ),

                  // ⏺️ Amplitude controls
                  Wrap(
                    spacing: 8,
                    children: [
                      _controlButton("Amp -", '5'),
                      _controlButton("Amp +", '8'),
                    ],
                  ),
                  Expanded(
                    child: LineChart(
                      LineChartData(
                        lineBarsData: [
                          LineChartBarData(
                            spots: _points,
                            isCurved: false,
                            color: Colors.greenAccent,
                            dotData: FlDotData(show: false),
                            barWidth: 1,
                          )
                        ],
                        titlesData: FlTitlesData(show: false),
                        gridData: FlGridData(show: false),
                        borderData: FlBorderData(show: false),
                      ),
                    ),
                  ),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Paired Devices:"),
                  ..._devices.map((device) => ListTile(
                        title: Text(device.name ?? "Unknown"),
                        subtitle: Text(device.address),
                        onTap: () => _connectToDevice(device),
                      )),
                ],
              ),
      ),
    );
  }
}
